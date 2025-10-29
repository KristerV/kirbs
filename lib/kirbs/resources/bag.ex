defmodule Kirbs.Resources.Bag do
  use Ash.Resource,
    domain: Kirbs,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "bags"
    repo Kirbs.Repo
  end

  code_interface do
    define :get, args: [:id]
    define :list
    define :create
    define :update
  end

  actions do
    default_accept [:client_id]

    defaults [:create, :read, :update, :destroy]

    read :get do
      get_by [:id]
    end

    read :list
  end

  attributes do
    uuid_primary_key :id

    attribute :number, :integer do
      allow_nil? false
      generated? true
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :client, Kirbs.Resources.Client do
      allow_nil? true
    end

    has_many :items, Kirbs.Resources.Item
    has_many :images, Kirbs.Resources.Image
  end

  calculations do
    calculate :needs_review, :boolean, expr(exists(items, status in [:pending, :ai_processed]))
  end

  aggregates do
    count :item_count, :items
  end
end
