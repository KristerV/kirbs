defmodule Kirbs.Shipping.Rates do
  @moduledoc """
  Delivery methods (parcel machines only) and what the buyer pays for them: Montonio's own
  price for the parcel (`Kirbs.Montonio.Shipping.FetchRates`), passed on without markup.

  An order is described to Montonio as one parcel made of its items. Items have a
  `parcel_size` (`:s | :m | :l`, items without one count as `:m`) and optionally a
  `weight_grams`; the dimensions and default weights per size below are ASSUMPTIONS for a
  bag of kids' clothes.

  The Montonio sandbox cannot have carriers enabled, so there (and only there) a placeholder
  price table stands in. In production a failing rates call is an error: we never charge a
  made-up price.
  """

  require Logger

  alias Kirbs.Montonio.Config
  alias Kirbs.Montonio.Shipping.FetchRates

  @default_size :m

  # Parcel dimensions in cm (length, width, height) per size.
  @dimensions_cm %{s: {30, 20, 5}, m: {35, 25, 10}, l: {45, 35, 15}}

  # Default parcel weights (kg), used when an item has no `weight_grams`.
  @weights_kg %{s: 0.5, m: 1.0, l: 2.5}

  # Sandbox-only placeholder prices in cents: carrier => size => cents.
  @sandbox_prices %{
    omniva: %{s: 299, m: 349, l: 499},
    dpd: %{s: 349, m: 399, l: 549},
    smartposti: %{s: 299, m: 349, l: 499}
  }

  @methods [
    omniva_parcel_machine: %{carrier: :omniva, label: "Omniva pakiautomaat"},
    dpd_parcel_machine: %{carrier: :dpd, label: "DPD pakiautomaat"},
    smartposti_parcel_machine: %{carrier: :smartposti, label: "SmartPosti pakiautomaat"}
  ]

  def methods, do: Keyword.keys(@methods)

  def method?(value), do: value in methods()

  @doc "`{:ok, [{method, label, cents}]}` in display order, priced for these items."
  def options(items) do
    with {:ok, by_carrier} <- carrier_cents(items) do
      options =
        for {method, %{carrier: carrier, label: label}} <- @methods,
            cents = Map.get(by_carrier, carrier),
            do: {method, label, cents}

      if options == [], do: {:error, :no_rates}, else: {:ok, options}
    end
  end

  @doc "`{:ok, cents}` for one delivery method, `{:error, reason}` when Montonio has no price."
  def cents(method, items) do
    with {:ok, options} <- options(items) do
      case List.keyfind(options, method, 0) do
        {_method, _label, cents} -> {:ok, cents}
        nil -> {:error, :no_rates}
      end
    end
  end

  defp carrier_cents(items) do
    case fetcher().run(Enum.map(items, &montonio_item/1)) do
      {:ok, by_carrier} when map_size(by_carrier) > 0 ->
        {:ok, by_carrier}

      other ->
        sandbox_fallback(other, items)
    end
  end

  # Tests swap in a stub (`config :kirbs, :rates_fetcher, Module`) instead of calling Montonio.
  defp fetcher, do: Application.get_env(:kirbs, :rates_fetcher, FetchRates)

  defp sandbox_fallback(result, items) do
    if Config.env() == :sandbox do
      Logger.warning("Montonio shipping rates unavailable in sandbox; using placeholders")
      size = parcel_size(items)
      {:ok, Map.new(@sandbox_prices, fn {carrier, prices} -> {carrier, prices[size]} end)}
    else
      Logger.error("Montonio shipping rates unavailable: #{inspect(result)}")
      {:error, :rates_unavailable}
    end
  end

  defp montonio_item(item) do
    size = item.parcel_size || @default_size
    {length, width, height} = Map.fetch!(@dimensions_cm, size)
    %{length: length, width: width, height: height, weight: item_weight_kg(item)}
  end

  @doc "Largest parcel size of a list of items (anything with a `parcel_size`)."
  def parcel_size(items) do
    sizes = Enum.map(items, &(&1.parcel_size || @default_size))
    Enum.find([:l, :m, :s], @default_size, &(&1 in sizes))
  end

  @doc "Total parcel weight in kg: sum of `weight_grams`, or the default weight per size."
  def weight_kg(items) do
    items |> Enum.map(&item_weight_kg/1) |> Enum.sum() |> Float.round(2)
  end

  defp item_weight_kg(%{weight_grams: grams}) when is_integer(grams), do: grams / 1000
  defp item_weight_kg(item), do: Map.fetch!(@weights_kg, item.parcel_size || @default_size)

  def label(method), do: Keyword.fetch!(@methods, method).label

  @doc "Carrier atom of a delivery method."
  def carrier(method), do: Keyword.fetch!(@methods, method).carrier
end
