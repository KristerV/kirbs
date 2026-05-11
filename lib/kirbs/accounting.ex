defmodule Kirbs.Accounting do
  @moduledoc """
  Pure helpers for the cutoff, Tallinn calendar months, and the payout grid's
  month columns. Heavier accounting computations live as services under
  `Kirbs.Services.Accounting`.

  ## Model

  - **Closed month**: a calendar month with a recorded payout for that client.
    The recorded amount is the truth — never recomputed.
  - **Open month**: a post-cutoff calendar month with no payout yet.
  - **Month earnings**: half the `sold_price` of items the client currently
    owns whose `sold_at` is in that Tallinn month.
  - **Carryover** (per client): closed-month reconciliation deltas
    (`month_earnings − month_paid`) summed with the orphan share (sold items
    with no `sold_at`). Captures historical mistakes only.

  Open months display their month earnings; the earliest open month absorbs
  the carryover, with negative carryover rolling forward.
  """

  @cutoff ~U[2026-04-01 12:00:00Z]
  @tz "Europe/Tallinn"

  def cutoff_datetime, do: @cutoff

  def cutoff_month, do: tallinn_month(@cutoff)

  def tallinn_month(%DateTime{} = utc_dt) do
    dt = DateTime.shift_zone!(utc_dt, @tz)
    {dt.year, dt.month}
  end

  def current_month, do: DateTime.utc_now() |> tallinn_month()

  def current_month?({year, month}), do: {year, month} == current_month()

  def post_cutoff_month?({year, month}) do
    {cy, cm} = cutoff_month()
    {year, month} >= {cy, cm}
  end

  @doc """
  Sorted union of payout months, post-cutoff sale months, the cutoff month,
  and the current month (so carryover always has somewhere to land).
  """
  def month_columns(payouts, sold_items) do
    payout_months =
      Enum.map(payouts, fn p -> {p.for_month.year, p.for_month.month} end)

    sale_months =
      sold_items
      |> Enum.filter(&post_cutoff_sale?/1)
      |> Enum.map(&tallinn_month(&1.sold_at))

    (payout_months ++ sale_months ++ [cutoff_month(), current_month()])
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp post_cutoff_sale?(item) do
    item.status == :sold and not is_nil(item.sold_price) and not is_nil(item.sold_at) and
      DateTime.compare(item.sold_at, @cutoff) == :gt
  end
end
