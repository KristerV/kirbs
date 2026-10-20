defmodule Kirbs.Services.Jobs.RequeueOrphanedJobsTest do
  use Kirbs.DataCase, async: false

  alias Kirbs.Repo
  alias Kirbs.Services.Jobs.RequeueOrphanedJobs

  defp own_host, do: node() |> Atom.to_string() |> String.split("@", parts: 2) |> List.last()

  defp insert_executing(node_name, attrs \\ []) do
    %{}
    |> Oban.Job.new(
      Keyword.merge(
        [
          worker: "Kirbs.Jobs.SomeJob",
          state: "executing",
          attempt: 1,
          max_attempts: 1,
          attempted_by: [node_name, "backfill"]
        ],
        attrs
      )
    )
    |> Repo.insert!()
  end

  test "re-queues jobs this machine was executing, even from an older image ref" do
    job = insert_executing("kirbs-oldimage@#{own_host()}")

    assert {:ok, 1} = RequeueOrphanedJobs.run()

    job = Repo.reload!(job)
    assert job.state == "available"
    assert job.max_attempts == 2
  end

  test "leaves jobs executing on other machines and other states alone" do
    other = insert_executing("kirbs-img@fdaa:0:other:1")
    done = insert_executing("kirbs-img@#{own_host()}", state: "completed")

    assert {:ok, 0} = RequeueOrphanedJobs.run()

    assert Repo.reload!(other).state == "executing"
    assert Repo.reload!(done).state == "completed"
  end
end
