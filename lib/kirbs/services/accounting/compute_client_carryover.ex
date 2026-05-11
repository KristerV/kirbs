defmodule Kirbs.Services.Accounting.ComputeClientCarryover do
  @moduledoc """
  Computes a single client's carryover:

      carryover = lifetime_share − total_paid − sum(open_month_earnings)

  Where `lifetime_share` is half the sold_price of items the client currently
  owns, `total_paid` is the sum of recorded payouts, and `open_month_earnings`
  is the share for items whose `sold_at` falls in a post-cutoff month with no
  payout yet.

  Carryover is everything not accounted for by closed-month payouts and not
  about to be shown as a normal open-month cell. Captures historical mistakes
  (items moved between clients), orphan items (sold with no `sold_at`), and
  pre-cutoff sales that were never paid for.
  """

  alias Kirbs.Accounting

  def run(%{items: items, payouts: payouts, open_months: open_months}) do
    lifetime_share = lifetime_share(items)
    total_paid = sum_amounts(payouts)
    open_earnings = sum_open_earnings(items, open_months)

    carryover =
      lifetime_share
      |> Decimal.sub(total_paid)
      |> Decimal.sub(open_earnings)

    {:ok, carryover}
  end

  defp lifetime_share(items) do
    items
    |> Enum.filter(&(&1.status == :sold and not is_nil(&1.sold_price)))
    |> Enum.reduce(Decimal.new(0), fn i, acc -> Decimal.add(acc, i.sold_price) end)
    |> Decimal.div(2)
  end

  defp sum_amounts(payouts) do
    Enum.reduce(payouts, Decimal.new(0), fn p, acc -> Decimal.add(acc, p.amount) end)
  end

  defp sum_open_earnings(items, open_months) do
    Enum.reduce(open_months, Decimal.new(0), fn month, acc ->
      Decimal.add(acc, month_earnings(items, month))
    end)
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
