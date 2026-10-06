defmodule KirbsWeb.MontonioWebhookController do
  @moduledoc """
  Montonio webhooks. Controller (not LiveView) because webhooks are inherently
  non-interactive server-to-server calls.

  * `payment/2`  - POST /webhooks/montonio          body `{"orderToken": jwt}`
  * `shipping/2` - POST /webhooks/montonio/shipping body `{"payload": jwt}`

  Answers 200 on success or duplicate, 401 on a bad token, 500 when the handler
  failed (so Montonio retries).
  """
  use KirbsWeb, :controller

  require Logger

  alias Kirbs.Montonio.Payments.ApplyPaymentUpdate
  alias Kirbs.Montonio.Shipping.ApplyShipmentUpdate

  def payment(conn, %{"orderToken" => token}), do: respond(conn, ApplyPaymentUpdate.run(token))
  def payment(conn, _params), do: send_resp(conn, 400, "missing orderToken")

  def shipping(conn, %{"payload" => token}), do: respond(conn, ApplyShipmentUpdate.run(token))
  def shipping(conn, _params), do: send_resp(conn, 400, "missing payload")

  defp respond(conn, {:ok, _}), do: send_resp(conn, 200, "ok")

  defp respond(conn, {:error, {:handler_failed, reason}}) do
    Logger.error("Montonio webhook handler failed: #{inspect(reason)}")
    send_resp(conn, 500, "handler failed")
  end

  defp respond(conn, {:error, reason}) do
    Logger.warning("Montonio webhook rejected: #{inspect(reason)}")
    send_resp(conn, 401, "invalid token")
  end
end
