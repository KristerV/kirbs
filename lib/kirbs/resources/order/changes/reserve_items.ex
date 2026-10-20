defmodule Kirbs.Resources.Order.Changes.ReserveItems do
  @moduledoc """
  `Order.start`: reserves every item (atomic `Item.reserve`), snapshots title/price into
  OrderItems and totals them. All in the action's transaction: if any item is not
  reservable the whole order is rolled back and the error is reported on `:item_ids`.
  """
  use Ash.Resource.Change

  alias Kirbs.Orders.Config
  alias Kirbs.Resources.{Item, OrderItem}
  alias KirbsWeb.ShopComponents

  @impl true
  def change(changeset, _opts, _context) do
    item_ids = Ash.Changeset.get_argument(changeset, :item_ids) || []

    changeset
    |> Ash.Changeset.before_action(&reserve(&1, Enum.uniq(item_ids)))
    |> Ash.Changeset.after_action(&create_order_items/2)
  end

  defp reserve(changeset, item_ids) do
    until = Config.reservation_deadline()

    case reserve_all(item_ids, until) do
      {:ok, items} ->
        total = items |> Enum.map(&price_cents/1) |> Enum.sum()

        changeset
        |> Ash.Changeset.force_change_attribute(:reserved_until, until)
        |> Ash.Changeset.force_change_attribute(:items_total_cents, total)
        |> Ash.Changeset.force_change_attribute(:total_cents, total)
        |> Ash.Changeset.put_context(:reserved_items, items)

      {:error, message} ->
        Ash.Changeset.add_error(changeset, field: :item_ids, message: message)
    end
  end

  defp reserve_all(item_ids, until) do
    Enum.reduce_while(item_ids, {:ok, []}, fn id, {:ok, acc} ->
      with {:ok, item} <- fetch(id),
           :ok <- sellable(item),
           {:ok, item} <- Item.reserve(item, until) do
        {:cont, {:ok, [item | acc]}}
      else
        {:error, _} -> {:halt, {:error, "ese ei ole enam saadaval"}}
      end
    end)
    |> then(fn
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end)
  end

  defp fetch(id) do
    case Item.get(id, not_found_error?: false, load: [:category]) do
      {:ok, %Item{} = item} -> {:ok, item}
      _ -> {:error, :not_found}
    end
  end

  defp sellable(%Item{published_at: nil}), do: {:error, :unpublished}
  defp sellable(%Item{listed_price: nil}), do: {:error, :no_price}
  defp sellable(_item), do: :ok

  defp price_cents(item) do
    item.listed_price |> Decimal.mult(100) |> Decimal.round(0) |> Decimal.to_integer()
  end

  defp create_order_items(changeset, order) do
    items = changeset.context[:reserved_items] || []

    Enum.reduce_while(items, {:ok, order}, fn item, acc ->
      result =
        OrderItem.create(%{
          order_id: order.id,
          item_id: item.id,
          title: ShopComponents.item_title(item),
          price_cents: price_cents(item)
        })

      case result do
        {:ok, _} -> {:cont, acc}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
end
