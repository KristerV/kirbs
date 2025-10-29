defmodule Kirbs.Jobs.UploadItemJob do
  @moduledoc """
  Background job to upload an item to yaga.ee marketplace.
  Multi-step process: create draft → upload photos → publish.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: 60, keys: [:item_id]]

  alias Kirbs.Services.Yaga.Uploader

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"item_id" => item_id}}) do
    case Uploader.run(item_id) do
      {:ok, _item} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end
end
