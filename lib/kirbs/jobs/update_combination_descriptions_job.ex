defmodule Kirbs.Jobs.UpdateCombinationDescriptionsJob do
  use Oban.Worker,
    queue: :yaga,
    max_attempts: 3,
    unique: [period: 60, keys: [:combination_group]]

  alias Kirbs.Services.Yaga.CombinationDescriptionUpdate

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"combination_group" => combination_group}}) do
    case CombinationDescriptionUpdate.run(combination_group) do
      {:ok, _items} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
