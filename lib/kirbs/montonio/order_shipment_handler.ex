defmodule Kirbs.Montonio.OrderShipmentHandler do
  @moduledoc """
  `Kirbs.Montonio.ShipmentHandler` for shop orders. Finds the order by shipment id, falling back
  to `merchant_reference` (= `Order.reference`; the webhook can beat the create job). Stores
  status and tracking, records registration failures, and advances the order:

    * status `inTransit` / `awaitingCollection` / `delivered` -> `Order.mark_shipped` (if paid)
    * status `delivered` -> `Order.mark_delivered`

  ASSUMPTION: these Montonio status names (see docs/montonio.md); verify in sandbox.
  """
  @behaviour Kirbs.Montonio.ShipmentHandler

  require Logger

  alias Kirbs.Resources.Order

  @shipped ["inTransit", "awaitingCollection", "delivered"]

  @impl true
  def handle_shipment_update(event) do
    case find_order(event) do
      %Order{} = order ->
        update(order, event)

      nil ->
        Logger.warning("Montonio shipment event for unknown order: #{inspect(event.shipment_id)}")
        :ok
    end
  end

  defp find_order(event) do
    with {:ok, nil} <- by_shipment(event.shipment_id),
         {:ok, order} <- by_reference(event.merchant_reference) do
      order
    else
      {:ok, order} -> order
      _ -> nil
    end
  end

  defp by_shipment(id) when is_binary(id),
    do: Order.get_by_shipment_id(id, not_found_error?: false)

  defp by_shipment(_), do: {:ok, nil}

  defp by_reference(ref) when is_binary(ref),
    do: Order.get_by_reference(ref, not_found_error?: false)

  defp by_reference(_), do: {:ok, nil}

  defp update(order, event) do
    with {:ok, order} <- Order.set_shipment(order, attrs(order, event)),
         {:ok, order} <- maybe_ship(order, event.status),
         {:ok, _order} <- maybe_deliver(order, event.status) do
      :ok
    end
  end

  defp attrs(order, event) do
    %{
      montonio_shipment_id: event.shipment_id || order.montonio_shipment_id,
      shipment_status: event.status || order.shipment_status,
      tracking_number: List.first(event.tracking_numbers) || order.tracking_number,
      tracking_url: List.first(event.tracking_links) || order.tracking_url,
      shipment_label_url: event.label_file_url || order.shipment_label_url,
      shipment_error: error(order, event)
    }
  end

  defp error(_order, %{event_type: "shipment.registrationFailed"}),
    do: "Montonio: registration failed"

  defp error(_order, %{event_type: "labelFile.creationFailed"}),
    do: "Montonio: label creation failed"

  defp error(%{shipment_error: error}, %{event_type: type}) when type != "shipment.registered",
    do: error

  defp error(_order, _event), do: nil

  defp maybe_ship(%{status: :paid} = order, status) when status in @shipped,
    do: Order.mark_shipped(order, %{})

  defp maybe_ship(order, _status), do: {:ok, order}

  defp maybe_deliver(%{status: :shipped} = order, "delivered"), do: Order.mark_delivered(order)
  defp maybe_deliver(order, _status), do: {:ok, order}
end
