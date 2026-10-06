defmodule Kirbs.Resources.Item.Validations.Reservable do
  @moduledoc """
  An item can be reserved when it is available, or when its previous reservation has
  expired (the release job may not have run yet). Atomic, so the check and the write are
  one SQL statement and a qty-1 item cannot be reserved twice.
  """
  use Ash.Resource.Validation

  alias Ash.Error.Changes.InvalidAttribute

  @message "ese ei ole enam saadaval"

  @impl true
  def atomic(_changeset, _opts, _context) do
    {:atomic, [:kirbs_status, :reserved_until],
     expr(
       not (^atomic_ref(:kirbs_status) == :available or
              (^atomic_ref(:kirbs_status) == :reserved and
                 ^atomic_ref(:reserved_until) < now()))
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

    if item.kirbs_status == :available or
         ((item.kirbs_status == :reserved and item.reserved_until) &&
            DateTime.compare(item.reserved_until, DateTime.utc_now()) == :lt) do
      :ok
    else
      {:error, field: :kirbs_status, message: @message}
    end
  end
end
