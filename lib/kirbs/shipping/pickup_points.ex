defmodule Kirbs.Shipping.PickupPoints do
  @moduledoc """
  Parcel-machine lookup used by the checkout. This is the interface the Montonio shipping
  integration (Phase 6) fills in: implement `Kirbs.Shipping.PickupPoints.Provider` and set

      config :kirbs, :pickup_points_provider, MyMontonioProvider

  Until then `Kirbs.Shipping.PickupPoints.Static` serves a small hardcoded list.

  A pickup point is a map `%{id: String.t(), name: String.t(), carrier: atom(), address: String.t()}`
  with `carrier` one of `:omniva | :dpd | :smartposti`.
  """

  require Logger
  alias Kirbs.Shipping.PickupPoints.Static

  @type carrier :: :omniva | :dpd | :smartposti
  @type point :: %{id: String.t(), name: String.t(), carrier: carrier(), address: String.t()}

  defmodule Provider do
    @moduledoc "Behaviour for pickup point sources."
    @callback list(carrier :: Kirbs.Shipping.PickupPoints.carrier()) ::
                [Kirbs.Shipping.PickupPoints.point()]
    @callback get(carrier :: Kirbs.Shipping.PickupPoints.carrier(), id :: String.t()) ::
                {:ok, Kirbs.Shipping.PickupPoints.point()} | :error
  end

  @doc """
  Pickup points of a carrier, sorted for display. `search` (case-insensitive substring of name
  or address) and `limit` narrow the result.
  """
  def list(carrier, search \\ nil, limit \\ nil) do
    points = filter(provider_list(carrier), search)
    if limit, do: Enum.take(points, limit), else: points
  end

  @doc "One point by carrier and id, `{:ok, point}` or `:error`."
  def get(carrier, id) do
    case provider().get(carrier, id) do
      :error -> sandbox_fallback(fn -> Static.get(carrier, id) end, :error)
      found -> found
    end
  end

  defp provider_list(carrier) do
    case provider().list(carrier) do
      [] -> sandbox_fallback(fn -> Static.list(carrier) end, [])
      points -> points
    end
  end

  # Montonio sandbox keys usually cover payments only: the Shipping API answers 401, so there are
  # no real points. In sandbox we fall back to the static list so checkout stays testable; in
  # production an empty list stays empty rather than offering made-up parcel machines.
  defp sandbox_fallback(fun, empty) do
    if provider() == Kirbs.Shipping.PickupPoints.Montonio and
         Kirbs.Montonio.Config.env() == :sandbox do
      Logger.warning("Montonio pickup points unavailable in sandbox; using the static list")
      fun.()
    else
      empty
    end
  end

  defp filter(points, search) when search in [nil, ""], do: points

  defp filter(points, search) do
    needle = search |> String.trim() |> String.downcase()
    Enum.filter(points, &String.contains?(String.downcase("#{&1.name} #{&1.address}"), needle))
  end

  # Explicit config wins; otherwise Montonio when it has credentials, else the static list.
  defp provider do
    case Application.get_env(:kirbs, :pickup_points_provider) do
      nil ->
        if Kirbs.Montonio.Config.configured?(),
          do: Kirbs.Shipping.PickupPoints.Montonio,
          else: Kirbs.Shipping.PickupPoints.Static

      provider ->
        provider
    end
  end
end
