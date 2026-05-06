defmodule Kirbs.Jobs.YagaMonthlyWithdrawJob do
  @moduledoc """
  Runs at the start of each Tallinn month and asks Yaga to transfer all
  available (escrow-cleared) funds to kirbs's linked bank account.

  No retry loop: if the call fails, log it and fix manually. Trying again
  automatically risks double-withdraw if the first call partially succeeded.
  """

  use Oban.Worker,
    queue: :yaga,
    max_attempts: 1

  require Logger

  alias Kirbs.Services.Yaga.Withdraw

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("YagaMonthlyWithdrawJob: starting")

    case Withdraw.run() do
      {:ok, :nothing_to_withdraw} ->
        Logger.info("YagaMonthlyWithdrawJob: nothing to withdraw")
        :ok

      {:ok, %{withdrawn: amount}} ->
        Logger.info("YagaMonthlyWithdrawJob: withdrew #{Decimal.to_string(amount)}")
        :ok

      {:error, reason} ->
        Logger.error("YagaMonthlyWithdrawJob: failed - #{inspect(reason)}")
        {:error, reason}
    end
  end
end
