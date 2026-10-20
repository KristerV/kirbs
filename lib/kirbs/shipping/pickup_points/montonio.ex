defmodule Kirbs.Shipping.PickupPoints.Montonio do
  @moduledoc """
  `Kirbs.Shipping.PickupPoints.Provider` backed by `Kirbs.Shipping.MontonioPickupPoints`
  (cached Montonio data). Used automatically when Montonio is configured and no explicit
  `:pickup_points_provider` is set. Point ids are Montonio pickup point uuids, which is what
  the shipment creation needs.
  """
  @behaviour Kirbs.Shipping.PickupPoints.Provider

  alias Kirbs.Shipping.MontonioPickupPoints

  # Our carrier atoms => Montonio carrier codes.
  @codes %{omniva: "omniva", dpd: "dpd", smartposti: "smartpost"}

  @impl true
  def list(carrier) do
    case MontonioPickupPoints.list(carrier: Map.fetch!(@codes, carrier)) do
      {:ok, points} -> Enum.map(points, &to_point(&1, carrier))
      {:error, _} -> []
    end
  end

  @impl true
  def get(carrier, id) do
    case MontonioPickupPoints.get(id, carrier: Map.fetch!(@codes, carrier)) do
      {:ok, point} -> {:ok, to_point(point, carrier)}
      {:error, _} -> :error
    end
  end

  defp to_point(point, carrier) do
    address = [point.street_address, point.locality] |> Enum.reject(&is_nil/1) |> Enum.join(", ")
    %{id: point.id, name: point.name, carrier: carrier, address: address}
  end
end
