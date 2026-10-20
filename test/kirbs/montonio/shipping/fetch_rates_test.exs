defmodule Kirbs.Montonio.Shipping.FetchRatesTest do
  use ExUnit.Case, async: false

  alias Kirbs.Montonio.Shipping.FetchRates

  @items [%{length: 35, width: 25, height: 10, weight: 1.0}]

  test "posts the parcel and returns parcel machine prices in cents per carrier" do
    Req.Test.stub(Kirbs.Montonio, fn conn ->
      assert conn.request_path == "/api/v2/shipping-methods/rates"
      assert conn.query_string == "shippingMethodType=pickupPoint"
      ["Bearer " <> token] = Plug.Conn.get_req_header(conn, "authorization")
      assert {:ok, %{"accessKey" => "test_access_key"}} = Kirbs.Montonio.Jwt.verify(token)

      {:ok, raw, conn} = Plug.Conn.read_body(conn)

      assert %{
               "destination" => "EE",
               "parcels" => [
                 %{
                   "items" => [
                     %{"length" => 35, "width" => 25, "height" => 10, "weight" => 1.0} = item
                   ]
                 }
               ]
             } = Jason.decode!(raw)

      assert item["dimensionUnit"] == "cm"
      assert item["weightUnit"] == "kg"

      Req.Test.json(conn, %{
        "destination" => "EE",
        "carriers" => [
          %{
            "carrierCode" => "omniva",
            "shippingMethods" => [
              %{
                "type" => "pickupPoint",
                "subtypes" => [
                  %{"code" => "postOffice", "rate" => "9.99", "currency" => "EUR"},
                  %{"code" => "parcelMachine", "rate" => "2.50", "currency" => "EUR"}
                ]
              }
            ]
          },
          %{
            "carrierCode" => "smartpost",
            "shippingMethods" => [
              %{
                "type" => "pickupPoint",
                "subtypes" => [
                  %{"code" => "parcelMachine", "rate" => "3.05", "currency" => "EUR"}
                ]
              }
            ]
          },
          %{"carrierCode" => "venipak", "shippingMethods" => []}
        ]
      })
    end)

    assert {:ok, %{omniva: 250, smartposti: 305} = rates} = FetchRates.run(@items)
    refute Map.has_key?(rates, :dpd)
  end

  test "surfaces Montonio errors" do
    Req.Test.stub(Kirbs.Montonio, fn conn ->
      conn
      |> Plug.Conn.put_status(404)
      |> Req.Test.json(%{"error" => "carrier_not_found_for_store"})
    end)

    assert {:error, {:http_error, 404, %{"error" => "carrier_not_found_for_store"}}} =
             FetchRates.run(@items)
  end

  test "rejects an unexpected response shape" do
    Req.Test.stub(Kirbs.Montonio, &Req.Test.json(&1, %{"nope" => true}))
    assert {:error, {:unexpected_response, _}} = FetchRates.run(@items)
  end
end
