defmodule Kirbs.Resources.Item.FacetCache do
  @moduledoc """
  Short-lived ETS cache for `Item.facets`. Only unfiltered and category-only params are cached:
  those are the shop's landing pages (most traffic, a bounded set of keys). Filtered
  combinations are computed every time. TTL comes from `config :kirbs, :facet_cache_ttl_ms`
  (default 60s, 0 disables).
  """
  use GenServer

  @table __MODULE__
  @default_ttl_ms 60_000

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Cached result for `params`, computing (and storing) it with `fun` when missing or stale."
  def fetch(params, fun) do
    ttl = ttl_ms()

    if ttl > 0 and cacheable?(params) do
      now = System.monotonic_time(:millisecond)

      case :ets.lookup(@table, params) do
        [{_, expires_at, value}] when expires_at > now ->
          value

        _ ->
          value = fun.()
          :ets.insert(@table, {params, now + ttl, value})
          value
      end
    else
      fun.()
    end
  end

  @doc "Whether facets for these params go through the cache (no filters besides category)."
  def cacheable?(params), do: params |> Map.keys() |> Enum.all?(&(&1 == :category))

  defp ttl_ms, do: Application.get_env(:kirbs, :facet_cache_ttl_ms, @default_ttl_ms)

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, nil}
  end
end
