defmodule Kirbs.Resources.Order.Changes.SetRefundedAmount do
  @moduledoc "`Order.refund`: records the full order total as refunded."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.force_change_attribute(changeset, :refunded_cents, changeset.data.total_cents)
  end
end
