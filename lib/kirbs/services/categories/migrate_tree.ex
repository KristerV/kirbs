defmodule Kirbs.Services.Categories.MigrateTree do
  @moduledoc """
  One-off, idempotent migration from the old gender-split tree
  (`lapsed-<poisid|tudrukud|beebid>-<type>`) to the type-only tree (see docs/taxonomy.md).

  Items and categorization proposals on an old leaf are re-pointed to the matching new leaf by
  type. Gender / age group are taken over from the old group when the item has none. Old
  categories (and their Yaga mappings) are deleted only once nothing references them; old
  leaves with an unknown type are reported in `:unmapped` and left alone.

  Requires the new tree to be seeded (`SeedTree`).
  """

  alias Kirbs.Resources.{CategorizationProposal, Category, Item, YagaCategoryMapping}

  @old_groups %{
    "poisid" => %{gender: :boy},
    "tudrukud" => %{gender: :girl},
    "beebid" => %{age_group: :baby}
  }

  # old type slug => new leaf slug
  @type_map %{
    "talvejakid" => "lapsed-valisriided-jakid",
    "jakid-vestid" => "lapsed-valisriided-jakid",
    "pusid" => "lapsed-puksid-luhikesed-puksid",
    "kombinesoonid" => "lapsed-kombinesoonid",
    "pluusid-sargid" => "lapsed-ulaosad-t-sargid-pluusid",
    "dressipluusid-kampsunid" => "lapsed-ulaosad-dressipluusid-kampsunid",
    "alussargid-bodyd" => "lapsed-ulaosad-bodyd-alussargid",
    "pidzaamad" => "lapsed-oo-vabaaeg-pidzaamad",
    "mutsid-sallid" => "lapsed-aksessuaarid-mutsid-sallid",
    "kingad" => "lapsed-jalatsid-kingad",
    "kleidid-seelikud" => "lapsed-kleidid-seelikud",
    "muu" => "lapsed-muu"
  }

  # Mappings that are a guess and need a human look.
  @ambiguous %{
    "kingad" => "kingad -> kingad (could be saapad, kummikud, tossud, sandaalid-sussid)",
    "jakid-vestid" => "jakid-vestid -> jakid (some may be vests)"
  }

  @doc "Old type slug => new leaf slug, also used to redirect legacy shop URLs."
  def type_map, do: @type_map

  @doc "Old gender group slugs (`poisid`, ...)."
  def old_group_slugs, do: Map.keys(@old_groups)

  def run do
    with {:ok, all} <- Category.list_all(),
         {:ok, plan} <- plan(all),
         {:ok, moved} <- move_all(plan.mappable),
         {:ok, deleted} <- delete_obsolete(plan, all) do
      {:ok,
       %{
         items_moved: moved.items,
         proposals_moved: moved.proposals,
         gender_or_age_filled: moved.attributes_filled,
         by_old_leaf: moved.by_old_leaf,
         needs_review: needs_review(moved.by_old_leaf),
         unmapped: Enum.map(plan.unmapped, & &1.slug),
         deleted_categories: deleted
       }}
    end
  end

  defp plan(all) do
    by_id = Map.new(all, &{&1.id, &1})
    by_slug = Map.new(all, &{&1.slug, &1})

    groups =
      Enum.filter(all, &(&1.slug in Enum.map(old_group_slugs(), fn g -> "lapsed-#{g}" end)))

    group_ids = MapSet.new(groups, & &1.id)
    old_leaves = Enum.filter(all, &(&1.parent_id && MapSet.member?(group_ids, &1.parent_id)))

    {mappable, unmapped} =
      old_leaves
      |> Enum.map(fn leaf ->
        group = Map.fetch!(by_id, leaf.parent_id)
        type = String.replace_prefix(leaf.slug, group.slug <> "-", "")
        {leaf, group, type, Map.get(@type_map, type) && Map.get(by_slug, @type_map[type])}
      end)
      |> Enum.split_with(fn {_leaf, _group, _type, target} -> target end)

    case Enum.find(@type_map, fn {_type, slug} -> not Map.has_key?(by_slug, slug) end) do
      {_, slug} when mappable != [] ->
        {:error, "New leaf #{slug} missing, run SeedTree first"}

      _ ->
        {:ok,
         %{
           groups: groups,
           old_leaves: old_leaves,
           mappable: mappable,
           unmapped: Enum.map(unmapped, &elem(&1, 0))
         }}
    end
  end

  defp move_all(mappable) do
    empty = %{items: 0, proposals: 0, attributes_filled: 0, by_old_leaf: %{}}

    Enum.reduce_while(mappable, {:ok, empty}, fn {leaf, group, type, target}, {:ok, acc} ->
      attrs = Map.fetch!(@old_groups, String.replace_prefix(group.slug, "lapsed-", ""))

      with {:ok, items} <- Item.list_by_category(leaf.id),
           {:ok, filled} <- move_items(items, target, attrs),
           {:ok, proposals} <- CategorizationProposal.list_by_category(leaf.id),
           :ok <- move_proposals(proposals, target, attrs) do
        {:cont,
         {:ok,
          %{
            acc
            | items: acc.items + length(items),
              proposals: acc.proposals + length(proposals),
              attributes_filled: acc.attributes_filled + filled,
              by_old_leaf: bump(acc.by_old_leaf, type, length(items) + length(proposals), target)
          }}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp bump(map, _type, 0, _target), do: map

  defp bump(map, type, n, target) do
    Map.update(map, type, %{to: target.slug, count: n}, &%{&1 | count: &1.count + n})
  end

  defp move_items(items, target, attrs) do
    Enum.reduce_while(items, {:ok, 0}, fn item, {:ok, filled} ->
      fill = fill_attrs(item, attrs)

      case Item.update(item, Map.put(fill, :category_id, target.id)) do
        {:ok, _item} -> {:cont, {:ok, filled + min(map_size(fill), 1)}}
        error -> {:halt, error}
      end
    end)
  end

  defp move_proposals(proposals, target, attrs) do
    Enum.reduce_while(proposals, :ok, fn proposal, :ok ->
      fill = fill_attrs(proposal, attrs)

      case CategorizationProposal.update(proposal, Map.put(fill, :category_id, target.id)) do
        {:ok, _} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  # Only fills what is blank, never overrides an existing gender / age group.
  defp fill_attrs(record, attrs) do
    Map.filter(attrs, fn {field, _value} -> is_nil(Map.fetch!(record, field)) end)
  end

  defp needs_review(by_old_leaf) do
    for {type, %{count: count}} <- by_old_leaf, note = @ambiguous[type], do: "#{note}: #{count}"
  end

  # Deletes old leaves (and their Yaga mapping) that nothing references any more, then empty old groups.
  defp delete_obsolete(plan, all) do
    with {:ok, leaves} <- delete_unreferenced(plan.old_leaves -- plan.unmapped),
         {:ok, groups} <- delete_empty_groups(plan.groups, all, leaves) do
      {:ok, Enum.map(leaves ++ groups, & &1.slug)}
    end
  end

  defp delete_unreferenced(leaves) do
    Enum.reduce_while(leaves, {:ok, []}, fn leaf, {:ok, deleted} ->
      with {:ok, []} <- Item.list_by_category(leaf.id),
           {:ok, []} <- CategorizationProposal.list_by_category(leaf.id),
           :ok <- destroy_mapping(leaf),
           :ok <- Category.destroy(leaf) do
        {:cont, {:ok, [leaf | deleted]}}
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

  defp delete_empty_groups(groups, all, deleted_leaves) do
    deleted_ids = MapSet.new(deleted_leaves, & &1.id)

    groups
    |> Enum.filter(fn group ->
      all
      |> Enum.filter(&(&1.parent_id == group.id))
      |> Enum.all?(&MapSet.member?(deleted_ids, &1.id))
    end)
    |> Enum.reduce_while({:ok, []}, fn group, {:ok, deleted} ->
      with {:ok, []} <- Item.list_by_category(group.id),
           :ok <- Category.destroy(group) do
        {:cont, {:ok, [group | deleted]}}
      else
        {:ok, [_ | _]} -> {:cont, {:ok, deleted}}
        error -> {:halt, error}
      end
    end)
  end
end
