defmodule Kirbs.Services.Orders.StartMontonioPayment do
  @moduledoc """
  Creates the Montonio payment for a submitted (`:reserved`, `payment_method: :montonio`)
  order, stores Montonio's uuid and payment url on it and returns the url to redirect to.

  If Montonio cannot be reached the order is cancelled (items released) so nothing stays
  reserved without a way to pay; the caller shows the error and the buyer starts over.
  """
  use Phoenix.VerifiedRoutes, endpoint: KirbsWeb.Endpoint, router: KirbsWeb.Router

  alias Kirbs.Montonio.Payments.CreateOrder
  alias Kirbs.Resources.Order

  def run(%Order{} = order) do
    with {:ok, order} <- Order.get(order.id),
         {:ok, payment} <- create(order),
         {:ok, order} <-
           Order.set_montonio_ref(order, %{
             montonio_order_ref: payment.montonio_order_uuid,
             montonio_payment_url: payment.payment_url
           }) do
      {:ok, order.montonio_payment_url}
    else
      {:error, reason} = error ->
        Kirbs.Resources.OrderEvent.record(%{
          order_id: order.id,
          kind: :error,
          source: :api,
          summary: "Montonio payment not started: #{inspect(reason)}"
        })

        Order.cancel(order, %{cancel_reason: "Montonio payment not started: #{inspect(reason)}"},
          context: %{event_source: :api}
        )

        error
    end
  end

  defp create(order) do
    CreateOrder.run(%{
      merchant_reference: order.reference,
      total_cents: order.total_cents,
      return_url: url(~p"/checkout/montonio/return"),
      notification_url: url(~p"/webhooks/montonio"),
      line_items: line_items(order),
      billing: billing(order),
      payment_description: "Kirbs #{order.reference}"
    })
  end

  defp line_items(order) do
    items =
      for oi <- order.order_items, do: %{name: oi.title, quantity: 1, price_cents: oi.price_cents}

    if order.shipping_cents > 0,
      do: items ++ [%{name: "Tarne", quantity: 1, price_cents: order.shipping_cents}],
      else: items
  end

  defp billing(order) do
    {first, last} =
      case String.split(order.buyer_name || "", " ", parts: 2, trim: true) do
        [first, last] -> {first, last}
        [first] -> {first, nil}
        [] -> {nil, nil}
      end

    %{first_name: first, last_name: last, email: order.buyer_email}
  end
end
