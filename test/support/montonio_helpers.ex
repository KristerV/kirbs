defmodule Kirbs.MontonioHelpers do
  @moduledoc false

  alias Kirbs.Montonio.Jwt

  def order_token(overrides \\ %{}, opts \\ []) do
    claims =
      Map.merge(
        %{
          "uuid" => "mont-uuid-1",
          "accessKey" => Kirbs.Montonio.Config.access_key(),
          "merchantReference" => "ORD-1",
          "paymentStatus" => "PAID",
          "paymentMethod" => "paymentInitiation",
          "grandTotal" => 25.0,
          "currency" => "EUR"
        },
        overrides
      )

    Jwt.sign(claims, Keyword.get(opts, :ttl, 600))
  end

  def foreign_token(claims) do
    jwk = JOSE.JWK.from_oct("some_other_secret_some_other_secret_1")
    {_, token} = jwk |> JOSE.JWT.sign(%{"alg" => "HS256"}, claims) |> JOSE.JWS.compact()
    token
  end

  def decode_unverified(token), do: token |> JOSE.JWT.peek_payload() |> Map.fetch!(:fields)

  def reset_store, do: Kirbs.Montonio.Store.clear()

  defmodule RecordingPaymentHandler do
    @moduledoc false
    @behaviour Kirbs.Montonio.PaymentHandler

    @impl true
    def handle_payment_update(ref, status) do
      send(Application.fetch_env!(:kirbs, :montonio_test_pid), {:payment, ref, status})
      Application.get_env(:kirbs, :montonio_test_result, :ok)
    end
  end

  defmodule RecordingShipmentHandler do
    @moduledoc false
    @behaviour Kirbs.Montonio.ShipmentHandler

    @impl true
    def handle_shipment_update(event) do
      send(Application.fetch_env!(:kirbs, :montonio_test_pid), {:shipment, event})
      :ok
    end
  end

  def use_recording_handlers do
    Application.put_env(:kirbs, :montonio_test_pid, self())
    Application.delete_env(:kirbs, :montonio_test_result)
    original = Application.get_env(:kirbs, :montonio)

    Application.put_env(
      :kirbs,
      :montonio,
      Keyword.merge(original,
        payment_handler: RecordingPaymentHandler,
        shipment_handler: RecordingShipmentHandler
      )
    )

    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:kirbs, :montonio, original) end)
  end
end
