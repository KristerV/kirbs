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
    define :get_bags_needing_review, args: []
    define :get_first_bag_needing_review, args: []
    define :create
    define :update
  end

  actions do
    default_accept [:client_id, :status]

    defaults [:create, :read, :update, :destroy]

    read :get do
      get_by [:id]
    end

    read :list do
      prepare build(sort: [number: :asc])
    end

    read :get_bags_needing_review do
      prepare build(sort: [created_at: :asc], load: [:client, :items])

      filter expr(status in [:pending, :ai_processed])
    end

    read :get_first_bag_needing_review do
      prepare build(sort: [created_at: :asc], limit: 1)

      filter expr(status in [:pending, :ai_processed])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :number, :integer do
      allow_nil? false
      generated? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :pending

      constraints one_of: [
                    :pending,
                    :ai_processed,
                    :reviewed
                  ]
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
    calculate :bag_needs_review, :boolean, expr(status in [:pending, :ai_processed])

    calculate :has_items_needing_review,
              :boolean,
              expr(exists(items, status in [:pending, :ai_processed]))
  end

  aggregates do
    count :item_count, :items

    count :items_needing_review_count, :items do
      filter expr(status in [:pending, :ai_processed])
    end
  end
end
