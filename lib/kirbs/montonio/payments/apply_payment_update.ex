defmodule Kirbs.Montonio.Payments.ApplyPaymentUpdate do
  @moduledoc """
  Verifies an order token and hands the result to the configured
  `Kirbs.Montonio.PaymentHandler`, at most once per (reference, status) on
  success. Used by both the webhook and the browser return endpoint.
  """

  alias Kirbs.Montonio.{Config, Payments.VerifyOrderToken, Store}

  def run(token) do
    with {:ok, update} <- VerifyOrderToken.run(token),
         {:ok, outcome} <- dispatch(update) do
      {:ok, Map.put(update, :outcome, outcome)}
    end
  end

  defp dispatch(%{merchant_reference: ref, payment_status: status}) do
    key = {:payment, ref, status}

    if Store.seen?(key) do
      {:ok, :duplicate}
    else
      case Config.payment_handler().handle_payment_update(ref, status) do
        :ok ->
          Store.mark_seen(key)
          {:ok, :handled}

        {:error, reason} ->
          {:error, {:handler_failed, reason}}
      end
    end
  end
end
