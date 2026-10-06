defmodule Kirbs.Jobs.RefreshMontonioPickupPointsJob do
  @moduledoc "Daily refresh of the cached Montonio pickup points."

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias Kirbs.Shipping.MontonioPickupPoints

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    # Not configured (no credentials yet) is a quiet no-op, not a failure.
    if Kirbs.Montonio.Config.configured?() do
      case MontonioPickupPoints.refresh() do
        {:ok, summary} ->
          Logger.info("Montonio pickup points refreshed: #{inspect(summary)}")
          :ok

        {:error, reason} ->
          Logger.error("Montonio pickup point refresh failed: #{inspect(reason)}")
          {:error, reason}
      end
    else
      :ok
    end
  end
end
