defmodule Kirbs.Resources.Order.Changes.EnqueueShipment do
  @moduledoc """
  After `mark_paid`: enqueues `Kirbs.Jobs.CreateMontonioShipmentJob` for Montonio-paid parcel
  machine orders (only when Montonio is configured). Own pickup and manually paid orders are
  handled by hand on `/orders/shipping`.
  """
  use Ash.Resource.Change

  alias Kirbs.Montonio.Config

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, order ->
      if shipment?(order) do
        {:ok, _job} =
          %{order_id: order.id} |> Kirbs.Jobs.CreateMontonioShipmentJob.new() |> Oban.insert()
      end

      {:ok, order}
    end)
  end

  defp shipment?(order) do
    order.payment_method == :montonio and Config.configured?() and order.delivery_method != nil
  end
end
