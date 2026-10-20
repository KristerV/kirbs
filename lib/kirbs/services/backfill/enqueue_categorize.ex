defmodule Kirbs.Services.Backfill.EnqueueCategorize do
  @moduledoc """
  Enqueues the categorization backfill. Dry run unless `apply: true` is passed.
  Already queued backfills are not duplicated (job uniqueness).
  """

  alias Kirbs.Jobs.BackfillCategorizeJob

  def run(opts \\ []) do
    args =
      %{"apply" => Keyword.get(opts, :apply, false)}
      |> put_opt("min_confidence", Keyword.get(opts, :min_confidence))
      |> put_opt("limit", Keyword.get(opts, :limit))

    with {:ok, job} <- args |> BackfillCategorizeJob.new() |> Oban.insert() do
      {:ok, job}
    end
  end

  defp put_opt(args, _key, nil), do: args
  defp put_opt(args, key, value), do: Map.put(args, key, value)
end
