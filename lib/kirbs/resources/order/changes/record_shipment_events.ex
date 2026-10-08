defmodule Kirbs.Resources.Order.Changes.RecordShipmentEvents do
  @moduledoc """
  `Order.set_shipment`: appends one OrderEvent per shipment fact that changed (shipment created,
  status change, label created, error), in the same transaction.
  """
  use Ash.Resource.Change

  alias Kirbs.Resources.OrderEvent

  @impl true
  def change(changeset, _opts, _context) do
    before = changeset.data

    Ash.Changeset.after_action(changeset, fn changeset, order ->
      source = Map.get(changeset.context, :event_source, :system)

      events = events(before, order)

      Enum.reduce_while(events, {:ok, order}, fn {kind, summary}, acc ->
        attrs = %{
          order_id: order.id,
          kind: kind,
          source: source,
          summary: summary,
          payload: %{
            "shipment_id" => order.montonio_shipment_id,
            "status" => order.shipment_status,
            "tracking_number" => order.tracking_number
          }
        }

        case OrderEvent.record(attrs) do
          {:ok, _} -> {:cont, acc}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
    end)
  end

  defp events(before, order) do
    created =
      if is_nil(before.montonio_shipment_id) and order.montonio_shipment_id,
        do: [{:shipment_created, "Shipment #{order.montonio_shipment_id} created"}],
        else: []

    status =
      if (order.shipment_status != before.shipment_status and order.shipment_status) &&
           created == [],
         do: [{:status_changed, "Shipment status: #{order.shipment_status}"}],
         else: []

    label =
      if order.shipment_label_url && order.shipment_label_url != before.shipment_label_url,
        do: [{:label_created, "Label ready"}],
        else: []

    error =
      if order.shipment_error && order.shipment_error != before.shipment_error,
        do: [{:error, order.shipment_error}],
        else: []

    created ++ status ++ label ++ error
  end
end
