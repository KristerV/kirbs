defmodule Kirbs.Services.PhotoCapture do
  @moduledoc """
  Service for capturing and saving photos for bags and items.
  Saves photos to disk and creates Image records.
  """

  def run(%{type: :bag, photos: photos}) do
    with {:ok, bag} <- create_bag(),
         {:ok, bag} <- save_photos(bag, :bag, photos) do
      {:ok, bag}
    end
  end

  def run(%{type: :item, bag_id: bag_id, photos: photos}) do
    with {:ok, item} <- create_item(bag_id),
         {:ok, item} <- save_photos(item, :item, photos) do
      {:ok, item}
    end
  end

  defp create_bag do
    Kirbs.Resources.Bag.create(%{})
  end

  defp create_item(bag_id) do
    Kirbs.Resources.Item.create(%{bag_id: bag_id})
  end

  defp save_photos(record, type, photos) do
    upload_dir = get_upload_dir()
    File.mkdir_p!(upload_dir)

    photo_results =
      photos
      |> Enum.with_index()
      |> Enum.map(fn {photo, index} ->
        save_photo(record, type, photo, index, upload_dir)
      end)

    case Enum.find(photo_results, &match?({:error, _}, &1)) do
      {:error, reason} -> {:error, reason}
      nil -> {:ok, record}
    end
  end

  defp save_photo(record, type, photo_binary, index, upload_dir) do
    timestamp = System.system_time(:millisecond)
    filename = "#{record.id}_#{timestamp}_#{index}.jpg"
    file_path = Path.join(upload_dir, filename)

    case File.write(file_path, photo_binary) do
      :ok ->
        params = %{
          path: filename,
          order: index
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
