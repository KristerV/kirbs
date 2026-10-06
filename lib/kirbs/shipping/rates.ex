defmodule Kirbs.Shipping.Rates do
  @moduledoc """
  Delivery methods and their shipping price (cents) per carrier and parcel size.

  Price depends on carrier and parcel size (`Item.parcel_size` `:s | :m | :l`; an order is
  priced by its largest item, items without a size count as `:m`).

  TODO(owner): ALL prices below (`@prices`), the default parcel weights (`@weights_kg`) and the
  own-pickup address are PLACEHOLDERS. Replace them with your real carrier contract prices.
  Montonio's shipment API does not return prices; this table is what the buyer is charged.
  """

  @default_size :m

  # Placeholder prices in cents: carrier => size => cents.
  @prices %{
    omniva: %{s: 299, m: 349, l: 499},
    dpd: %{s: 349, m: 399, l: 549},
    smartposti: %{s: 299, m: 349, l: 499}
  }

  # Placeholder parcel weights (kg), used when an item has no `weight_grams`.
  @weights_kg %{s: 0.5, m: 1.0, l: 2.5}

  @methods [
    omniva_parcel_machine: %{carrier: :omniva, label: "Omniva pakiautomaat"},
    dpd_parcel_machine: %{carrier: :dpd, label: "DPD pakiautomaat"},
    smartposti_parcel_machine: %{carrier: :smartposti, label: "SmartPosti pakiautomaat"},
    pickup: %{carrier: nil, label: "Tulen ise järele"}
  ]

  # TODO(owner): real own-pickup address and instructions.
  @pickup_address "Kirbsi väljastuspunkt (aadress lisatakse) – leiame aja kokku e-kirjas"

  def methods, do: Keyword.keys(@methods)

  def method?(value), do: value in methods()

  @doc "Shipping price in cents for a delivery method and parcel size (default `:m`)."
  def cents(method, size \\ @default_size) do
    case fetch!(method).carrier do
      nil -> 0
      carrier -> @prices |> Map.fetch!(carrier) |> Map.fetch!(size || @default_size)
    end
  end

  @doc "Largest parcel size of a list of items (anything with a `parcel_size`)."
  def parcel_size(items) do
    sizes = Enum.map(items, &(&1.parcel_size || @default_size))
    Enum.find([:l, :m, :s], @default_size, &(&1 in sizes))
  end

  @doc "Total parcel weight in kg: sum of `weight_grams`, or the placeholder weight per size."
  def weight_kg(items) do
    items
    |> Enum.map(fn item ->
      if item.weight_grams,
        do: item.weight_grams / 1000,
        else: Map.fetch!(@weights_kg, item.parcel_size || @default_size)
    end)
    |> Enum.sum()
    |> Float.round(2)
  end

  def label(method), do: fetch!(method).label

  @doc "Carrier atom for parcel-machine methods, nil for own pickup."
  def carrier(method), do: fetch!(method).carrier

  def parcel_machine?(method), do: carrier(method) != nil

  def pickup_address, do: @pickup_address

  @doc "[{method, label, cents}] in display order, priced for `size`."
  def options(size \\ @default_size) do
    for {method, %{label: label}} <- @methods, do: {method, label, cents(method, size)}
  end

  defp fetch!(method), do: Keyword.fetch!(@methods, method)
end
