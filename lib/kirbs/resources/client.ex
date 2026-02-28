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
    define :find_by_email, args: [:email]
    define :find_by_iban, args: [:iban]
    define :find_by_name, args: [:name]
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

    read :find_by_email do
      get_by [:email]
    end

    read :find_by_iban do
      get_by [:iban]
    end

    read :find_by_name do
      get? true
      argument :name, :string, allow_nil?: false
      filter expr(fragment("lower(?) = lower(?)", name, ^arg(:name)))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? true
    end

    attribute :phone, :string do
      allow_nil? true
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
    has_many :payouts, Kirbs.Resources.Payout
  end

  identities do
    identity :unique_client, [:name, :phone, :email, :iban], nils_distinct?: false
  end
end
