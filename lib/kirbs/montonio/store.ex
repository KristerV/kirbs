defmodule Kirbs.Montonio.Store do
  @moduledoc """
  Owns the ETS table used by the Montonio integration: the pickup point cache.
  In-memory only (lost on deploy), points are lazily refetched. Webhook de-duplication is
  persisted as `Kirbs.Resources.OrderEvent` rows (unique kind + external_id).
  """
  use GenServer

  @points :montonio_pickup_points

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(_) do
    :ets.new(@points, [:named_table, :public, read_concurrency: true])
    {:ok, nil}
  end

  def put_points(key, points) do
    :ets.insert(@points, {key, points})
    :ok
  end

  def get_points(key) do
    case :ets.lookup(@points, key) do
      [{_, points}] -> {:ok, points}
      [] -> :miss
    end
  end

  def clear do
    :ets.delete_all_objects(@points)
    :ok
  end
end
