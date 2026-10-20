defmodule Kirbs.Montonio.Shipping.FetchRates do
  @moduledoc """
  Parcel-machine shipping prices from Montonio (`POST /shipping-methods/rates`), i.e. what
  Montonio charges the store under its contract for one parcel to Estonia.

  Params: a list of items `%{length: cm, width: cm, height: cm, weight: kg}` that go into a
  single parcel.

  Returns `{:ok, %{omniva: 250, dpd: 300, smartposti: 250}}` (cents of the `parcelMachine`
  subtype per carrier). Carriers without a Montonio contract are missing from the map.
  """

  alias Kirbs.Montonio.{Client, Config}

  # Montonio carrier codes => our carrier atoms. ASSUMPTION: same codes as the pickup points.
  @carriers %{"omniva" => :omniva, "dpd" => :dpd, "smartpost" => :smartposti}

  def run(items, destination \\ "EE") when is_list(items) and items != [] do
    with :ok <- ensure_configured(),
         {:ok, body} <- post(items, destination),
         {:ok, rates} <- parse(body) do
      {:ok, rates}
    end
  end

  defp ensure_configured do
    if Config.configured?(), do: :ok, else: {:error, :montonio_not_configured}
  end

  defp post(items, destination) do
    payload = %{
      "destination" => destination,
      "parcels" => [%{"items" => Enum.map(items, &item/1)}]
    }

    Client.shipping()
    |> Req.post(
      url: "/shipping-methods/rates",
      params: [shippingMethodType: "pickupPoint"],
      json: payload
    )
    |> Client.handle()
  end

  defp item(item) do
    %{
      "length" => item.length,
      "width" => item.width,
      "height" => item.height,
      "dimensionUnit" => "cm",
      "weight" => item.weight,
      "weightUnit" => "kg",
      "quantity" => 1
    }
  end

  defp parse(%{"carriers" => carriers}) when is_list(carriers) do
    rates =
      for %{"carrierCode" => code, "shippingMethods" => methods} <- carriers,
          carrier = Map.get(@carriers, code),
          cents = parcel_machine_cents(methods),
          into: %{},
          do: {carrier, cents}

    {:ok, rates}
  end

  defp parse(body), do: {:error, {:unexpected_response, body}}

  defp parcel_machine_cents(methods) do
    Enum.find_value(methods, fn
      %{"type" => "pickupPoint", "subtypes" => subtypes} ->
        Enum.find_value(subtypes, fn
          %{"code" => "parcelMachine", "rate" => rate} -> to_cents(rate)
          _ -> nil
        end)

      _ ->
        nil
    end)
  end

  defp to_cents(rate) do
    rate |> Decimal.new() |> Decimal.mult(100) |> Decimal.round(0) |> Decimal.to_integer()
  end
end
