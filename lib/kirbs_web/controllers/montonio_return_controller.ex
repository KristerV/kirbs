defmodule KirbsWeb.MontonioReturnController do
  @moduledoc """
  Browser return endpoint (GET /checkout/montonio/return?order-token=...).

  Pass this URL as `return_url` to `Payments.CreateOrder`. It verifies the
  token, feeds the (idempotent) payment handler as a second source next to the
  webhook, then redirects to the order page `/order/:token` (resolved from the
  merchant reference, which is `Order.reference`). `Kirbs.Montonio.Config.return_redirect/0`
  can override the target (`:merchant_reference` is substituted).
  """
  use KirbsWeb, :controller

  alias Kirbs.Montonio.Config
  alias Kirbs.Montonio.Payments.ApplyPaymentUpdate
  alias Kirbs.Resources.Order

  def show(conn, %{"order-token" => token}) do
    case ApplyPaymentUpdate.run(token) do
      {:ok, %{merchant_reference: ref}} ->
        redirect(conn, to: target(ref))

      # Handler errors are retried by the webhook; still send the customer on.
      {:error, {:handler_failed, _}} ->
        redirect(conn, to: "/")

      {:error, _reason} ->
        conn |> put_status(400) |> text("Invalid payment return")
    end
  end

  def show(conn, _params), do: conn |> put_status(400) |> text("Invalid payment return")

  defp target(ref) do
    case Config.return_redirect() do
      nil ->
        case Order.get_by_reference(ref, not_found_error?: false) do
          {:ok, %Order{token: token}} -> ~p"/order/#{token}"
          _ -> "/"
        end

      template ->
        String.replace(template, ":merchant_reference", URI.encode(ref))
    end
  end
end
