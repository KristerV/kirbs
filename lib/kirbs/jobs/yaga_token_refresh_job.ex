defmodule Kirbs.Jobs.YagaTokenRefreshJob do
  @moduledoc """
  Refreshes the Yaga JWT daily so the login never expires.

  Yaga tokens live 30 days; refreshing daily keeps a rolling window alive and
  removes the need to paste a new token into Settings by hand.
  """

  use Oban.Worker,
    queue: :yaga,
    max_attempts: 3

  require Logger

  alias Kirbs.Services.Yaga.TokenRefresh

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case TokenRefresh.run() do
      {:ok, _token} ->
        Logger.info("YagaTokenRefreshJob: Refreshed Yaga JWT")
        :ok

      {:error, reason} ->
        Logger.error("YagaTokenRefreshJob: Failed - #{inspect(reason)}")
        {:error, reason}
    end
  end
end
