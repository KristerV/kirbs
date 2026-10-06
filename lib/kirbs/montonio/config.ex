defmodule Kirbs.Montonio.Config do
  @moduledoc """
  Runtime configuration for the Montonio integration.

  Read from `Application.get_env(:kirbs, :montonio)`, fed in `config/runtime.exs`
  from `MONTONIO_ACCESS_KEY`, `MONTONIO_SECRET_KEY` and `MONTONIO_ENV`
  (`sandbox` or `production`).
  """

  @stargate_urls %{
    sandbox: "https://sandbox-stargate.montonio.com/api",
    production: "https://stargate.montonio.com/api"
  }

  # ASSUMPTION: the shipping overview page says https://api.shipping.montonio.com,
  # the guides say https://shipping.montonio.com/api/v2. We follow the guides
  # (they are what the code samples use). Override with `shipping_base_url`.
  @shipping_urls %{
    sandbox: "https://sandbox-shipping.montonio.com/api/v2",
    production: "https://shipping.montonio.com/api/v2"
  }

  def access_key, do: get(:access_key)
  def secret_key, do: get(:secret_key)

  def env do
    case get(:env) do
      env when env in [:production, "production", "prod"] -> :production
      _ -> :sandbox
    end
  end

  def configured?, do: is_binary(access_key()) and is_binary(secret_key())

  def stargate_base_url, do: get(:stargate_base_url) || Map.fetch!(@stargate_urls, env())
  def shipping_base_url, do: get(:shipping_base_url) || Map.fetch!(@shipping_urls, env())

  @doc "Extra Req options (tests set `plug: {Req.Test, Kirbs.Montonio}`)."
  def req_options, do: get(:req_options) || []

  def payment_handler, do: get(:payment_handler) || Kirbs.Montonio.OrderPaymentHandler
  def shipment_handler, do: get(:shipment_handler) || Kirbs.Montonio.OrderShipmentHandler

  @doc "Carriers whose pickup points are cached. ASSUMPTION: carrier codes below."
  def carriers, do: get(:carriers) || ["omniva", "smartpost", "dpd"]

  @doc "Delay between label-file polls in ms."
  def label_poll_delay, do: get(:label_poll_delay) || 1000

  @doc "Optional override of the return redirect (`:merchant_reference` is substituted); default resolves `/order/:token`."
  def return_redirect, do: get(:return_redirect)

  defp get(key), do: :kirbs |> Application.get_env(:montonio, []) |> Keyword.get(key)
end
