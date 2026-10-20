defmodule Kirbs.Resources.YagaCategoryMapping do
  @moduledoc """
  Maps an own-shop Category to a Yaga.ee category id. Used only by the Yaga uploader.
  """
  use Ash.Resource,
    domain: Kirbs,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "yaga_category_mappings"
    repo Kirbs.Repo

    references do
      reference :category, on_delete: :delete
    end
  end

  code_interface do
    define :get_by_category, args: [:category_id]
    define :upsert
    define :destroy
  end

  actions do
    default_accept [:category_id, :yaga_category_id]

    defaults [:destroy]

    read :read do
      primary? true
    end

    read :get_by_category do
      get? true
      argument :category_id, :uuid, allow_nil?: false
      filter expr(category_id == ^arg(:category_id))
    end

    create :upsert do
      upsert? true
      upsert_identity :unique_category
      upsert_fields [:yaga_category_id]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :yaga_category_id, :integer, allow_nil?: false

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :category, Kirbs.Resources.Category do
      allow_nil? false
    end
  end

  identities do
    identity :unique_category, [:category_id]
  end
end
