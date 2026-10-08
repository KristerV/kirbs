defmodule Kirbs.Services.Categories.RenameJakidToJoped do
  @moduledoc """
  One-off, idempotent rename of the category `Jakid` (`lapsed-valisriided-jakid`) to `Joped`
  (`lapsed-valisriided-joped`).

  Items and pending categorization proposals on the old leaf are re-pointed to the new one
  (`Item.update` rebuilds `search_text`), then the old category and its Yaga mapping are deleted
  once nothing references them. Requires the new tree to be seeded (`SeedTree`).
  """

  alias Kirbs.Resources.{CategorizationProposal, Category, Item, YagaCategoryMapping}

  @old "lapsed-valisriided-jakid"
  @new "lapsed-valisriided-joped"

  @doc "Old shop leaf path (relative to the default root, `-` joined) => new leaf path."
  def redirects, do: %{"valisriided-jakid" => "valisriided-joped"}

  def run do
    with {:ok, all} <- Category.list_all(),
         {:ok, target} <- target(all),
         {:ok, moved} <- move(Enum.find(all, &(&1.slug == @old)), target),
         {:ok, deleted} <- delete_old(Enum.find(all, &(&1.slug == @old))) do
      {:ok, Map.put(moved, :deleted_categories, deleted)}
    end
  end

  defp target(all) do
    case Enum.find(all, &(&1.slug == @new)) do
      nil -> {:error, "New leaf #{@new} missing, run SeedTree first"}
      category -> {:ok, category}
    end
  end

  defp move(nil, _target), do: {:ok, %{items_moved: 0, proposals_moved: 0}}

  defp move(old, target) do
    with {:ok, items} <- Item.list_by_category(old.id),
         :ok <- update_all(items, &Item.update/2, target),
         {:ok, proposals} <- CategorizationProposal.list_by_category(old.id),
         :ok <- update_all(proposals, &CategorizationProposal.update/2, target) do
      {:ok, %{items_moved: length(items), proposals_moved: length(proposals)}}
    end
  end

  defp update_all(records, update, target) do
    Enum.reduce_while(records, :ok, fn record, :ok ->
      case update.(record, %{category_id: target.id}) do
        {:ok, _} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp delete_old(nil), do: {:ok, []}

  defp delete_old(old) do
    with {:ok, []} <- Item.list_by_category(old.id),
         {:ok, []} <- CategorizationProposal.list_by_category(old.id),
         :ok <- destroy_mapping(old),
         :ok <- Category.destroy(old) do
      {:ok, [old.slug]}
    else
      {:ok, [_ | _]} -> {:ok, []}
      error -> error
    end
  end

  defp destroy_mapping(category) do
    case YagaCategoryMapping.get_by_category(category.id, not_found_error?: false) do
      {:ok, nil} -> :ok
      {:ok, mapping} -> YagaCategoryMapping.destroy(mapping)
      error -> error
    end
  end
end
