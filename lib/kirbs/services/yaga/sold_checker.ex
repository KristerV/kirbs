defmodule Kirbs.Services.Yaga.SoldChecker do
  @moduledoc """
  Checks Yaga orders API to detect sold items and update their status.
  """

  alias Kirbs.Resources.Item
  alias Kirbs.Services.Yaga.Auth

  @base_url "https://www.yaga.ee"

  @doc """
  Checks all orders from Yaga and updates sold items.

  Returns {:ok, %{updated: count, errors: [messages]}}
  """
  def run do
    with {:ok, jwt} <- Auth.run(),
         {:ok, orders} <- fetch_all_orders(jwt) do
      results = process_orders(orders)

      updated = Enum.count(results, &match?({:ok, _}, &1))

      errors =
        Enum.flat_map(results, fn
          {:error, reason} -> [reason]
          _ -> []
        end)

      {:ok, %{updated: updated, errors: errors}}
    end
  end

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

  defp process_orders(orders) do
    # Only process completed/delivered orders
    orders
    |> Enum.filter(&order_is_sold?/1)
    |> Enum.map(&process_order/1)
  end

  defp order_is_sold?(order) do
    order["status"] in ["complete", "completed", "in-transit", "delivered", "paid"]
  end

  defp process_order(order) do
    product = order["product"]
    yaga_id = product["id"]

    case find_item_by_yaga_id(yaga_id) do
      nil ->
        # Item not in our system, skip
        {:ok, :skipped}

      item ->
        if item.status == :sold do
          # Already marked as sold
          {:ok, :already_sold}
        else
          update_item_as_sold(item, order)
        end
    end
  end

  defp find_item_by_yaga_id(yaga_id) do
    Item.list!() |> Enum.find(&(&1.yaga_id == yaga_id))
  end

  defp update_item_as_sold(item, order) do
    product = order["product"]
    sold_price = parse_price(product["price"])
    sold_at = parse_datetime(order["paid_at"] || order["paidAt"])

    case Item.update(item, %{
           status: :sold,
           sold_price: sold_price,
           sold_at: sold_at
         }) do
      {:ok, item} -> {:ok, item}
      {:error, error} -> {:error, "Failed to update item #{item.id}: #{inspect(error)}"}
    end
  end

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
