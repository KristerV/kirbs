defmodule Kirbs.Resources.Item.Changes.SyncExtraCategories do
  @moduledoc """
  Keeps the extra categories (`ItemCategory`) of an item consistent.

  With an `extra_category_ids` argument the set of extras is replaced, in the action's
  transaction. Rules: every extra is a leaf (has a parent, no children), differs from the
  primary `category_id`, and appears once. Without the argument the extras stay as they are,
  except that an extra equal to a newly set primary is dropped.
  """
  use Ash.Resource.Change

  alias Kirbs.Resources.{Category, ItemCategory}

  @impl true
  def change(changeset, _opts, _context) do
    primary = Ash.Changeset.get_attribute(changeset, :category_id)

    case Ash.Changeset.get_argument(changeset, :extra_category_ids) do
      nil ->
        Ash.Changeset.after_action(changeset, fn _cs, item -> drop_primary(item, primary) end)

      ids ->
        case validate(ids, primary) do
          :ok ->
            Ash.Changeset.after_action(changeset, fn _cs, item -> replace(item, ids) end)

          {:error, message} ->
            Ash.Changeset.add_error(changeset, field: :extra_category_ids, message: message)
        end
    end
  end

  @doc "Ids of the extra categories the item will have after this changeset (primary excluded)."
  def effective_ids(changeset) do
    primary = Ash.Changeset.get_attribute(changeset, :category_id)

    ids =
      case Ash.Changeset.get_argument(changeset, :extra_category_ids) do
        nil -> stored_ids(changeset.data)
        ids -> ids
      end

    Enum.reject(ids, &(&1 == primary))
  end

  defp stored_ids(%{__meta__: %{state: :loaded}, id: id}),
    do: id |> ItemCategory.list_by_item!() |> Enum.map(& &1.category_id)

  defp stored_ids(_), do: []

  defp validate(ids, primary) do
    leaves = leaf_ids()

    cond do
      length(Enum.uniq(ids)) != length(ids) ->
        {:error, "duplicate extra categories"}

      primary in ids ->
        {:error, "extra category must differ from the primary category"}

      Enum.any?(ids, &(not MapSet.member?(leaves, &1))) ->
        {:error, "extra categories must be leaves"}

      true ->
        :ok
    end
  end

  defp leaf_ids do
    all = Category.list_all!()
    parent_ids = all |> Enum.map(& &1.parent_id) |> MapSet.new()

    all
    |> Enum.reject(&(is_nil(&1.parent_id) or MapSet.member?(parent_ids, &1.id)))
    |> MapSet.new(& &1.id)
  end

  defp replace(item, ids) do
    existing = ItemCategory.list_by_item!(item.id)

    for row <- existing, row.category_id not in ids, do: ItemCategory.destroy!(row)

    present = MapSet.new(existing, & &1.category_id)

    for id <- ids,
        not MapSet.member?(present, id),
        do: ItemCategory.create!(%{item_id: item.id, category_id: id})

    {:ok, item}
  end

  defp drop_primary(item, nil), do: {:ok, item}

  defp drop_primary(item, primary) do
    for row <- ItemCategory.list_by_item!(item.id),
        row.category_id == primary,
        do: ItemCategory.destroy!(row)

    {:ok, item}
  end
end
