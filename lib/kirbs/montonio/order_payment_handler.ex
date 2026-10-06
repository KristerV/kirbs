defmodule Kirbs.Montonio.OrderPaymentHandler do
  @moduledoc """
  `Kirbs.Montonio.PaymentHandler` for shop orders. `merchant_reference` is `Order.reference`.

    * `:paid` -> `Order.mark_paid` (no-op when already paid; also accepts a late payment of a
      cancelled/expired order, as long as the items are still free). If the items were sold
      meanwhile the order is flagged for a manual refund and the update is acknowledged (a retry
      would not help).
    * `:failed | :cancelled` -> `Order.cancel` while the order is still unpaid.
    * `:pending | :unknown` -> no-op.

  Idempotent: both the webhook and the browser return call it.
  """
  @behaviour Kirbs.Montonio.PaymentHandler

  require Logger

  alias Kirbs.Resources.Order

  @impl true
  def handle_payment_update(reference, status) do
    case Order.get_by_reference(reference, not_found_error?: false) do
      {:ok, %Order{} = order} ->
        apply_status(order, status)

      {:ok, nil} ->
        Logger.warning("Montonio payment update for unknown order #{reference} (#{status})")
        :ok

      {:error, error} ->
        {:error, error}
    end
  end

  defp apply_status(%{payment_status: :paid}, _status), do: :ok

  defp apply_status(order, :paid) do
    case Order.mark_paid(order) do
      {:ok, _order} ->
        :ok

      {:error, error} ->
        Logger.error(
          "Montonio paid #{order.reference} but it cannot be fulfilled: #{inspect(error)}"
        )

        flag_conflict(order)
    end
  end

  defp apply_status(%{status: status} = order, failure)
       when failure in [:failed, :cancelled] and status in [:pending, :reserved] do
    case Order.cancel(order, %{cancel_reason: "Montonio: #{failure}"}) do
      {:ok, _order} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp apply_status(_order, _status), do: :ok

  defp flag_conflict(order) do
    note = "PAID IN MONTONIO BUT NOT FULFILLABLE - refund manually in the Montonio partner system"

    case Order.flag_payment_conflict(order, %{cancel_reason: note}) do
      {:ok, _order} -> :ok
      {:error, error} -> {:error, error}
    end
  end
end
