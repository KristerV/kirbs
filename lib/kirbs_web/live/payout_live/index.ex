defmodule KirbsWeb.PayoutLive.Index do
  use KirbsWeb, :live_view

  alias Kirbs.Resources.{Client, Payout}

  @impl true
  def mount(_params, _session, socket) do
    clients = load_clients()
    payouts = Payout.list!()
    months = get_payout_months(payouts)

    {:ok,
     socket
     |> assign(:page_title, "Payouts")
     |> assign(:clients, clients)
     |> assign(:payouts, payouts)
     |> assign(:months, months)
     |> assign(:show_modal, false)
     |> assign(:selected_client, nil)
     |> assign(:selected_payout, nil)
     |> assign(:payout_amount, nil)
     |> assign(:payout_date, Date.utc_today())
     |> assign(:for_month, default_for_month())}
  end

  defp default_for_month do
    today = Date.utc_today()

    if today.day <= 10 do
      # First 10 days: default to previous month
      today |> Date.beginning_of_month() |> Date.add(-1) |> Date.beginning_of_month()
    else
      # After day 10: default to current month
      Date.beginning_of_month(today)
    end
  end

  defp load_clients do
    Client
    |> Ash.Query.load(bags: [:items])
    |> Ash.Query.sort(created_at: :desc)
    |> Ash.read!()
    |> Enum.map(fn client ->
      sold_items =
        client.bags
        |> Enum.flat_map(& &1.items)
        |> Enum.filter(&(&1.status == :sold && &1.sold_price != nil))

      total_sales = Enum.reduce(sold_items, Decimal.new(0), &Decimal.add(&2, &1.sold_price))
      client_share = Decimal.div(total_sales, Decimal.new(2))

      %{
        id: client.id,
        name: client.name,
        iban: client.iban,
        client_share: client_share
      }
    end)
  end

  defp get_payout_months(payouts) do
    payouts
    |> Enum.map(fn p -> {p.for_month.year, p.for_month.month} end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp client_payouts_for_month(payouts, client_id, year, month) do
    payouts
    |> Enum.filter(fn p ->
      p.client_id == client_id &&
        p.for_month.year == year &&
        p.for_month.month == month
    end)
  end

  defp client_total_paid(payouts, client_id) do
    payouts
    |> Enum.filter(&(&1.client_id == client_id))
    |> Enum.reduce(Decimal.new(0), fn p, acc -> Decimal.add(acc, p.amount) end)
  end

  defp client_unsent(client, payouts) do
    total_paid = client_total_paid(payouts, client.id)
    Decimal.sub(client.client_share, total_paid)
  end

  defp format_amount(decimal) do
    decimal
    |> Decimal.round(2)
    |> Decimal.to_string()
  end

  defp month_name(month) do
    Enum.at(
      ~w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec],
      month - 1
    )
  end

  defp format_month_input(date) do
    # Format for HTML month input: "2024-11"
    year = date.year |> Integer.to_string()
    month = date.month |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{year}-#{month}"
  end

  defp parse_month_input(str) do
    # Parse "2024-11" format
    [year_str, month_str] = String.split(str, "-")
    {String.to_integer(year_str), String.to_integer(month_str)}
  end

  defp lhv_js(client, amount, for_month) do
    month_name = month_name(for_month.month)
    description = "Kirbs #{month_name} #{for_month.year}"

    """
    (function() {
      function setInput(selector, value) {
        const el = document.querySelector(selector);
        if (el) {
          el.value = value;
          el.dispatchEvent(new Event('input', { bubbles: true }));
          el.dispatchEvent(new Event('blur', { bubbles: true }));
        }
      }
      setInput('[data-testid="payment-creditor-account-input"]', '#{client.iban}');
      setInput('[data-testid="payment-amount-input"]', '#{amount}');
      setInput('[data-testid="payment-description-input"]', '#{description}');
      setInput('[data-testid="payment-receiver-select"] input', '#{client.name}');
    })();
    """
  end

  @impl true
  def handle_event("open_modal", %{"client-id" => client_id}, socket) do
    client = Enum.find(socket.assigns.clients, &(&1.id == client_id))
    unsent = client_unsent(client, socket.assigns.payouts)

    {:noreply,
     socket
     |> assign(:show_modal, true)
     |> assign(:selected_client, client)
     |> assign(:selected_payout, nil)
     |> assign(:payout_amount, format_amount(unsent))
     |> assign(:payout_date, Date.utc_today())
     |> assign(:for_month, default_for_month())}
  end

  def handle_event("edit_payout", %{"payout-id" => payout_id}, socket) do
    payout = Enum.find(socket.assigns.payouts, &(&1.id == payout_id))
    client = Enum.find(socket.assigns.clients, &(&1.id == payout.client_id))
    sent_date = DateTime.to_date(payout.sent_at)

    {:noreply,
     socket
     |> assign(:show_modal, true)
     |> assign(:selected_client, client)
     |> assign(:selected_payout, payout)
     |> assign(:payout_amount, format_amount(payout.amount))
     |> assign(:payout_date, sent_date)
     |> assign(:for_month, payout.for_month)}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_modal, false)
     |> assign(:selected_client, nil)
     |> assign(:selected_payout, nil)}
  end

  def handle_event("form_changed", %{"amount" => amount, "for_month" => for_month_str}, socket) do
    {for_year, for_month} = parse_month_input(for_month_str)
    for_month_date = Date.new!(for_year, for_month, 1)

    {:noreply,
     socket
     |> assign(:payout_amount, amount)
     |> assign(:for_month, for_month_date)}
  end

  def handle_event(
        "record_payout",
        %{"amount" => amount_str, "date" => date_str, "for_month" => for_month_str},
        socket
      ) do
    client = socket.assigns.selected_client
    amount = Decimal.new(amount_str)
    date = Date.from_iso8601!(date_str)
    {for_year, for_month} = parse_month_input(for_month_str)
    for_month_date = Date.new!(for_year, for_month, 1)

    sent_at =
      date
      |> DateTime.new!(~T[12:00:00], "Etc/UTC")

    result =
      case socket.assigns.selected_payout do
        nil ->
          Payout.create(%{
            client_id: client.id,
            amount: amount,
            sent_at: sent_at,
            for_month: for_month_date
          })

        payout ->
          Payout.update(payout, %{
            amount: amount,
            sent_at: sent_at,
            for_month: for_month_date
          })
      end

    case result do
      {:ok, _payout} ->
        payouts = Payout.list!()
        months = get_payout_months(payouts)
        action = if socket.assigns.selected_payout, do: "updated", else: "recorded"

        {:noreply,
         socket
         |> assign(:payouts, payouts)
         |> assign(:months, months)
         |> assign(:show_modal, false)
         |> assign(:selected_client, nil)
         |> assign(:selected_payout, nil)
         |> put_flash(:info, "Payout #{action} for #{client.name}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save payout")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-base-300 min-h-screen">
      <div class="max-w-7xl mx-auto p-6">
        <h1 class="text-3xl font-bold mb-6">Payouts</h1>

        <%= if Enum.empty?(@clients) do %>
          <div class="alert alert-info">
            <span>No clients yet.</span>
          </div>
        <% else %>
          <div class="card bg-base-100 shadow-xl">
            <div class="card-body">
              <div class="overflow-x-auto">
                <table class="table">
                  <thead>
                    <tr>
                      <th>Client</th>
                      <%= for {year, month} <- @months do %>
                        <th class="text-right">{month_name(month)} {year}</th>
                      <% end %>
                      <th class="text-right border-l-2 border-base-300 bg-base-200">Total Paid</th>
                      <th class="text-right bg-base-200">Unsent</th>
                      <th class="bg-base-200">Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for client <- @clients do %>
                      <% unsent = client_unsent(client, @payouts) %>
                      <% total_paid = client_total_paid(@payouts, client.id) %>
                      <tr>
                        <td>
                          <.link navigate={~p"/clients/#{client.id}"} class="link link-primary">
                            {client.name}
                          </.link>
                        </td>
                        <%= for {year, month} <- @months do %>
                          <% month_payouts =
                            client_payouts_for_month(@payouts, client.id, year, month) %>
                          <td class="text-right">
                            <%= if Enum.any?(month_payouts) do %>
                              <%= for payout <- month_payouts do %>
                                <button
                                  class="link link-hover"
                                  phx-click="edit_payout"
                                  phx-value-payout-id={payout.id}
                                >
                                  {format_amount(payout.amount)}
                                </button>
                              <% end %>
                            <% else %>
                              <span class="text-base-content/30">-</span>
                            <% end %>
                          </td>
                        <% end %>
                        <td class="text-right font-semibold border-l-2 border-base-300 bg-base-200">
                          {format_amount(total_paid)}
                        </td>
                        <td class={[
                          "text-right font-semibold bg-base-200",
                          Decimal.compare(unsent, Decimal.new(0)) == :gt && "text-warning"
                        ]}>
                          {format_amount(unsent)}
                        </td>
                        <td class="bg-base-200">
                          <%= if Decimal.compare(unsent, Decimal.new(0)) == :gt do %>
                            <button
                              class="btn btn-primary btn-sm"
                              phx-click="open_modal"
                              phx-value-client-id={client.id}
                            >
                              Send
                            </button>
                          <% end %>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        <% end %>

        <%= if @show_modal && @selected_client do %>
          <div class="modal modal-open">
            <div class="modal-box">
              <div class="flex justify-between items-center mb-4">
                <h3 class="font-bold text-lg">
                  {if @selected_payout, do: "Edit Payout", else: "Record Payout"}
                </h3>
                <%= if @selected_client.iban do %>
                  <button
                    type="button"
                    class="btn btn-sm btn-outline"
                    onclick={"navigator.clipboard.writeText(#{lhv_js(@selected_client, @payout_amount, @for_month) |> Jason.encode!()}); this.textContent='Copied!'; setTimeout(() => this.textContent='LHV JS', 1500)"}
                  >
                    LHV JS
                  </button>
                <% end %>
              </div>

              <div class="form-control mb-4">
                <label class="label">
                  <span class="label-text">Name</span>
                </label>
                <div class="bg-base-200 p-2 rounded">{@selected_client.name}</div>
              </div>

              <%= if @selected_client.iban do %>
                <div class="form-control mb-4">
                  <label class="label">
                    <span class="label-text">IBAN</span>
                  </label>
                  <div class="font-mono bg-base-200 p-2 rounded">{@selected_client.iban}</div>
                </div>
              <% end %>

              <form phx-submit="record_payout" phx-change="form_changed">
                <div class="form-control mb-4">
                  <label class="label">
                    <span class="label-text">Amount</span>
                  </label>
                  <input
                    type="number"
                    step="0.01"
                    class="input input-bordered w-full"
                    value={@payout_amount}
                    name="amount"
                    required
                  />
                </div>

                <div class="form-control mb-4">
                  <label class="label">
                    <span class="label-text">Sent On</span>
                  </label>
                  <input
                    type="date"
                    class="input input-bordered w-full"
                    value={Date.to_iso8601(@payout_date)}
                    name="date"
                    required
                  />
                </div>

                <div class="form-control mb-4">
                  <label class="label">
                    <span class="label-text">For Period</span>
                  </label>
                  <input
                    type="month"
                    class="input input-bordered w-full"
                    value={format_month_input(@for_month)}
                    name="for_month"
                    required
                  />
                </div>

                <div class="modal-action">
                  <button type="button" class="btn" phx-click="close_modal">Cancel</button>
                  <button type="submit" class="btn btn-primary">
                    {if @selected_payout, do: "Update Payout", else: "Record Payout"}
                  </button>
                </div>
              </form>
            </div>
            <div class="modal-backdrop" phx-click="close_modal"></div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
