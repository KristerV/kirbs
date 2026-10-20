defmodule Kirbs.Jobs.DelistFromYagaJob do
  @moduledoc "Queues an item's Yaga listing for delisting after it sold on kirbs."

  use Oban.Worker,
    queue: :yaga,
    max_attempts: 3,
    unique: [period: 60, keys: [:item_id]]

  alias Kirbs.Services.Yaga.RequestDelist

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"item_id" => item_id}}) do
    with {:ok, _result} <- RequestDelist.run(item_id), do: :ok
  end
end
