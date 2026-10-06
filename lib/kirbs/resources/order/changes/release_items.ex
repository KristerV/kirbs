defmodule Kirbs.Resources.Order.Changes.ReleaseItems do
  @moduledoc """
  `Order.cancel`: makes the order's items available again, but only those still held with
  this order's deadline (a newer buyer's reservation is never touched).
  """
  use Ash.Resource.Change

  alias Kirbs.Resources.Item

  @impl true
  def change(changeset, _opts, _context) do
    held_until = changeset.data.reserved_until

    Ash.Changeset.after_action(changeset, fn _changeset, order ->
      order = Ash.load!(order, :order_items)

      Enum.reduce_while(order.order_items, {:ok, order}, fn order_item, acc ->
        with {:ok, item} <- Item.get(order_item.item_id),
             {:ok, _} <- Item.release_reservation(item, held_until) do
          {:cont, acc}
        else
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
    end)
  end
end
