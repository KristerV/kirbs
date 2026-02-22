defmodule Kirbs.Services.FindNextBagItemToReview do
  alias Kirbs.Resources.Item

  def run(bag_id) do
    case Item.get_first_item_needing_review_in_bag!(bag_id) do
      [] -> {:ok, nil}
      [item | _] -> {:ok, item.id}
    end
  end
end
