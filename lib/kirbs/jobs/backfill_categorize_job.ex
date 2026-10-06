defmodule Kirbs.Jobs.BackfillCategorizeJob do
  @moduledoc """
  Resumable backfill that categorizes items without a category in batches.

  Each run handles one batch and enqueues the next one (cursor = `after_id`), so a crash
  or deploy loses at most one batch. Default is a dry run that only stores proposals for
  review at `/backfill`; pass `"apply" => true` to apply confident results directly.
  """

  use Oban.Worker,
    queue: :backfill,
    max_attempts: 3,
    unique: [period: :infinity, states: [:available, :scheduled, :retryable], fields: [:worker]]

  alias Kirbs.Services.Backfill.CategorizeBatch

  @batch_size 25

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    limit = args["limit"] || @batch_size

    opts = [
      after_id: args["after_id"],
      limit: limit,
      apply: args["apply"] == true,
      min_confidence: args["min_confidence"] || 0.85
    ]

    with {:ok, summary} <- CategorizeBatch.run(opts) do
      continue(summary, args, limit)
    end
  end

  defp continue(%{rate_limited: seconds}, _args, _limit) when is_integer(seconds),
    do: {:snooze, seconds + 60}

  defp continue(%{fetched: fetched, last_id: last_id}, args, limit)
       when fetched >= limit and not is_nil(last_id) do
    with {:ok, _job} <- args |> Map.put("after_id", last_id) |> new() |> Oban.insert() do
      :ok
    end
  end

  defp continue(_summary, _args, _limit), do: :ok
end
