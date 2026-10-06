defmodule Kirbs.Services.Accounting.ChannelPayoutsTest do
  use ExUnit.Case, async: true

  alias Kirbs.Accounting
  alias Kirbs.Services.Accounting.{ComputeClientCarryover, ComputeOpenMonthAmounts}

  defp sold(price, channel, sold_at) do
    %{
      status: :sold,
      sold_price: Decimal.new(price),
      sales_channel: channel,
      sold_at: sold_at
    }
  end

  # May 2026 (post-cutoff), Tallinn midday
  @may ~U[2026-05-12 09:00:00Z]
  @june ~U[2026-06-03 09:00:00Z]

  test "client share is half of the price for every channel (no Yaga fee on kirbs)" do
    assert Decimal.equal?(Accounting.client_share(sold("24.00", :yaga, @may)), "12")
    assert Decimal.equal?(Accounting.client_share(sold("24.00", :kirbs, @may)), "12")
    assert Decimal.equal?(Accounting.client_share(sold("17.50", :warehouse, @may)), "8.75")
  end

  test "items without a channel (legacy structs) are treated as yaga" do
    assert Decimal.equal?(
             Accounting.client_share(%{sold_price: Decimal.new("9.90")}),
             "4.95"
           )
  end

  test "unsold or priceless items are worth nothing" do
    assert Decimal.equal?(Accounting.client_share(%{sold_price: nil}), "0")
  end

  test "shop sales count towards open month earnings like Yaga sales" do
    items = [
      sold("24.00", :yaga, @may),
      sold("18.50", :kirbs, @may),
      sold("9.00", :kirbs, @june)
    ]

    {:ok, carryover} =
      ComputeClientCarryover.run(%{
        items: items,
        payouts: [],
        open_months: [{2026, 5}, {2026, 6}]
      })

    assert Decimal.equal?(carryover, "0")

    {:ok, amounts} =
      ComputeOpenMonthAmounts.run(%{
        items: items,
        open_months: [{2026, 5}, {2026, 6}],
        carryover: carryover
      })

    # May: (24.00 + 18.50) / 2, June: 9.00 / 2
    assert Decimal.equal?(amounts[{2026, 5}].total, "21.25")
    assert Decimal.equal?(amounts[{2026, 6}].total, "4.50")
  end

  test "a shop sale in a month already paid out surfaces as carryover" do
    items = [sold("24.00", :yaga, @may), sold("30.00", :kirbs, @may)]
    paid = [%{amount: Decimal.new("12.00")}]

    {:ok, carryover} =
      ComputeClientCarryover.run(%{items: items, payouts: paid, open_months: [{2026, 6}]})

    # lifetime share 27.00 - paid 12.00 - open earnings 0
    assert Decimal.equal?(carryover, "15")
  end
end
