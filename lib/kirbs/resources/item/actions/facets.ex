defmodule Kirbs.Resources.Item.Actions.Facets do
  @moduledoc """
  Implementation of `Item.facets`: for every facet, aggregates the same search with that facet's
  own filter removed and counts the values. Gender counts unisex items towards boy and girl too. Season keeps `nil` (items without a season) so the shop can show an "all" count. Returns `%{brand: [{"Name", 3}, ...], ...}`.

  Values are collected in SQL with `:list` aggregates over the search query (no records are
  loaded); facets that end up with the same search params share one query, so an unfiltered
  page is a single query. Unfiltered and category-only results are cached (`FacetCache`).

  Category facets use primary AND extra categories (an item counts once in every category it
  is in, never twice in the same one):

  - `:category_id` - per leaf category: distinct items in it
  - `:category_rollup` - per category node (leaf and every ancestor): distinct items below it,
    so an item in two leaves of one family counts once in that family
  """
  use Ash.Resource.Actions.Implementation

  alias Kirbs.Resources.{Category, Item}
  alias Kirbs.Resources.Item.FacetCache

  @facets [:brand, :size, :season, :gender, :age_group, :waterproof]

  @impl true
  def run(input, _opts, _context) do
    params = input.arguments.params
    {:ok, FacetCache.fetch(params, fn -> compute(params) end)}
  end

  defp compute(params) do
    values =
      [
        {:category_set, Map.drop(params, [:category])}
        | Enum.map(@facets, &{&1, Map.drop(params, [&1])})
      ]
      |> Enum.group_by(fn {_facet, params} -> params end, fn {facet, _params} -> facet end)
      |> Enum.map(fn {params, facets} -> aggregate(params, facets) end)
      |> Enum.reduce(%{}, &Map.merge/2)

    sets = Enum.map(values.category_set, &String.split(&1, ",", trim: true))

    @facets
    |> Map.new(&{&1, count(&1, values[&1])})
    |> Map.put(:category_id, category_counts(sets))
    |> Map.put(:category_rollup, rollup(sets))
  end

  defp aggregate(params, facets) do
    Item
    |> Ash.Query.for_read(:search, params)
    |> Ash.aggregate!(Enum.map(facets, &aggregate_spec/1))
    |> Map.new(fn {facet, values} -> {facet, values || []} end)
  end

  defp aggregate_spec(facet), do: {facet, :list, field: facet, include_nil?: true}

  # Only season keeps `nil` (items without a season).
  defp count(:season, values), do: values |> Enum.frequencies() |> sorted()

  defp count(:gender, values),
    do: values |> Enum.reject(&is_nil/1) |> Enum.frequencies() |> spread_unisex() |> sorted()

  defp count(_facet, values),
    do: values |> Enum.reject(&is_nil/1) |> Enum.frequencies() |> sorted()

  defp category_counts(sets), do: sets |> Enum.flat_map(&Enum.uniq/1) |> frequencies()

  defp rollup(sets) do
    by_id = Map.new(Category.list_all!(), &{&1.id, &1})

    sets
    |> Enum.flat_map(fn ids ->
      ids |> Enum.flat_map(&with_ancestors(&1, by_id)) |> Enum.uniq()
    end)
    |> frequencies()
  end

  defp with_ancestors(id, by_id) do
    case Map.get(by_id, id) do
      nil -> []
      %{parent_id: nil} -> [id]
      %{parent_id: parent_id} -> [id | with_ancestors(parent_id, by_id)]
    end
  end

  defp frequencies(ids), do: ids |> Enum.frequencies() |> sorted()

  defp sorted(counts),
    do: Enum.sort_by(counts, fn {value, count} -> {-count, to_string(value)} end)

  # Unisex items also match the boy and girl filters, so they count towards both.
  defp spread_unisex(counts) do
    case Map.get(counts, :unisex, 0) do
      0 ->
        counts

      unisex ->
        counts
        |> Map.update(:boy, unisex, &(&1 + unisex))
        |> Map.update(:girl, unisex, &(&1 + unisex))
    end
  end
end
