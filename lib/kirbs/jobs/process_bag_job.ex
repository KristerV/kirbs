defmodule Kirbs.Jobs.ProcessBagJob do
  @moduledoc """
  Background job to process a bag after photos are captured.
  Extracts client info from the third photo and matches/creates client.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Kirbs.Services.Ai.{BagClientExtract, ClientMatch}
  alias Kirbs.Resources.Bag

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"bag_id" => bag_id}}) do
    with {:ok, extracted_info} <- BagClientExtract.run(bag_id),
         {:ok, client} <- ClientMatch.run(extracted_info),
         {:ok, _bag} <- update_bag_with_client(bag_id, client.id) do
      {:ok, "Bag processed successfully"}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_bag_with_client(bag_id, client_id) do
    case Ash.get(Bag, bag_id) do
      {:ok, bag} ->
        Ash.update(bag, %{client_id: client_id})

      {:error, reason} ->
        {:error, reason}
    end
  end
end
