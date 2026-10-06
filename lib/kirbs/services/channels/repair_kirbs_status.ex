defmodule Kirbs.Services.Channels.RepairKirbsStatus do
  @moduledoc """
  One-off repair: `Item.kirbs_status` must be `:sold` exactly when `Item.status == :sold`.

  Items sold before `mark_sold` kept `kirbs_status` in sync (e.g. every historic Yaga sale)
  are flipped to `:sold`; items with a stale `:sold` kirbs_status but a non-sold status are
  made `:available` again. Idempotent. Run on a release with:

      bin/kirbs eval 'Kirbs.Release.repair_kirbs_status()'
  """

  alias Kirbs.Resources.Item

  def run do
    with {:ok, to_sold} <- Item.list_sold_with_stale_kirbs_status(),
         {:ok, to_available} <- Item.list_kirbs_sold_with_stale_status(),
         :ok <- update_all(to_sold, :sold),
         :ok <- update_all(to_available, :available) do
      {:ok, %{marked_sold: length(to_sold), marked_available: length(to_available)}}
    end
  end

  defp update_all(items, kirbs_status) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case Item.update(item, %{kirbs_status: kirbs_status}) do
        {:ok, _} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
end
