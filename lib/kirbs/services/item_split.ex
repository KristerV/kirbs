defmodule Kirbs.Services.ItemSplit do
  @moduledoc """
  Service for splitting images between items.
  Creates a new item with selected images and schedules AI processing for both items.
  """

  alias Kirbs.Resources.{Item, Image}

  def run(item_id, image_ids_to_move) do
    with {:ok, item} <- load_item_with_images(item_id),
         :ok <- validate_split(item, image_ids_to_move),
         {:ok, item} <- clear_item_ai_data(item),
         {:ok, new_item} <- create_new_item(item.bag_id),
         {:ok, _} <- move_images_to_new_item(image_ids_to_move, new_item.id),
         {:ok, _} <- reorder_images(item.id),
         {:ok, _} <- reorder_images(new_item.id),
         {:ok, _} <- schedule_ai_for_item(item.id),
         {:ok, _} <- schedule_ai_for_item(new_item.id) do
      {:ok, %{original_item: item, new_item: new_item}}
    end
  end

  defp load_item_with_images(item_id) do
    case Ash.get(Item, item_id, load: [:images, :bag]) do
      {:ok, nil} -> {:error, "Item not found"}
      {:ok, item} -> {:ok, item}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_split(item, image_ids_to_move) do
    image_ids_set = MapSet.new(image_ids_to_move)
    total_images = length(item.images)
    images_to_move = MapSet.size(image_ids_set)
    images_remaining = total_images - images_to_move

    cond do
      images_to_move == 0 ->
        {:error, "Must select at least one image to move"}

      images_remaining == 0 ->
        {:error, "Must leave at least one image in the original item"}

      true ->
        :ok
    end
  end

  defp clear_item_ai_data(item) do
    Item.clear_ai_data(item)
  end

  defp create_new_item(bag_id) do
    Item.create(%{bag_id: bag_id})
  end

  defp move_images_to_new_item(image_ids, new_item_id) do
    results =
      Enum.map(image_ids, fn image_id ->
        case Ash.get(Image, image_id) do
          {:ok, image} -> Image.update(image, %{item_id: new_item_id})
          error -> error
        end
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      {:error, reason} -> {:error, reason}
      nil -> {:ok, :moved}
    end
  end

  defp reorder_images(item_id) do
    # Load all images for this item, ordered by current order
    images =
      Image.list!()
      |> Enum.filter(&(&1.item_id == item_id))
      |> Enum.sort_by(& &1.order)

    # Reorder sequentially starting from 0
    results =
      images
      |> Enum.with_index()
      |> Enum.map(fn {image, index} ->
        Image.update(image, %{order: index})
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      {:error, reason} -> {:error, reason}
      nil -> {:ok, :reordered}
    end
  end

  defp schedule_ai_for_item(item_id) do
    case %{item_id: item_id}
         |> Kirbs.Jobs.ProcessItemJob.new()
         |> Oban.insert() do
      {:ok, _job} -> {:ok, :scheduled}
      error -> error
    end
  end
end
