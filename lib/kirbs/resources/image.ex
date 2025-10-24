defmodule Kirbs.Resources.Image do
  use Ash.Resource,
    domain: Kirbs,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "images"
    repo Kirbs.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :path, :string do
      allow_nil? false
    end

    attribute :order, :integer do
      allow_nil? false
      default 0
    end

    create_timestamp :created_at
  end

  relationships do
    belongs_to :bag, Kirbs.Resources.Bag do
      allow_nil? true
    end

    belongs_to :item, Kirbs.Resources.Item do
      allow_nil? true
    end
  end

  actions do
    default_accept [:path, :order, :bag_id, :item_id]

    defaults [:read, :destroy]

    create :create do
      accept [:path, :order, :bag_id, :item_id]
    end

    update :update do
      accept [:path, :order, :bag_id, :item_id]
    end

    read :get do
      get_by [:id]
    end

    read :list
  end

  code_interface do
    define :get, args: [:id]
    define :list
    define :create
    define :update
    define :destroy
  end
end
