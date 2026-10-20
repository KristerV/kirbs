defmodule Kirbs.Resources.Item.Validations.HeldBy do
  @moduledoc """
  Guards `Item.sell_on_kirbs` when `held_until` is given: the item may only be sold to the
  order that holds it. Allowed when the item is available, or reserved with exactly that
  order's `held_until` deadline. An item reserved by another buyer's newer hold (or already
  sold) is refused. Atomic, like `Reservable`.
  """
  use Ash.Resource.Validation

  alias Ash.Error.Changes.InvalidAttribute

  @message "ese on juba teisele ostjale broneeritud"

  @impl true
  def atomic(changeset, _opts, _context) do
    case Ash.Changeset.get_argument(changeset, :held_until) do
      nil ->
        :ok

      held_until ->
        {:atomic, [:kirbs_status, :reserved_until],
         expr(
           not (^atomic_ref(:kirbs_status) == :available or
                  (^atomic_ref(:kirbs_status) == :reserved and
                     ^atomic_ref(:reserved_until) == ^held_until))
         ),
         expr(
           error(^InvalidAttribute, %{
             field: :kirbs_status,
             value: ^atomic_ref(:kirbs_status),
             message: ^@message
           })
         )}
    end
  end

  @impl true
  def validate(changeset, _opts, _context) do
    item = changeset.data
    held_until = Ash.Changeset.get_argument(changeset, :held_until)

    if is_nil(held_until) or item.kirbs_status == :available or
         (item.kirbs_status == :reserved and item.reserved_until == held_until) do
      :ok
    else
      {:error, field: :kirbs_status, message: @message}
    end
  end
end
