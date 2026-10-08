defmodule Kirbs.Resources.Item.Actions.Facets do
  @moduledoc """
  Implementation of `Item.facets`: for every facet, runs the same search with that facet's own
  filter removed and counts the values. Gender counts unisex items towards boy and girl too. Season keeps `nil` (items without a season) so the shop can show an "all" count. Returns `%{brand: [{"Name", 3}, ...], ...}`.
  """
  use Ash.Resource.Actions.Implementation

  alias Kirbs.Resources.Item

  @facets [:brand, :size, :season, :gender, :age_group, :category_id]
  @filter_key %{category_id: :category}

  @impl true
  def run(input, _opts, _context) do
    params = input.arguments.params

    facets =
      Map.new(@facets, fn facet ->
        params = Map.drop(params, [Map.get(@filter_key, facet, facet)])

        counts =
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

        {facet, counts}
      end)

    {:ok, facets}
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
