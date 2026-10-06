defmodule Kirbs.Resources.Order.Changes.TrackPaid do
  @moduledoc """
  Fires the funnel `paid` event once the payment transaction committed, using the visitor
  and assignments stored on the order at checkout (see docs/tracking.md). Works for
  admin confirmations and server webhooks alike.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_transaction(changeset, fn
      _changeset, {:ok, order} = result ->
        track(order)
        result

      _changeset, result ->
        result
    end)
  end

  defp track(%{ab_visitor_id: visitor_id} = order) when is_binary(visitor_id) do
    AbFunnel.track(visitor_id, "paid", order.ab_assignments || %{}, %{
      "order_id" => order.id,
      "value" => order.total_cents / 100,
      "currency" => "EUR"
    })
  end

  defp track(_order), do: :ok
end
