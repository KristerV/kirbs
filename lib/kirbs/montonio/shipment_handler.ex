defmodule Kirbs.Montonio.ShipmentHandler do
  @moduledoc """
  Behaviour the Order flow implements to react to Montonio shipping webhooks.

  Configure with `config :kirbs, :montonio, shipment_handler: MyApp.OrderShipmentHandler`.
  Must be idempotent. `event` is a map:

      %{event_id:, event_type:, shipment_id:, merchant_reference:, status:,
        tracking_numbers: [..], tracking_links: [..], label_file_url: nil | url}
  """

  @callback handle_shipment_update(event :: map()) :: :ok | {:ok, atom()} | {:error, term()}
end
