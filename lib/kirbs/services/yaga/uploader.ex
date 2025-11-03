defmodule Kirbs.Services.Yaga.Uploader do
  @moduledoc """
  Uploads item to yaga.ee marketplace.
  Multi-step process: create draft → upload photos → publish.
  """

  alias Kirbs.Resources.Item
  alias Kirbs.Services.Yaga.Auth
  alias Kirbs.YagaTaxonomy

  @base_url "https://www.yaga.ee"

  def run(item_id) do
    with {:ok, item} <- load_and_validate(item_id),
         {:ok, jwt} <- Auth.run(),
         {:ok, product} <- create_draft(jwt),
         {:ok, product} <- upload_photos(jwt, product, item),
         {:ok, product} <- publish_product(jwt, product, item),
         {:ok, item} <- mark_uploaded(item, product) do
      {:ok, item}
    else
      {:error, reason} = error ->
        mark_failed(item_id, reason)
        error
    end
  end

  defp load_and_validate(item_id) do
    case Ash.get(Item, item_id, load: [:images, :bag]) do
      {:ok, nil} ->
        {:error, "Item not found"}

      {:ok, item} ->
        validate_item(item)

      {:error, error} ->
        {:error, "Failed to load item: #{inspect(error)}"}
    end
  end

  defp validate_item(item) do
    errors = []

    # Filter out label images - only count actual item photos
    item_images = Enum.reject(item.images || [], & &1.is_label)

    errors =
      if Enum.empty?(item_images) do
        ["at least 1 photo required" | errors]
      else
        errors
      end

    errors =
      if is_nil(YagaTaxonomy.category_to_id(item.suggested_category)) do
        ["valid category required" | errors]
      else
        errors
      end

    errors =
      if is_nil(YagaTaxonomy.condition_to_id(item.quality)) do
        ["valid condition required" | errors]
      else
        errors
      end

    errors =
      if is_nil(item.listed_price) or Decimal.compare(item.listed_price, Decimal.new(0)) != :gt do
        ["listed_price must be > 0" | errors]
      else
        errors
      end

    errors =
      if is_nil(item.description) or String.trim(item.description) == "" do
        ["description required" | errors]
      else
        errors
      end

    case errors do
      [] -> {:ok, item}
      _ -> {:error, "Missing required fields: #{Enum.join(Enum.reverse(errors), ", ")}"}
    end
  end

  defp create_draft(jwt) do
    headers = [
      {"authorization", "Bearer #{jwt}"},
      {"content-type", "application/json"},
      {"x-country", "EE"},
      {"x-language", "et"}
    ]

    case Req.post("#{@base_url}/api/product", json: %{currency: "€"}, headers: headers) do
      {:ok, %{status: 200, body: %{"status" => "success", "data" => data}}} ->
        {:ok, %{id: data["id"], slug: data["slug"]}}

      {:ok, %{status: status, body: body}} ->
        {:error, "Failed to create draft: HTTP #{status} - #{inspect(body)}"}

      {:error, error} ->
        {:error, "Network error creating draft: #{inspect(error)}"}
    end
  end

  defp upload_photos(jwt, product, item) do
    # Filter out label images - only upload actual item photos
    images =
      item.images
      |> Enum.reject(& &1.is_label)
      |> Enum.sort_by(& &1.order)

    with {:ok, file_names} <- upload_photos_to_s3(jwt, product, images),
         {:ok, _} <- attach_all_images(jwt, product.id, file_names) do
      {:ok, product}
    end
  end

  defp upload_photos_to_s3(jwt, product, images) do
    upload_photos_recursive(jwt, product, images, [])
  end

  defp upload_photos_recursive(_jwt, _product, [], uploaded) do
    {:ok, Enum.reverse(uploaded)}
  end

  defp upload_photos_recursive(jwt, product, [image | rest], uploaded) do
    with {:ok, file_name} <- upload_single_photo(jwt, product, image) do
      upload_photos_recursive(jwt, product, rest, [file_name | uploaded])
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp upload_single_photo(jwt, product, image) do
    with {:ok, upload_url, file_name} <- get_upload_url(jwt, product.slug, image),
         {:ok, _} <- upload_to_s3(upload_url, image) do
      {:ok, file_name}
    end
  end

  defp get_upload_url(jwt, slug, image) do
    ext = Path.extname(image.path) |> String.trim_leading(".")
    timestamp = System.system_time(:millisecond)

    headers = [
      {"authorization", "Bearer #{jwt}"},
      {"x-country", "EE"},
      {"x-language", "et"}
    ]

    url = "#{@base_url}/api/product/uploadurl/?slug=#{slug}&type=#{ext}&timestamp=#{timestamp}"

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: %{"status" => "success", "data" => data}}} ->
        {:ok, data["url"], data["fileName"]}

      {:ok, %{status: status, body: body}} ->
        {:error, "Failed to get upload URL: HTTP #{status} - #{inspect(body)}"}

      {:error, error} ->
        {:error, "Network error getting upload URL: #{inspect(error)}"}
    end
  end

  defp upload_to_s3(url, image) do
    # Get full path to image file
    upload_dir = Application.get_env(:kirbs, :image_upload_dir)
    full_path = Path.join(upload_dir, image.path)

    case File.read(full_path) do
      {:ok, binary_data} ->
        content_type =
          case Path.extname(image.path) do
            ".jpg" -> "image/jpeg"
            ".jpeg" -> "image/jpeg"
            ".png" -> "image/png"
            _ -> "image/jpeg"
          end

        headers = [{"content-type", content_type}]

        case Req.put(url, body: binary_data, headers: headers) do
          {:ok, %{status: 200}} ->
            {:ok, :uploaded}

          {:ok, %{status: status}} ->
            {:error, "S3 upload failed: HTTP #{status}"}

          {:error, error} ->
            {:error, "Network error uploading to S3: #{inspect(error)}"}
        end

      {:error, reason} ->
        {:error, "Failed to read image file #{image.path}: #{inspect(reason)}"}
    end
  end

  defp attach_all_images(jwt, product_id, file_names) do
    headers = [
      {"authorization", "Bearer #{jwt}"},
      {"content-type", "application/json"},
      {"x-country", "EE"},
      {"x-language", "et"}
    ]

    images = Enum.map(file_names, fn file_name -> %{fileName: file_name} end)
    body = %{images: images}

    case Req.post("#{@base_url}/api/product/#{product_id}/images",
           json: body,
           headers: headers
         ) do
      {:ok, %{status: 200, body: %{"status" => "success"}}} ->
        {:ok, :attached}

      {:ok, %{status: status, body: body}} ->
        {:error, "Failed to attach images: HTTP #{status} - #{inspect(body)}"}

      {:error, error} ->
        {:error, "Network error attaching images: #{inspect(error)}"}
    end
  end

  defp publish_product(jwt, product, item) do
    headers = [
      {"authorization", "Bearer #{jwt}"},
      {"content-type", "application/json"},
      {"x-country", "EE"},
      {"x-language", "et"}
    ]

    body = build_product_body(item)

    case Req.patch("#{@base_url}/api/product/#{product.id}", json: body, headers: headers) do
      {:ok, %{status: 200, body: %{"status" => "success", "data" => data}}} ->
        {:ok, %{product | id: data["id"], slug: data["slug"]}}

      {:ok, %{status: status, body: body}} ->
        {:error, "Failed to publish product: HTTP #{status} - #{inspect(body)}"}

      {:error, error} ->
        {:error, "Network error publishing product: #{inspect(error)}"}
    end
  end

  defp build_product_body(item) do
    price = item.listed_price |> Decimal.to_float() |> trunc()

    category_id = YagaTaxonomy.category_to_id(item.suggested_category)
    condition_id = YagaTaxonomy.condition_to_id(item.quality)
    brand_id = YagaTaxonomy.brand_to_id(item.brand)
    colors_id_map = YagaTaxonomy.colors_to_ids(item.colors)
    materials_id_map = YagaTaxonomy.materials_to_ids(item.materials)

    description =
      if item.bag && item.bag.number do
        bag_label = "B#{String.pad_leading(Integer.to_string(item.bag.number), 4, "0")}"
        "#{item.description}\n\n#{bag_label}"
      else
        item.description
      end

    body = %{
      price: price,
      quantity: 1,
      category_id: category_id,
      condition_id: condition_id,
      description: description,
      location: "Tallinn/Harjumaa",
      address: "Saue vald",
      shipping: default_shipping(),
      status: "published"
    }

    body =
      if brand_id do
        Map.put(body, :brand_id, brand_id)
      else
        body
      end

    body =
      if colors_id_map != [] do
        Map.put(body, :colors_id_map, colors_id_map)
      else
        body
      end

    body =
      if materials_id_map != [] do
        Map.put(body, :materials_id_map, materials_id_map)
      else
        body
      end

    body =
      if item.size do
        Map.put(body, :attributes, %{size: item.size})
      else
        body
      end

    body
  end

  defp default_shipping do
    %{
      dpd: %{enabled: true, selectedPrice: "small"},
      omniva: %{enabled: true, selectedPrice: "small"},
      bundling: %{enabled: true, selectedPrice: "zero"},
      smartpost: %{enabled: true, selectedPrice: "small"},
      uponAgreement: %{enabled: false, selectedPrice: "zero"},
      fromHandToHand: %{enabled: true, selectedPrice: "zero"}
    }
  end

  defp mark_uploaded(item, product) do
    Item.update(item, %{
      status: :uploaded_to_yaga,
      yaga_id: product.id,
      yaga_slug: product.slug,
      upload_error: nil
    })
  end

  defp mark_failed(item_id, reason) do
    error_message =
      case reason do
        %{__struct__: _} -> Exception.message(reason)
        binary when is_binary(binary) -> binary
        _ -> inspect(reason)
      end

    case Ash.get(Item, item_id) do
      {:ok, item} ->
        Item.update(item, %{
          status: :upload_failed,
          upload_error: error_message
        })

      _ ->
        :ok
    end
  end
end
