defmodule Kirbs.Resources.Order.Changes.ApplyCheckout do
  @moduledoc """
  `Order.submit`: resolves the delivery choice (shipping price, pickup point), computes the
  total, moves the order to :reserved and extends the hold (order and its items) for the
  chosen payment method.
  """
  use Ash.Resource.Change

  alias Kirbs.Orders.Config
  alias Kirbs.Resources.Item
  alias Kirbs.Resources.Order.Changes.LockOrder
  alias Kirbs.Shipping.{PickupPoints, Rates}

  @impl true
  def change(changeset, _opts, _context) do
    # lock first: two tabs submitting the same pending order must not both apply
    Ash.Changeset.before_action(changeset, fn changeset ->
      changeset |> LockOrder.lock() |> apply_checkout()
    end)
  end

  defp apply_checkout(%{valid?: false} = changeset), do: changeset

  defp apply_checkout(changeset) do
    order = changeset.data
    now = DateTime.utc_now()

    cond do
      order.status != :pending ->
        Ash.Changeset.add_error(changeset,
          field: :base,
          message: "tellimus on juba esitatud"
        )

      DateTime.compare(order.reserved_until, now) != :gt ->
        Ash.Changeset.add_error(changeset,
          field: :base,
          message: "broneering on aegunud"
        )

      true ->
        changeset
        |> apply_delivery(order)
        |> apply_hold(now)
    end
  end

  defp apply_delivery(changeset, order) do
    case Ash.Changeset.get_attribute(changeset, :delivery_method) do
      nil ->
        changeset

      :pickup ->
        changeset
        |> clear_point()
        |> set_shipping(order, :pickup)

      method ->
        changeset |> set_shipping(order, method) |> set_point(method)
    end
  end

  defp set_shipping(changeset, order, method) do
    shipping = Rates.cents(method, parcel_size(order))

    changeset
    |> Ash.Changeset.force_change_attribute(:shipping_cents, shipping)
    |> Ash.Changeset.force_change_attribute(:total_cents, order.items_total_cents + shipping)
  end

  defp parcel_size(order) do
    order = Ash.load!(order, order_items: :item)
    order.order_items |> Enum.map(& &1.item) |> Rates.parcel_size()
  end

  defp set_point(changeset, method) do
    carrier = Rates.carrier(method)
    id = Ash.Changeset.get_attribute(changeset, :pickup_point_id)

    with id when is_binary(id) and id != "" <- id,
         {:ok, point} <- PickupPoints.get(carrier, id) do
      changeset
      |> Ash.Changeset.force_change_attribute(:pickup_point_name, point.name)
      |> Ash.Changeset.force_change_attribute(:pickup_point_carrier, carrier)
    else
      _ ->
        Ash.Changeset.add_error(changeset,
          field: :pickup_point_id,
          message: "vali pakiautomaat"
        )
    end
  end

  defp clear_point(changeset) do
    changeset
    |> Ash.Changeset.force_change_attribute(:pickup_point_id, nil)
    |> Ash.Changeset.force_change_attribute(:pickup_point_name, nil)
    |> Ash.Changeset.force_change_attribute(:pickup_point_carrier, nil)
  end

  defp apply_hold(%{valid?: false} = changeset, _now), do: changeset

  defp apply_hold(changeset, now) do
    payment_method = Ash.Changeset.get_attribute(changeset, :payment_method)
    until = Config.hold_deadline(payment_method, now)

    changeset
    |> Ash.Changeset.force_change_attribute(:status, :reserved)
    |> Ash.Changeset.force_change_attribute(:reserved_until, until)
    |> Ash.Changeset.after_action(&extend_items(&1, &2, until))
  end

  defp extend_items(_changeset, order, until) do
    order = Ash.load!(order, :order_items)

    Enum.reduce_while(order.order_items, {:ok, order}, fn order_item, acc ->
      with {:ok, item} <- Item.get(order_item.item_id),
           {:ok, _} <- Item.extend_reservation(item, until) do
        {:cont, acc}
      else
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
end
