defmodule Kirbs.Montonio.Shipping.FetchPickupPoints do
  @moduledoc "Fetches all pickup points for one carrier + country from Montonio."

  alias Kirbs.Montonio.{Client, Config}

  def run(carrier, country) do
    with :ok <- ensure_configured(),
         {:ok, body} <- get(carrier, country),
         {:ok, points} <- parse(body, carrier) do
      {:ok, points}
    end
  end

  defp ensure_configured do
    if Config.configured?(), do: :ok, else: {:error, :montonio_not_configured}
  end

  defp get(carrier, country) do
    params = [carrierCode: String.downcase(carrier), countryCode: String.downcase(country)]

    Client.shipping()
    |> Req.get(url: "/shipping-methods/pickup-points", params: params)
    |> Client.handle()
  end

  defp parse(%{"pickupPoints" => points}, carrier) when is_list(points) do
    {:ok,
     Enum.map(points, fn p ->
       %{
         id: p["id"],
         name: p["name"],
         type: p["type"],
         street_address: p["streetAddress"],
         locality: p["locality"],
         postal_code: p["postalCode"],
         carrier: p["carrierCode"] || carrier
       }
     end)}
  end

  defp parse(body, _carrier), do: {:error, {:unexpected_response, body}}
end
