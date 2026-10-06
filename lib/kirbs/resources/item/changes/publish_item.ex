defmodule Kirbs.Resources.Item.Changes.PublishItem do
  @moduledoc "Sets `published_at` and a unique public `slug` (if missing) so the item appears in the shop."
  use Ash.Resource.Change

  alias Kirbs.Resources.Category

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> set_published_at()
    |> set_slug()
  end

  defp set_published_at(changeset) do
    case changeset.data.published_at do
      nil -> Ash.Changeset.force_change_attribute(changeset, :published_at, DateTime.utc_now())
      _ -> changeset
    end
  end

  defp set_slug(%{data: %{slug: slug}} = changeset) when is_binary(slug), do: changeset

  defp set_slug(%{data: item} = changeset) do
    category =
      case item.category_id && Ash.get(Category, item.category_id, error?: false) do
        {:ok, %{name_et: name}} -> name
        _ -> nil
      end

    short_id = item.id |> String.replace("-", "") |> String.slice(0, 8)

    base =
      [category, item.brand, item.size]
      |> Enum.reject(&(is_nil(&1) or &1 == ""))
      |> Enum.join(" ")
      |> Kirbs.Slug.slugify()

    slug = if base == "", do: short_id, else: "#{base}-#{short_id}"
    Ash.Changeset.force_change_attribute(changeset, :slug, slug)
  end
end
