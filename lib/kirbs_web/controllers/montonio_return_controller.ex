defmodule KirbsWeb.MontonioReturnController do
  @moduledoc """
  Browser return endpoint (GET /checkout/montonio/return?order-token=...).

  Pass this URL as `return_url` to `Payments.CreateOrder`. It verifies the
  token, feeds the (idempotent) payment handler as a second source next to the
  webhook, then redirects to `Kirbs.Montonio.Config.return_redirect/0`
  (default `/orders/:merchant_reference`) - a LiveView owned by the Order flow.
  """
  use KirbsWeb, :controller

  alias Kirbs.Montonio.Config
  alias Kirbs.Montonio.Payments.ApplyPaymentUpdate

  def show(conn, %{"order-token" => token}) do
    case ApplyPaymentUpdate.run(token) do
      {:ok, %{merchant_reference: ref}} ->
        redirect(conn,
          to: String.replace(Config.return_redirect(), ":merchant_reference", URI.encode(ref))
        )

      # Handler errors are retried by the webhook; still send the customer on.
      {:error, {:handler_failed, _}} ->
        redirect(conn, to: "/")

      {:error, _reason} ->
        conn |> put_status(400) |> text("Invalid payment return")
    end
  end

  def show(conn, _params), do: conn |> put_status(400) |> text("Invalid payment return")
end
