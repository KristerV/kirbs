defmodule Kirbs.Montonio.Shipping.ApplyShipmentUpdate do
  @moduledoc """
  Verifies a shipping webhook token and hands the normalised event to the configured
  `Kirbs.Montonio.ShipmentHandler`. De-duplication (per `eventId`) is persisted by the default
  handler as OrderEvents; a handler may answer `{:ok, :duplicate}`.
  """

  alias Kirbs.Montonio.{Config, Shipping.VerifyWebhookPayload}

  def run(token) do
    with {:ok, event} <- VerifyWebhookPayload.run(token),
         {:ok, outcome} <- dispatch(event) do
      {:ok, Map.put(event, :outcome, outcome)}
    end
  end

  defp dispatch(event) do
    case Config.shipment_handler().handle_shipment_update(event) do
      :ok -> {:ok, :handled}
      {:ok, outcome} -> {:ok, outcome}
      {:error, reason} -> {:error, {:handler_failed, reason}}
    end
  end
end
