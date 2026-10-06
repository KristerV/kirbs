defmodule Kirbs.Services.Categories.GroupedLeafOptions do
  @moduledoc """
  Leaf categories grouped by "Root > Group", shaped for a grouped `<select>`:
  `[{"Lapsed > Beebid", [{"Talvejakid", id}, ...]}, ...]`.
  """

  alias Kirbs.Resources.Category

  def run do
    with {:ok, all} <- Category.list_all() do
      by_id = Map.new(all, &{&1.id, &1})
      parent_ids = all |> Enum.map(& &1.parent_id) |> MapSet.new()

      options =
        all
        |> Enum.reject(&(is_nil(&1.parent_id) or MapSet.member?(parent_ids, &1.id)))
        |> Enum.group_by(&group_label(&1, by_id))
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.map(fn {label, leaves} -> {label, Enum.map(leaves, &{&1.name_et, &1.id})} end)

      {:ok, options}
    end
  end

  defp group_label(leaf, by_id) do
    group = Map.get(by_id, leaf.parent_id)
    root = group && group.parent_id && Map.get(by_id, group.parent_id)

    [root, group]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join(" > ", & &1.name_et)
  end
end
