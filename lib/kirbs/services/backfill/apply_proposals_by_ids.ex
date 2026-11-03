defmodule Kirbs.Services.Backfill.ApplyProposalsByIds do
  @moduledoc """
  Applies the given pending proposals (those with a category), e.g. everything visible on the backfill page.
  """

  alias Kirbs.Resources.CategorizationProposal
  alias Kirbs.Services.Backfill.ApplyProposal

  def run(ids) when is_list(ids) do
    with {:ok, proposals} <- CategorizationProposal.list_pending_by_ids(ids) do
      results = Enum.map(proposals, &ApplyProposal.run/1)

      {:ok,
       %{
         applied: Enum.count(results, &match?({:ok, _}, &1)),
         failed: Enum.count(results, &(not match?({:ok, _}, &1)))
       }}
    end
  end
end
