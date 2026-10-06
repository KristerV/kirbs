defmodule Kirbs.Resources.Item.Changes.ProtectLifecycleStatus do
  @moduledoc """
  Prevents an item's lifecycle status from being demoted once it is sold/discarded
  or live on a sales channel. Only explicit transitions (mark sold, clear_ai_data)
  should move it back.

  Editing an item whose Yaga upload failed resets the failed listing, so the item
  re-enters the upload queue.
  """
  use Ash.Resource.Change

  alias Kirbs.Resources.YagaListing

  @protected [:sold, :discarded]
  @demotions [:pending, :ai_processed]

  @impl true
  def change(changeset, _opts, _context) do
    current = changeset.data.status
    new = Ash.Changeset.get_attribute(changeset, :status)

    cond do
      current in @protected and new not in @protected ->
        Ash.Changeset.force_change_attribute(changeset, :status, current)

      not status_given?(changeset) ->
        changeset

      true ->
        handle_listing(changeset, current, new)
    end
  end

  # The status may be passed unchanged (e.g. the review form always sends it).
  defp status_given?(changeset) do
    Map.has_key?(changeset.params, :status) or Map.has_key?(changeset.params, "status")
  end

  defp handle_listing(changeset, current, new) do
    case YagaListing.get_by_item(changeset.data.id, not_found_error?: false) do
      {:ok, %{status: status}} when status in [:listed, :sold] and new in @demotions ->
        Ash.Changeset.force_change_attribute(changeset, :status, current)

      {:ok, %{status: :failed} = listing} when new in [:reviewed | @demotions] ->
        Ash.Changeset.after_action(changeset, fn _changeset, record ->
          YagaListing.destroy!(listing)
          {:ok, record}
        end)

      _ ->
        changeset
    end
  end
end
