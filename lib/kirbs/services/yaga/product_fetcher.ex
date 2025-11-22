defmodule Kirbs.Services.Yaga.ProductFetcher do
  @moduledoc """
  Fetches product data from yaga.ee using the Next.js API.
  """

  @base_url "https://www.yaga.ee"

  alias Kirbs.YagaTaxonomy

  @doc """
  Fetches a single product from yaga.ee.

  ## Parameters
  - shop_slug: The shop slug (e.g., "kirbs-ee")
  - product_slug: The product slug (e.g., "kglherrafro")
  - build_id: The Next.js build ID (optional, will be fetched if not provided)

  ## Returns
  - {:ok, product_map} with normalized data
  - {:error, reason}
  """
  def run(shop_slug, product_slug, build_id \\ nil) do
    with {:ok, build_id} <- ensure_build_id(build_id),
         {:ok, raw_product} <- fetch_product(shop_slug, product_slug, build_id),
         {:ok, product} <- normalize_product(raw_product) do
      {:ok, product}
    end
  end

  @doc """
  Fetches the current Next.js build ID from yaga.ee.
  """
  def fetch_build_id do
    case Req.get(@base_url) do
      {:ok, %{status: 200, body: body}} ->
        case Regex.run(~r/buildId":"([^"]+)"/, body) do
          [_, build_id] -> {:ok, build_id}
          _ -> {:error, "Could not find buildId in page"}
        end

      {:ok, %{status: status}} ->
        {:error, "Failed to fetch yaga.ee: HTTP #{status}"}

      {:error, error} ->
        {:error, "Network error: #{inspect(error)}"}
    end
  end

  @doc """
  Parses a yaga.ee product URL into shop and product slugs.

  ## Examples
      iex> parse_url("https://www.yaga.ee/kirbs-ee/toode/kglherrafro")
      {:ok, "kirbs-ee", "kglherrafro"}

      iex> parse_url("https://www.yaga.ee/kirbs-ee/toode/kglherrafro?foo=bar")
      {:ok, "kirbs-ee", "kglherrafro"}
  """
  def parse_url(url) do
    uri = URI.parse(url)

    case Regex.run(~r{^/([^/]+)/toode/([^/?]+)}, uri.path || "") do
      [_, shop_slug, product_slug] -> {:ok, shop_slug, product_slug}
      _ -> {:error, "Invalid yaga.ee product URL: #{url}"}
    end
  end

  # Private functions

  defp ensure_build_id(nil), do: fetch_build_id()
  defp ensure_build_id(build_id) when is_binary(build_id), do: {:ok, build_id}

  defp fetch_product(shop_slug, product_slug, build_id) do
    url = "#{@base_url}/_next/data/#{build_id}/#{shop_slug}/toode/#{product_slug}.json"

    params = [
      replace: true,
      "shop-slug": shop_slug,
      "product-slug": product_slug
    ]

    case Req.get(url, params: params) do
      {:ok, %{status: 200, body: body}} ->
        case get_in(body, ["pageProps", "initialProduct"]) do
          nil -> {:error, "Product not found in response"}
          product -> {:ok, product}
        end

      {:ok, %{status: 404}} ->
        {:error, "Product not found"}

      {:ok, %{status: status, body: body}} ->
        {:error, "Failed to fetch product: HTTP #{status} - #{inspect(body)}"}

      {:error, error} ->
        {:error, "Network error: #{inspect(error)}"}
    end
  end

  defp normalize_product(raw) do
    product = %{
      yaga_id: raw["id"],
      yaga_slug: raw["slug"],
      description: raw["description"],
      listed_price: raw["price"] && Decimal.new(raw["price"]),
      brand: get_brand_name(raw["brand_id"]),
      quality: get_condition_name(raw["condition_id"]),
      suggested_category: get_category_name(raw["category_id"]),
      colors: get_color_names(raw["colors"]),
      materials: get_material_names(raw["materials"]),
      size: get_in(raw, ["attributes", "size"]),
      images: normalize_images(raw["images"] || []),
      created_at: parse_datetime(raw["created_at"] || raw["createdAt"])
    }

    {:ok, product}
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp get_brand_name(nil), do: nil
  defp get_brand_name(id) when is_integer(id), do: YagaTaxonomy.brand_name(id)

  defp get_condition_name(nil), do: nil
  defp get_condition_name(id) when is_integer(id), do: YagaTaxonomy.condition_name(id)

  defp get_category_name(nil), do: nil
  defp get_category_name(id) when is_integer(id), do: YagaTaxonomy.category_name(id)

  defp get_color_names(nil), do: []

  defp get_color_names(colors) when is_list(colors) do
    Enum.map(colors, fn color -> color["name"] end)
  end

  defp get_material_names(nil), do: []

  defp get_material_names(materials) when is_list(materials) do
    Enum.map(materials, fn material -> material["name"] end)
  end

  defp normalize_images(images) do
    images
    |> Enum.with_index()
    |> Enum.map(fn {img, index} ->
      %{
        url: img["original"] || img["gallery"],
        file_name: img["fileName"] || img["file_name"],
        order: index
      }
    end)
  end
end
