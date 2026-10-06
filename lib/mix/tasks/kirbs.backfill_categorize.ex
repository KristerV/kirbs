defmodule Mix.Tasks.Kirbs.BackfillCategorize do
  @shortdoc "Enqueues the item categorization backfill (dry run unless --apply)"

  @moduledoc """
  Enqueues `Kirbs.Jobs.BackfillCategorizeJob`.

      mix kirbs.backfill_categorize [--apply] [--min-confidence 0.85] [--limit 25]

  Without `--apply` only proposals are stored; review them at /backfill.
  On a release use `Kirbs.Release.enqueue_categorize_backfill/1`.
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [apply: :boolean, min_confidence: :float, limit: :integer]
      )

    {:ok, job} = Kirbs.Services.Backfill.EnqueueCategorize.run(opts)
    Mix.shell().info("Enqueued backfill job #{job.id} (#{inspect(job.args)})")
  end
end
