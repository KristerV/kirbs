defmodule Kirbs.Services.Accounting.ComputeOpenMonthAmounts do
  @moduledoc """
  Walks a client's open months in order. Each month gets its raw earnings;
  the earliest open month additionally absorbs the carryover. Negative
  carryover clamps the cell total at zero and rolls forward into the next
  month's cell.

  Returns `{:ok, %{ {year, month} => %{earnings, carryover, total} }}` where:
    - `earnings`   = month's earnings only (Decimal)
    - `carryover`  = signed carryover applied to this cell (Decimal)
    - `total`      = max(0, earnings + carryover) — what to pay (Decimal)
  """

  alias Kirbs.Accounting

  def run(%{items: items, open_months: open_months, carryover: carryover}) do
    {pairs, _remaining} =
      open_months
      |> Enum.sort()
      |> Enum.map_reduce(carryover, fn month, remaining ->
        earnings = month_earnings(items, month)
        sum = Decimal.add(earnings, remaining)

        case Decimal.compare(sum, Decimal.new(0)) do
          :gt ->
            cell = %{earnings: earnings, carryover: remaining, total: sum}
            {{month, cell}, Decimal.new(0)}

          _ ->
            cell = %{earnings: earnings, carryover: remaining, total: Decimal.new(0)}
            {{month, cell}, sum}
        end
      end)

    {:ok, Map.new(pairs)}
  end

  defp month_earnings(items, {year, month}) do
    items
    |> Enum.filter(fn i ->
      i.status == :sold and not is_nil(i.sold_price) and not is_nil(i.sold_at) and
        Accounting.tallinn_month(i.sold_at) == {year, month}
    end)
    |> Enum.reduce(Decimal.new(0), fn i, acc -> Decimal.add(acc, i.sold_price) end)
    |> Decimal.div(2)
  end
end
