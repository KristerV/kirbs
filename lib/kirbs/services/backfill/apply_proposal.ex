defmodule Kirbs.Services.Backfill.ApplyProposal do
  @moduledoc """
  Applies one categorization proposal to its item and marks the proposal applied.
  Only ever called from an explicit action (approve button, apply-all, or `apply: true` backfill).
  """

  alias Kirbs.Resources.{CategorizationProposal, Item}

  @fields [
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

  def run(proposal, item \\ nil) do
    with {:ok, item} <- fetch_item(proposal, item),
         {:ok, item} <- Item.apply_categorization(item, params(proposal)),
         {:ok, _proposal} <- CategorizationProposal.mark_applied(proposal) do
      {:ok, item}
    end
  end

  # waterproof is only ever switched on (never off), extras replace the item's extras.
  defp params(proposal) do
    proposal
    |> Map.take(@fields)
    |> Map.put(:extra_category_ids, proposal.extra_category_ids -- [proposal.category_id])
    |> then(&if(proposal.waterproof, do: Map.put(&1, :waterproof, true), else: &1))
  end

  defp fetch_item(_proposal, %Item{} = item), do: {:ok, item}
  defp fetch_item(proposal, nil), do: Item.get(proposal.item_id)
end
