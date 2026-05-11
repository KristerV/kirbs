defmodule Kirbs.Services.Accounting.ComputeOpenMonthAmounts do
  @moduledoc """
  Walks a client's open months in order, displaying each month's earnings.
  The earliest open month additionally absorbs the carryover; negative
  carryover clamps the cell at zero and rolls forward into the next month.

  Returns `{:ok, %{ {year, month} => Decimal }}`.
  """

  alias Kirbs.Accounting

  def run(%{items: items, open_months: open_months, carryover: carryover}) do
    {pairs, _remaining} =
      open_months
      |> Enum.sort()
      |> Enum.map_reduce(carryover, fn month, remaining ->
        total = Decimal.add(month_earnings(items, month), remaining)

        case Decimal.compare(total, Decimal.new(0)) do
          :gt -> {{month, total}, Decimal.new(0)}
          _ -> {{month, Decimal.new(0)}, total}
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
