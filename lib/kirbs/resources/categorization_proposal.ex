defmodule Kirbs.Resources.CategorizationProposal do
  @moduledoc """
  A proposed category + typed attributes for an item, produced by the categorization
  backfill. Nothing is applied to the item until a proposal is explicitly approved.
  """
  use Ash.Resource,
    domain: Kirbs,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "categorization_proposals"
    repo Kirbs.Repo

    references do
      reference :item, on_delete: :delete
    end
  end

  code_interface do
    define :get, args: [:id]
    define :list_pending, args: []
    define :list_pending_above, args: [:min_confidence]
    define :get_by_item, args: [:item_id]
    define :list_by_category, args: [:category_id]
    define :propose
    define :update
    define :mark_applied, args: []
    define :reject, args: []
    define :count_pending, args: []
  end

  actions do
    default_accept [
      :item_id,
      :category_id,
      :age_group,
      :gender,
      :season,
      :condition,
      :brand,
      :size,
      :colors,
      :materials,
      :confidence
    ]

    defaults [:create]

    read :read do
      primary? true
    end

    read :get do
      get_by [:id]
    end

    read :get_by_item do
      get? true
      argument :item_id, :uuid, allow_nil?: false
      filter expr(item_id == ^arg(:item_id))
    end

    read :list_by_category do
      argument :category_id, :uuid, allow_nil?: false
      filter expr(category_id == ^arg(:category_id))
    end

    read :list_pending do
      filter expr(status == :pending)

      prepare build(
                sort: [confidence: :desc, created_at: :asc],
                load: [:category, item: [:images]]
              )
    end

    read :list_pending_above do
      argument :min_confidence, :float, allow_nil?: false
      filter expr(status == :pending and confidence >= ^arg(:min_confidence))
      prepare build(sort: [confidence: :desc, created_at: :asc], load: [:category])
    end

    read :count_pending do
      filter expr(status == :pending)
    end

    create :propose do
      upsert? true
      upsert_identity :unique_item

      upsert_fields [
        :category_id,
        :age_group,
        :gender,
        :season,
        :condition,
        :brand,
        :size,
        :colors,
        :materials,
        :confidence,
        :status
      ]

      change set_attribute(:status, :pending)
    end

    update :update do
      primary? true
      require_atomic? false
    end

    update :mark_applied do
      accept []
      require_atomic? false
      change set_attribute(:status, :applied)
    end

    update :reject do
      accept []
      require_atomic? false
      change set_attribute(:status, :rejected)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :age_group, :atom do
      constraints one_of: [:baby, :toddler, :child, :teen, :adult]
    end

    attribute :gender, :atom do
      constraints one_of: [:girl, :boy, :unisex, :woman, :man]
    end

    attribute :season, :atom do
      constraints one_of: [:spring_autumn, :summer, :winter, :all_year]
    end

    attribute :condition, :atom do
      constraints one_of: [:new_with_tags, :like_new, :good, :fair]
    end

    attribute :brand, :string
    attribute :size, :string
    attribute :colors, {:array, :string}
    attribute :materials, {:array, :string}

    attribute :confidence, :float do
      allow_nil? false
      default 0.0
      constraints min: 0.0, max: 1.0
    end

    attribute :status, :atom do
      allow_nil? false
      default :pending
      constraints one_of: [:pending, :applied, :rejected]
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :item, Kirbs.Resources.Item do
      allow_nil? false
    end

    belongs_to :category, Kirbs.Resources.Category
  end

  identities do
    identity :unique_item, [:item_id]
  end
end
