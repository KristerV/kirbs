defmodule Kirbs.Montonio.ShipmentHandler.Logging do
  @moduledoc "Default no-op shipment handler that only logs."
  @behaviour Kirbs.Montonio.ShipmentHandler
  require Logger

  @impl true
  def handle_shipment_update(event) do
    Logger.info(
      "Montonio shipment update: #{event.event_type} shipment=#{event.shipment_id} " <>
        "status=#{event.status} tracking=#{inspect(event.tracking_numbers)}"
    )

    :ok
  end
end
