defmodule Kirbs.Jobs.UploadItemJob do
  @moduledoc """
  Background job to upload an item to yaga.ee marketplace.
  Multi-step process: create draft → upload photos → publish.
  """

  use Oban.Worker,
    queue: :yaga,
    max_attempts: 3,
    unique: [period: 60, keys: [:item_id]]

  alias Kirbs.Resources.Item
  alias Kirbs.Services.Yaga.Uploader

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"item_id" => item_id}}) do
    case Uploader.run(item_id) do
      {:ok, _item} ->
        maybe_enqueue_combination_job(item_id)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_enqueue_combination_job(item_id) do
    with {:ok, item} <- Ash.get(Item, item_id),
         group when not is_nil(group) <- item.combination_group,
         {:ok, items} <- Item.list_by_combination_group(group),
         true <- Enum.all?(items, &(&1.status == :uploaded_to_yaga)) do
      %{combination_group: group}
      |> Kirbs.Jobs.UpdateCombinationDescriptionsJob.new()
      |> Oban.insert()
    end
  end
end
