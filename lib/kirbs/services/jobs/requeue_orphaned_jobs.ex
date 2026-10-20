defmodule Kirbs.Services.Jobs.RequeueOrphanedJobs do
  @moduledoc """
  Puts Oban jobs back in the queue that this machine was executing when it went down.

  Runs once at boot. A job still `executing` whose `attempted_by` node lives on this machine's
  address was started by a previous run of this machine, so nothing is running it any more.
  Jobs executing on other machines are left alone, and there is no timer: a slow job is never
  re-queued while it is alive.

  The node name is `app-<image ref>@<private ip>`; the image ref changes on every deploy but
  the machine keeps its IP, so only the part after the `@` is compared. Jobs left behind by a
  machine that was destroyed (new IP) are not caught.
  """

  import Ecto.Query

  require Logger

  alias Kirbs.Repo

  def run do
    with {:ok, host} <- own_host(),
         {:ok, count} <- requeue(host) do
      if count > 0, do: Logger.warning("Re-queued #{count} orphaned Oban job(s) from #{host}")
      {:ok, count}
    end
  end

  defp own_host do
    [_name, host] = node() |> Atom.to_string() |> String.split("@", parts: 2)
    {:ok, host}
  end

  defp requeue(host) do
    pattern = "%@" <> host

    {count, _} =
      from(j in Oban.Job,
        where: j.state == "executing",
        where: fragment("?[1] LIKE ?", j.attempted_by, ^pattern),
        update: [
          set: [
            state: "available",
            scheduled_at: fragment("timezone('utc', now())"),
            # fetching only picks jobs with attempt < max_attempts, so leave room for one more
            max_attempts: fragment("GREATEST(?, ? + 1)", j.max_attempts, j.attempt)
          ]
        ]
      )
      |> Repo.update_all([])

    {:ok, count}
  end
end
