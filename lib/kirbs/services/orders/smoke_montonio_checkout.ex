defmodule Kirbs.Services.Orders.SmokeMontonioCheckout do
  @moduledoc """
  Sandbox smoke test of the Montonio checkout path without a browser: picks (or creates, via the
  dev seed) an available item, opens an order, submits it with `payment_method: :montonio` and an
  Omniva parcel machine (falls back to own pickup when there are no points), then starts the
  Montonio payment. Returns the order and the sandbox payment url to open in a browser.
  """

  alias Kirbs.Resources.{Item, Order}
  alias Kirbs.Services.Orders.StartMontonioPayment
  alias Kirbs.Shipping.PickupPoints

  def run do
    with {:ok, item} <- find_item(),
         {:ok, order} <- Order.start([item.id]),
         {:ok, order} <- Order.submit(order, checkout_params()),
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
      payment_method: :montonio
    }

    case PickupPoints.list(:omniva, nil, 1) do
      [point | _] ->
        Map.merge(base, %{delivery_method: :omniva_parcel_machine, pickup_point_id: point.id})

      [] ->
        Map.put(base, :delivery_method, :pickup)
    end
  end
end
