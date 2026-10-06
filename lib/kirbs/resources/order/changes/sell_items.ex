defmodule Kirbs.Resources.Order.Changes.SellItems do
  @moduledoc """
  `Order.mark_paid`: marks every item sold (kirbs_status + Item.status + sold_price/sold_at).
  Runs in the action's transaction, so an item that was sold elsewhere fails the whole
  payment confirmation cleanly instead of double-selling.
  """
  use Ash.Resource.Change

  alias Kirbs.Resources.Item

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, order ->
      order = Ash.load!(order, :order_items)

      Enum.reduce_while(order.order_items, {:ok, order}, fn order_item, acc ->
        price = Decimal.div(Decimal.new(order_item.price_cents), 100)

        with {:ok, item} <- Item.get(order_item.item_id),
             {:ok, _} <- Item.sell_on_kirbs(item, price) do
          {:cont, acc}
        else
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
    end)
  end
end
