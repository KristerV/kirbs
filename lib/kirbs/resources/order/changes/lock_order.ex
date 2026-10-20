defmodule Kirbs.Resources.Order.Changes.LockOrder do
  @moduledoc """
  Serializes order transitions. Before the action writes, locks the order row
  (`SELECT ... FOR UPDATE`) and swaps the changeset's data for the fresh row, so a payment,
  a cancel and a checkout submit can never act on a stale copy of each other's result.

  Options: `statuses` (the order must currently be in one of these) and `unpaid` (the order
  must not be paid yet). Both are checked against the locked row.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Kirbs.Resources.Order

  @impl true
  def change(changeset, opts, _context) do
    Ash.Changeset.before_action(changeset, &lock(&1, opts))
  end

  def lock(changeset, opts \\ []) do
    fresh =
      Order
      |> Ash.Query.filter(id == ^changeset.data.id)
      |> Ash.Query.lock(:for_update)
      |> Ash.read_one!()

    changeset
    |> Map.put(:data, fresh)
    |> check(fresh, opts)
  end

  defp check(changeset, order, opts) do
    cond do
      opts[:statuses] && order.status not in opts[:statuses] ->
        Ash.Changeset.add_error(changeset,
          field: :status,
          message: "tellimuse staatus on muutunud"
        )

      opts[:unpaid] && order.payment_status == :paid ->
        Ash.Changeset.add_error(changeset, field: :payment_status, message: "on juba tasutud")

      true ->
        changeset
    end
  end
end
