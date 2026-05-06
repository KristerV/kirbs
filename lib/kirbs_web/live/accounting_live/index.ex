defmodule KirbsWeb.AccountingLive.Index do
  use KirbsWeb, :live_view

  alias Kirbs.Resources.Payout

  @impl true
  def mount(_params, _session, socket) do
    payouts = Payout.list!()
    months = month_options(payouts)
    selected = List.first(months)

    {:ok,
     socket
     |> assign(:page_title, "Accounting")
     |> assign(:payouts, payouts)
     |> assign(:months, months)
     |> assign(:selected_month, selected)}
  end

  @impl true
  def handle_event("select_month", %{"month" => month_str}, socket) do
    selected =
      case Date.from_iso8601(month_str) do
        {:ok, date} -> date
        _ -> socket.assigns.selected_month
      end

    {:noreply, assign(socket, :selected_month, selected)}
  end

  defp month_options(payouts) do
    payouts
    |> Enum.map(& &1.for_month)
    |> Enum.uniq()
    |> Enum.sort({:desc, Date})
  end

  defp payouts_for_month(_payouts, nil), do: []

  defp payouts_for_month(payouts, %Date{} = month) do
    payouts
    |> Enum.filter(&(&1.for_month == month))
    |> Enum.sort_by(& &1.sent_at, DateTime)
  end

  defp format_amount(decimal) do
    decimal |> Decimal.round(2) |> Decimal.to_string()
  end

  defp tallinn_date(utc_dt) do
    utc_dt |> DateTime.shift_zone!("Europe/Tallinn") |> DateTime.to_date()
  end

  defp month_name(month) do
    Enum.at(~w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec], month - 1)
  end

  defp month_label(%Date{year: y, month: m}), do: "#{month_name(m)} #{y}"

  defp totals(rows) do
    Enum.reduce(rows, {Decimal.new(0), Decimal.new(0), Decimal.new(0)}, fn row,
                                                                           {tot, prof, sent} ->
      {Decimal.add(tot, row.total), Decimal.add(prof, row.profit), Decimal.add(sent, row.sent)}
    end)
  end

  defp build_rows(payouts) do
    Enum.map(payouts, fn p ->
      %{
        id: p.id,
        date: tallinn_date(p.sent_at),
        total: Decimal.mult(p.amount, Decimal.new(2)),
        profit: p.amount,
        sent: p.amount
      }
    end)
  end

  @impl true
  def render(assigns) do
    rows = build_rows(payouts_for_month(assigns.payouts, assigns.selected_month))
    {tot, prof, sent} = totals(rows)

    assigns =
      assigns
      |> assign(:rows, rows)
      |> assign(:total_sum, tot)
      |> assign(:profit_sum, prof)
      |> assign(:sent_sum, sent)

    ~H"""
    <div class="bg-base-300 min-h-screen">
      <div class="max-w-5xl mx-auto p-6">
        <div class="flex items-center justify-between mb-6">
          <h1 class="text-3xl font-bold">Accounting</h1>
          <.link navigate={~p"/payouts"} class="btn btn-ghost btn-sm">← Payouts</.link>
        </div>

        <%= if Enum.empty?(@months) do %>
          <div class="alert alert-info"><span>No payouts yet.</span></div>
        <% else %>
          <form phx-change="select_month" class="mb-4">
            <select class="select select-bordered" name="month">
              <%= for month <- @months do %>
                <option value={Date.to_iso8601(month)} selected={month == @selected_month}>
                  {month_label(month)}
                </option>
              <% end %>
            </select>
          </form>

          <div class="card bg-base-100 shadow-xl">
            <div class="card-body">
              <div class="overflow-x-auto">
                <table class="table">
                  <thead>
                    <tr>
                      <th>Date</th>
                      <th class="text-right">Total</th>
                      <th class="text-right">Profit</th>
                      <th class="text-right">Sent</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= if Enum.empty?(@rows) do %>
                      <tr>
                        <td colspan="4" class="text-center text-base-content/50">
                          No payouts for this month.
                        </td>
                      </tr>
                    <% else %>
                      <%= for row <- @rows do %>
                        <tr>
                          <td>{Date.to_iso8601(row.date)}</td>
                          <td class="text-right">{format_amount(row.total)}</td>
                          <td class="text-right">{format_amount(row.profit)}</td>
                          <td class="text-right">{format_amount(row.sent)}</td>
                        </tr>
                      <% end %>
                    <% end %>
                  </tbody>
                  <%= if not Enum.empty?(@rows) do %>
                    <tfoot>
                      <tr class="font-semibold bg-base-200">
                        <td>Total</td>
                        <td class="text-right">{format_amount(@total_sum)}</td>
                        <td class="text-right">{format_amount(@profit_sum)}</td>
                        <td class="text-right">{format_amount(@sent_sum)}</td>
                      </tr>
                    </tfoot>
                  <% end %>
                </table>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
