defmodule Kirbs.Montonio.Payments.VerifyOrderTokenTest do
  use ExUnit.Case, async: true

  import Kirbs.MontonioHelpers

  alias Kirbs.Montonio.Payments.VerifyOrderToken

  test "accepts a valid token" do
    assert {:ok, %{merchant_reference: "ORD-1", payment_status: :paid, montonio_order_uuid: "mont-uuid-1"}} =
             VerifyOrderToken.run(order_token())
  end

  test "maps statuses" do
    assert {:ok, %{payment_status: :cancelled}} =
             VerifyOrderToken.run(order_token(%{"paymentStatus" => "CANCELLED"}))

    assert {:ok, %{payment_status: :unknown, raw_payment_status: "ABANDONED"}} =
             VerifyOrderToken.run(order_token(%{"paymentStatus" => "ABANDONED"}))
  end

  test "rejects bad signature" do
    token = foreign_token(%{"exp" => 4_000_000_000, "paymentStatus" => "PAID"})
    assert {:error, :invalid_signature} = VerifyOrderToken.run(token)
  end

  test "rejects expired tokens" do
    assert {:error, :expired} = VerifyOrderToken.run(order_token(%{}, ttl: -1000))
  end

  test "rejects other access keys and garbage" do
    assert {:error, :access_key_mismatch} =
             VerifyOrderToken.run(order_token(%{"accessKey" => "other"}))

    assert {:error, _} = VerifyOrderToken.run("not-a-jwt")
    assert {:error, _} = VerifyOrderToken.run(nil)
  end

  test "rejects alg none tokens" do
    claims = Jason.encode!(%{"exp" => 4_000_000_000, "merchantReference" => "x", "paymentStatus" => "PAID", "accessKey" => "test_access_key"})
    token = Base.url_encode64(~s({"alg":"none"}), padding: false) <> "." <> Base.url_encode64(claims, padding: false) <> "."
    assert {:error, _} = VerifyOrderToken.run(token)
  end
end
