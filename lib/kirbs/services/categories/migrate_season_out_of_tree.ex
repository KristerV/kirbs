defmodule Kirbs.Services.Categories.MigrateSeasonOutOfTree do
  @moduledoc """
  One-off, idempotent migration from the season-flavoured type tree (`talvejakid`, `talvesaapad`, ...)
  to the pure type tree (see docs/taxonomy.md): the season lives in `Item.season`, not in the category.

  Items and pending categorization proposals on an obsolete leaf are re-pointed to the type leaf. When the
  old leaf implied a season and the record has none, the season is filled in (an existing season is never
  overwritten); `Item.update` rebuilds `search_text`. Obsolete categories (and their Yaga mappings) are
  deleted only when nothing references them any more. Moves that are a guess are reported in
  `:needs_review` with the affected item ids.

  Requires the new tree to be seeded (`SeedTree`).
  """

  alias Kirbs.Resources.{CategorizationProposal, Category, Item, YagaCategoryMapping}

  @root "lapsed-"

  # old leaf => {new leaf, season implied by the old leaf, review note}
  @moves %{
    "valisriided-talvejakid" => {"valisriided-joped", :winter, nil},
    "valisriided-uleminekujakid-vestid" =>
      {"valisriided-joped", nil, "uleminekujakid-vestid -> joped: some may be vests"},
    "kombinesoonid-talvekombinesoonid" => {"kombinesoonid", :winter, nil},
    "kombinesoonid-vihmakombinesoonid" =>
      {"kombinesoonid", nil,
       "vihmakombinesoonid -> kombinesoonid: rain overalls, check season/use"},
    "jalatsid-talvesaapad" => {"jalatsid-saapad", :winter, nil}
  }

  # Leaves that stay, but whose old meaning implies a season to preserve.
  @season_only %{"jalatsid-sandaalid-sussid" => :summer}

  @doc "Old shop leaf path (relative to the default root, `-` joined) => new leaf path."
  def redirects, do: Map.new(@moves, fn {old, {new, _, _}} -> {old, new} end)

  def run do
    with {:ok, all} <- Category.list_all(),
         {:ok, by_slug} <- index(all),
         {:ok, moved} <- move_all(by_slug),
         {:ok, filled} <- fill_season_only(by_slug),
         {:ok, deleted} <- delete_obsolete(by_slug) do
      {:ok,
       %{
         items_moved: moved.items,
         proposals_moved: moved.proposals,
         season_filled: moved.season_filled + filled,
         by_old_leaf: moved.by_old_leaf,
         needs_review: moved.needs_review,
         unmapped: unmapped(),
         deleted_categories: deleted
       }}
    end
  end

  defp index(all) do
    by_slug = Map.new(all, &{&1.slug, &1})
    missing = for {_old, {new, _, _}} <- @moves, not Map.has_key?(by_slug, @root <> new), do: new

    case Enum.uniq(missing) do
      [] -> {:ok, by_slug}
      [slug | _] -> {:error, "New leaf #{@root}#{slug} missing, run SeedTree first"}
    end
  end

  defp move_all(by_slug) do
    empty = %{items: 0, proposals: 0, season_filled: 0, by_old_leaf: %{}, needs_review: []}

    Enum.reduce_while(@moves, {:ok, empty}, fn {old, {new, season, note}}, {:ok, acc} ->
      with %{} = old_cat <- Map.get(by_slug, @root <> old),
           target = Map.fetch!(by_slug, @root <> new),
           {:ok, items} <- Item.list_by_category(old_cat.id),
           {:ok, filled} <- move_items(items, target, season),
           {:ok, proposals} <- CategorizationProposal.list_by_category(old_cat.id),
           {:ok, proposal_filled} <- move_proposals(proposals, target, season) do
        {:cont, {:ok, add(acc, old, new, note, items, proposals, filled + proposal_filled)}}
      else
        nil -> {:cont, {:ok, acc}}
        error -> {:halt, error}
      end
    end)
  end

  defp add(acc, old, new, note, items, proposals, filled) do
    count = length(items) + length(proposals)

    %{
      acc
      | items: acc.items + length(items),
        proposals: acc.proposals + length(proposals),
        season_filled: acc.season_filled + filled,
        by_old_leaf:
          if(count == 0,
            do: acc.by_old_leaf,
            else: Map.put(acc.by_old_leaf, old, %{to: new, count: count})
          ),
        needs_review:
          if(note && count > 0,
            do:
              acc.needs_review ++
                [%{note: note, items: Enum.map(items, & &1.id), proposals: length(proposals)}],
            else: acc.needs_review
          )
    }
  end

  defp move_items(items, target, season) do
    Enum.reduce_while(items, {:ok, 0}, fn item, {:ok, filled} ->
      fill = fill_season(item, season)

      case Item.update(item, Map.put(fill, :category_id, target.id)) do
        {:ok, _} -> {:cont, {:ok, filled + map_size(fill)}}
        error -> {:halt, error}
      end
    end)
  end

  defp move_proposals(proposals, target, season) do
    Enum.reduce_while(proposals, {:ok, 0}, fn proposal, {:ok, filled} ->
      fill = fill_season(proposal, season)

      case CategorizationProposal.update(proposal, Map.put(fill, :category_id, target.id)) do
        {:ok, _} -> {:cont, {:ok, filled + map_size(fill)}}
        error -> {:halt, error}
      end
    end)
  end

  # Items on a kept leaf whose old meaning implies a season (sandaalid-sussid -> summer).
  defp fill_season_only(by_slug) do
    Enum.reduce_while(@season_only, {:ok, 0}, fn {path, season}, {:ok, total} ->
      with %{} = category <- Map.get(by_slug, @root <> path),
           {:ok, items} <- Item.list_by_category(category.id),
           {:ok, filled} <- fill_items(items, season) do
        {:cont, {:ok, total + filled}}
      else
        nil -> {:cont, {:ok, total}}
        error -> {:halt, error}
      end
    end)
  end

  defp fill_items(items, season) do
    items
    |> Enum.filter(&is_nil(&1.season))
    |> Enum.reduce_while({:ok, 0}, fn item, {:ok, n} ->
      case Item.update(item, %{season: season}) do
        {:ok, _} -> {:cont, {:ok, n + 1}}
        error -> {:halt, error}
      end
    end)
  end

  # Never overwrites an existing season.
  defp fill_season(_record, nil), do: %{}
  defp fill_season(%{season: nil}, season), do: %{season: season}
  defp fill_season(_record, _season), do: %{}

  defp delete_obsolete(by_slug) do
    @moves
    |> Map.keys()
    |> Enum.flat_map(&List.wrap(Map.get(by_slug, @root <> &1)))
    |> Enum.reduce_while({:ok, []}, fn category, {:ok, deleted} ->
      with {:ok, []} <- Item.list_by_category(category.id),
           {:ok, []} <- CategorizationProposal.list_by_category(category.id),
           :ok <- destroy_mapping(category),
           :ok <- Category.destroy(category) do
        {:cont, {:ok, [category.slug | deleted]}}
      else
        {:ok, [_ | _]} -> {:cont, {:ok, deleted}}
        error -> {:halt, error}
      end
    end)
  end

  defp destroy_mapping(category) do
    case YagaCategoryMapping.get_by_category(category.id, not_found_error?: false) do
      {:ok, nil} -> :ok
      {:ok, mapping} -> YagaCategoryMapping.destroy(mapping)
      error -> error
    end
  end

  # Obsolete leaves that still exist (still referenced).
  defp unmapped do
    {:ok, all} = Category.list_all()
    obsolete = Enum.map(Map.keys(@moves), &(@root <> &1))
    for category <- all, category.slug in obsolete, do: category.slug
  end
end
