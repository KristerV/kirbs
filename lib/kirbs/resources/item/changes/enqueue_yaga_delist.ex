defmodule Kirbs.Resources.Item.Changes.EnqueueYagaDelist do
  @moduledoc "After a shop sale, queues the job that takes the item's Yaga listing down."
  use Ash.Resource.Change

  alias Kirbs.Jobs.DelistFromYagaJob

  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, item ->
      case %{item_id: item.id} |> DelistFromYagaJob.new() |> Oban.insert() do
        {:ok, _job} -> {:ok, item}
        {:error, reason} -> {:error, reason}
      end
    end)
  end
end
