defmodule Kirbs.Services.Backfill.ApplyProposalsAbove do
  @moduledoc """
  Applies every pending proposal with confidence >= `min_confidence`.
  """

  alias Kirbs.Resources.CategorizationProposal
  alias Kirbs.Services.Backfill.ApplyProposal

  def run(min_confidence) when is_number(min_confidence) do
    with {:ok, proposals} <- CategorizationProposal.list_pending_above(min_confidence * 1.0) do
      results = Enum.map(proposals, &ApplyProposal.run/1)

      {:ok,
       %{
         applied: Enum.count(results, &match?({:ok, _}, &1)),
         failed: Enum.count(results, &(not match?({:ok, _}, &1)))
       }}
    end
  end
end
