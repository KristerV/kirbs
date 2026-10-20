defmodule Kirbs.Montonio.OrderFlowTest do
  @moduledoc "Payment + shipment webhooks wired to real orders (Req.Test stubs, no network)."
  use KirbsWeb.ConnCase, async: false
  use Oban.Testing, repo: Kirbs.Repo

  import Kirbs.MontonioHelpers
  import Kirbs.ShopFixtures
  import Phoenix.LiveViewTest

  alias Kirbs.Jobs.CreateMontonioShipmentJob
  alias Kirbs.Montonio.Jwt
  alias Kirbs.Resources.{Item, Order}
  alias Kirbs.Services.Orders.CreateMontonioShipment

  setup {Req.Test, :set_req_test_from_context}

  setup do
    reset_store()
    seed_shop!()
    :ok
  end

  defp montonio_order(overrides \\ %{}) do
    item = item!(bag!(), %{listed_price: 30})
    {:ok, order} = Order.start([item.id])

    {:ok, order} =
      Order.submit(
        order,
        Map.merge(
          %{
            buyer_name: "Mari Maasikas",
            buyer_email: "mari@example.com",
            buyer_phone: "+372 5551234",
            delivery_method: :omniva_parcel_machine,
            pickup_point_id: "omniva-tallinn-ulemiste"
          },
          overrides
        )
      )

    {:ok, order} =
      Order.set_montonio_ref(order, %{
        montonio_order_ref: "mont-#{order.reference}",
        montonio_payment_url: "https://pay.example"
      })

    {order, item}
  end

  defp pay_webhook(conn, order, status) do
    token = order_token(%{"merchantReference" => order.reference, "paymentStatus" => status})
    post(conn, "/webhooks/montonio", %{"orderToken" => token})
  end

  describe "payment webhook" do
    test "PAID marks the order paid once and enqueues the shipment", %{conn: conn} do
      {order, item} = montonio_order()

      assert conn |> pay_webhook(order, "PAID") |> response(200)
      paid = Order.get!(order.id)
      assert paid.status == :paid
      assert paid.payment_status == :paid
      assert Item.get!(item.id).kirbs_status == :sold
      assert_enqueued(worker: CreateMontonioShipmentJob, args: %{order_id: order.id})

      # replay (even after the in-memory dedupe is lost) is a no-op
      reset_store()
      assert build_conn() |> pay_webhook(order, "PAID") |> response(200)
      assert Order.get!(order.id).paid_at == paid.paid_at
    end

    test "FAILED cancels and frees the item; a late PAID still wins", %{conn: conn} do
      {order, item} = montonio_order()

      assert conn |> pay_webhook(order, "FAILED") |> response(200)
      assert Order.get!(order.id).status == :cancelled
      assert Item.get!(item.id).kirbs_status == :available

      assert build_conn() |> pay_webhook(order, "PAID") |> response(200)
      assert Order.get!(order.id).status == :paid
      assert Item.get!(item.id).kirbs_status == :sold
    end

    test "PENDING and unknown references are no-ops", %{conn: conn} do
      {order, _item} = montonio_order()
      assert conn |> pay_webhook(order, "PENDING") |> response(200)
      assert Order.get!(order.id).status == :reserved

      token = order_token(%{"merchantReference" => "K0000000"})
      assert build_conn() |> post("/webhooks/montonio", %{"orderToken" => token}) |> response(200)
    end

    test "late payment for an item that was sold elsewhere is flagged for refund", %{conn: conn} do
      {order, item} = montonio_order()
      assert conn |> pay_webhook(order, "CANCELLED") |> response(200)

      {:ok, other} = Order.start([item.id])

      {:ok, other} =
        Order.submit(other, %{
          buyer_name: "Teine Ostja",
          buyer_email: "t@example.com",
          buyer_phone: "5550000",
          delivery_method: :omniva_parcel_machine,
          pickup_point_id: "omniva-tallinn-ulemiste"
        })

      {:ok, _} = Order.mark_paid(other)

      assert build_conn() |> pay_webhook(order, "PAID") |> response(200)
      flagged = Order.get!(order.id)
      assert flagged.status == :cancelled
      assert flagged.cancel_reason =~ "refund"
    end

    test "browser return redirects to the order page", %{conn: conn} do
      {order, _} = montonio_order()
      token = order_token(%{"merchantReference" => order.reference, "paymentStatus" => "PAID"})

      conn = get(conn, "/checkout/montonio/return", %{"order-token" => token})
      assert redirected_to(conn) == "/order/#{order.token}"
      assert Order.get!(order.id).status == :paid

      {:ok, view, _} = live(build_conn(), ~p"/order/#{order.token}")
      assert has_element?(view, "#order-status[data-status=paid]")
    end
  end

  describe "shipment creation" do
    defp stub_shipments(test_pid) do
      Req.Test.stub(Kirbs.Montonio, fn conn ->
        send(test_pid, {:request, conn.method, conn.request_path})
        {:ok, raw, conn} = Plug.Conn.read_body(conn)

        case {conn.method, conn.request_path} do
          {"POST", "/api/v2/shipments"} ->
            body = Jason.decode!(raw)
            send(test_pid, {:shipment_body, body})

            Req.Test.json(conn, %{
              "id" => "ship-1",
              "status" => "pending",
              "shippingMethod" => %{"carrierCode" => "omniva"},
              "parcels" => [%{"carrierParcelId" => "CC1", "trackingLink" => "https://track/CC1"}]
            })

          {"POST", "/api/v2/label-files"} ->
            Req.Test.json(conn, %{"id" => "lf-1", "labelFileUrl" => "https://labels/lf-1.pdf"})
        end
      end)
    end

    test "job creates the shipment once and stores the result", %{conn: conn} do
      stub_shipments(self())
      {order, _} = montonio_order()
      assert conn |> pay_webhook(order, "PAID") |> response(200)

      assert :ok = perform_job(CreateMontonioShipmentJob, %{"order_id" => order.id})
      assert_received {:shipment_body, body}

      assert body["shippingMethod"] == %{
               "type" => "pickupPoint",
               "id" => "omniva-tallinn-ulemiste"
             }

      assert body["merchantReference"] == order.reference
      assert body["receiver"]["phoneCountryCode"] == "+372"
      assert body["receiver"]["phoneNumber"] == "5551234"
      assert [%{"weight" => 1.0}] = body["parcels"]

      stored = Order.get!(order.id)
      assert stored.montonio_shipment_id == "ship-1"
      assert stored.tracking_number == "CC1"
      assert stored.shipment_error == nil

      # idempotent: no second POST
      assert_received {:request, "POST", "/api/v2/shipments"}
      assert :ok = perform_job(CreateMontonioShipmentJob, %{"order_id" => order.id})
      refute_received {:request, "POST", "/api/v2/shipments"}
    end

    test "failure is stored on the order and retryable", %{conn: conn} do
      Req.Test.stub(Kirbs.Montonio, fn conn ->
        conn |> Plug.Conn.put_status(422) |> Req.Test.json(%{"message" => "bad pickup point"})
      end)

      {order, _} = montonio_order()
      assert conn |> pay_webhook(order, "PAID") |> response(200)

      assert {:error, _} = perform_job(CreateMontonioShipmentJob, %{"order_id" => order.id})
      assert Order.get!(order.id).shipment_error =~ "422"

      stub_shipments(self())
      assert {:ok, retried} = CreateMontonioShipment.run(order.id)
      assert retried.montonio_shipment_id == "ship-1"
      assert retried.shipment_error == nil
    end
  end

  describe "shipping webhook" do
    defp ship_event(order, type, status, extra \\ %{}) do
      claims = %{
        "eventId" => "ev-#{System.unique_integer([:positive])}",
        "eventType" => type,
        "shipmentId" => "ship-1",
        "data" =>
          Map.merge(
            %{
              "merchantReference" => order.reference,
              "status" => status,
              "parcels" => [%{"carrierParcelId" => "CC9", "trackingLink" => "https://track/CC9"}]
            },
            extra
          )
      }

      Jwt.sign(claims, 600)
    end

    test "updates tracking, ships and delivers the order", %{conn: conn} do
      {order, _} = montonio_order()
      assert conn |> pay_webhook(order, "PAID") |> response(200)

      post_event = fn type, status ->
        build_conn()
        |> post("/webhooks/montonio/shipping", %{"payload" => ship_event(order, type, status)})
        |> response(200)
      end

      post_event.("shipment.registered", "registered")
      o = Order.get!(order.id)
      assert o.status == :paid
      assert o.montonio_shipment_id == "ship-1"
      assert o.tracking_number == "CC9"
      assert o.shipment_status == "registered"

      post_event.("shipment.statusUpdated", "inTransit")
      assert Order.get!(order.id).status == :shipped
      assert_enqueued(worker: Kirbs.Jobs.SendOrderEmailJob, args: %{kind: "shipped"})

      post_event.("shipment.statusUpdated", "delivered")
      assert Order.get!(order.id).status == :delivered
    end

    test "registration failure is recorded", %{conn: conn} do
      {order, _} = montonio_order()
      assert conn |> pay_webhook(order, "PAID") |> response(200)

      assert build_conn()
             |> post("/webhooks/montonio/shipping", %{
               "payload" => ship_event(order, "shipment.registrationFailed", "registrationFailed")
             })
             |> response(200)

      assert Order.get!(order.id).shipment_error =~ "registration failed"
    end
  end

  describe "admin" do
    defp admin_conn(conn) do
      user =
        Ash.create!(
          Kirbs.Accounts.User,
          %{
            email: "admin#{System.unique_integer([:positive])}@example.com",
            password: "supersecret123",
            password_confirmation: "supersecret123"
          },
          action: :register_with_password,
          authorize?: false
        )

      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> AshAuthentication.Plug.Helpers.store_in_session(user)
    end

    test "shows shipment error with retry, then label download", %{conn: conn} do
      Req.Test.stub(Kirbs.Montonio, fn conn ->
        conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{})
      end)

      {order, _} = montonio_order()
      assert conn |> pay_webhook(order, "PAID") |> response(200)
      {:error, _} = CreateMontonioShipment.run(order.id)

      {:ok, view, _} = live(admin_conn(build_conn()), ~p"/orders/shipping")
      assert has_element?(view, "#shipment-error-#{order.id}")

      stub_shipments(self())
      view |> element("#create-shipment-#{order.id}") |> render_click()
      refute has_element?(view, "#shipment-error-#{order.id}")
      assert has_element?(view, "#shipment-status-#{order.id}", "pending")
      refute has_element?(view, "#download-label-#{order.id}")

      view |> element("#fetch-label-#{order.id}") |> render_click()
      assert has_element?(view, "#download-label-#{order.id}[href='https://labels/lf-1.pdf']")
    end

    test "cancel / refund marks a paid order refunded", %{conn: conn} do
      {order, _} = montonio_order()
      assert conn |> pay_webhook(order, "PAID") |> response(200)

      {:ok, view, _} = live(admin_conn(build_conn()), ~p"/orders")
      view |> element("#refund-#{order.id}") |> render_click()

      refunded = Order.get!(order.id)
      assert refunded.status == :cancelled
      assert refunded.payment_status == :refunded
    end
  end
end
