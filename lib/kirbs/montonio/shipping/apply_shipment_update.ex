defmodule Kirbs.Montonio.Shipping.ApplyShipmentUpdate do
  @moduledoc """
  Verifies a shipping webhook token and hands the normalised event to the
  configured `Kirbs.Montonio.ShipmentHandler`, once per `eventId` on success.
  """

  alias Kirbs.Montonio.{Config, Shipping.VerifyWebhookPayload, Store}

  def run(token) do
    with {:ok, event} <- VerifyWebhookPayload.run(token),
         {:ok, outcome} <- dispatch(event) do
      {:ok, Map.put(event, :outcome, outcome)}
    end
  end

  defp dispatch(event) do
    key = {:shipment, event.event_id || {event.shipment_id, event.event_type, event.status}}

    if Store.seen?(key) do
      {:ok, :duplicate}
    else
      case Config.shipment_handler().handle_shipment_update(event) do
        :ok ->
          Store.mark_seen(key)
          {:ok, :handled}

        {:error, reason} ->
          {:error, {:handler_failed, reason}}
      end
    end
  end
end
