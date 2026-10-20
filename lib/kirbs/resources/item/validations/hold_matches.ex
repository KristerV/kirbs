defmodule Kirbs.Resources.Item.Validations.HoldMatches do
  @moduledoc """
  The item must still be reserved with exactly the `held_until` deadline the caller holds,
  so an order can only extend its own reservation, never overwrite a newer buyer's.
  Atomic, so the check and the write are one SQL statement.
  """
  use Ash.Resource.Validation

  alias Ash.Error.Changes.InvalidAttribute

  @message "ese on juba teisele ostjale broneeritud"

  @impl true
  def atomic(changeset, _opts, _context) do
    held_until = Ash.Changeset.get_argument(changeset, :held_until)

    {:atomic, [:kirbs_status, :reserved_until],
     expr(
       not (^atomic_ref(:kirbs_status) == :reserved and
              ^atomic_ref(:reserved_until) == ^held_until)
     ),
     expr(
       error(^InvalidAttribute, %{
         field: :kirbs_status,
         value: ^atomic_ref(:kirbs_status),
         message: ^@message
       })
     )}
  end

  @impl true
  def validate(changeset, _opts, _context) do
    item = changeset.data
    held_until = Ash.Changeset.get_argument(changeset, :held_until)

    if item.kirbs_status == :reserved and item.reserved_until == held_until do
      :ok
    else
      {:error, field: :kirbs_status, message: @message}
    end
  end
end
