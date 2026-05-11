defmodule Kirbs.Services.Yaga.WarehouseSaleDetector do
  @moduledoc """
  Finds items that Yaga lists as `status="sold"` but for which no completed
  order exists — typically warehouse sales where the buyer paid us directly
  and the platform never produced an escrow flow.

  Returns the subset of those that we still have as `:uploaded_to_yaga`,
  enriched with Yaga's listed price and `updated_at` so the review page can
  prefill a manual mark-sold action.
  """

  alias Kirbs.Resources.Item
  alias Kirbs.Services.Yaga.Auth

  @base_url "https://www.yaga.ee"
  @shop_id "6750465"

  def run do
    with {:ok, jwt} <- Auth.run(),
         {:ok, sold_products} <- fetch_all_sold(jwt),
         {:ok, orders} <- fetch_all_orders(jwt),
         completed_ids <- completed_order_yaga_ids(orders),
         orphan_products <- Enum.reject(sold_products, &(&1["id"] in completed_ids)),
         {:ok, candidates} <- match_items(orphan_products) do
      {:ok, candidates}
    end
  end

  defp match_items(orphan_products) do
    by_slug = Map.new(orphan_products, fn p -> {p["slug"], p} end)

    candidates =
      Item.list!()
      |> Enum.filter(&(&1.status == :uploaded_to_yaga and not is_nil(&1.yaga_slug)))
      |> Enum.filter(&Map.has_key?(by_slug, &1.yaga_slug))
      |> Enum.map(fn item ->
        product = Map.fetch!(by_slug, item.yaga_slug)

        %{
          item: item,
          yaga_id: product["id"],
          yaga_slug: product["slug"],
          listed_price: parse_price(product["price"]),
          yaga_updated_at: parse_datetime(product["updated_at"] || product["updatedAt"])
        }
      end)

    {:ok, candidates}
  end

  defp completed_order_yaga_ids(orders) do
    orders
    |> Enum.filter(&(&1["status"] in ["complete", "completed"]))
    |> Enum.map(fn order -> get_in(order, ["product", "id"]) end)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp fetch_all_sold(jwt), do: fetch_products_page(jwt, 0, [])

  defp fetch_products_page(jwt, offset, acc) do
    case fetch_products(jwt, offset) do
      {:ok, %{list: list, total: total}} ->
        all = acc ++ list

        if length(all) < total do
          fetch_products_page(jwt, offset + length(list), all)
        else
          {:ok, all}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_products(jwt, offset) do
    headers = auth_headers(jwt)
    url = "#{@base_url}/api/product/"
    params = [status: "sold", shopId: @shop_id, offset: offset, limit: 100]

    case Req.get(url, headers: headers, params: params) do
      {:ok, %{status: 200, body: %{"status" => "success", "data" => data}}} ->
        {:ok, %{list: data["list"], total: data["total"]}}

      {:ok, %{status: status, body: body}} ->
        {:error, "Failed to fetch sold products: HTTP #{status} - #{inspect(body)}"}

      {:error, error} ->
        {:error, "Network error fetching sold products: #{inspect(error)}"}
    end
  end

  defp fetch_all_orders(jwt), do: fetch_orders_page(jwt, 0, [])

  defp fetch_orders_page(jwt, offset, acc) do
    case fetch_orders(jwt, offset) do
      {:ok, %{list: list, total: total}} ->
        all = acc ++ list

        if length(all) < total do
          fetch_orders_page(jwt, offset + length(list), all)
        else
          {:ok, all}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_orders(jwt, offset) do
    headers = auth_headers(jwt)
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

  defp auth_headers(jwt) do
    [
      {"authorization", "Bearer #{jwt}"},
      {"x-language", "et"},
      {"x-country", "EE"},
      {"accept", "application/json"}
    ]
  end

  defp parse_price(nil), do: nil
  defp parse_price(n) when is_number(n), do: Decimal.new(to_string(n))

  defp parse_price(s) when is_binary(s) do
    case Decimal.parse(s) do
      {d, _} -> d
      :error -> nil
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(s) when is_binary(s) do
    case DateTime.from_iso8601(s) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end
