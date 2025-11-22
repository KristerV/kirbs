defmodule Kirbs.Services.Yaga.Importer do
  @moduledoc """
  Imports products from yaga.ee into a bag.
  Parses multiple links, fetches product data, downloads images, and creates items.
  """

  alias Kirbs.Resources.{Bag, Item, Image}
  alias Kirbs.Services.Yaga.ProductFetcher

  @doc """
  Imports products from yaga.ee links into a bag.

  ## Parameters
  - bag_id: The bag ID to import items into
  - links_text: Text containing yaga.ee product URLs (one per line or comma-separated)

  ## Returns
  - {:ok, %{imported: count, errors: [error_messages]}}
  """
  def run(bag_id, links_text) do
    with {:ok, bag} <- get_bag(bag_id),
         {:ok, links} <- parse_links(links_text),
         {:ok, build_id} <- ProductFetcher.fetch_build_id() do
      results = import_all(bag, links, build_id)

      imported = Enum.count(results, &match?({:ok, _}, &1))

      errors =
        Enum.flat_map(results, fn
          {:error, reason} -> [reason]
          _ -> []
        end)

      {:ok, %{imported: imported, errors: errors}}
    end
  end

  defp get_bag(bag_id) do
    case Ash.get(Bag, bag_id) do
      {:ok, nil} -> {:error, "Bag not found"}
      {:ok, bag} -> {:ok, bag}
      {:error, error} -> {:error, "Failed to load bag: #{inspect(error)}"}
    end
  end

  defp parse_links(text) do
    links =
      text
      |> String.split(~r/[\n,]+/)
      |> Enum.map(&String.trim/1)
      |> Enum.filter(&String.contains?(&1, "yaga.ee"))
      |> Enum.uniq()

    if links == [] do
      {:error, "No valid yaga.ee links found"}
    else
      {:ok, links}
    end
  end

  defp import_all(bag, links, build_id) do
    Enum.map(links, fn link ->
      import_single(bag, link, build_id)
    end)
  end

  defp import_single(bag, link, build_id) do
    with {:ok, shop_slug, product_slug} <- ProductFetcher.parse_url(link),
         {:ok, product} <- ProductFetcher.run(shop_slug, product_slug, build_id),
         {:ok, item} <- create_item(bag, product),
         {:ok, _images} <- download_and_create_images(item, product.images) do
      {:ok, item}
    else
      {:error, reason} -> {:error, "#{link}: #{reason}"}
    end
  end

  defp create_item(bag, product) do
    attrs = %{
      bag_id: bag.id,
      description: product.description,
      listed_price: product.listed_price,
      brand: product.brand,
      quality: product.quality,
      suggested_category: product.suggested_category,
      colors: product.colors,
      materials: product.materials,
      size: product.size,
      yaga_id: product.yaga_id,
      yaga_slug: product.yaga_slug,
      status: :uploaded_to_yaga,
      created_at: product.created_at
    }

    case Item.create(attrs) do
      {:ok, item} -> {:ok, item}
      {:error, error} -> {:error, "Failed to create item: #{inspect(error)}"}
    end
  end

  defp download_and_create_images(item, images) do
    upload_dir = Application.get_env(:kirbs, :image_upload_dir)
    File.mkdir_p!(upload_dir)

    results =
      Enum.map(images, fn image_data ->
        download_and_create_image(item, image_data, upload_dir)
      end)

    errors = Enum.filter(results, &match?({:error, _}, &1))

    if errors == [] do
      {:ok, Enum.map(results, fn {:ok, img} -> img end)}
    else
      # Return success anyway, but with partial images
      {:ok,
       Enum.flat_map(results, fn
         {:ok, img} -> [img]
         _ -> []
       end)}
    end
  end

  defp download_and_create_image(item, image_data, upload_dir) do
    timestamp = System.system_time(:millisecond)
    filename = "#{item.id}_#{timestamp}_#{image_data.order}.jpg"
    file_path = Path.join(upload_dir, filename)

    with {:ok, binary} <- download_image(image_data.url),
         :ok <- File.write(file_path, binary),
         {:ok, image} <- create_image_record(item, filename, image_data.order) do
      {:ok, image}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp download_image(url) do
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, "Failed to download image: HTTP #{status}"}

      {:error, error} ->
        {:error, "Network error downloading image: #{inspect(error)}"}
    end
  end

  defp create_image_record(item, path, order) do
    case Image.create(%{
           item_id: item.id,
           path: path,
           order: order,
           is_label: false
         }) do
      {:ok, image} -> {:ok, image}
      {:error, error} -> {:error, "Failed to create image record: #{inspect(error)}"}
    end
  end
end
