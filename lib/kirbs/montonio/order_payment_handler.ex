defmodule Kirbs.Montonio.OrderPaymentHandler do
  @moduledoc """
  `Kirbs.Montonio.PaymentHandler` for shop orders. `merchant_reference` is `Order.reference`.

    * `:paid` -> `Order.mark_paid` with the payment facts from the verified token (no-op when
      already paid; also accepts a late payment of a cancelled/expired order, as long as the
      items are still free). If the items were sold or reserved by someone else meanwhile the order
      is flagged for a manual refund and the update is acknowledged (a retry would not help).
      Any other failure is returned as an error so Montonio retries.
    * `:failed | :cancelled` -> `Order.cancel` while the order is still unpaid.
    * `:pending | :unknown` -> only the latest status is stored.

  Every verified notification for a known order is persisted as an `OrderEvent`
  (`payment_webhook` / `payment_return`, external id `"<reference>:<RAW_STATUS>"`). A replay of
  the same notification finds that event and does nothing (`{:ok, :duplicate}`), also across
  deploys. Verified notifications for unknown references are only logged.
  """
  @behaviour Kirbs.Montonio.PaymentHandler

  require Logger

  alias Kirbs.Montonio.RedactPayload
  alias Kirbs.Resources.{Order, OrderEvent}

  @impl true
  def handle_payment_update(reference, status), do: handle_payment_update(reference, status, %{})

  @impl true
  def handle_payment_update(reference, status, update) do
    case Order.get_by_reference(reference, not_found_error?: false) do
      {:ok, %Order{} = order} ->
        process(order, status, update)

      {:ok, nil} ->
        Logger.warning("Montonio payment update for unknown order #{reference} (#{status})")
        :ok

      {:error, error} ->
        {:error, error}
    end
  end

  defp process(order, status, update) do
    received_at = DateTime.utc_now()
    receipt_kind = if update[:source] == :return, do: :payment_return, else: :payment_webhook
    external_id = "#{order.reference}:#{update[:raw_payment_status] || status}"

    case OrderEvent.get_by_external(receipt_kind, external_id, not_found_error?: false) do
      {:ok, %OrderEvent{}} ->
        {:ok, :duplicate}

      {:ok, nil} ->
        with :ok <- apply_status(order, status, update) do
          record_receipt(order, receipt_kind, external_id, status, update, received_at)
          :ok
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp record_receipt(order, kind, external_id, status, update, received_at) do
    attrs = %{
      order_id: order.id,
      kind: kind,
      source: source(update),
      occurred_at: received_at,
      external_id: external_id,
      summary: "Montonio reported #{update[:raw_payment_status] || status}",
      payload: RedactPayload.run(update[:claims] || %{})
    }

    case OrderEvent.record(attrs) do
      {:ok, _event} ->
        :ok

      {:error, error} ->
        Logger.warning(
          "Could not record Montonio event for #{order.reference}: #{inspect(error)}"
        )
    end
  end

  defp source(%{source: :return}), do: :montonio_return
  defp source(_update), do: :montonio_webhook

  defp apply_status(%{payment_status: :paid}, _status, _update), do: :ok

  defp apply_status(order, :paid, update) do
    case Order.mark_paid(order, paid_facts(update), context: context(update)) do
      {:ok, _order} ->
        :ok

      {:error, error} ->
        # A concurrent webhook/return may have paid it between our read and this write.
        case Order.get(order.id) do
          {:ok, %{payment_status: :paid}} -> :ok
          _ -> unfulfillable_or_retry(order, error, update)
        end
    end
  end

  defp apply_status(%{status: status} = order, failure, update)
       when failure in [:failed, :cancelled] and status in [:pending, :reserved] do
    attrs = %{
      cancel_reason: "Montonio: #{failure}",
      payment_failure_reason: "Montonio payment #{failure}",
      last_montonio_status: update[:raw_payment_status]
    }

    ctx = context(update) |> Map.put(:event_kind, failure_kind(failure))

    case Order.cancel(order, attrs, context: ctx) do
      {:ok, _order} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp apply_status(order, status, update) when status in [:pending, :unknown] do
    facts =
      Map.reject(
        %{
          last_montonio_status: update[:raw_payment_status],
          montonio_order_uuid: update[:montonio_order_uuid]
        },
        fn {_k, v} -> is_nil(v) end
      )

    case Order.note_payment_status(order, facts) do
      {:ok, _order} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp apply_status(_order, _status, _update), do: :ok

  defp failure_kind(:failed), do: :payment_failed
  defp failure_kind(:cancelled), do: :payment_cancelled

  defp context(update) do
    %{event_source: source(update), event_payload: update[:claims] || %{}}
  end

  defp paid_facts(update) do
    %{
      montonio_order_uuid: update[:montonio_order_uuid],
      montonio_payment_method: update[:payment_method],
      amount_paid_cents: cents(update[:grand_total]),
      currency: update[:currency],
      last_montonio_status: update[:raw_payment_status]
    }
    |> Map.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp cents(amount) when is_number(amount), do: round(amount * 100)

  defp cents(amount) when is_binary(amount) do
    case Float.parse(amount) do
      {number, _} -> cents(number)
      :error -> nil
    end
  end

  defp cents(_), do: nil

  # Only a confirmed inventory conflict (an item sold or held by someone else) is acknowledged
  # and flagged for a manual refund. Anything else (db trouble, a failing side effect) is
  # returned as an error so Montonio retries the notification.
  defp unfulfillable_or_retry(order, error, update) do
    if inventory_conflict?(error),
      do: not_fulfillable(order, error, update),
      else: {:error, error}
  end

  defp inventory_conflict?(%{errors: errors}) when is_list(errors) do
    Enum.any?(errors, &inventory_conflict?/1)
  end

  defp inventory_conflict?(%{field: :kirbs_status}), do: true
  defp inventory_conflict?(_error), do: false

  defp not_fulfillable(order, error, update) do
    Logger.error("Montonio paid #{order.reference} but it cannot be fulfilled: #{inspect(error)}")

    note = "PAID IN MONTONIO BUT NOT FULFILLABLE - refund manually in the Montonio partner system"

    case Order.flag_payment_conflict(order, %{cancel_reason: note}, context: context(update)) do
      {:ok, _order} -> :ok
      {:error, error} -> {:error, error}
    end
  end
end
