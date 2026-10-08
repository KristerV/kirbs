defmodule Kirbs.Resources.Order.Changes.RecordEvent do
  @moduledoc """
  Appends an `OrderEvent` from inside the order action (same transaction), so state and audit
  trail never diverge.

  Options: `kind:` (atom), `summary:` (string, or one of the atoms resolved below from the order).
  Callers can pass `context: %{event_source:, event_kind:, event_payload:, event_external_id:}`
  to the action; `event_kind` overrides the option, `event_source` defaults to `:system`.
  """
  use Ash.Resource.Change

  alias Kirbs.Montonio.RedactPayload
  alias Kirbs.Resources.OrderEvent

  @impl true
  def change(changeset, opts, _context) do
    Ash.Changeset.after_action(changeset, fn changeset, order ->
      ctx = changeset.context

      attrs = %{
        order_id: order.id,
        kind: Map.get(ctx, :event_kind) || Keyword.fetch!(opts, :kind),
        source: Map.get(ctx, :event_source, :system),
        summary: resolve(opts[:summary], order),
        payload: RedactPayload.run(Map.get(ctx, :event_payload, %{}))
      }

      case OrderEvent.record(attrs) do
        {:ok, _event} -> {:ok, order}
        {:error, error} -> {:error, error}
      end
    end)
  end

  defp resolve(:submitted, o),
    do: "Checkout submitted (#{o.payment_method}, #{o.delivery_method})"

  defp resolve(:payment_created, o), do: "Montonio payment created (#{o.montonio_order_ref})"

  defp resolve(:refund, o),
    do:
      "Refund of #{o.refunded_cents} cents recorded (money is refunded in Montonio partner system)"

  defp resolve(:paid, o),
    do: "Paid (#{o.payment_method}, #{o.amount_paid_cents || o.total_cents} cents)"

  defp resolve(:cancelled, o), do: "Cancelled: #{o.cancel_reason}"
  defp resolve(:cancel_reason, o), do: o.cancel_reason
  defp resolve(value, _order), do: value
end
