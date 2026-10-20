defmodule Kirbs.Services.Backfill.CategorizeBatch do
  @moduledoc """
  Categorizes one batch of items that have no category yet.

  Default is a dry run: proposals are stored, items are never touched. With `apply: true`
  proposals at or above `min_confidence` are applied to the item right away (the rest stay
  as pending proposals). Items already holding a proposal or a category are skipped, so
  re-running is safe; `after_id` is the resume cursor.
  """

  alias Kirbs.Resources.{CategorizationProposal, Item}
  alias Kirbs.Services.Ai.ItemCategorize

  def run(opts \\ []) do
    after_id = Keyword.get(opts, :after_id)
    limit = Keyword.get(opts, :limit, 25)
    apply? = Keyword.get(opts, :apply, false)
    min_confidence = Keyword.get(opts, :min_confidence, 0.85)

    with {:ok, items} <- Item.list_uncategorized(after_id, limit) do
      summary = categorize_items(items, %{apply: apply?, min_confidence: min_confidence})

      {:ok, Map.put(summary, :fetched, length(items))}
    end
  end

  defp categorize_items(items, config) do
    initial = %{proposed: 0, applied: 0, failed: 0, last_id: nil, rate_limited: nil}

    Enum.reduce_while(items, initial, fn item, acc ->
      case categorize_item(item, config) do
        {:ok, :proposed} -> {:cont, %{acc | proposed: acc.proposed + 1, last_id: item.id}}
        {:ok, :applied} -> {:cont, %{acc | applied: acc.applied + 1, last_id: item.id}}
        {:error, {:rate_limited, seconds}} -> {:halt, %{acc | rate_limited: seconds}}
        _failed -> {:cont, %{acc | failed: acc.failed + 1, last_id: item.id}}
      end
    end)
  end

  defp categorize_item(item, config) do
    with {:ok, result} <- ItemCategorize.run(item),
         {:ok, proposal} <- store_proposal(item, result) do
      maybe_apply(item, proposal, config)
    end
  end

  defp store_proposal(item, result) do
    result
    |> Map.take([
      :category_id,
      :age_group,
      :gender,
      :season,
      :condition,
      :waterproof,
      :extra_category_ids,
      :brand,
      :size,
      :colors,
      :materials,
      :confidence
    ])
    |> Map.put(:item_id, item.id)
    |> CategorizationProposal.propose()
  end

  defp maybe_apply(item, proposal, %{apply: true, min_confidence: min})
       when proposal.confidence >= min do
    with {:ok, _item} <- Kirbs.Services.Backfill.ApplyProposal.run(proposal, item) do
      {:ok, :applied}
    end
  end

  defp maybe_apply(_item, _proposal, _config), do: {:ok, :proposed}
end
