defmodule Kirbs.Resources.Item.Changes.BuildSearchText do
  @moduledoc """
  Builds the denormalized `search_text` from brand, size, description, the primary and extra
  category names, "veekindel" for waterproof items, etc.
  """
  use Ash.Resource.Change

  alias Kirbs.Resources.Category
  alias Kirbs.Resources.Item.Changes.SyncExtraCategories

  @impl true
  def change(changeset, _opts, _context) do
    category_names =
      [Ash.Changeset.get_attribute(changeset, :category_id) | extra_ids(changeset)]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&category_name/1)

    parts =
      [
        Ash.Changeset.get_attribute(changeset, :brand),
        Ash.Changeset.get_attribute(changeset, :size)
      ] ++
        category_names ++
        [
          if(Ash.Changeset.get_attribute(changeset, :waterproof), do: "veekindel"),
          Ash.Changeset.get_attribute(changeset, :suggested_category),
          Ash.Changeset.get_attribute(changeset, :description)
        ] ++
        List.wrap(Ash.Changeset.get_attribute(changeset, :colors)) ++
        List.wrap(Ash.Changeset.get_attribute(changeset, :materials))

    text =
      parts
      |> Enum.reject(&(is_nil(&1) or &1 == ""))
      |> Enum.join(" ")

    Ash.Changeset.force_change_attribute(
      changeset,
      :search_text,
      if(text == "", do: nil, else: text)
    )
  end

  defp extra_ids(changeset) do
    if changeset.action && changeset.action.type == :create,
      do: [],
      else: SyncExtraCategories.effective_ids(changeset)
  end

  defp category_name(id) do
    case Category.get(id) do
      {:ok, %{name_et: name}} -> name
      _ -> nil
    end
  end
end
