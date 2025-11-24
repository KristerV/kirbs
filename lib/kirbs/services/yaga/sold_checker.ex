defmodule Kirbs.Services.Yaga.SoldChecker do
  @moduledoc """
  Checks Yaga product and orders APIs to detect sold/unsold items and update their status.
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

  # Fetch all products from product API

  defp fetch_all_products(jwt) do
    fetch_products_page(jwt, 0, [])
  end

  defp fetch_products_page(jwt, offset, acc) do
    case fetch_products(jwt, offset) do
      {:ok, %{list: list, total: total}} ->
        all_products = acc ++ list

        if length(all_products) < total do
          fetch_products_page(jwt, offset + length(list), all_products)
        else
          {:ok, all_products}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_products(jwt, offset) do
    headers = [
      {"authorization", "Bearer #{jwt}"},
      {"x-language", "et"},
      {"x-country", "EE"},
      {"accept", "application/json"}
    ]

    url = "#{@base_url}/api/product/"
    params = [status: "sold", status: "published", shopId: @shop_id, offset: offset, limit: 100]

    case Req.get(url, headers: headers, params: params) do
      {:ok, %{status: 200, body: %{"status" => "success", "data" => data}}} ->
        {:ok, %{list: data["list"], total: data["total"]}}

      {:ok, %{status: status, body: body}} ->
        {:error, "Failed to fetch products: HTTP #{status} - #{inspect(body)}"}

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
        status = product["status"]
        listed_price = product["price"]

        order_data = Map.get(orders_by_yaga_id, yaga_id, %{})
        sold_price = order_data[:price] || listed_price
        sold_at = order_data[:paid_at] || DateTime.utc_now()

        Map.put(acc, slug, %{
          status: status,
          sold_price: sold_price,
          sold_at: sold_at
        })
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
      paid_at = parse_datetime(order["paid_at"] || order["paidAt"])

      Map.put(acc, yaga_id, %{price: price, paid_at: paid_at})
    end)
  end

  defp order_is_sold?(order) do
    order["status"] in ["complete", "completed", "in-transit", "delivered", "paid"]
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
