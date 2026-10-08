defmodule Kirbs.Montonio.Shipping.VerifyWebhookPayload do
  @moduledoc """
  Verifies the JWT in a shipping webhook body (`%{"payload" => jwt}`, signed
  with our secret key) and normalises it to an event map for
  `Kirbs.Montonio.ShipmentHandler`.
  """

  alias Kirbs.Montonio.{Config, Jwt}

  def run(token) do
    with :ok <- ensure_configured(),
         {:ok, claims} <- Jwt.verify(token),
         {:ok, event} <- normalise(claims) do
      {:ok, event}
    end
  end

  defp ensure_configured do
    if Config.configured?(), do: :ok, else: {:error, :montonio_not_configured}
  end

  defp normalise(%{"eventType" => type} = claims) when is_binary(type) do
    data = Map.get(claims, "data") || %{}
    parcels = Map.get(data, "parcels") || []

    {:ok,
     %{
       claims: claims,
       event_id: claims["eventId"],
       event_type: type,
       shipment_id: claims["shipmentId"] || data["id"],
       merchant_reference: data["merchantReference"],
       status: data["status"],
       tracking_numbers: parcels |> Enum.map(& &1["carrierParcelId"]) |> Enum.reject(&is_nil/1),
       tracking_links: parcels |> Enum.map(& &1["trackingLink"]) |> Enum.reject(&is_nil/1),
       # ASSUMPTION: labelFile.* events carry the label file object in `data`.
       label_file_url: data["labelFileUrl"]
     }}
  end

  defp normalise(_), do: {:error, :missing_claims}
end
