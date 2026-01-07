defmodule Kirbs.YagaTaxonomy do
  @moduledoc """
  Static Yaga taxonomy data compiled at build time.

  Provides lookup functions to map between human-readable names and Yaga IDs.
  Data is compiled into the BEAM file for optimal performance and release compatibility.
  """

  # Load data from .exs files at compile time
  # These paths are relative to project root during compilation
  # In releases, priv/ is automatically included and accessible via :code.priv_dir/1
  @external_resource Path.expand("priv/data/yaga_brand.exs")
  @external_resource Path.expand("priv/data/yaga_category.exs")
  @external_resource Path.expand("priv/data/yaga_color.exs")
  @external_resource Path.expand("priv/data/yaga_material.exs")
  @external_resource Path.expand("priv/data/yaga_condition.exs")
  @external_resource Path.expand("priv/data/yaga_size.exs")

  @brands Code.eval_file(Path.expand("priv/data/yaga_brand.exs")) |> elem(0)
  @categories Code.eval_file(Path.expand("priv/data/yaga_category.exs")) |> elem(0)
  @colors Code.eval_file(Path.expand("priv/data/yaga_color.exs")) |> elem(0)
  @materials Code.eval_file(Path.expand("priv/data/yaga_material.exs")) |> elem(0)
  @conditions Code.eval_file(Path.expand("priv/data/yaga_condition.exs")) |> elem(0)
  @sizes Code.eval_file(Path.expand("priv/data/yaga_size.exs")) |> elem(0)

  # Create lookup maps for fast access
  @brand_name_to_id Map.new(@brands, fn item -> {String.downcase(item.name), item.yaga_id} end)
  @brand_id_to_name Map.new(@brands, fn item -> {item.yaga_id, item.name} end)

  @category_name_to_id Map.new(@categories, fn item ->
                         {String.downcase(item.name), item.yaga_id}
                       end)
  @category_id_to_name Map.new(@categories, fn item -> {item.yaga_id, item.name} end)

  @color_name_to_id Map.new(@colors, fn item -> {String.downcase(item.name), item.yaga_id} end)
  @color_id_to_name Map.new(@colors, fn item -> {item.yaga_id, item.name} end)

  @material_name_to_id Map.new(@materials, fn item ->
                         {String.downcase(item.name), item.yaga_id}
                       end)
  @material_id_to_name Map.new(@materials, fn item -> {item.yaga_id, item.name} end)

  @condition_name_to_id Map.new(@conditions, fn item ->
                          {String.downcase(item.name), item.yaga_id}
                        end)
  @condition_id_to_name Map.new(@conditions, fn item -> {item.yaga_id, item.name} end)

  # Public API - Get all items

  @doc "Returns all brands as list of maps with yaga_id, name, name_en, parent_id"
  def all_brands, do: @brands

  @doc "Returns all categories as list of maps"
  def all_categories, do: @categories

  @doc "Returns all colors as list of maps"
  def all_colors, do: @colors

  @doc "Returns all materials as list of maps"
  def all_materials, do: @materials

  @doc "Returns all conditions as list of maps"
  def all_conditions, do: @conditions

  @doc "Returns all sizes as list of maps"
  def all_sizes, do: @sizes

  @doc "Returns only kids categories (under parent_id 3 'Lastele' or containing 'laste')"
  def kids_categories do
    @categories
    |> Enum.filter(fn cat ->
      # Category 3 is "Lastele", 438 is "Riided" under Lastele
      cat.parent_id == 3 or cat.parent_id == 438 or cat.yaga_id == 3 or cat.yaga_id == 438 or
        String.contains?(String.downcase(cat.name), "laste")
    end)
  end

  # Public API - Name to ID lookups

  @doc "Looks up brand ID by name (case-insensitive). Returns nil if not found."
  def brand_to_id(nil), do: nil

  def brand_to_id(name) when is_binary(name) do
    Map.get(@brand_name_to_id, String.downcase(name))
  end

  @doc "Looks up category ID by name (case-insensitive). Returns nil if not found."
  def category_to_id(nil), do: nil

  def category_to_id(name) when is_binary(name) do
    Map.get(@category_name_to_id, String.downcase(name))
  end

  @doc "Looks up color ID by name (case-insensitive). Returns nil if not found."
  def color_to_id(nil), do: nil

  def color_to_id(name) when is_binary(name) do
    Map.get(@color_name_to_id, String.downcase(name))
  end

  @doc "Looks up material ID by name (case-insensitive). Returns nil if not found."
  def material_to_id(nil), do: nil

  def material_to_id(name) when is_binary(name) do
    Map.get(@material_name_to_id, String.downcase(name))
  end

  @doc "Looks up condition ID by name (case-insensitive). Returns nil if not found."
  def condition_to_id(nil), do: nil

  def condition_to_id(name) when is_binary(name) do
    Map.get(@condition_name_to_id, String.downcase(name))
  end

  @doc """
  Converts array of color names to array of Yaga IDs.
  Skips any names that can't be mapped.

  ## Examples
      iex> colors_to_ids(["Punane", "Sinine"])
      [1, 3]

      iex> colors_to_ids(["unknown"])
      []
  """
  def colors_to_ids(nil), do: []

  def colors_to_ids(names) when is_list(names) do
    names
    |> Enum.map(&color_to_id/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.take(2)
  end

  @doc """
  Converts array of material names to array of Yaga IDs.
  Skips any names that can't be mapped.
  """
  def materials_to_ids(nil), do: []

  def materials_to_ids(names) when is_list(names) do
    names
    |> Enum.map(&material_to_id/1)
    |> Enum.reject(&is_nil/1)
  end

  # Public API - ID to name lookups (for display)

  @doc "Looks up brand name by Yaga ID. Returns nil if not found."
  def brand_name(nil), do: nil

  def brand_name(yaga_id) when is_integer(yaga_id) do
    Map.get(@brand_id_to_name, yaga_id)
  end

  @doc "Looks up category name by Yaga ID. Returns nil if not found."
  def category_name(nil), do: nil

  def category_name(yaga_id) when is_integer(yaga_id) do
    Map.get(@category_id_to_name, yaga_id)
  end

  @doc "Looks up color name by Yaga ID. Returns nil if not found."
  def color_name(nil), do: nil

  def color_name(yaga_id) when is_integer(yaga_id) do
    Map.get(@color_id_to_name, yaga_id)
  end

  @doc "Looks up material name by Yaga ID. Returns nil if not found."
  def material_name(nil), do: nil

  def material_name(yaga_id) when is_integer(yaga_id) do
    Map.get(@material_id_to_name, yaga_id)
  end

  @doc "Looks up condition name by Yaga ID. Returns nil if not found."
  def condition_name(nil), do: nil

  def condition_name(yaga_id) when is_integer(yaga_id) do
    Map.get(@condition_id_to_name, yaga_id)
  end

  # Helper for building category paths (hierarchical display)

  @doc """
  Builds full category path string like "Parent > Child > Grandchild".

  ## Examples
      iex> category_path(665)
      "Parent > Õppematerjalid"
  """
  def category_path(nil), do: nil

  def category_path(yaga_id) when is_integer(yaga_id) do
    case Enum.find(@categories, &(&1.yaga_id == yaga_id)) do
      nil -> nil
      category -> build_category_path(category, [])
    end
  end

  defp build_category_path(category, acc) do
    acc = [category.name | acc]

    case category.parent_id do
      nil ->
        Enum.join(acc, " > ")

      parent_id ->
        case Enum.find(@categories, &(&1.yaga_id == parent_id)) do
          nil -> Enum.join(acc, " > ")
          parent -> build_category_path(parent, acc)
        end
    end
  end
end
