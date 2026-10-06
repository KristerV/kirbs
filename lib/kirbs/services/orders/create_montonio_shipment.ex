defmodule Kirbs.Services.Orders.CreateMontonioShipment do
  @moduledoc """
  Registers a Montonio shipment for a paid parcel-machine order and stores the shipment id,
  status and tracking on the order. Idempotent: an order that already has a shipment id is
  returned untouched. On failure the error is stored on the order (`shipment_error`, shown in
  the admin with a retry button) and `{:error, reason}` is returned so Oban retries.
  """

  alias Kirbs.Montonio.Shipping.CreateShipment
  alias Kirbs.Resources.Order
  alias Kirbs.Shipping.Rates

  def run(order_id) do
    with {:ok, order} <- Order.get(order_id),
         :ok <- ensure_shippable(order),
         {:ok, order} <- create(order) do
      {:ok, order}
    else
      {:skip, order} -> {:ok, order}
      {:error, _} = error -> error
    end
  end

  defp ensure_shippable(%{montonio_shipment_id: id} = order) when is_binary(id),
    do: {:skip, order}

  defp ensure_shippable(%{status: :paid, delivery_method: method} = order) do
    if method != nil and Rates.parcel_machine?(method), do: :ok, else: {:skip, order}
  end

  defp ensure_shippable(order), do: {:skip, order}

  defp create(order) do
    with {:ok, shipment} <- CreateShipment.run(params(order)),
         {:ok, order} <- Order.set_shipment(order, attrs(shipment)) do
      {:ok, order}
    else
      {:error, reason} = error ->
        Order.set_shipment(order, %{shipment_error: format(reason)})
        error
    end
  end

  defp params(order) do
    items = Enum.map(order.order_items, & &1.item)
    {country_code, number} = split_phone(order.buyer_phone)

    %{
      merchant_reference: order.reference,
      montonio_order_uuid: order.montonio_order_ref,
      shipping_method: %{type: :pickup_point, id: order.pickup_point_id},
      parcels: [%{weight: Rates.weight_kg(items)}],
      receiver: %{
        name: order.buyer_name,
        email: order.buyer_email,
        phone_country: country_code,
        phone_number: number
      },
      products:
        for oi <- order.order_items do
          %{sku: oi.item_id, name: oi.title, quantity: 1, price_cents: oi.price_cents}
        end
    }
  end

  defp attrs(shipment) do
    %{
      montonio_shipment_id: shipment.shipment_id,
      shipment_status: shipment.status,
      shipment_error: nil,
      tracking_number: List.first(shipment.tracking_numbers),
      tracking_url: List.first(shipment.tracking_links)
    }
  end

  @doc """
  Splits a free-text phone into `{"+372", "5551234"}`. ASSUMPTION: no prefix means Estonia;
  an unknown `+` prefix is cut after 3 digits (verify in sandbox for non-Estonian numbers).
  """
  def split_phone(phone) do
    clean = String.replace(phone || "", ~r/[^\d+]/, "")

    case clean do
      "+372" <> rest -> {"+372", rest}
      "00372" <> rest -> {"+372", rest}
      "+" <> digits -> {"+" <> String.slice(digits, 0, 3), String.slice(digits, 3..-1//1)}
      number -> {"+372", number}
    end
  end

  defp format({:http_error, status, body}), do: "Montonio HTTP #{status}: #{inspect(body)}"
  defp format(reason) when is_binary(reason), do: reason
  defp format(reason), do: inspect(reason)
end
