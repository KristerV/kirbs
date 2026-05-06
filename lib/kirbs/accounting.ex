defmodule Kirbs.Accounting do
  @moduledoc """
  Accounting helpers shared by `PayoutLive` and `AccountingLive`.

  ## Cutoff

  We migrated mid-stream from "pay clients whatever they're owed lifetime" to
  "pay clients per calendar month based on items sold". Everything sent before
  the cutoff is the source of truth for those months (we trust the historical
  payouts as recorded). Everything sold after the cutoff is bucketed by
  `sold_at`'s Tallinn calendar month and paid for that month.

  The cutoff is the `sent_at` of the last "old world" payout batch
  (2026-04-01 12:00 UTC, which paid for March 2026 in Tallinn).

  Sales filter for post-cutoff buckets: `sold_at > cutoff` (strict). This
  excludes sales that were already covered by the pre-cutoff batch.

  ## Split

  Hardcoded 50/50: client gets `sold_price / 2`, kirbs keeps the rest.
  """

  @cutoff ~U[2026-04-01 12:00:00Z]
  @tz "Europe/Tallinn"

  def cutoff_datetime, do: @cutoff

  def cutoff_month, do: tallinn_month(@cutoff)

  @doc "Convert a UTC datetime to its `{year, month}` in Europe/Tallinn."
  def tallinn_month(%DateTime{} = utc_dt) do
    dt = DateTime.shift_zone!(utc_dt, @tz)
    {dt.year, dt.month}
  end

  @doc """
  Build the sorted list of `{year, month}` columns the Payout view should show:
  union of payout `for_month` values and Tallinn months from the cutoff month
  through the latest post-cutoff sale.
  """
  def month_columns(payouts, sold_items) do
    payout_months =
      Enum.map(payouts, fn p -> {p.for_month.year, p.for_month.month} end)

    sale_months =
      sold_items
      |> Enum.filter(&post_cutoff_sale?/1)
      |> Enum.map(&tallinn_month(&1.sold_at))

    (payout_months ++ sale_months)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Sum a client's owed amount (50% of post-cutoff sales) for a given Tallinn month.
  Returns a Decimal.
  """
  def client_owed_for_month(items, {year, month}) do
    items
    |> Enum.filter(&post_cutoff_sale?/1)
    |> Enum.filter(fn item -> tallinn_month(item.sold_at) == {year, month} end)
    |> Enum.reduce(Decimal.new(0), fn item, acc -> Decimal.add(acc, item.sold_price) end)
    |> Decimal.div(2)
  end

  @doc "True if this `{year, month}` is at or after the cutoff month."
  def post_cutoff_month?({year, month}) do
    {cy, cm} = cutoff_month()
    {year, month} >= {cy, cm}
  end

  @doc "Current Tallinn `{year, month}`."
  def current_month do
    DateTime.utc_now() |> tallinn_month()
  end

  @doc "True if `{year, month}` is the current Tallinn month (still in progress)."
  def current_month?({year, month}) do
    {year, month} == current_month()
  end

  defp post_cutoff_sale?(item) do
    item.status == :sold and not is_nil(item.sold_price) and not is_nil(item.sold_at) and
      DateTime.compare(item.sold_at, @cutoff) == :gt
  end
end
