defmodule Kirbs.Services.Yaga.RequestDelist do
  @moduledoc """
  Takes an item that sold on kirbs off Yaga.

  The code base has no Yaga delete/hide call: `Uploader` only creates and publishes products
  and `SoldChecker`/`StatusChecker` only read. Guessing at a destructive endpoint on the live
  marketplace account is not safe, so this service does the safest available thing: it stamps
  `delist_requested_at` on the `YagaListing`, which puts it in the admin "needs manual
  delisting" queue (section on `/warehouse-sales`). The owner removes the product on yaga.ee
  and clicks "Delisted", which moves the listing to `:delisted`.

  If Yaga ever gets a delete API, only `request/1` below needs to change.

  Returns `{:ok, :requested | :not_listed}`.
  """

  alias Kirbs.Resources.YagaListing

  def run(item_id) do
    with {:ok, listing} <- find_listing(item_id),
         {:ok, result} <- request(listing) do
      {:ok, result}
    end
  end

  defp find_listing(item_id) do
    YagaListing.get_by_item(item_id, not_found_error?: false)
  end

  defp request(%YagaListing{status: :listed} = listing) do
    with {:ok, _} <- YagaListing.request_delist(listing), do: {:ok, :requested}
  end

  defp request(_not_live_or_nil), do: {:ok, :not_listed}
end
