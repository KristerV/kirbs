defmodule Kirbs.Services.Channels.PublishReviewedToShop do
  @moduledoc """
  Bulk "publish to shop" for a bag: publishes every reviewed, not yet published item via
  `Item.publish`. Items without a category or a listed price are skipped (they could not be
  shown properly in the shop) and reported back.

  Returns `{:ok, %{published: n, skipped: n}}`.
  """

  alias Kirbs.Resources.Item

  def run(bag_id) do
    with {:ok, items} <- Item.list_unpublished_reviewed_by_bag(bag_id),
         {publishable, skipped} <- Enum.split_with(items, &publishable?/1),
         :ok <- publish_all(publishable) do
      {:ok, %{published: length(publishable), skipped: length(skipped)}}
    end
  end

  @doc "An item can go to the shop once it has a category and a price."
  def publishable?(item), do: not is_nil(item.category_id) and not is_nil(item.listed_price)

  defp publish_all(items) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case Item.publish(item) do
        {:ok, _} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
end
