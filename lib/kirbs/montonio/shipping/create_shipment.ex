defmodule Kirbs.Montonio.Shipping.CreateShipment do
  @moduledoc """
  Registers a shipment with Montonio Shipping v2 (`POST /shipments`).

  Params (plain map):

      %{
        merchant_reference: "ORD-1",
        montonio_order_uuid: "...",          # optional, links to the payment
        shipping_method: %{type: :pickup_point, id: "<pickup point uuid>"},
        # or %{type: :courier, id: "<courier service uuid>"}
        parcels: [%{weight: 1.2, length: nil, width: nil, height: nil}],  # kg / cm
        receiver: %{name:, email:, phone_country: "+372", phone_number:,
                    street_address:, locality:, postal_code:, country: "EE"},
        products: [%{sku:, name:, quantity:, price_cents:}],   # optional
        synchronous: false                   # optional, default async
      }

  The carrier is implied by the pickup point / courier service id. Sender
  defaults to the store settings in the Montonio partner system.
  """

  alias Kirbs.Montonio.{Client, Config}

  def run(params) when is_map(params) do
    with :ok <- ensure_configured(),
         :ok <- validate(params),
         payload = build_payload(params),
         {:ok, body} <- post(payload),
         {:ok, result} <- parse(body) do
      {:ok, result}
    end
  end

  defp ensure_configured do
    if Config.configured?(), do: :ok, else: {:error, :montonio_not_configured}
  end

  defp validate(params) do
    method = Map.get(params, :shipping_method, %{})

    cond do
      method[:type] not in [:pickup_point, :courier] -> {:error, :invalid_shipping_method_type}
      method[:id] in [nil, ""] -> {:error, :missing_shipping_method_id}
      Map.get(params, :parcels, []) == [] -> {:error, :missing_parcels}
      not is_map(Map.get(params, :receiver)) -> {:error, :missing_receiver}
      true -> :ok
    end
  end

  defp build_payload(params) do
    %{
      "receiver" => contact(params.receiver),
      "shippingMethod" => %{
        "type" => method_type(params.shipping_method.type),
        "id" => params.shipping_method.id
      },
      "parcels" => Enum.map(params.parcels, &parcel/1),
      "merchantReference" => Map.get(params, :merchant_reference),
      "montonioOrderUuid" => Map.get(params, :montonio_order_uuid),
      "synchronous" => Map.get(params, :synchronous, false)
    }
    |> put_if("sender", params |> Map.get(:sender) |> maybe_contact())
    |> put_if("products", params |> Map.get(:products) |> maybe_products())
    |> reject_nil()
  end

  defp method_type(:pickup_point), do: "pickupPoint"
  defp method_type(:courier), do: "courier"

  defp parcel(parcel) do
    reject_nil(%{
      "weight" => parcel[:weight],
      "length" => parcel[:length],
      "width" => parcel[:width],
      "height" => parcel[:height]
    })
  end

  defp maybe_contact(nil), do: nil
  defp maybe_contact(contact), do: contact(contact)

  defp contact(contact) do
    reject_nil(%{
      "name" => contact[:name],
      "companyName" => contact[:company_name],
      "streetAddress" => contact[:street_address],
      "locality" => contact[:locality],
      "region" => contact[:region],
      "postalCode" => contact[:postal_code],
      "country" => contact[:country],
      "phoneCountryCode" => contact[:phone_country],
      "phoneNumber" => contact[:phone_number],
      "email" => contact[:email]
    })
  end

  defp maybe_products(nil), do: nil

  defp maybe_products(products) do
    Enum.map(products, fn p ->
      reject_nil(%{
        "sku" => p.sku,
        "name" => p.name,
        "quantity" => p.quantity,
        "price" => p[:price_cents] && Float.round(p.price_cents / 100, 2),
        "currency" => p[:price_cents] && "EUR"
      })
    end)
  end

  defp post(payload) do
    Client.shipping() |> Req.post(url: "/shipments", json: payload) |> Client.handle()
  end

  defp parse(%{"id" => id} = body) when is_binary(id) do
    parcels = Map.get(body, "parcels") || []

    {:ok,
     %{
       shipment_id: id,
       status: body["status"],
       carrier_code: get_in(body, ["shippingMethod", "carrierCode"]),
       tracking_numbers: parcels |> Enum.map(& &1["carrierParcelId"]) |> Enum.reject(&is_nil/1),
       tracking_links: parcels |> Enum.map(& &1["trackingLink"]) |> Enum.reject(&is_nil/1)
     }}
  end

  defp parse(body), do: {:error, {:unexpected_response, body}}

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)

  defp reject_nil(map), do: map |> Enum.reject(fn {_, v} -> is_nil(v) end) |> Map.new()
end
