defmodule Kirbs.Jobs.SendOrderEmailJob do
  @moduledoc "Sends one transactional order email. Enqueued by the Order actions."
  use Oban.Worker, queue: :default, max_attempts: 5

  alias Kirbs.Services.Orders.SendOrderEmail

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"order_id" => order_id, "kind" => kind}}) do
    with {:ok, _order} <- SendOrderEmail.run(order_id, String.to_existing_atom(kind)) do
      :ok
    end
  end
end
