defmodule Kirbs.ReviewQueue do
  @moduledoc """
  Helper functions for the unified review queue that handles both bags and items.
  """

  alias Kirbs.Resources.{Bag, Item}

  @doc """
  Finds the first thing that needs review.
  Returns {:bag, bag_id} | {:item, item_id} | nil
  """
  def find_first_review_target do
    bags = Bag.get_bags_needing_review!()

    case List.first(bags) do
      nil ->
        nil

      bag ->
        if is_nil(bag.client_id) do
          {:bag, bag.id}
        else
          # Bag has client, go to first item
          first_item =
            bag.items
            |> Enum.filter(&(&1.status in [:pending, :ai_processed]))
            |> Enum.sort_by(& &1.created_at, DateTime)
            |> List.first()

          case first_item do
            nil -> find_next_bag_target(after_bag_id: bag.id)
            item -> {:item, item.id}
          end
        end
    end
  end

  @doc """
  Finds the next thing to review after saving a bag.
  Returns {:bag, bag_id} | {:item, item_id} | nil
  """
  def find_next_after_bag(bag) do
    # After assigning client to bag, check if bag has items to review
    items_to_review =
      Item.get_by_bag!(bag.id)
      |> Enum.filter(&(&1.status in [:pending, :ai_processed]))
      |> Enum.sort_by(& &1.created_at, DateTime)

    case List.first(items_to_review) do
      nil ->
        # No items in this bag, find next bag
        find_next_bag_target(after_bag_id: bag.id)

      item ->
        {:item, item.id}
    end
  end

  @doc """
  Finds the next thing to review after saving an item.
  Returns {:bag, bag_id} | {:item, item_id} | nil
  """
  def find_next_after_item(item) do
    # Get all items from current bag that need review
    current_bag_items =
      Item.get_by_bag!(item.bag_id)
      |> Enum.filter(&(&1.status in [:pending, :ai_processed]))
      |> Enum.sort_by(& &1.created_at, DateTime)

    # Find next item in current bag
    current_index = Enum.find_index(current_bag_items, &(&1.id == item.id))

    next_item_in_bag =
      case current_index do
        nil -> nil
        index -> Enum.at(current_bag_items, index + 1)
      end

    case next_item_in_bag do
      nil ->
        # No more items in current bag, find next bag
        find_next_bag_target(after_bag_id: item.bag_id)

      next_item ->
        {:item, next_item.id}
    end
  end

  # Private helper to find next bag
  defp find_next_bag_target(after_bag_id: current_bag_id) do
    bags = Bag.get_bags_needing_review!()

    current_index = Enum.find_index(bags, &(&1.id == current_bag_id))

    next_bag =
      case current_index do
        nil -> List.first(bags)
        index -> Enum.at(bags, index + 1)
      end

    case next_bag do
      nil ->
        nil

      bag ->
        if is_nil(bag.client_id) do
          {:bag, bag.id}
        else
          # Bag has client, go to first item
          first_item =
            bag.items
            |> Enum.filter(&(&1.status in [:pending, :ai_processed]))
            |> Enum.sort_by(& &1.created_at, DateTime)
            |> List.first()

          case first_item do
            nil -> find_next_bag_target(after_bag_id: bag.id)
            item -> {:item, item.id}
          end
        end
    end
  end
end
