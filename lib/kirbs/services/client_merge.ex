defmodule Kirbs.Services.ClientMerge do
  @moduledoc """
  Service for merging two clients.
  Moves all bags from the secondary client to the primary client, then deletes the secondary.
  """

  alias Kirbs.Resources.{Client, Bag}

  def run(primary_client_id, secondary_client_id) do
    with {:ok, :different} <- validate_different_clients(primary_client_id, secondary_client_id),
         {:ok, primary} <- load_client(primary_client_id),
         {:ok, secondary} <- load_client(secondary_client_id),
         {:ok, _} <- reassign_bags(secondary, primary),
         {:ok, _} <- delete_client(secondary) do
      {:ok, primary}
    end
  end

  defp validate_different_clients(id1, id2) do
    if id1 == id2 do
      {:error, "Cannot merge a client with itself"}
    else
      {:ok, :different}
    end
  end

  defp load_client(client_id) do
    case Ash.get(Client, client_id, load: [:bags]) do
      {:ok, nil} -> {:error, "Client not found"}
      {:ok, client} -> {:ok, client}
      {:error, reason} -> {:error, reason}
    end
  end

  defp reassign_bags(secondary, primary) do
    results =
      Enum.map(secondary.bags, fn bag ->
        Bag.update(bag, %{client_id: primary.id})
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      {:error, reason} -> {:error, reason}
      nil -> {:ok, :reassigned}
    end
  end

  defp delete_client(client) do
    case Ash.destroy(client) do
      :ok -> {:ok, :deleted}
      {:error, reason} -> {:error, reason}
    end
  end
end
