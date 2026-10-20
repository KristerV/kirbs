defmodule Kirbs.Resources.ItemCategory do
  @moduledoc """
  Extra (non-primary) category of an item, e.g. a jacket+trousers set whose primary category
  is Joped and that also shows up under Valipuksid. The primary category stays on
  `items.category_id`. Written only through `Item.set_extra_categories` (see docs/taxonomy.md).
  """
  use Ash.Resource,
    domain: Kirbs,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "item_categories"
    repo Kirbs.Repo

    references do
      reference :item, on_delete: :delete
      reference :category, on_delete: :delete
    end

    custom_indexes do
      index [:category_id]
    end
  end

  code_interface do
    define :create
    define :destroy
    define :list_by_item, args: [:item_id]
  end

  actions do
    default_accept [:item_id, :category_id]

    defaults [:create, :destroy]

    read :read do
      primary? true
    end

    read :list_by_item do
      argument :item_id, :uuid, allow_nil?: false
      filter expr(item_id == ^arg(:item_id))
    end
  end

  attributes do
    uuid_primary_key :id
    create_timestamp :created_at
  end

  relationships do
    belongs_to :item, Kirbs.Resources.Item do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :category, Kirbs.Resources.Category do
      allow_nil? false
      attribute_writable? true
    end
  end

  identities do
    identity :unique_item_category, [:item_id, :category_id]
  end
end
