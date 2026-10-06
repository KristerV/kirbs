defmodule Kirbs.Jobs.ProcessItemJob do
  @moduledoc """
  Background job to process an item after photos are captured.
  Extracts item info from label photos, then proposes category + typed attributes.
  """

  use Oban.Worker, queue: :ai, max_attempts: 3, unique: true

  require Logger

  alias Kirbs.Resources.Item
  alias Kirbs.Services.Ai.{ItemCategorize, ItemInfoExtract}

  @categorization_fields [
    :category_id,
    :age_group,
    :gender,
    :season,
    :condition,
    :brand,
    :size,
    :colors,
    :materials
  ]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"item_id" => item_id}}) do
    case ItemInfoExtract.run(item_id) do
      {:ok, item} ->
        {:ok, item} = mark_as_processed(item)
        categorize(item)

        Phoenix.PubSub.broadcast(
          Kirbs.PubSub,
          "item:#{item_id}",
          {:item_processed, item_id}
        )

        {:ok, "Item #{item_id} processed"}

      {:error, :not_found} ->
        {:ok, "Item #{item_id} not found, skipping"}

      {:cancel, reason} ->
        {:cancel, reason}

      {:error, {:rate_limited, seconds}} ->
        {:snooze, seconds + 60}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp mark_as_processed(item) do
    Ash.update(item, %{status: :ai_processed})
  end

  # Best effort: a failed categorization must not redo the (expensive) extraction.
  # Uncategorized items are picked up later by the backfill.
  defp categorize(item) do
    with {:ok, result} <- ItemCategorize.run(item),
         {:ok, _item} <- Item.apply_categorization(item, Map.take(result, @categorization_fields)) do
      :ok
    else
      other ->
        Logger.warning("Categorization skipped for item #{item.id}: #{inspect(other)}")
        :error
    end
  end
end
