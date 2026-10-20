defmodule Kirbs.Montonio.Payments.CreateOrder do
  @moduledoc """
  Creates a Montonio Stargate order (bank payment, Estonia) and returns the
  URL the customer must be redirected to.

  Params (plain map, money in integer cents):

      %{
        merchant_reference: "ORD-1",
        total_cents: 2500,
        currency: "EUR",                 # optional
        locale: "et",                    # optional
        return_url: "https://...",
        notification_url: "https://.../webhooks/montonio",
        line_items: [%{name: "Jacket", quantity: 1, price_cents: 2000}],
        billing: %{first_name:, last_name:, email:, phone_number:, phone_country:,
                   address_line1:, locality:, region:, postal_code:, country:},
        shipping: %{...},                # optional, same shape as billing
        preferred_provider: "LHVBEE22",  # optional bank BIC
        payment_description: "Kirbs ORD-1"  # optional
      }

  The sum of line items must equal `total_cents` (include shipping as a line item).
  """

  alias Kirbs.Montonio.{Client, Config, Jwt}

  @token_ttl 600
  @required [:merchant_reference, :total_cents, :return_url, :line_items]

  def run(params) when is_map(params) do
    with :ok <- ensure_configured(),
         :ok <- validate(params),
         payload = build_payload(params),
         token = Jwt.sign(payload, @token_ttl),
         {:ok, body} <- post(token),
         {:ok, result} <- parse(body) do
      {:ok, result}
    end
  end

  defp ensure_configured do
    if Config.configured?(), do: :ok, else: {:error, :montonio_not_configured}
  end

  defp validate(params) do
    missing = Enum.filter(@required, &(Map.get(params, &1) in [nil, "", []]))
    items = Map.get(params, :line_items, [])

    cond do
      missing != [] ->
        {:error, {:missing_params, missing}}

      Enum.sum(Enum.map(items, &(&1.quantity * &1.price_cents))) != params.total_cents ->
        {:error, :line_items_total_mismatch}

      true ->
        :ok
    end
  end

  # Montonio rejects local notification URLs (e.g. localhost in dev), and the field is
  # optional: without it the return URL still verifies the token and drives the same handler.
  defp put_notification_url(payload, nil), do: payload
  defp put_notification_url(payload, url), do: Map.put(payload, "notificationUrl", url)

  defp build_payload(params) do
    total = cents_to_amount(params.total_cents)
    currency = Map.get(params, :currency, "EUR")
    locale = Map.get(params, :locale, "et")

    payload =
      %{
        "accessKey" => Config.access_key(),
        "merchantReference" => params.merchant_reference,
        "returnUrl" => params.return_url,
        "grandTotal" => total,
        "currency" => currency,
        "locale" => locale,
        "lineItems" =>
          Enum.map(params.line_items, fn item ->
            %{
              "name" => item.name,
              "quantity" => item.quantity,
              "finalPrice" => cents_to_amount(item.price_cents)
            }
          end),
        "payment" => %{
          "method" => "paymentInitiation",
          "amount" => total,
          "currency" => currency,
          "methodOptions" =>
            reject_nil(%{
              "preferredCountry" => "EE",
              "preferredLocale" => locale,
              "preferredProvider" => Map.get(params, :preferred_provider),
              "paymentDescription" => Map.get(params, :payment_description)
            })
        }
      }
      |> put_address("billingAddress", Map.get(params, :billing))
      |> put_address("shippingAddress", Map.get(params, :shipping))

    put_notification_url(payload, Map.get(params, :notification_url))
  end

  defp put_address(payload, _key, nil), do: payload

  defp put_address(payload, key, contact) do
    address =
      reject_nil(%{
        "firstName" => contact[:first_name],
        "lastName" => contact[:last_name],
        "email" => contact[:email],
        "phoneNumber" => contact[:phone_number],
        "phoneCountry" => contact[:phone_country],
        "addressLine1" => contact[:address_line1],
        "addressLine2" => contact[:address_line2],
        "locality" => contact[:locality],
        "region" => contact[:region],
        "postalCode" => contact[:postal_code],
        "country" => contact[:country]
      })

    Map.put(payload, key, address)
  end

  defp post(token) do
    Client.stargate() |> Req.post(url: "/orders", json: %{data: token}) |> Client.handle()
  end

  defp parse(%{"paymentUrl" => url, "uuid" => uuid}) when is_binary(url) and is_binary(uuid),
    do: {:ok, %{payment_url: url, montonio_order_uuid: uuid}}

  defp parse(body), do: {:error, {:unexpected_response, body}}

  defp cents_to_amount(cents), do: Float.round(cents / 100, 2)

  defp reject_nil(map), do: map |> Enum.reject(fn {_, v} -> is_nil(v) end) |> Map.new()
end
