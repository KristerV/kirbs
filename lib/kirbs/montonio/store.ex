defmodule Kirbs.Montonio.Store do
  @moduledoc """
  Owns the ETS tables used by the Montonio integration: the pickup point cache
  and the webhook de-duplication set. In-memory only (lost on deploy): pickup
  points are lazily refetched, and handlers must be idempotent anyway.
  """
  use GenServer

  @points :montonio_pickup_points
  @seen :montonio_seen_events

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(_) do
    :ets.new(@points, [:named_table, :public, read_concurrency: true])
    :ets.new(@seen, [:named_table, :public])
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

  def seen?(key), do: :ets.member(@seen, key)

  def mark_seen(key) do
    :ets.insert(@seen, {key, System.os_time(:second)})
    :ok
  end

  def clear do
    :ets.delete_all_objects(@points)
    :ets.delete_all_objects(@seen)
    :ok
  end
end
