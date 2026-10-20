defmodule KirbsWeb.MontonioWebhookControllerTest do
  use KirbsWeb.ConnCase, async: false

  import Kirbs.MontonioHelpers

  setup do
    reset_store()
    use_recording_handlers()
    :ok
  end

  describe "POST /webhooks/montonio" do
    test "valid token calls handler", %{conn: conn} do
      token = order_token()
      assert conn |> post("/webhooks/montonio", %{"orderToken" => token}) |> response(200)
      assert_received {:payment, "ORD-1", :paid}
    end

    test "bad signature is 401 and handler is not called", %{conn: conn} do
      token =
        foreign_token(%{
          "exp" => 4_000_000_000,
          "merchantReference" => "ORD-1",
          "paymentStatus" => "PAID",
          "accessKey" => "test_access_key"
        })

      assert conn |> post("/webhooks/montonio", %{"orderToken" => token}) |> response(401)
      refute_received {:payment, _, _}
    end

    test "missing token is 400", %{conn: conn} do
      assert conn |> post("/webhooks/montonio", %{}) |> response(400)
    end

    test "handler error is 500 and not marked processed", %{conn: conn} do
      Application.put_env(:kirbs, :montonio_test_result, {:error, :db_down})
      token = order_token()
      assert conn |> post("/webhooks/montonio", %{"orderToken" => token}) |> response(500)

      Application.delete_env(:kirbs, :montonio_test_result)
      assert build_conn() |> post("/webhooks/montonio", %{"orderToken" => token}) |> response(200)
      assert_received {:payment, "ORD-1", :paid}
    end

    test "different status for same order is dispatched", %{conn: conn} do
      post(conn, "/webhooks/montonio", %{
        "orderToken" => order_token(%{"paymentStatus" => "PENDING"})
      })

      post(build_conn(), "/webhooks/montonio", %{"orderToken" => order_token()})
      assert_received {:payment, "ORD-1", :pending}
      assert_received {:payment, "ORD-1", :paid}
    end
  end

  describe "POST /webhooks/montonio/shipping" do
    defp shipping_token(overrides \\ %{}) do
      Kirbs.Montonio.Jwt.sign(
        Map.merge(
          %{
            "eventId" => "evt-1",
            "shipmentId" => "ship-1",
            "eventType" => "shipment.statusUpdated",
            "data" => %{
              "id" => "ship-1",
              "status" => "inTransit",
              "merchantReference" => "ORD-1",
              "parcels" => [
                %{"carrierParcelId" => "CE123EE", "trackingLink" => "https://track.test/CE123EE"}
              ]
            }
          },
          overrides
        ),
        600
      )
    end

    test "extracts tracking (dedupe lives in the handler, see OrderEventsTest)", %{conn: conn} do
      token = shipping_token()
      assert conn |> post("/webhooks/montonio/shipping", %{"payload" => token}) |> response(200)

      assert_received {:shipment,
                       %{
                         shipment_id: "ship-1",
                         merchant_reference: "ORD-1",
                         status: "inTransit",
                         tracking_numbers: ["CE123EE"],
                         tracking_links: ["https://track.test/CE123EE"]
                       }}
    end

    test "rejects bad signature", %{conn: conn} do
      token = foreign_token(%{"exp" => 4_000_000_000, "eventType" => "shipment.registered"})
      assert conn |> post("/webhooks/montonio/shipping", %{"payload" => token}) |> response(401)
    end
  end

  describe "GET /checkout/montonio/return" do
    test "verifies token, notifies handler, redirects", %{conn: conn} do
      conn = get(conn, "/checkout/montonio/return", %{"order-token" => order_token()})
      assert redirected_to(conn) == "/"
      assert_received {:payment, "ORD-1", :paid}
    end

    test "rejects invalid token", %{conn: conn} do
      assert conn |> get("/checkout/montonio/return", %{"order-token" => "junk"}) |> response(400)
      assert build_conn() |> get("/checkout/montonio/return") |> response(400)
    end
  end
end
