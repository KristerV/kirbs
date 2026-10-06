defmodule KirbsWeb.Shop.CategoryTree do
  @moduledoc """
  In-memory view of the category tree for the storefront (breadcrumbs, URL paths,
  subcategory navigation, rolled-up counts). Build once from `Category.list_all!/0`.

  Category slugs are prefixed by their path (`lapsed-poisid-pusid`), so the public URL
  `/k/lapsed/poisid/pusid` is derived by stripping each parent's slug prefix.
  """

  defstruct by_id: %{}, by_slug: %{}, children: %{}

  def build(categories) do
    %__MODULE__{
      by_id: Map.new(categories, &{&1.id, &1}),
      by_slug: Map.new(categories, &{&1.slug, &1}),
      children: Enum.group_by(categories, & &1.parent_id)
    }
  end

  def get_by_slug(%__MODULE__{by_slug: by_slug}, slug), do: Map.get(by_slug, slug)

  def get(%__MODULE__{by_id: by_id}, id), do: Map.get(by_id, id)

  def roots(%__MODULE__{children: children}), do: Map.get(children, nil, [])

  def children(%__MODULE__{children: children}, %{id: id}), do: Map.get(children, id, [])

  @doc "Chain from root to the category itself."
  def ancestors(%__MODULE__{}, %{parent_id: nil} = category), do: [category]

  def ancestors(%__MODULE__{} = tree, category) do
    case get(tree, category.parent_id) do
      nil -> [category]
      parent -> ancestors(tree, parent) ++ [category]
    end
  end

  @doc "URL path segments, e.g. `[\"lapsed\", \"poisid\", \"pusid\"]`."
  def segments(%__MODULE__{} = tree, category) do
    tree
    |> ancestors(category)
    |> Enum.reduce({[], nil}, fn node, {segments, parent} ->
      segment =
        case parent do
          nil -> node.slug
          parent -> String.replace_prefix(node.slug, parent.slug <> "-", "")
        end

      {[segment | segments], node}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  @doc "Category for URL path segments (`[\"lapsed\", \"poisid\"]`), or nil."
  def get_by_segments(%__MODULE__{} = tree, segments) when is_list(segments) do
    get_by_slug(tree, Enum.join(segments, "-"))
  end

  @doc "Counts per category id rolled up to every ancestor: `%{id => count}`."
  def rollup(%__MODULE__{} = tree, counts) do
    Enum.reduce(counts, %{}, fn {category_id, count}, acc ->
      case get(tree, category_id) do
        nil ->
          acc

        category ->
          tree
          |> ancestors(category)
          |> Enum.reduce(acc, fn node, acc -> Map.update(acc, node.id, count, &(&1 + count)) end)
      end
    end)
  end
end
