defmodule Kirbs.Services.PhotoCapture do
  @moduledoc """
  Service for capturing and saving photos for bags and items.
  Saves photos to disk and creates Image records.
  """

  def run(%{type: :bag, photos: photos}) do
    with {:ok, bag} <- create_bag(),
         {:ok, bag} <- save_photos(bag, :bag, photos, false) do
      {:ok, bag}
    end
  end

  def run(%{type: :item, bag_id: bag_id, photos: photos, label_photos: label_photos}) do
    with {:ok, item} <- create_item(bag_id),
         {:ok, item} <- save_photos(item, :item, photos, false),
         {:ok, item} <- save_photos(item, :item, label_photos, true) do
      {:ok, item}
    end
  end

  defp create_bag do
    Kirbs.Resources.Bag.create(%{})
  end

  defp create_item(bag_id) do
    Kirbs.Resources.Item.create(%{bag_id: bag_id})
  end

  defp save_photos(record, type, photos, is_label) do
    # Skip if no photos
    if Enum.empty?(photos) do
      {:ok, record}
    else
      upload_dir = get_upload_dir()
      File.mkdir_p!(upload_dir)

      # Get current max order for this record
      base_order = get_max_order(record, type)

      photo_results =
        photos
        |> Enum.with_index()
        |> Enum.map(fn {photo, index} ->
          save_photo(record, type, photo, base_order + index, upload_dir, is_label)
        end)

      case Enum.find(photo_results, &match?({:error, _}, &1)) do
        {:error, reason} -> {:error, reason}
        nil -> {:ok, record}
      end
    end
  end

  defp get_max_order(record, :bag) do
    case Ash.load(record, :images) do
      {:ok, loaded} -> length(loaded.images)
      _ -> 0
    end
  end

  defp get_max_order(record, :item) do
    case Ash.load(record, :images) do
      {:ok, loaded} -> length(loaded.images)
      _ -> 0
    end
  end

  defp save_photo(record, type, photo_binary, index, upload_dir, is_label) do
    timestamp = System.system_time(:millisecond)
    filename = "#{record.id}_#{timestamp}_#{index}.jpg"
    file_path = Path.join(upload_dir, filename)

    case File.write(file_path, photo_binary) do
      :ok ->
        params = %{
          path: filename,
          order: index,
          is_label: is_label
        }

        params =
          case type do
            :bag -> Map.put(params, :bag_id, record.id)
            :item -> Map.put(params, :item_id, record.id)
          end

        Kirbs.Resources.Image.create(params)

      {:error, reason} ->
        {:error, "Failed to save photo: #{inspect(reason)}"}
    end
  end

  defp get_upload_dir do
    Application.get_env(:kirbs, :image_upload_dir, "/tmp/kirbs_uploads")
  end
end
