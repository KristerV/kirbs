defmodule Kirbs.Services.Accounting.ComputeClientCarryover do
  @moduledoc """
  Computes a single client's carryover: closed-month reconciliation deltas
  (`month_earnings − month_paid`) summed with the orphan share (sold items
  with no `sold_at`).

  Carryover captures historical mistakes only — items that moved between
  clients after a payout was made. Open-month earnings are untouched.
  """

  alias Kirbs.Accounting

  def run(%{items: items, payouts: payouts}) do
    with {:ok, closed_delta} <- sum_closed_deltas(items, payouts),
         {:ok, orphan} <- orphan_share(items) do
      {:ok, Decimal.add(closed_delta, orphan)}
    end
  end

  defp sum_closed_deltas(items, payouts) do
    delta =
      payouts
      |> Enum.group_by(fn p -> {p.for_month.year, p.for_month.month} end)
      |> Enum.reduce(Decimal.new(0), fn {month, month_payouts}, acc ->
        earnings = month_earnings(items, month)
        paid = sum_amounts(month_payouts)
        Decimal.add(acc, Decimal.sub(earnings, paid))
      end)

    {:ok, delta}
  end

  defp orphan_share(items) do
    share =
      items
      |> Enum.filter(fn i ->
        i.status == :sold and not is_nil(i.sold_price) and is_nil(i.sold_at)
      end)
      |> Enum.reduce(Decimal.new(0), fn i, acc -> Decimal.add(acc, i.sold_price) end)
      |> Decimal.div(2)

    {:ok, share}
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

  defp sum_amounts(payouts) do
    Enum.reduce(payouts, Decimal.new(0), fn p, acc -> Decimal.add(acc, p.amount) end)
  end
end
