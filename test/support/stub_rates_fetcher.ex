defmodule Kirbs.StubRatesFetcher do
  @moduledoc "Stands in for `Kirbs.Montonio.Shipping.FetchRates` in tests: fixed prices, or a failure."

  @prices %{omniva: 349, dpd: 399, smartposti: 349}

  def run(items) do
    if pid = Application.get_env(:kirbs, :stub_rates_pid),
      do: send(pid, {:rates_requested, items})

    case Application.get_env(:kirbs, :stub_rates_result) do
      nil -> {:ok, @prices}
      result -> result
    end
  end

  @doc "Sends `{:rates_requested, items}` to the calling test process on every call."
  def notify_me do
    Application.put_env(:kirbs, :stub_rates_pid, self())
    ExUnit.Callbacks.on_exit(fn -> Application.delete_env(:kirbs, :stub_rates_pid) end)
  end

  def fail_with(reason) do
    Application.put_env(:kirbs, :stub_rates_result, {:error, reason})
    ExUnit.Callbacks.on_exit(fn -> Application.delete_env(:kirbs, :stub_rates_result) end)
  end
end
