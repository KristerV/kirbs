defmodule Kirbs.Resources.OrderItem do
  @moduledoc "One purchased item on an Order, with title and price snapshotted at reservation time."
  use Ash.Resource,
    domain: Kirbs,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "order_items"
    repo Kirbs.Repo

    references do
      reference :order, on_delete: :delete
      reference :item, on_delete: :restrict
    end
  end

  code_interface do
    define :create
  end

  actions do
    default_accept [:order_id, :item_id, :title, :price_cents]

    defaults [:create, :destroy]

    read :read do
      primary? true
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string, allow_nil?: false
    attribute :price_cents, :integer, allow_nil?: false, constraints: [min: 0]

    create_timestamp :created_at
  end

  relationships do
    belongs_to :order, Kirbs.Resources.Order, allow_nil?: false
    belongs_to :item, Kirbs.Resources.Item, allow_nil?: false
  end

  identities do
    identity :unique_order_item, [:order_id, :item_id]
  end
end
