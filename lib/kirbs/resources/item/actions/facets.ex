defmodule Kirbs.Resources.Item.Actions.Facets do
  @moduledoc """
  Implementation of `Item.facets`: for every facet, runs the same search with that facet's own
  filter removed and counts the values. Returns `%{brand: [{"Name", 3}, ...], ...}`.
  """
  use Ash.Resource.Actions.Implementation

  alias Kirbs.Resources.Item

  @facets [:brand, :size, :age_group, :gender, :season, :condition, :category_id]
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
          |> Enum.reject(&is_nil/1)
          |> Enum.frequencies()
          |> Enum.sort_by(fn {value, count} -> {-count, to_string(value)} end)

        {facet, counts}
      end)

    {:ok, facets}
  end
end
