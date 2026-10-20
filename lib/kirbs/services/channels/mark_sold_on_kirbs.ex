defmodule Kirbs.Services.Channels.MarkSoldOnKirbs do
  @moduledoc """
  ENTRY POINT FOR THE ORDER/CHECKOUT FLOW. Call this once an order line is paid
  (or, for manual payment, once the admin marks the order paid).

      MarkSoldOnKirbs.run(%{item_id: id, sold_price: Decimal.new("12.00")})
      MarkSoldOnKirbs.run(%{item_id: id, sold_price: price, sold_at: paid_at})

  What it does:

    1. loads the item and refuses if it is already sold (`{:error, :already_sold}`),
       so a double sale (e.g. a Yaga order landing at the same moment) surfaces to the caller
    2. `Item.mark_sold` with `sales_channel: :kirbs` -> `status: :sold`, `kirbs_status: :sold`
       (disappears from the shop), `sold_price`/`sold_at` (feeds client payouts, see
       `Kirbs.Accounting.client_share/1`)
    3. enqueues `Kirbs.Jobs.DelistFromYagaJob` so the Yaga listing is taken down

  `sold_price` is the item price paid by the buyer, excluding shipping and payment fees.

  Reservation (`kirbs_status: :reserved`) intentionally does NOT delist from Yaga: reservations
  expire and delisting/relisting costs a manual step. Only a completed sale delists.
  """

  alias Kirbs.Jobs.DelistFromYagaJob
  alias Kirbs.Resources.Item

  def run(%{item_id: item_id, sold_price: sold_price} = params) do
    sold_at = Map.get(params, :sold_at) || DateTime.utc_now()

    with {:ok, item} <- load_item(item_id),
         :ok <- ensure_not_sold(item),
         {:ok, sold} <- mark_sold(item, sold_price, sold_at),
         {:ok, _job} <- enqueue_delist(sold) do
      {:ok, sold}
    end
  end

  defp load_item(item_id) do
    case Item.get(item_id) do
      {:ok, item} -> {:ok, item}
      {:error, _} -> {:error, :item_not_found}
    end
  end

  defp ensure_not_sold(%{status: :sold}), do: {:error, :already_sold}
  defp ensure_not_sold(_item), do: :ok

  defp mark_sold(item, sold_price, sold_at) do
    Item.mark_sold(item, %{sold_price: sold_price, sold_at: sold_at, sales_channel: :kirbs})
  end

  defp enqueue_delist(item) do
    %{item_id: item.id} |> DelistFromYagaJob.new() |> Oban.insert()
  end
end
