defmodule Kirbs.Jobs.CheckSoldItemsJob do
  @moduledoc """
  Background job to check Yaga for sold items and update their status.
  Runs hourly via Oban cron, can also be triggered manually.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3

  require Logger

  alias Kirbs.Services.Yaga.SoldChecker

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("CheckSoldItemsJob: Starting sold items check")

    case SoldChecker.run() do
      {:ok, %{updated: updated, errors: errors}} ->
        if errors == [] do
          Logger.info("CheckSoldItemsJob: Updated #{updated} items")
        else
          Logger.warning(
            "CheckSoldItemsJob: Updated #{updated} items with #{length(errors)} errors: #{inspect(errors)}"
          )
        end

        :ok

      {:error, reason} ->
        Logger.error("CheckSoldItemsJob: Failed - #{inspect(reason)}")
        {:error, reason}
    end
  end
end
