defmodule Kirbs.Shipping.Rates do
  @moduledoc """
  Delivery methods and their flat shipping price (cents) per carrier.

  TODO(owner): the prices and the own-pickup address below are placeholders. Phase 6
  (Montonio shipping) replaces the flat table with per carrier / parcel-size prices.
  """

  @methods [
    omniva_parcel_machine: %{carrier: :omniva, label: "Omniva pakiautomaat", cents: 349},
    dpd_parcel_machine: %{carrier: :dpd, label: "DPD pakiautomaat", cents: 399},
    smartposti_parcel_machine: %{
      carrier: :smartposti,
      label: "SmartPosti pakiautomaat",
      cents: 349
    },
    pickup: %{carrier: nil, label: "Tulen ise järele", cents: 0}
  ]

  # TODO(owner): real own-pickup address and instructions.
  @pickup_address "Kirbsi väljastuspunkt (aadress lisatakse) – leiame aja kokku e-kirjas"

  def methods, do: Keyword.keys(@methods)

  def method?(value), do: value in methods()

  @doc "Shipping price in cents for a delivery method."
  def cents(method), do: fetch!(method).cents

  def label(method), do: fetch!(method).label

  @doc "Carrier atom for parcel-machine methods, nil for own pickup."
  def carrier(method), do: fetch!(method).carrier

  def parcel_machine?(method), do: carrier(method) != nil

  def pickup_address, do: @pickup_address

  @doc "[{method, label, cents}] in display order."
  def options do
    for {method, %{label: label, cents: cents}} <- @methods, do: {method, label, cents}
  end

  defp fetch!(method), do: Keyword.fetch!(@methods, method)
end
