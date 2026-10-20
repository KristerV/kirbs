defmodule Kirbs.Montonio.Payments.ApplyPaymentUpdate do
  @moduledoc """
  Verifies an order token and hands the result to the configured
  `Kirbs.Montonio.PaymentHandler`. Used by both the webhook (`:webhook`) and the browser return
  endpoint (`:return`). De-duplication is the handler's job (the default
  `Kirbs.Montonio.OrderPaymentHandler` persists it as OrderEvents); the handler may answer
  `{:ok, :duplicate}`.
  """

  alias Kirbs.Montonio.{Config, Payments.VerifyOrderToken}

  def run(token, source \\ :webhook) when source in [:webhook, :return] do
    with {:ok, update} <- VerifyOrderToken.run(token),
         {:ok, outcome} <- dispatch(update, source) do
      {:ok, Map.put(update, :outcome, outcome)}
    end
  end

  defp dispatch(%{merchant_reference: ref, payment_status: status} = update, source) do
    handler = Config.payment_handler()
    Code.ensure_loaded(handler)

    result =
      if function_exported?(handler, :handle_payment_update, 3),
        do: handler.handle_payment_update(ref, status, Map.put(update, :source, source)),
        else: handler.handle_payment_update(ref, status)

    case result do
      :ok -> {:ok, :handled}
      {:ok, outcome} -> {:ok, outcome}
      {:error, reason} -> {:error, {:handler_failed, reason}}
    end
  end
end
