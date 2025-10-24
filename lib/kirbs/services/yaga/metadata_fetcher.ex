defmodule Kirbs.Services.Yaga.MetadataFetcher do
  @moduledoc """
  Fetches metadata from Yaga public APIs and stores in YagaMetadata resource.
  Fetches: brands, categories, colors, materials, conditions
  """

  alias Kirbs.Resources.YagaMetadata

  @base_url "https://www.yaga.ee/api"

  def run do
    with {:ok, brand_count} <- fetch_brands(),
         {:ok, category_count} <- fetch_categories(),
         {:ok, color_count} <- fetch_colors(),
         {:ok, material_count} <- fetch_materials(),
         {:ok, condition_count} <- fetch_conditions() do
      total = brand_count + category_count + color_count + material_count + condition_count
      {:ok, total}
    end
  end

  defp fetch_brands do
    with {:ok, response} <- http_get("/brand/?groupedFlat=true&sortOtherAlphabetically=true"),
         {:ok, brands} <- parse_brands(response) do
      count = Enum.reduce(brands, 0, fn brand, acc ->
        case YagaMetadata.create(%{
               metadata_type: :brand,
               yaga_id: brand.id,
               name: brand.name,
               name_en: brand.name_en,
               metadata_json: brand.raw
             }) do
          {:ok, _} -> acc + 1
          {:error, _} -> acc
        end
      end)

      {:ok, count}
    end
  end

  defp fetch_categories do
    with {:ok, response} <- http_get("/category"),
         {:ok, categories} <- parse_categories(response) do
      count = Enum.reduce(categories, 0, fn category, acc ->
        case YagaMetadata.create(%{
               metadata_type: :category,
               yaga_id: category.id,
               name: category.name,
               name_en: category.name_en,
               parent_id: category.parent_id,
               metadata_json: category.raw
             }) do
          {:ok, _} -> acc + 1
          {:error, _} -> acc
        end
      end)

      {:ok, count}
    end
  end

  defp fetch_colors do
    with {:ok, response} <- http_get("/color"),
         {:ok, colors} <- parse_generic(response) do
      count = Enum.reduce(colors, 0, fn color, acc ->
        case YagaMetadata.create(%{
               metadata_type: :color,
               yaga_id: color.id,
               name: color.name,
               name_en: color.name_en,
               metadata_json: color.raw
             }) do
          {:ok, _} -> acc + 1
          {:error, _} -> acc
        end
      end)

      {:ok, count}
    end
  end

  defp fetch_materials do
    with {:ok, response} <- http_get("/material"),
         {:ok, materials} <- parse_generic(response) do
      count = Enum.reduce(materials, 0, fn material, acc ->
        case YagaMetadata.create(%{
               metadata_type: :material,
               yaga_id: material.id,
               name: material.name,
               name_en: material.name_en,
               metadata_json: material.raw
             }) do
          {:ok, _} -> acc + 1
          {:error, _} -> acc
        end
      end)

      {:ok, count}
    end
  end

  defp fetch_conditions do
    with {:ok, response} <- http_get("/condition"),
         {:ok, conditions} <- parse_generic(response) do
      count = Enum.reduce(conditions, 0, fn condition, acc ->
        case YagaMetadata.create(%{
               metadata_type: :condition,
               yaga_id: condition.id,
               name: condition.name,
               name_en: condition.name_en,
               metadata_json: condition.raw
             }) do
          {:ok, _} -> acc + 1
          {:error, _} -> acc
        end
      end)

      {:ok, count}
    end
  end

  defp http_get(path) do
    url = @base_url <> path

    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_brands(body) when is_map(body) do
    # Brands API returns nested structure with groups
    brands =
      body
      |> Map.get("data", [])
      |> Enum.flat_map(fn group ->
        group
        |> Map.get("brands", [])
        |> Enum.map(fn brand ->
          %{
            id: brand["id"],
            name: brand["name"],
            name_en: brand["nameEn"],
            raw: brand
          }
        end)
      end)

    {:ok, brands}
  end

  defp parse_brands(_), do: {:error, "Invalid brands response"}

  defp parse_categories(body) when is_map(body) do
    categories =
      body
      |> Map.get("data", [])
      |> Enum.map(fn cat ->
        %{
          id: cat["id"],
          name: cat["name"],
          name_en: cat["nameEn"],
          parent_id: cat["parentId"],
          raw: cat
        }
      end)

    {:ok, categories}
  end

  defp parse_categories(_), do: {:error, "Invalid categories response"}

  defp parse_generic(body) when is_map(body) do
    items =
      body
      |> Map.get("data", [])
      |> Enum.map(fn item ->
        %{
          id: item["id"],
          name: item["name"],
          name_en: item["nameEn"],
          raw: item
        }
      end)

    {:ok, items}
  end

  defp parse_generic(_), do: {:error, "Invalid response"}
end
