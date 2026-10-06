defmodule Kirbs.Montonio.PaymentHandler do
  @moduledoc """
  Behaviour the Order flow implements to react to payment updates.

  Configure with `config :kirbs, :montonio, payment_handler: MyApp.OrderPaymentHandler`.
  The callback must be idempotent (Montonio retries; the return page and the
  webhook both report the same payment). Return `:ok` or `{:error, reason}`;
  an error makes the webhook answer 500 so Montonio retries.

  `status` is one of `:paid | :pending | :failed | :cancelled | :unknown`.
  """

  @callback handle_payment_update(merchant_reference :: String.t(), status :: atom()) ::
              :ok | {:error, term()}
end
