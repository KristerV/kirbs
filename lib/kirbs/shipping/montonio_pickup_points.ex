defmodule Kirbs.Shipping.MontonioPickupPoints do
  @moduledoc """
  Cached Montonio pickup points (ETS, `Kirbs.Montonio.Store`), refreshed daily
  by `Kirbs.Jobs.RefreshMontonioPickupPointsJob`.

  Each point is `%{id, name, type, street_address, locality, postal_code, carrier}`
  where `type` is `"parcelMachine" | "parcelShop" | "postOffice"`.

  Swapping in for the `Kirbs.Shipping.PickupPoints` interface stub: point the
  stub's implementation (config or delegate) at this module; `list/1` and
  `get/2` below are the whole surface.
  """

  alias Kirbs.Montonio.{Config, Shipping.FetchPickupPoints, Store}

  @doc """
  Lists pickup points. Options: `carrier:` (code, default all configured),
  `country:` (default "EE"), `search:` (case-insensitive substring of name,
  locality or street), `type:`. A cold cache is filled lazily.
  """
  def list(opts \\ []) do
    country = Keyword.get(opts, :country, "EE")
    carriers = opts |> Keyword.get(:carrier) |> carriers()

    with {:ok, groups} <- load_all(carriers, country) do
      points =
        groups
        |> Enum.concat()
        |> filter_type(opts[:type])
        |> filter_search(opts[:search])
        |> Enum.sort_by(&{&1.carrier, &1.locality, &1.name})

      {:ok, points}
    end
  end

  @doc "Finds one pickup point by id in the cache."
  def get(id, opts \\ []) do
    with {:ok, points} <- list(opts) do
      case Enum.find(points, &(&1.id == id)) do
        nil -> {:error, :not_found}
        point -> {:ok, point}
      end
    end
  end

  @doc "Refetches every configured carrier for `country`; keeps old data on failure."
  def refresh(country \\ "EE") do
    results = Enum.map(Config.carriers(), &{&1, fetch_and_store(&1, country)})
    ok = for {carrier, {:ok, count}} <- results, do: {carrier, count}
    failed = for {carrier, {:error, reason}} <- results, do: {carrier, reason}

    if ok == [] and failed != [],
      do: {:error, failed},
      else: {:ok, %{refreshed: ok, failed: failed}}
  end

  defp carriers(nil), do: Config.carriers()
  defp carriers(carrier), do: [carrier]

  defp load_all(carriers, country) do
    Enum.reduce_while(carriers, {:ok, []}, fn carrier, {:ok, acc} ->
      case load(carrier, country) do
        {:ok, points} -> {:cont, {:ok, [points | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp load(carrier, country) do
    case Store.get_points({carrier, country}) do
      {:ok, points} ->
        {:ok, points}

      :miss ->
        with {:ok, _count} <- fetch_and_store(carrier, country) do
          Store.get_points({carrier, country})
        end
    end
  end

  defp fetch_and_store(carrier, country) do
    with {:ok, points} <- FetchPickupPoints.run(carrier, country) do
      Store.put_points({carrier, country}, points)
      {:ok, length(points)}
    end
  end

  defp filter_type(points, nil), do: points
  defp filter_type(points, type), do: Enum.filter(points, &(&1.type == type))

  defp filter_search(points, search) when search in [nil, ""], do: points

  defp filter_search(points, search) do
    needle = String.downcase(search)

    Enum.filter(points, fn p ->
      [p.name, p.locality, p.street_address]
      |> Enum.any?(&(is_binary(&1) and String.contains?(String.downcase(&1), needle)))
    end)
  end
end
