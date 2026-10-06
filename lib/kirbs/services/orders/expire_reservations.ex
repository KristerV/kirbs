defmodule Kirbs.Services.Orders.ExpireReservations do
  @moduledoc """
  Cancels unpaid orders whose hold ran out and releases their items, then sweeps any
  orphaned expired item reservations (reserved items without a live order).
  """

  alias Kirbs.Resources.{Item, Order}

  def run do
    with {:ok, orders} <- Order.list_expired(),
         {:ok, cancelled} <- cancel_all(orders),
         {:ok, items} <- Item.list_expired_reservations(),
         {:ok, released} <- release_all(items) do
      {:ok, %{orders_cancelled: cancelled, items_released: released}}
    end
  end

  defp cancel_all(orders) do
    Enum.reduce_while(orders, {:ok, 0}, fn order, {:ok, count} ->
      case Order.cancel(order, %{cancel_reason: "aegunud"}) do
        {:ok, _} -> {:cont, {:ok, count + 1}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp release_all(items) do
    Enum.reduce_while(items, {:ok, 0}, fn item, {:ok, count} ->
      case Item.release_reservation(item, item.reserved_until) do
        {:ok, _} -> {:cont, {:ok, count + 1}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
end
