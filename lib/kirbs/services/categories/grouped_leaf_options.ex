defmodule Kirbs.Services.Categories.GroupedLeafOptions do
  @moduledoc """
  Leaf categories grouped by family, shaped for a grouped `<select>`:
  `[{"Välisriided", [{"Talvejakid", id}, ...]}, {"Kleidid ja seelikud", [{"Kleidid ja seelikud", id}]}, ...]`.
  Families without children are leaves themselves and form a one-option group. Audience roots
  other than the default one are prefixed (`"Naised > Kleidid"`). Groups keep tree order.
  """

  alias Kirbs.Resources.Category
  alias Kirbs.Services.Categories.SeedTree

  def run do
    with {:ok, all} <- Category.list_all() do
      by_id = Map.new(all, &{&1.id, &1})
      parent_ids = all |> Enum.map(& &1.parent_id) |> MapSet.new()

      options =
        all
        |> Enum.reject(&(is_nil(&1.parent_id) or MapSet.member?(parent_ids, &1.id)))
        |> Enum.map(&{group(&1, by_id), &1})
        |> Enum.group_by(fn {group, _leaf} -> group.label end, fn {group, leaf} ->
          {group, leaf}
        end)
        |> Enum.sort_by(fn {_label, [{group, _} | _]} -> group.order end)
        |> Enum.map(fn {label, entries} ->
          {label, Enum.map(entries, fn {_group, leaf} -> {leaf.name_et, leaf.id} end)}
        end)

      {:ok, options}
    end
  end

  # The family is the node directly below the root (the leaf itself for a leaf family).
  defp group(leaf, by_id) do
    parent = Map.fetch!(by_id, leaf.parent_id)

    {family, root} =
      if parent.parent_id, do: {parent, Map.fetch!(by_id, parent.parent_id)}, else: {leaf, parent}

    label =
      if root.slug == SeedTree.default_root(),
        do: family.name_et,
        else: root.name_et <> " > " <> family.name_et

    %{label: label, order: {root.position, family.position}}
  end
end
