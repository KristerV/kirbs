defmodule Kirbs.Resources.Item.Changes.BuildSearchText do
  @moduledoc "Builds the denormalized `search_text` from brand, size, description, category etc."
  use Ash.Resource.Change

  alias Kirbs.Resources.Category

  @impl true
  def change(changeset, _opts, _context) do
    category_name = category_name(Ash.Changeset.get_attribute(changeset, :category_id))

    parts =
      [
        Ash.Changeset.get_attribute(changeset, :brand),
        Ash.Changeset.get_attribute(changeset, :size),
        category_name,
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

  defp category_name(nil), do: nil

  defp category_name(id) do
    case Ash.get(Category, id, error?: false) do
      {:ok, %{name_et: name}} -> name
      _ -> nil
    end
  end
end
