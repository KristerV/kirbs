defmodule Kirbs.Montonio.Shipping.CreateShipmentTest do
  use ExUnit.Case, async: false

  alias Kirbs.Montonio.Shipping.CreateShipment

  @params %{
    merchant_reference: "ORD-1",
    shipping_method: %{type: :pickup_point, id: "pp-1"},
    parcels: [%{weight: 1.2, length: 30, width: 20, height: 10}],
    receiver: %{name: "Mari Maasikas", email: "m@example.com", phone_country: "+372", phone_number: "5551234"},
    products: [%{sku: "A1", name: "Jacket", quantity: 1, price_cents: 2000}]
  }

  test "creates a shipment with bearer JWT" do
    Req.Test.stub(Kirbs.Montonio, fn conn ->
      assert conn.request_path == "/api/v2/shipments"
      ["Bearer " <> token] = Plug.Conn.get_req_header(conn, "authorization")
      assert {:ok, %{"access_key" => "test_access_key"}} = Kirbs.Montonio.Jwt.verify(token)

      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      body = Jason.decode!(raw)
      assert body["shippingMethod"] == %{"type" => "pickupPoint", "id" => "pp-1"}
      assert body["receiver"]["phoneCountryCode"] == "+372"
      assert body["parcels"] == [%{"weight" => 1.2, "length" => 30, "width" => 20, "height" => 10}]
      assert body["merchantReference"] == "ORD-1"
      assert [%{"price" => 20.0, "sku" => "A1"}] = Enum.map(body["products"], &Map.take(&1, ["price", "sku"]))

      Req.Test.json(conn, %{
        "id" => "ship-1",
        "status" => "pending",
        "shippingMethod" => %{"carrierCode" => "omniva"},
        "parcels" => [%{"carrierParcelId" => nil, "trackingLink" => nil}]
      })
    end)

    assert {:ok, %{shipment_id: "ship-1", status: "pending", carrier_code: "omniva", tracking_numbers: []}} =
             CreateShipment.run(@params)
  end

  test "validates input" do
    assert {:error, :missing_parcels} = CreateShipment.run(%{@params | parcels: []})

    assert {:error, :missing_shipping_method_id} =
             CreateShipment.run(%{@params | shipping_method: %{type: :courier, id: nil}})
  end

  test "surfaces http errors" do
    Req.Test.stub(Kirbs.Montonio, fn conn ->
      conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"message" => "bad"})
    end)

    assert {:error, {:http_error, 400, _}} = CreateShipment.run(@params)
  end
end
