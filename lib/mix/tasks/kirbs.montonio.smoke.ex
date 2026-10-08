defmodule Mix.Tasks.Kirbs.Montonio.Smoke do
  @shortdoc "Starts a Montonio sandbox payment for a test order (or --check <reference>)"

  @moduledoc """
  Sandbox smoke test, see "End-to-end sandbox test" in docs/montonio.md.

      MONTONIO_ACCESS_KEY=... MONTONIO_SECRET_KEY=... MONTONIO_ENV=sandbox mix kirbs.montonio.smoke
      mix kirbs.montonio.smoke --check K1234567

  Without keys it prints instructions and exits non-zero. Uses the real Montonio API of the
  configured environment: only run it against `sandbox`.
  """
  use Mix.Task

  alias Kirbs.Montonio.Config
  alias Kirbs.Services.Orders.{DescribeOrder, SmokeMontonioCheckout}

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [check: :string])
    Mix.Task.run("app.start")

    if Config.configured?() do
      execute(opts)
    else
      Mix.raise(not_configured_message())
    end
  end

  defp execute(check: reference) do
    case DescribeOrder.run(reference) do
      {:ok, report} -> Mix.shell().info(report)
      {:error, reason} -> Mix.raise("Cannot show #{reference}: #{inspect(reason)}")
    end
  end

  defp execute(_opts) do
    case SmokeMontonioCheckout.run() do
      {:ok, %{order: order, payment_url: url}} ->
        Mix.shell().info("""
        Montonio #{Config.env()} order created: #{order.reference} (#{order.total_cents} cents, #{order.delivery_method})

        1. Open this payment URL and pay with the sandbox bank:
           #{url}
        2. After paying you are sent to /checkout/montonio/return (needs the server on the
           host in PHX_HOST, e.g. PORT=4010 mix phx.server). Webhooks cannot reach localhost
           without a tunnel; the return URL drives the same handler.
        3. Inspect the result:
           mix kirbs.montonio.smoke --check #{order.reference}
           or http://localhost:4010/orders (log in, open the order)
        """)

      {:error, reason} ->
        Mix.raise("Smoke test failed: #{inspect(reason)}")
    end
  end

  defp not_configured_message do
    """
    Montonio is not configured. Set the sandbox keys (partner system > Stores > API keys,
    https://sandbox-partner.montonio.com) and run again:

        export MONTONIO_ACCESS_KEY=<sandbox access key>
        export MONTONIO_SECRET_KEY=<sandbox secret key>
        export MONTONIO_ENV=sandbox
        mix kirbs.montonio.smoke
    """
  end
end
