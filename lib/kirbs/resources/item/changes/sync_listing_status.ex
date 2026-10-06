defmodule Kirbs.Resources.Item.Changes.SyncListingStatus do
  @moduledoc "After an item is marked sold/unsold, moves its Yaga listing to the matching channel status."
  use Ash.Resource.Change

  alias Kirbs.Resources.YagaListing

  @impl true
  def change(changeset, opts, _context) do
    listing_status = Keyword.fetch!(opts, :listing_status)

    Ash.Changeset.after_action(changeset, fn _changeset, item ->
      case YagaListing.get_by_item(item.id, not_found_error?: false) do
        {:ok, %YagaListing{} = listing} ->
          {:ok, _} = YagaListing.update(listing, %{status: listing_status})
          {:ok, item}

        _ ->
          {:ok, item}
      end
    end)
  end
end
