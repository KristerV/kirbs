defmodule KirbsWeb.PayoutLive.Index do
  use KirbsWeb, :live_view

  alias Kirbs.Accounting
  alias Kirbs.Resources.{Client, Payout}
  alias Kirbs.Services.Accounting.{ComputeClientCarryover, ComputeOpenMonthAmounts}

  @impl true
  def mount(_params, _session, socket) do
    clients = load_clients()
    payouts = Payout.list!()

    months =
      Accounting.month_columns(
        payouts,
        Enum.flat_map(clients, & &1.sold_items)
      )

    clients = Enum.map(clients, &enrich_with_open_amounts(&1, payouts, months))

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
     |> assign(:for_month, nil)}
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
        |> Enum.filter(&(&1.status == :sold and not is_nil(&1.sold_price)))

      total_sales = Enum.reduce(sold_items, Decimal.new(0), &Decimal.add(&2, &1.sold_price))
      client_share = Decimal.div(total_sales, Decimal.new(2))

      %{
        id: client.id,
        name: client.name,
        iban: client.iban,
        client_share: client_share,
        sold_items: sold_items
      }
    end)
  end

  defp enrich_with_open_amounts(client, payouts, months) do
    client_payouts = Enum.filter(payouts, &(&1.client_id == client.id))

    open_months =
      months
      |> Enum.filter(&Accounting.post_cutoff_month?/1)
      |> Enum.reject(fn {y, m} ->
        Enum.any?(client_payouts, &(&1.for_month.year == y and &1.for_month.month == m))
      end)

    {:ok, carryover} =
      ComputeClientCarryover.run(%{
        items: client.sold_items,
        payouts: client_payouts,
        open_months: open_months
      })

    {:ok, open_amounts} =
      ComputeOpenMonthAmounts.run(%{
        items: client.sold_items,
        open_months: open_months,
        carryover: carryover
      })

    Map.put(client, :open_amounts, open_amounts)
  end

  defp client_payouts_for_month(payouts, client_id, year, month) do
    Enum.filter(payouts, fn p ->
      p.client_id == client_id and
        p.for_month.year == year and
        p.for_month.month == month
    end)
  end

  defp client_total_paid(payouts, client_id) do
    payouts
    |> Enum.filter(&(&1.client_id == client_id))
    |> Enum.reduce(Decimal.new(0), fn p, acc -> Decimal.add(acc, p.amount) end)
  end

  defp format_amount(decimal) do
    decimal
    |> Decimal.round(2)
    |> Decimal.to_string()
  end

  defp format_cell(%{earnings: earnings, carryover: carryover}) do
    if Decimal.compare(carryover, Decimal.new(0)) == :eq do
      format_amount(earnings)
    else
      sign = if Decimal.compare(carryover, Decimal.new(0)) == :gt, do: "+", else: ""
      "#{format_amount(earnings)} (#{sign}#{format_amount(carryover)})"
    end
  end

  defp month_name(month) do
    Enum.at(~w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec], month - 1)
  end

  defp format_month_input(date) do
    year = date.year |> Integer.to_string()
    month = date.month |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{year}-#{month}"
  end

  defp parse_month_input(str) do
    case String.split(str, "-") do
      [year_str, month_str] ->
        with {year, ""} <- Integer.parse(year_str),
             {month, ""} <- Integer.parse(month_str),
             true <- month >= 1 and month <= 12 do
          {:ok, {year, month}}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp lhv_js(client, amount, for_month) do
    description = "Kirbs #{month_name(for_month.month)} #{for_month.year}"

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

  # A cell is worth showing if either the total is positive or the carryover
  # is non-zero (so the user sees a negative carryover even when no payment).
  defp show_cell?(%{total: total, carryover: carryover}) do
    Decimal.compare(total, Decimal.new(0)) == :gt or
      Decimal.compare(carryover, Decimal.new(0)) != :eq
  end

  # Decide what to render in a (client, month) cell.
  defp cell_state(client, payouts, {year, month}) do
    month_payouts = client_payouts_for_month(payouts, client.id, year, month)

    cond do
      Enum.any?(month_payouts) ->
        {:paid, month_payouts}

      Accounting.post_cutoff_month?({year, month}) ->
        cell = Map.get(client.open_amounts, {year, month})

        cond do
          is_nil(cell) ->
            :empty

          show_cell?(cell) and Accounting.current_month?({year, month}) ->
            {:owed_in_progress, cell}

          show_cell?(cell) ->
            {:owed, cell}

          true ->
            :empty
        end

      true ->
        :empty
    end
  end

  @impl true
  def handle_event(
        "open_send_modal",
        %{"client-id" => client_id, "amount" => amount, "year" => year, "month" => month},
        socket
      ) do
    client = Enum.find(socket.assigns.clients, &(&1.id == client_id))
    {year, ""} = Integer.parse(year)
    {month, ""} = Integer.parse(month)
    for_month = Date.new!(year, month, 1)

    {:noreply,
     socket
     |> assign(:show_modal, true)
     |> assign(:selected_client, client)
     |> assign(:selected_payout, nil)
     |> assign(:payout_amount, amount)
     |> assign(:payout_date, Date.utc_today())
     |> assign(:for_month, for_month)}
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
    socket = assign(socket, :payout_amount, amount)

    socket =
      case parse_month_input(for_month_str) do
        {:ok, {for_year, for_month}} ->
          assign(socket, :for_month, Date.new!(for_year, for_month, 1))

        :error ->
          socket
      end

    {:noreply, socket}
  end

  def handle_event(
        "record_payout",
        %{"amount" => amount_str, "date" => date_str, "for_month" => for_month_str},
        socket
      ) do
    client = socket.assigns.selected_client
    amount = Decimal.new(amount_str)
    date = Date.from_iso8601!(date_str)

    for_month_date =
      case parse_month_input(for_month_str) do
        {:ok, {for_year, for_month}} -> Date.new!(for_year, for_month, 1)
        :error -> socket.assigns.for_month
      end

    sent_at = DateTime.new!(date, ~T[12:00:00], "Etc/UTC")

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

        months =
          Accounting.month_columns(
            payouts,
            Enum.flat_map(socket.assigns.clients, & &1.sold_items)
          )

        clients = Enum.map(socket.assigns.clients, &enrich_with_open_amounts(&1, payouts, months))

        action = if socket.assigns.selected_payout, do: "updated", else: "recorded"

        {:noreply,
         socket
         |> assign(:clients, clients)
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
        <div class="flex items-center justify-between mb-6">
          <h1 class="text-3xl font-bold">Payouts</h1>
          <div class="flex gap-2">
            <.link navigate={~p"/warehouse-sales"} class="btn btn-ghost btn-sm">
              Warehouse sales →
            </.link>
            <.link navigate={~p"/accounting"} class="btn btn-ghost btn-sm">Accounting →</.link>
          </div>
        </div>

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
                    </tr>
                  </thead>
                  <tbody>
                    <%= for client <- @clients do %>
                      <% total_paid = client_total_paid(@payouts, client.id) %>
                      <tr>
                        <td>
                          <.link navigate={~p"/clients/#{client.id}"} class="link link-primary">
                            {client.name}
                          </.link>
                        </td>
                        <%= for {year, month} <- @months do %>
                          <td class="text-right">
                            {render_cell(assigns, client, {year, month})}
                          </td>
                        <% end %>
                        <td class="text-right font-semibold border-l-2 border-base-300 bg-base-200">
                          {format_amount(total_paid)}
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
                <label class="label"><span class="label-text">Name</span></label>
                <div class="bg-base-200 p-2 rounded">{@selected_client.name}</div>
              </div>

              <%= if @selected_client.iban do %>
                <div class="form-control mb-4">
                  <label class="label"><span class="label-text">IBAN</span></label>
                  <div class="font-mono bg-base-200 p-2 rounded">{@selected_client.iban}</div>
                </div>
              <% end %>

              <form phx-submit="record_payout" phx-change="form_changed">
                <div class="form-control mb-4">
                  <label class="label"><span class="label-text">Amount</span></label>
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
                  <label class="label"><span class="label-text">Sent On</span></label>
                  <input
                    type="date"
                    class="input input-bordered w-full"
                    value={Date.to_iso8601(@payout_date)}
                    name="date"
                    required
                  />
                </div>

                <div class="form-control mb-4">
                  <label class="label"><span class="label-text">For Period</span></label>
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

  defp render_cell(assigns, client, {year, month}) do
    assigns =
      assigns
      |> assign(:client, client)
      |> assign(:year, year)
      |> assign(:month, month)
      |> assign(:state, cell_state(client, assigns.payouts, {year, month}))

    ~H"""
    <%= case @state do %>
      <% {:paid, payouts} -> %>
        <%= for payout <- payouts do %>
          <button
            class="link link-hover"
            phx-click="edit_payout"
            phx-value-payout-id={payout.id}
          >
            {format_amount(payout.amount)}
          </button>
        <% end %>
      <% {:owed, cell} -> %>
        <div class="flex items-center justify-end gap-2">
          <span class="text-warning font-semibold">{format_cell(cell)}</span>
          <%= if Decimal.compare(cell.total, Decimal.new(0)) == :gt do %>
            <button
              class="btn btn-primary btn-xs"
              phx-click="open_send_modal"
              phx-value-client-id={@client.id}
              phx-value-amount={format_amount(cell.total)}
              phx-value-year={@year}
              phx-value-month={@month}
            >
              Send
            </button>
          <% end %>
        </div>
      <% {:owed_in_progress, cell} -> %>
        <span class="text-warning font-semibold" title="Month still in progress">
          {format_cell(cell)}
        </span>
      <% :empty -> %>
        <span class="text-base-content/30">-</span>
    <% end %>
    """
  end
end
