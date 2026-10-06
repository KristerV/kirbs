defmodule Kirbs.Jobs.CreateMontonioShipmentJob do
  @moduledoc "Registers the Montonio shipment of a paid order. Enqueued by `Order.mark_paid`."
  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [period: 300, keys: [:order_id]]

  alias Kirbs.Services.Orders.CreateMontonioShipment

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"order_id" => order_id}}) do
    with {:ok, _order} <- CreateMontonioShipment.run(order_id) do
      :ok
    end
  end
end
