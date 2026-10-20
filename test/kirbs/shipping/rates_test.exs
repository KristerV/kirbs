defmodule Kirbs.Shipping.RatesTest do
  use ExUnit.Case, async: false

  alias Kirbs.Shipping.Rates

  defp item(attrs \\ %{}), do: Map.merge(%{parcel_size: nil, weight_grams: nil}, attrs)

  defp production! do
    original = Application.get_env(:kirbs, :montonio)
    Application.put_env(:kirbs, :montonio, Keyword.put(original, :env, :production))
    on_exit(fn -> Application.put_env(:kirbs, :montonio, original) end)
  end

  test "only parcel machines are delivery methods" do
    assert Rates.methods() ==
             [:omniva_parcel_machine, :dpd_parcel_machine, :smartposti_parcel_machine]

    refute Rates.method?(:pickup)
  end

  test "passes Montonio's price on without markup" do
    assert {:ok, [{:omniva_parcel_machine, "Omniva pakiautomaat", 349} | _] = options} =
             Rates.options([item()])

    assert Enum.map(options, &elem(&1, 0)) == Rates.methods()
    assert {:ok, 399} = Rates.cents(:dpd_parcel_machine, [item()])
  end

  test "describes the items to Montonio by parcel size and weight" do
    Kirbs.StubRatesFetcher.notify_me()

    {:ok, _} = Rates.options([item(%{parcel_size: :l}), item(%{weight_grams: 700})])

    assert_received {:rates_requested, [large, light]}
    assert %{length: 45, width: 35, height: 15, weight: 2.5} = large
    assert %{length: 35, width: 25, height: 10, weight: 0.7} = light
  end

  test "a carrier Montonio has no contract with is not offered" do
    Application.put_env(:kirbs, :stub_rates_result, {:ok, %{omniva: 250}})
    on_exit(fn -> Application.delete_env(:kirbs, :stub_rates_result) end)

    assert {:ok, [{:omniva_parcel_machine, _, 250}]} = Rates.options([item()])
    assert {:error, :no_rates} = Rates.cents(:dpd_parcel_machine, [item()])
  end

  test "in the sandbox, which has no carriers, placeholder prices stand in" do
    Kirbs.StubRatesFetcher.fail_with(:carrier_not_found_for_store)

    assert {:ok, 349} = Rates.cents(:omniva_parcel_machine, [item()])
    assert {:ok, 549} = Rates.cents(:dpd_parcel_machine, [item(%{parcel_size: :l})])
  end

  test "in production a failing call is an error, never a guessed price" do
    production!()
    Kirbs.StubRatesFetcher.fail_with(:boom)

    assert {:error, :rates_unavailable} = Rates.options([item()])
    assert {:error, :rates_unavailable} = Rates.cents(:omniva_parcel_machine, [item()])
  end

  test "an empty answer is an error in production too" do
    production!()
    Application.put_env(:kirbs, :stub_rates_result, {:ok, %{}})
    on_exit(fn -> Application.delete_env(:kirbs, :stub_rates_result) end)

    assert {:error, :rates_unavailable} = Rates.options([item()])
  end

  test "weight and parcel size of several items" do
    items = [item(%{parcel_size: :s}), item(%{parcel_size: :l}), item(%{weight_grams: 500})]
    assert Rates.parcel_size(items) == :l
    assert Rates.weight_kg(items) == 3.5
  end
end
