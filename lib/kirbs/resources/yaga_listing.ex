defmodule Kirbs.Resources.YagaListing do
  @moduledoc """
  The Yaga.ee sales-channel listing of an Item. At most one per item.

  Item lifecycle (pending -> sold) lives on `Item.status`; everything that is
  specific to the Yaga channel lives here.
  """
  use Ash.Resource,
    domain: Kirbs,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "yaga_listings"
    repo Kirbs.Repo

    references do
      reference :item, on_delete: :delete
    end
  end

  code_interface do
    define :get_by_item, args: [:item_id]
    define :mark_listed
    define :mark_failed
    define :mark_sold, args: []
    define :mark_relisted, args: []
    define :list
    define :update
    define :destroy
  end

  actions do
    default_accept [:item_id, :yaga_id, :yaga_slug, :uploaded_at, :upload_error, :status]

    defaults [:destroy]

    update :update do
      primary? true
    end

    read :list do
      primary? true
    end

    read :get_by_item do
      get? true
      argument :item_id, :uuid, allow_nil?: false
      filter expr(item_id == ^arg(:item_id))
    end

    create :mark_listed do
      accept [:item_id, :yaga_id, :yaga_slug, :uploaded_at]
      upsert? true
      upsert_identity :unique_item
      upsert_fields [:yaga_id, :yaga_slug, :uploaded_at, :upload_error, :status]

      change set_attribute(:status, :listed)
      change set_attribute(:upload_error, nil)

      change fn changeset, _ctx ->
        if Ash.Changeset.get_attribute(changeset, :uploaded_at) do
          changeset
        else
          Ash.Changeset.force_change_attribute(changeset, :uploaded_at, DateTime.utc_now())
        end
      end
    end

    create :mark_failed do
      accept [:item_id, :upload_error]
      upsert? true
      upsert_identity :unique_item
      upsert_fields [:upload_error, :status]

      change set_attribute(:status, :failed)
    end

    update :mark_sold do
      accept []
      change set_attribute(:status, :sold)
    end

    update :mark_relisted do
      accept []
      change set_attribute(:status, :listed)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :yaga_id, :integer
    attribute :yaga_slug, :string
    attribute :uploaded_at, :utc_datetime_usec
    attribute :upload_error, :string

    attribute :status, :atom do
      allow_nil? false
      default :listed
      constraints one_of: [:listed, :failed, :sold, :delisted]
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :item, Kirbs.Resources.Item do
      allow_nil? false
    end
  end

  identities do
    identity :unique_item, [:item_id]
  end
end
