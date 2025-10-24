defmodule Kirbs.Resources.YagaMetadata do
  use Ash.Resource,
    domain: Kirbs,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "yaga_metadata"
    repo Kirbs.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :metadata_type, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:brand, :category, :color, :material, :condition]
    end

    attribute :yaga_id, :integer do
      allow_nil? false
      public? true
    end

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :name_en, :string do
      allow_nil? true
      public? true
    end

    attribute :parent_id, :integer do
      allow_nil? true
      public? true
    end

    attribute :metadata_json, :map do
      allow_nil? true
      public? true
    end

    update_timestamp :updated_at
  end

  identities do
    identity :unique_metadata, [:metadata_type, :yaga_id]
  end

  actions do
    defaults [:destroy]

    read :get do
      argument :id, :uuid do
        allow_nil? false
      end

      get? true
      primary? true
    end

    read :list

    create :create do
      accept [:metadata_type, :yaga_id, :name, :name_en, :parent_id, :metadata_json]
      primary? true
      upsert? true
      upsert_identity :unique_metadata
      upsert_fields [:name, :name_en, :parent_id, :metadata_json, :updated_at]
    end

    update :update do
      accept [:metadata_type, :yaga_id, :name, :name_en, :parent_id, :metadata_json]
      primary? true
    end

    read :list_by_type do
      argument :metadata_type, :atom do
        allow_nil? false
        constraints one_of: [:brand, :category, :color, :material, :condition]
      end

      filter expr(metadata_type == ^arg(:metadata_type))
    end
  end

  code_interface do
    define :create
    define :update
    define :get, args: [:id]
    define :list
    define :list_by_type, args: [:metadata_type]
    define :destroy
  end
end
