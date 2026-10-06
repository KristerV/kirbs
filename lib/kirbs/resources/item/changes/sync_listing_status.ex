defmodule Kirbs.Resources.Item.Changes.SyncListingStatus do
  @moduledoc "After an item is marked sold/unsold, moves its Yaga listing to the matching channel status."
  use Ash.Resource.Change

  alias Kirbs.Resources.YagaListing

  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}

  @impl true
  def change(changeset, opts, _context) do
    listing_status = Keyword.fetch!(opts, :listing_status)

    Ash.Changeset.after_action(changeset, fn _changeset, item ->
      case YagaListing.get_by_item(item.id, not_found_error?: false) do
        # A kirbs-channel sale does not touch the Yaga listing: it is still live
        # there and queued for delisting instead (see Services.Yaga.RequestDelist).
        {:ok, %YagaListing{}} when listing_status == :sold and item.sales_channel == :kirbs ->
          {:ok, item}

        # Manually delisted on Yaga: it stays delisted until someone relists it.
        {:ok, %YagaListing{status: :delisted}} when listing_status == :listed ->
          {:ok, item}

        {:ok, %YagaListing{} = listing} ->
          {:ok, _} =
            YagaListing.update(listing, %{
              status: listing_status,
              delist_requested_at:
                if(listing_status == :listed, do: nil, else: listing.delist_requested_at)
            })

          {:ok, item}

        _ ->
          {:ok, item}
      end
    end)
  end
end
