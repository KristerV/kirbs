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
         {:ok, item} <- Item.apply_categorization(item, Map.take(proposal, @fields)),
         {:ok, _proposal} <- CategorizationProposal.mark_applied(proposal) do
      {:ok, item}
    end
  end

  defp fetch_item(_proposal, %Item{} = item), do: {:ok, item}
  defp fetch_item(proposal, nil), do: Item.get(proposal.item_id)
end
