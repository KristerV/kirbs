defmodule Kirbs.Montonio.OrderEventsTest do
  @moduledoc "Persisted audit trail, webhook idempotency and payment facts (Req.Test stubs, no network)."
  use KirbsWeb.ConnCase, async: false

  import Kirbs.MontonioHelpers
  import Kirbs.ShopFixtures

  alias Kirbs.Montonio.Jwt
  alias Kirbs.Resources.{Order, OrderEvent}

  setup {Req.Test, :set_req_test_from_context}

  setup do
    reset_store()
    seed_shop!()
    :ok
  end

  defp montonio_order do
    item = item!(bag!(), %{listed_price: 30})
    {:ok, order} = Order.start([item.id])

    {:ok, order} =
      Order.submit(order, %{
        buyer_name: "Mari Maasikas",
        buyer_email: "mari@example.com",
        buyer_phone: "+372 5551234",
        delivery_method: :omniva_parcel_machine,
        pickup_point_id: "omniva-tallinn-ulemiste"
      })

    {:ok, order} =
      Order.set_montonio_ref(order, %{
        montonio_order_ref: "mont-#{order.reference}",
        montonio_payment_url: "https://pay.example"
      })

    order
  end

  defp pay_webhook(order, status, extra \\ %{}) do
    token =
      order_token(
        Map.merge(%{"merchantReference" => order.reference, "paymentStatus" => status}, extra)
      )

    post(build_conn(), "/webhooks/montonio", %{"orderToken" => token})
  end

  defp kinds(order), do: order.id |> OrderEvent.list_for_order!() |> Enum.map(& &1.kind)
  defp count(order, kind), do: Enum.count(kinds(order), &(&1 == kind))

  test "order actions append events in order" do
    order = montonio_order()
    assert kinds(order) == [:status_changed, :payment_created]

    assert [%{summary: "Checkout submitted" <> _, source: :system}, %{kind: :payment_created}] =
             OrderEvent.list_for_order!(order.id)
  end

  describe "payment webhook" do
    test "PAID persists the receipt, the paid event and the payment facts" do
      order = montonio_order()
      assert order |> pay_webhook("PAID", %{"uuid" => "u-1"}) |> response(200)

      paid = Order.get!(order.id)
      assert paid.status == :paid
      assert paid.paid_at
      assert paid.amount_paid_cents == 2500
      assert paid.currency == "EUR"
      assert paid.montonio_order_uuid == "u-1"
      assert paid.montonio_payment_method == "paymentInitiation"
      assert paid.last_montonio_status == "PAID"

      assert kinds(order) == [:status_changed, :payment_created, :payment_webhook, :payment_paid]

      receipt = Enum.find(OrderEvent.list_for_order!(order.id), &(&1.kind == :payment_webhook))
      assert receipt.source == :montonio_webhook
      assert receipt.external_id == "#{order.reference}:PAID"
      assert receipt.payload["merchantReference"] == order.reference
      assert receipt.payload["accessKey"] == "[redacted]"
    end

    test "replaying the webhook adds no event and changes nothing" do
      order = montonio_order()
      assert order |> pay_webhook("PAID") |> response(200)
      paid = Order.get!(order.id)
      before = kinds(order)

      assert order |> pay_webhook("PAID") |> response(200)
      assert kinds(order) == before
      assert Order.get!(order.id).paid_at == paid.paid_at
      assert Order.get!(order.id).updated_at == paid.updated_at
    end

    test "dedupe survives losing all in-memory state" do
      order = montonio_order()
      assert order |> pay_webhook("PAID") |> response(200)
      reset_store()
      assert order |> pay_webhook("PAID") |> response(200)
      assert count(order, :payment_webhook) == 1
      assert count(order, :payment_paid) == 1
    end

    test "browser return is a separate source and does not double-pay" do
      order = montonio_order()
      assert order |> pay_webhook("PAID") |> response(200)

      token = order_token(%{"merchantReference" => order.reference, "paymentStatus" => "PAID"})
      conn = get(build_conn(), "/checkout/montonio/return", %{"order-token" => token})
      assert redirected_to(conn) == "/order/#{order.token}"

      assert count(order, :payment_return) == 1
      assert count(order, :payment_paid) == 1

      get(build_conn(), "/checkout/montonio/return", %{"order-token" => token})
      assert count(order, :payment_return) == 1
    end

    test "return alone can drive the payment (no webhook)" do
      order = montonio_order()
      token = order_token(%{"merchantReference" => order.reference, "paymentStatus" => "PAID"})
      get(build_conn(), "/checkout/montonio/return", %{"order-token" => token})

      assert Order.get!(order.id).status == :paid
      paid_event = Enum.find(OrderEvent.list_for_order!(order.id), &(&1.kind == :payment_paid))
      assert paid_event.source == :montonio_return
    end

    test "FAILED records failure facts and a payment_failed event" do
      order = montonio_order()
      assert order |> pay_webhook("FAILED") |> response(200)

      failed = Order.get!(order.id)
      assert failed.status == :cancelled
      assert failed.payment_failure_reason =~ "failed"
      assert failed.last_montonio_status == "FAILED"
      assert count(order, :payment_failed) == 1
      assert count(order, :status_changed) == 1
    end

    test "CANCELLED records a payment_cancelled event" do
      order = montonio_order()
      assert order |> pay_webhook("CANCELLED") |> response(200)
      assert count(order, :payment_cancelled) == 1
    end

    test "PENDING stores only the latest status and the receipt" do
      order = montonio_order()
      assert order |> pay_webhook("PENDING") |> response(200)
      assert Order.get!(order.id).last_montonio_status == "PENDING"
      assert Order.get!(order.id).status == :reserved
      assert count(order, :payment_webhook) == 1
    end

    test "verified update for an unknown order is acknowledged and not persisted" do
      order = montonio_order()
      conn = pay_webhook(%{order | reference: "K0000000"}, "PAID")
      assert response(conn, 200)
      assert Ash.count!(OrderEvent) == 2
    end

    test "invalid signature persists nothing" do
      order = montonio_order()

      token =
        foreign_token(%{
          "exp" => 4_000_000_000,
          "merchantReference" => order.reference,
          "paymentStatus" => "PAID",
          "accessKey" => "test_access_key"
        })

      assert build_conn() |> post("/webhooks/montonio", %{"orderToken" => token}) |> response(401)
      assert kinds(order) == [:status_changed, :payment_created]
      assert Order.get!(order.id).status == :reserved
    end
  end

  describe "shipment and refund events" do
    defp ship_event(order, id, type, status) do
      Jwt.sign(
        %{
          "eventId" => id,
          "eventType" => type,
          "shipmentId" => "ship-1",
          "data" => %{
            "merchantReference" => order.reference,
            "status" => status,
            "parcels" => [%{"carrierParcelId" => "CC9", "trackingLink" => "https://track/CC9"}]
          }
        },
        600
      )
    end

    defp ship(order, id, type, status) do
      post(build_conn(), "/webhooks/montonio/shipping", %{
        "payload" => ship_event(order, id, type, status)
      })
    end

    test "shipment webhooks append events once per eventId" do
      order = montonio_order()
      assert order |> pay_webhook("PAID") |> response(200)

      assert order |> ship("e1", "shipment.registered", "registered") |> response(200)
      assert order |> ship("e2", "shipment.statusUpdated", "inTransit") |> response(200)
      assert order |> ship("e2", "shipment.statusUpdated", "inTransit") |> response(200)

      assert count(order, :shipment_webhook) == 2
      assert count(order, :shipment_created) == 1
      assert Order.get!(order.id).status == :shipped
      assert OrderEvent.get_by_external!(:shipment_webhook, "e1").order_id == order.id
    end

    test "label and error events come from set_shipment" do
      order = montonio_order()
      {:ok, order} = Order.set_shipment(order, %{shipment_error: "boom"})
      {:ok, order} = Order.set_shipment(order, %{shipment_label_url: "https://l/x.pdf"})
      assert :label_created in kinds(order)
      assert :error in kinds(order)
    end

    test "refund records amount, time and event" do
      order = montonio_order()
      assert order |> pay_webhook("PAID") |> response(200)
      {:ok, refunded} = Order.refund(Order.get!(order.id), %{cancel_reason: "test"})

      assert refunded.refunded_cents == refunded.total_cents
      assert refunded.refunded_at
      assert count(order, :refund_recorded) == 1
    end
  end
end
