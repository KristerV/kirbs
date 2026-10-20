defmodule Kirbs.Services.Orders.SmokeMontonioCheckout do
  @moduledoc """
  Sandbox smoke test of the Montonio checkout path without a browser: picks (or creates, via the
  dev seed) an available item, opens an order, submits it with an Omniva parcel machine, then
  starts the Montonio payment. Returns the order and the sandbox payment url to open in a browser.
  """

  alias Kirbs.Resources.{Item, Order}
  alias Kirbs.Services.Orders.StartMontonioPayment
  alias Kirbs.Shipping.PickupPoints

  def run do
    with {:ok, item} <- find_item(),
         {:ok, order} <- Order.start([item.id]),
         {:ok, params} <- checkout_params(),
         {:ok, order} <- Order.submit(order, params),
         {:ok, payment_url} <- StartMontonioPayment.run(order),
         {:ok, order} <- Order.get(order.id) do
      {:ok, %{order: order, payment_url: payment_url, item: item}}
    end
  end

  defp find_item do
    case available_item() do
      %Item{} = item ->
        {:ok, item}

      nil ->
        with {:ok, :seeded} <- Kirbs.Services.Categories.SeedTree.run(),
             {:ok, _items} <- Kirbs.Services.Shop.SeedDevItems.run(),
             %Item{} = item <- available_item() do
          {:ok, item}
        else
          _ -> {:error, :no_available_item}
        end
    end
  end

  defp available_item do
    Enum.find(Item.list_for_sitemap!(), &(&1.kirbs_status == :available))
  end

  defp checkout_params do
    base = %{
      buyer_name: "Smoke Test",
      buyer_email: "smoke-test@example.com",
      buyer_phone: "+37255512345",
      delivery_method: :omniva_parcel_machine
    }

    case PickupPoints.list(:omniva, nil, 1) do
      [point | _] -> {:ok, Map.put(base, :pickup_point_id, point.id)}
      [] -> {:error, :no_pickup_points}
    end
  end
end
