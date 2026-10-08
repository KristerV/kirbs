defmodule Kirbs.Services.Orders.DescribeOrder do
  @moduledoc "Plain-text report of an order (by reference): state, payment/shipment facts and the OrderEvent timeline."

  alias Kirbs.Resources.{Order, OrderEvent}

  def run(reference) do
    with {:ok, order} <- Order.get_by_reference(reference, not_found_error?: false),
         {:ok, order} <- found(order),
         {:ok, events} <- OrderEvent.list_for_order(order.id) do
      {:ok, render(order, events)}
    end
  end

  defp found(nil), do: {:error, :order_not_found}
  defp found(order), do: {:ok, order}

  defp render(order, events) do
    facts =
      [
        {"status", order.status},
        {"payment", "#{order.payment_method} / #{order.payment_status}"},
        {"total_cents", order.total_cents},
        {"montonio_order_ref", order.montonio_order_ref},
        {"montonio_order_uuid", order.montonio_order_uuid},
        {"montonio_payment_method", order.montonio_payment_method},
        {"last_montonio_status", order.last_montonio_status},
        {"paid_at", order.paid_at},
        {"amount_paid_cents", order.amount_paid_cents},
        {"currency", order.currency},
        {"refunded_cents", order.refunded_cents},
        {"payment_failure_reason", order.payment_failure_reason},
        {"shipment_id", order.montonio_shipment_id},
        {"shipment_status", order.shipment_status},
        {"tracking_number", order.tracking_number},
        {"shipment_error", order.shipment_error}
      ]
      |> Enum.map(fn {key, value} -> "  #{String.pad_trailing(key, 24)} #{value || "-"}" end)

    timeline =
      Enum.map(events, fn e ->
        "  #{DateTime.to_iso8601(e.occurred_at)}  #{String.pad_trailing(to_string(e.kind), 18)} " <>
          "[#{e.source}] #{e.summary}"
      end)

    Enum.join(["Order #{order.reference}" | facts] ++ ["Events:" | timeline], "\n")
  end
end
