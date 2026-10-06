defmodule Kirbs.Shipping.PickupPoints do
  @moduledoc """
  Parcel-machine lookup used by the checkout. This is the interface the Montonio shipping
  integration (Phase 6) fills in: implement `Kirbs.Shipping.PickupPoints.Provider` and set

      config :kirbs, :pickup_points_provider, MyMontonioProvider

  Until then `Kirbs.Shipping.PickupPoints.Static` serves a small hardcoded list.

  A pickup point is a map `%{id: String.t(), name: String.t(), carrier: atom(), address: String.t()}`
  with `carrier` one of `:omniva | :dpd | :smartposti`.
  """

  @type carrier :: :omniva | :dpd | :smartposti
  @type point :: %{id: String.t(), name: String.t(), carrier: carrier(), address: String.t()}

  defmodule Provider do
    @moduledoc "Behaviour for pickup point sources."
    @callback list(carrier :: Kirbs.Shipping.PickupPoints.carrier()) ::
                [Kirbs.Shipping.PickupPoints.point()]
    @callback get(carrier :: Kirbs.Shipping.PickupPoints.carrier(), id :: String.t()) ::
                {:ok, Kirbs.Shipping.PickupPoints.point()} | :error
  end

  @doc "All pickup points of a carrier, sorted for display."
  def list(carrier), do: provider().list(carrier)

  @doc "One point by carrier and id, `{:ok, point}` or `:error`."
  def get(carrier, id), do: provider().get(carrier, id)

  defp provider do
    Application.get_env(:kirbs, :pickup_points_provider, Kirbs.Shipping.PickupPoints.Static)
  end
end
