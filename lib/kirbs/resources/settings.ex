defmodule Kirbs.Resources.Settings do
  use Ash.Resource,
    domain: Kirbs,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "settings"
    repo Kirbs.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :key, :string do
      allow_nil? false
      public? true
    end

    attribute :value, :string do
      allow_nil? true
      public? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_key, [:key]
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
      accept [:key, :value]
      primary? true
      upsert? true
      upsert_identity :unique_key
      upsert_fields [:value, :updated_at]
    end

    update :update do
      accept [:key, :value]
      primary? true
    end

    read :get_by_key do
      argument :key, :string do
        allow_nil? false
      end

      filter expr(key == ^arg(:key))
      get? true
    end
  end

  code_interface do
    define :create
    define :update
    define :get, args: [:id]
    define :list
    define :get_by_key, args: [:key]
    define :destroy
  end
end
