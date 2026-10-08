defmodule KirbsWeb.Shop.CategoryTree do
  @moduledoc """
  In-memory view of the category tree for the storefront (breadcrumbs, URL paths,
  subcategory navigation, rolled-up counts). Build once from `Category.list_all!/0`.

  Category slugs are prefixed by their path (`lapsed-valisriided-talvejakid`), so the public URL
  is derived by stripping each parent's slug prefix. Kids is the default audience: its root
  (`lapsed`) is not a level in the shop, so the URL is `/k/valisriided/talvejakid` and the
  breadcrumbs start at the family. Other audience roots keep their segment (`/k/naised/...`).
  """

  @default_root "lapsed"

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

  @doc "Slug of the default audience root, which is not shown as a level."
  def default_root, do: @default_root

  @doc "Chain from the first shown level (default audience root dropped) to the category."
  def trail(%__MODULE__{} = tree, category) do
    tree |> ancestors(category) |> Enum.reject(&(&1.slug == @default_root))
  end

  @doc "URL path segments, e.g. `[\"valisriided\", \"talvejakid\"]` (empty for the default root)."
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
    |> then(fn
      [@default_root | rest] -> rest
      segments -> segments
    end)
  end

  @doc """
  Category for URL path segments, or nil. Segments are relative to the default audience
  (`["valisriided"]` is `lapsed-valisriided`); other audiences start with their root slug
  (`["naised", "kleidid"]`). The legacy `["lapsed", ...]` form resolves too.
  """
  def get_by_segments(%__MODULE__{} = tree, segments) when is_list(segments) do
    joined = Enum.join(segments, "-")

    get_by_slug(tree, @default_root <> "-" <> joined) || get_by_slug(tree, joined)
  end

  @doc """
  Resolves a pre-type-tree URL (`["lapsed", "poisid", "pusid"]`) to the category it became:
  `{:ok, category}`, `{:ok, nil}` (everything) or `:error`.
  """
  def legacy_category(%__MODULE__{} = tree, ["lapsed", group | rest]) do
    if group in Kirbs.Services.Categories.MigrateTree.old_group_slugs() do
      case rest do
        [] -> {:ok, nil}
        [type] -> legacy_type(tree, type)
        _ -> :error
      end
    else
      legacy_season_leaf(tree, ["lapsed", group | rest])
    end
  end

  def legacy_category(tree, segments), do: legacy_season_leaf(tree, segments)

  # Season-flavoured leaves removed from the tree (`talvejakid` -> `jakid`, ...), with or without `lapsed`.
  defp legacy_season_leaf(%__MODULE__{} = tree, segments) when is_list(segments) do
    path = segments |> Enum.reject(&(&1 == "lapsed")) |> Enum.join("-")

    redirects =
      Map.merge(
        Kirbs.Services.Categories.MigrateSeasonOutOfTree.redirects(),
        Kirbs.Services.Categories.RenameJakidToJoped.redirects()
      )

    case Map.get(redirects, path) do
      nil -> :error
      new -> {:ok, get_by_slug(tree, @default_root <> "-" <> new)}
    end
  end

  defp legacy_type(tree, type) do
    case Map.get(Kirbs.Services.Categories.MigrateTree.type_map(), type) do
      nil -> :error
      slug -> {:ok, get_by_slug(tree, slug)}
    end
  end

  @doc "Audience roots with a positive rolled-up count, in tree order."
  def audiences(%__MODULE__{} = tree, rolled_counts) do
    Enum.filter(roots(tree), &(Map.get(rolled_counts, &1.id, 0) > 0))
  end

  @doc "The audience root a category belongs to (default root for nil)."
  def audience(%__MODULE__{} = tree, nil), do: get_by_slug(tree, @default_root)
  def audience(%__MODULE__{} = tree, category), do: tree |> ancestors(category) |> hd()

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
