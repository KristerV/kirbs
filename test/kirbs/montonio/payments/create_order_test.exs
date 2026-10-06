defmodule Kirbs.Montonio.Payments.CreateOrderTest do
  use ExUnit.Case, async: false

  import Kirbs.MontonioHelpers

  alias Kirbs.Montonio.Payments.CreateOrder

  @params %{
    merchant_reference: "ORD-1",
    total_cents: 2500,
    return_url: "https://kirbs.test/checkout/montonio/return",
    notification_url: "https://kirbs.test/webhooks/montonio",
    line_items: [
      %{name: "Jacket", quantity: 1, price_cents: 2000},
      %{name: "Shipping", quantity: 1, price_cents: 500}
    ],
    billing: %{first_name: "Mari", last_name: "Maasikas", email: "m@example.com", country: "EE"}
  }

  test "posts a signed JWT and returns payment url and uuid" do
    Req.Test.stub(Kirbs.Montonio, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/api/orders"
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      %{"data" => token} = Jason.decode!(raw)

      assert {:ok, claims} = Kirbs.Montonio.Jwt.verify(token)
      assert claims["accessKey"] == "test_access_key"
      assert claims["grandTotal"] == 25.0
      assert claims["merchantReference"] == "ORD-1"
      assert claims["locale"] == "et"
      assert claims["payment"]["method"] == "paymentInitiation"
      assert claims["payment"]["methodOptions"]["preferredCountry"] == "EE"
      assert [%{"finalPrice" => 20.0}, %{"finalPrice" => 5.0}] = claims["lineItems"]
      assert claims["billingAddress"]["firstName"] == "Mari"
      refute Map.has_key?(claims, "shippingAddress")

      Req.Test.json(conn, %{"uuid" => "mont-uuid-1", "paymentUrl" => "https://stargate.test/abc"})
    end)

    assert {:ok, %{payment_url: "https://stargate.test/abc", montonio_order_uuid: "mont-uuid-1"}} =
             CreateOrder.run(@params)
  end

  test "rejects mismatching totals without calling the API" do
    assert {:error, :line_items_total_mismatch} = CreateOrder.run(%{@params | total_cents: 999})
  end

  test "rejects missing params" do
    assert {:error, {:missing_params, [:return_url]}} =
             CreateOrder.run(Map.delete(@params, :return_url))
  end

  test "surfaces http errors" do
    Req.Test.stub(Kirbs.Montonio, fn conn ->
      conn |> Plug.Conn.put_status(403) |> Req.Test.json(%{"message" => "forbidden"})
    end)

    assert {:error, {:http_error, 403, _}} = CreateOrder.run(@params)
  end

  test "token is verifiable only with our secret" do
    refute match?({:ok, _}, Kirbs.Montonio.Jwt.verify(foreign_token(%{"exp" => 4_000_000_000})))
  end
end
