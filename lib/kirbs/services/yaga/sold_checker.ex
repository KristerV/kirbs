defmodule Kirbs.Services.Yaga.SoldChecker do
  @moduledoc """
  Checks Yaga product and orders APIs to detect sold/unsold items and update their status.

  ## Escrow

  Yaga holds buyer payments in escrow until the buyer confirms receipt (or it
  auto-completes). Order status progression on Yaga:

      paid → in-transit → delivered → complete

  Funds only land in our Yaga wallet (and become withdrawable) once the order
  reaches `complete`. Earlier states show as `pending_amount` — the buyer paid,
  but the money is not ours yet.

  Accounting needs to mirror "money is actually mine", so we only mark an item
  `:sold` once its order is `complete`/`completed`, and we stamp `sold_at` from
  the order's `complete_at`. Items in earlier states stay `:uploaded_to_yaga`
  and get picked up on a later sync once they finalize.
  """

  alias Kirbs.Resources.Item
  alias Kirbs.Services.Yaga.Auth

  @base_url "https://www.yaga.ee"
  @shop_id "6750465"

  def run do
    with {:ok, jwt} <- Auth.run(),
         {:ok, products} <- fetch_all_products(jwt),
         {:ok, orders} <- fetch_all_orders(jwt),
         {:ok, status_map} <- build_status_map(products, orders),
         {:ok, results} <- sync_items(status_map) do
      {:ok, results}
    end
  end

  # Fetch all products from product API.
  #
  # Yaga's product endpoint only honors one `status` filter per request, so we
  # run two separate sweeps (sold + published) and merge. The previous combined
  # request silently dropped sold items, leaving warehouse sales invisible.

  defp fetch_all_products(jwt) do
    with {:ok, sold} <- fetch_all_with_status(jwt, "sold"),
         {:ok, published} <- fetch_all_with_status(jwt, "published") do
      {:ok, sold ++ published}
    end
  end

  defp fetch_all_with_status(jwt, status) do
    fetch_products_page(jwt, status, 0, [])
  end

  defp fetch_products_page(jwt, status, offset, acc) do
    case fetch_products(jwt, status, offset) do
      {:ok, %{list: list, total: total}} ->
        all_products = acc ++ list

        if length(all_products) < total do
          fetch_products_page(jwt, status, offset + length(list), all_products)
        else
          {:ok, all_products}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_products(jwt, status, offset) do
    headers = [
      {"authorization", "Bearer #{jwt}"},
      {"x-language", "et"},
      {"x-country", "EE"},
      {"accept", "application/json"}
    ]

    url = "#{@base_url}/api/product/"
    params = [status: status, shopId: @shop_id, offset: offset, limit: 100]

    case Req.get(url, headers: headers, params: params) do
      {:ok, %{status: 200, body: %{"status" => "success", "data" => data}}} ->
        {:ok, %{list: data["list"], total: data["total"]}}

      {:ok, %{status: http_status, body: body}} ->
        {:error, "Failed to fetch products: HTTP #{http_status} - #{inspect(body)}"}

      {:error, error} ->
        {:error, "Network error fetching products: #{inspect(error)}"}
    end
  end

  # Fetch all orders from orders API

  defp fetch_all_orders(jwt) do
    fetch_orders_page(jwt, 0, [])
  end

  defp fetch_orders_page(jwt, offset, acc) do
    case fetch_orders(jwt, offset) do
      {:ok, %{list: list, total: total}} ->
        all_orders = acc ++ list

        if length(all_orders) < total do
          fetch_orders_page(jwt, offset + length(list), all_orders)
        else
          {:ok, all_orders}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_orders(jwt, offset) do
    headers = [
      {"authorization", "Bearer #{jwt}"},
      {"x-language", "et"},
      {"x-country", "EE"},
      {"accept", "application/json"}
    ]

    url = "#{@base_url}/api/order/"
    params = [offset: offset, limit: 50, userType: "seller"]

    case Req.get(url, headers: headers, params: params) do
      {:ok, %{status: 200, body: %{"status" => "success", "data" => data}}} ->
        {:ok, %{list: data["list"], total: data["total"]}}

      {:ok, %{status: status, body: body}} ->
        {:error, "Failed to fetch orders: HTTP #{status} - #{inspect(body)}"}

      {:error, error} ->
        {:error, "Network error fetching orders: #{inspect(error)}"}
    end
  end

  # Build combined status map

  defp build_status_map(products, orders) do
    orders_by_yaga_id = build_orders_map(orders)

    status_map =
      products
      |> Enum.reduce(%{}, fn product, acc ->
        slug = product["slug"]
        yaga_id = product["id"]
        yaga_status = product["status"]
        listed_price = product["price"]
        order = Map.get(orders_by_yaga_id, yaga_id)

        cond do
          # Cleared escrow → trust the order's price and complete_at.
          order != nil ->
            Map.put(acc, slug, %{
              status: "sold",
              sold_price: order.price || listed_price,
              sold_at: order.complete_at
            })

          # Yaga lists it as sold but no completed order on our side. Could be
          # in-escrow or a warehouse sale. Either way, don't auto-flip — leave
          # the item alone and surface it in the warehouse-sales review.
          yaga_status == "sold" ->
            acc

          # Anything else (published, etc.) → mark unsold if we had it as sold.
          true ->
            Map.put(acc, slug, %{status: "published", sold_price: nil, sold_at: nil})
        end
      end)

    {:ok, status_map}
  end

  defp build_orders_map(orders) do
    orders
    |> Enum.filter(&order_is_sold?/1)
    |> Enum.reduce(%{}, fn order, acc ->
      product = order["product"]
      yaga_id = product["id"]
      price = product["price"]
      complete_at = parse_datetime(complete_at_value(order))

      if complete_at do
        Map.put(acc, yaga_id, %{price: price, complete_at: complete_at})
      else
        acc
      end
    end)
  end

  # Only orders that have cleared escrow count as sold. See moduledoc.
  defp order_is_sold?(order) do
    order["status"] in ["complete", "completed"]
  end

  defp complete_at_value(order) do
    order["complete_at"] || order["completeAt"] ||
      get_in(order, ["status_changes", "complete_at"]) ||
      get_in(order, ["statusChanges", "completeAt"])
  end

  # Sync items with status map

  defp sync_items(status_map) do
    items =
      Item.list!()
      |> Enum.filter(&(&1.status in [:uploaded_to_yaga, :sold]))

    results = Enum.map(items, &sync_item(&1, status_map))

    marked_sold = Enum.count(results, &match?({:ok, :marked_sold}, &1))
    marked_unsold = Enum.count(results, &match?({:ok, :marked_unsold}, &1))

    errors =
      Enum.flat_map(results, fn
        {:error, reason} -> [reason]
        _ -> []
      end)

    {:ok, %{marked_sold: marked_sold, marked_unsold: marked_unsold, errors: errors}}
  end

  defp sync_item(item, status_map) do
    case Map.get(status_map, item.yaga_slug) do
      nil ->
        {:ok, :not_found}

      %{status: "sold"} = data when item.status == :uploaded_to_yaga ->
        mark_as_sold(item, data)

      %{status: "sold"} = data when item.status == :sold and is_nil(item.sold_at) ->
        mark_as_sold(item, data)

      %{status: "published"} when item.status == :sold ->
        mark_as_unsold(item)

      _ ->
        {:ok, :no_change}
    end
  end

  defp mark_as_sold(item, %{sold_price: sold_price, sold_at: sold_at}) do
    case Item.update(item, %{
           status: :sold,
           sold_price: parse_price(sold_price),
           sold_at: sold_at
         }) do
      {:ok, _item} -> {:ok, :marked_sold}
      {:error, error} -> {:error, "Failed to mark item #{item.id} as sold: #{inspect(error)}"}
    end
  end

  defp mark_as_unsold(item) do
    case Item.update(item, %{
           status: :uploaded_to_yaga,
           sold_price: nil,
           sold_at: nil
         }) do
      {:ok, _item} -> {:ok, :marked_unsold}
      {:error, error} -> {:error, "Failed to mark item #{item.id} as unsold: #{inspect(error)}"}
    end
  end

  # Helpers

  defp parse_price(nil), do: nil

  defp parse_price(price) when is_binary(price) do
    case Decimal.parse(price) do
      {decimal, _} -> decimal
      :error -> nil
    end
  end

  defp parse_price(price) when is_number(price) do
    Decimal.new(price)
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end
end
