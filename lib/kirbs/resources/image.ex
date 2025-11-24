defmodule Kirbs.Resources.Image do
  use Ash.Resource,
    domain: Kirbs,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "images"
    repo Kirbs.Repo
  end

  code_interface do
    define :get, args: [:id]
    define :list
    define :get_uncompressed, args: [:limit]
    define :create
    define :update
    define :destroy
  end

  actions do
    default_accept [:path, :order, :bag_id, :item_id, :is_label, :compressed]

    defaults [:read, :destroy]

    create :create do
      accept [:path, :order, :bag_id, :item_id, :is_label]
    end

    update :update do
      accept [:path, :order, :bag_id, :item_id, :is_label, :compressed]
    end

    read :get do
      get_by [:id]
    end

    read :list

    read :get_uncompressed do
      argument :limit, :integer do
        allow_nil? false
      end

      prepare build(limit: arg(:limit))
      filter expr(compressed == false and item.status == :uploaded_to_yaga)
    end
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

    attribute :is_label, :boolean do
      allow_nil? false
      default false
    end

    attribute :compressed, :boolean do
      allow_nil? false
      default false
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
end
