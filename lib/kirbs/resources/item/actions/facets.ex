defmodule Kirbs.Resources.Item.Actions.Facets do
  @moduledoc """
  Implementation of `Item.facets`: for every facet, runs the same search with that facet's own
  filter removed and counts the values. Gender counts unisex items towards boy and girl too. Season keeps `nil` (items without a season) so the shop can show an "all" count. Returns `%{brand: [{"Name", 3}, ...], ...}`.

  Category facets use primary AND extra categories (an item counts once in every category it
  is in, never twice in the same one):

  - `:category_id` - per leaf category: distinct items in it
  - `:category_rollup` - per category node (leaf and every ancestor): distinct items below it,
    so an item in two leaves of one family counts once in that family
  """
  use Ash.Resource.Actions.Implementation

  alias Kirbs.Resources.{Category, Item}

  @facets [:brand, :size, :season, :gender, :age_group, :waterproof, :category_id]
  @filter_key %{category_id: :category}

  @impl true
  def run(input, _opts, _context) do
    params = input.arguments.params

    facets =
      Map.new(@facets, fn facet ->
        params = Map.drop(params, [Map.get(@filter_key, facet, facet)])
        {facet, count(facet, params)}
      end)

    {:ok, Map.put(facets, :category_rollup, rollup(params))}
  end

  defp count(:category_id, params) do
    params
    |> category_sets()
    |> Enum.flat_map(fn {primary, extras} -> Enum.uniq([primary | extras]) end)
    |> Enum.reject(&is_nil/1)
    |> frequencies()
  end

  defp count(facet, params) do
    Item
    |> Ash.Query.for_read(:search, params)
    |> Ash.Query.select([facet])
    |> Ash.Query.limit(10_000)
    |> Ash.read!(page: false)
    |> Enum.map(&Map.fetch!(&1, facet))
    |> Enum.reject(&(is_nil(&1) and facet != :season))
    |> Enum.frequencies()
    |> then(&if(facet == :gender, do: spread_unisex(&1), else: &1))
    |> Enum.sort_by(fn {value, count} -> {-count, to_string(value)} end)
  end

  defp rollup(params) do
    by_id = Map.new(Category.list_all!(), &{&1.id, &1})

    params
    |> Map.drop([:category])
    |> category_sets()
    |> Enum.flat_map(fn {primary, extras} ->
      [primary | extras]
      |> Enum.reject(&is_nil/1)
      |> Enum.flat_map(&with_ancestors(&1, by_id))
      |> Enum.uniq()
    end)
    |> frequencies()
  end

  # `[{primary_id, [extra_id]}]` of every item matching `params`.
  defp category_sets(params) do
    Item
    |> Ash.Query.for_read(:search, Map.drop(params, [:category]))
    |> Ash.Query.select([:category_id])
    |> Ash.Query.load(item_categories: [:category_id])
    |> Ash.Query.limit(10_000)
    |> Ash.read!(page: false)
    |> Enum.map(fn item ->
      {item.category_id, Enum.map(item.item_categories, & &1.category_id)}
    end)
  end

  defp with_ancestors(id, by_id) do
    case Map.get(by_id, id) do
      nil -> []
      %{parent_id: nil} -> [id]
      %{parent_id: parent_id} -> [id | with_ancestors(parent_id, by_id)]
    end
  end

  defp frequencies(ids) do
    ids
    |> Enum.frequencies()
    |> Enum.sort_by(fn {value, count} -> {-count, to_string(value)} end)
  end

  # Unisex items also match the boy and girl filters, so they count towards both.
  defp spread_unisex(counts) do
    counts = Map.new(counts)

    case Map.get(counts, :unisex, 0) do
      0 ->
        Map.to_list(counts)

      unisex ->
        counts
        |> Map.update(:boy, unisex, &(&1 + unisex))
        |> Map.update(:girl, unisex, &(&1 + unisex))
        |> Map.to_list()
    end
  end
end
