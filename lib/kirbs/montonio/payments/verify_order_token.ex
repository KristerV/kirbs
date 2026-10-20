defmodule Kirbs.Montonio.Payments.VerifyOrderToken do
  @moduledoc """
  Verifies the `orderToken` (webhook body) / `order-token` (return query param)
  that Montonio signs with our secret key. Rejects bad signatures, expired
  tokens and tokens issued for a different access key.
  """

  alias Kirbs.Montonio.{Config, Jwt}

  @statuses %{
    "PAID" => :paid,
    "PENDING" => :pending,
    "FAILED" => :failed,
    "CANCELLED" => :cancelled
  }

  def run(token) do
    with :ok <- ensure_configured(),
         {:ok, claims} <- Jwt.verify(token),
         :ok <- check_access_key(claims),
         {:ok, result} <- extract(claims) do
      {:ok, result}
    end
  end

  defp ensure_configured do
    if Config.configured?(), do: :ok, else: {:error, :montonio_not_configured}
  end

  defp check_access_key(%{"accessKey" => key}) do
    if key == Config.access_key(), do: :ok, else: {:error, :access_key_mismatch}
  end

  defp check_access_key(_), do: {:error, :access_key_mismatch}

  defp extract(claims) do
    reference = claims["merchantReference"] || claims["merchant_reference"]
    raw_status = claims["paymentStatus"] || claims["payment_status"]

    if is_binary(reference) and is_binary(raw_status) do
      {:ok,
       %{
         claims: claims,
         merchant_reference: reference,
         payment_status: Map.get(@statuses, raw_status, :unknown),
         raw_payment_status: raw_status,
         montonio_order_uuid: claims["uuid"],
         grand_total: claims["grandTotal"],
         currency: claims["currency"],
         payment_method: claims["paymentMethod"],
         sender_iban: claims["senderIban"],
         sender_name: claims["senderName"]
       }}
    else
      {:error, :missing_claims}
    end
  end
end
