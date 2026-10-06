defmodule Kirbs.Services.Orders.FetchMontonioLabel do
  @moduledoc "Fetches the label PDF url of an order's Montonio shipment and stores it on the order."

  alias Kirbs.Montonio.Shipping.FetchLabel
  alias Kirbs.Resources.Order

  def run(order_id) do
    with {:ok, order} <- Order.get(order_id),
         {:ok, shipment_id} <- shipment_id(order),
         {:ok, url} <- FetchLabel.run(%{shipment_ids: [shipment_id]}),
         {:ok, order} <- Order.set_shipment(order, %{shipment_label_url: url}) do
      {:ok, order}
    end
  end

  defp shipment_id(%{montonio_shipment_id: id}) when is_binary(id), do: {:ok, id}
  defp shipment_id(_order), do: {:error, :no_shipment}
end
