defmodule Kirbs.Services.FindFirstReviewTarget do
  alias Kirbs.Resources.{Bag, Item}

  def run do
    case Bag.get_first_bag_needing_review!() do
      [] ->
        case Item.get_first_item_needing_review!() do
          [] -> {:ok, nil}
          [item | _] -> {:ok, {:item, item.id}}
        end

      [bag | _] ->
        {:ok, {:bag, bag.id}}
    end
  end
end
