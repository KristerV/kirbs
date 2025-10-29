defmodule Kirbs.Jobs.ProcessItemJob do
  @moduledoc """
  Background job to process an item after photos are captured.
  Extracts item info from label photos and updates the item.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Kirbs.Services.Ai.ItemInfoExtract

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"item_id" => item_id}}) do
    with {:ok, item} <- ItemInfoExtract.run(item_id),
         {:ok, _item} <- mark_as_processed(item) do
      # Broadcast completion to LiveView
      Phoenix.PubSub.broadcast(
        Kirbs.PubSub,
        "item:#{item_id}",
        {:item_processed, item_id}
      )

      {:ok, "Item processed successfully"}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp mark_as_processed(item) do
    Ash.update(item, %{status: :ai_processed})
  end
end
