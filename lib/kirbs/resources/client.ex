defmodule Kirbs.Resources.Client do
  use Ash.Resource,
    domain: Kirbs,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "clients"
    repo Kirbs.Repo
  end

  code_interface do
    define :get, args: [:id]
    define :list
    define :find_by_phone, args: [:phone]
    define :create
    define :update
  end

  actions do
    default_accept [:name, :phone, :email, :iban]

    defaults [:create, :read, :update, :destroy]

    read :get do
      get_by [:id]
    end

    read :list

    read :find_by_phone do
      get_by [:phone]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
    end

    attribute :phone, :string do
      allow_nil? false
    end

    attribute :email, :string do
      allow_nil? true
    end

    attribute :iban, :string do
      allow_nil? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :bags, Kirbs.Resources.Bag
  end

  identities do
    identity :unique_phone, [:phone]
  end
end
