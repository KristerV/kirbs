defmodule Kirbs.Montonio.PaymentHandler.Logging do
  @moduledoc "Default no-op payment handler that only logs."
  @behaviour Kirbs.Montonio.PaymentHandler
  require Logger

  @impl true
  def handle_payment_update(merchant_reference, status) do
    Logger.info("Montonio payment update: #{merchant_reference} -> #{status}")
    :ok
  end
end
