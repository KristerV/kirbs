defmodule Kirbs.Resources.OrderTest do
  use Kirbs.DataCase
  use Oban.Testing, repo: Kirbs.Repo

  import Kirbs.ShopFixtures

  alias Kirbs.Resources.{Item, Order}
  alias Kirbs.Services.Orders.ExpireReservations

  @buyer %{
    buyer_name: "Mari Maasikas",
    buyer_email: "mari@example.com",
    buyer_phone: "5551234",
    delivery_method: :omniva_parcel_machine,
    pickup_point_id: "omniva-tallinn-ulemiste"
  }

  setup do
    seed_shop!()
    bag = bag!()
    %{item: item!(bag, %{listed_price: 30}), other: item!(bag, %{listed_price: 6})}
  end

  describe "start (reservation)" do
    test "reserves the item and snapshots the price", %{item: item} do
      assert {:ok, order} = Order.start([item.id])
      assert order.status == :pending
      assert order.items_total_cents == 3000
      assert DateTime.compare(order.reserved_until, DateTime.utc_now()) == :gt

      reserved = Item.get!(item.id)
      assert reserved.kirbs_status == :reserved
      assert reserved.reserved_until == order.reserved_until

      order = Order.get!(order.id)
      assert [%{price_cents: 3000}] = order.order_items
    end

    test "a reserved item cannot be reserved again", %{item: item} do
      {:ok, _} = Order.start([item.id])
      assert {:error, error} = Order.start([item.id])
      assert Exception.message(error) =~ "item_ids"
      assert Item.get!(item.id).kirbs_status == :reserved
    end

    test "a sold item cannot be reserved", %{item: item} do
      {:ok, _} = Item.sell_on_kirbs(item, 30)
      assert {:error, _} = Order.start([item.id])
    end

    test "failure on one item rolls back the others", %{item: item, other: other} do
      {:ok, _} = Order.start([other.id])
      assert {:error, _} = Order.start([item.id, other.id])
      assert Item.get!(item.id).kirbs_status == :available
    end

    test "an expired reservation can be taken over", %{item: item} do
      {:ok, order} = Order.start([item.id])
      expire!(order)
      assert {:ok, _} = Order.start([item.id])
    end
  end

  describe "concurrency" do
    test "of several simultaneous buyers exactly one reserves the item", %{item: item} do
      results =
        1..6
        |> Task.async_stream(fn _ -> Order.start([item.id]) end, timeout: :infinity)
        |> Enum.map(fn {:ok, result} -> result end)

      assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    end
  end

  describe "submit" do
    test "moves to reserved, prices shipping, extends hold and enqueues the email", %{item: item} do
      {:ok, order} = Order.start([item.id])
      assert {:ok, order} = Order.submit(order, @buyer)

      assert order.status == :reserved
      assert order.shipping_cents == 349
      assert order.total_cents == 3349
      assert order.pickup_point_name =~ "Ülemiste"
      assert order.pickup_point_carrier == :omniva
      assert DateTime.diff(order.reserved_until, DateTime.utc_now(), :hour) >= 70

      item = Item.get!(item.id)
      assert item.reserved_until == order.reserved_until

      assert_enqueued(
        worker: Kirbs.Jobs.SendOrderEmailJob,
        args: %{order_id: order.id, kind: "received"}
      )
    end

    test "own pickup is free and needs no point", %{item: item} do
      {:ok, order} = Order.start([item.id])
      attrs = %{@buyer | delivery_method: :pickup} |> Map.delete(:pickup_point_id)
      assert {:ok, order} = Order.submit(order, attrs)
      assert order.shipping_cents == 0
      assert order.total_cents == 3000
    end

    test "requires a valid pickup point, contact and email", %{item: item} do
      {:ok, order} = Order.start([item.id])
      assert {:error, _} = Order.submit(order, %{@buyer | pickup_point_id: "nope"})
      assert {:error, _} = Order.submit(order, %{@buyer | buyer_email: "not-an-email"})
      assert {:error, _} = Order.submit(order, %{@buyer | buyer_name: ""})
    end

    test "fails once the reservation expired", %{item: item} do
      {:ok, order} = Order.start([item.id])
      order = expire!(order)
      assert {:error, _} = Order.submit(order, @buyer)
    end
  end

  describe "payment" do
    setup %{item: item} do
      {:ok, order} = Order.start([item.id])
      {:ok, order} = Order.submit(order, @buyer)
      %{order: order}
    end

    test "mark_paid sells the item and enqueues the paid email", %{order: order, item: item} do
      assert {:ok, order} = Order.mark_paid(order)
      assert order.status == :paid
      assert order.payment_status == :paid
      assert order.paid_at

      sold = Item.get!(item.id)
      assert sold.kirbs_status == :sold
      assert sold.status == :sold
      assert Decimal.equal?(sold.sold_price, 30)
      assert sold.sold_at

      assert_enqueued(worker: Kirbs.Jobs.SendOrderEmailJob, args: %{kind: "paid"})
    end

    test "cannot be paid twice", %{order: order} do
      {:ok, order} = Order.mark_paid(order)
      assert {:error, _} = Order.mark_paid(order)
    end

    test "fails cleanly when the item was sold elsewhere", %{order: order, item: item} do
      {:ok, _} = item.id |> Item.get!() |> Item.sell_on_kirbs(30)
      assert {:error, _} = Order.mark_paid(order)
      assert Order.get!(order.id).status == :reserved
    end

    test "shipping flow", %{order: order} do
      {:ok, order} = Order.mark_paid(order)
      assert {:ok, order} = Order.mark_shipped(order, %{tracking_number: "CC123EE"})
      assert order.status == :shipped
      assert order.tracking_number == "CC123EE"
      assert_enqueued(worker: Kirbs.Jobs.SendOrderEmailJob, args: %{kind: "shipped"})
      assert {:ok, %{status: :delivered}} = Order.mark_delivered(order)
    end

    test "unpaid orders cannot be shipped", %{order: order} do
      assert {:error, _} = Order.mark_shipped(order, %{})
    end

    test "cancel releases the item, but not once paid", %{order: order, item: item} do
      assert {:ok, %{status: :cancelled}} = Order.cancel(order, %{cancel_reason: "test"})
      assert Item.get!(item.id).kirbs_status == :available

      {:ok, order} = Order.start([item.id])
      {:ok, order} = Order.submit(order, @buyer)
      {:ok, order} = Order.mark_paid(order)
      assert {:error, _} = Order.cancel(order, %{})
    end
  end

  describe "expiry" do
    test "ExpireReservations cancels expired orders and frees items", %{item: item, other: other} do
      {:ok, stale} = Order.start([item.id])
      {:ok, live} = Order.start([other.id])
      expire!(stale)

      assert {:ok, %{orders_cancelled: 1}} = ExpireReservations.run()
      assert Order.get!(stale.id).status == :cancelled
      assert Item.get!(item.id).kirbs_status == :available
      assert Order.get!(live.id).status == :pending
      assert Item.get!(other.id).kirbs_status == :reserved
    end

    test "cancelling an expired order does not free a newer buyer's reservation", %{item: item} do
      {:ok, stale} = Order.start([item.id])
      stale = expire!(stale)
      {:ok, _newer} = Order.start([item.id])

      assert {:ok, _} = Order.cancel(stale, %{})
      assert Item.get!(item.id).kirbs_status == :reserved
    end
  end

  defp expire!(order) do
    past = DateTime.add(DateTime.utc_now(), -60, :second)
    id = Ecto.UUID.dump!(order.id)

    Kirbs.Repo.query!("UPDATE orders SET reserved_until = $1 WHERE id = $2", [past, id])

    Kirbs.Repo.query!(
      "UPDATE items SET reserved_until = $1 WHERE id IN (SELECT item_id FROM order_items WHERE order_id = $2)",
      [past, id]
    )

    Order.get!(order.id)
  end
end
