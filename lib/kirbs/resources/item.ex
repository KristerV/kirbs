defmodule Kirbs.Resources.Item do
  use Ash.Resource,
    domain: Kirbs,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "items"
    repo Kirbs.Repo
  end

  code_interface do
    define :get, args: [:id]
    define :list
    define :get_by_bag, args: [:bag_id]
    define :create
    define :update
  end

  actions do
    default_accept [
      :bag_id,
      :brand,
      :size,
      :colors,
      :materials,
      :description,
      :quality,
      :suggested_category,
      :yaga_brand_id,
      :yaga_category_id,
      :yaga_colors_id_map,
      :yaga_materials_id_map,
      :yaga_condition_id,
      :ai_suggested_price,
      :ai_price_explanation,
      :listed_price,
      :sold_price,
      :status,
      :yaga_id,
      :yaga_slug,
      :upload_error
    ]

    defaults [:read, :destroy]

    create :create do
      accept [
        :bag_id,
        :brand,
        :size,
        :colors,
        :materials,
        :description,
        :quality,
        :suggested_category,
        :yaga_brand_id,
        :yaga_category_id,
        :yaga_colors_id_map,
        :yaga_materials_id_map,
        :yaga_condition_id,
        :ai_suggested_price,
        :ai_price_explanation,
        :listed_price,
        :sold_price,
        :status,
        :yaga_id,
        :yaga_slug,
        :upload_error
      ]
    end

    update :update do
      accept [
        :bag_id,
        :brand,
        :size,
        :colors,
        :materials,
        :description,
        :quality,
        :suggested_category,
        :yaga_brand_id,
        :yaga_category_id,
        :yaga_colors_id_map,
        :yaga_materials_id_map,
        :yaga_condition_id,
        :ai_suggested_price,
        :ai_price_explanation,
        :listed_price,
        :sold_price,
        :status,
        :yaga_id,
        :yaga_slug,
        :upload_error
      ]
    end

    read :get do
      get_by [:id]
    end

    read :list

    read :get_by_bag do
      argument :bag_id, :uuid do
        allow_nil? false
      end

      filter expr(bag_id == ^arg(:bag_id))
    end
  end

  attributes do
    uuid_primary_key :id

    # AI-extracted data
    attribute :brand, :string
    attribute :size, :string
    attribute :colors, {:array, :string}
    attribute :materials, {:array, :string}
    attribute :description, :string
    attribute :quality, :string
    attribute :suggested_category, :string

    # Yaga-specific fields
    attribute :yaga_brand_id, :integer
    attribute :yaga_category_id, :integer
    attribute :yaga_colors_id_map, {:array, :integer}
    attribute :yaga_materials_id_map, {:array, :integer}
    attribute :yaga_condition_id, :integer

    # Pricing
    attribute :ai_suggested_price, :decimal
    attribute :ai_price_explanation, :string
    attribute :listed_price, :decimal
    attribute :sold_price, :decimal

    # Status
    attribute :status, :atom do
      allow_nil? false
      default :pending

      constraints one_of: [
                    :pending,
                    :ai_processed,
                    :reviewed,
                    :uploaded_to_yaga,
                    :sold,
                    :discarded,
                    :upload_failed
                  ]
    end

    # Yaga integration
    attribute :yaga_id, :integer
    attribute :yaga_slug, :string
    attribute :upload_error, :string

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :bag, Kirbs.Resources.Bag do
      allow_nil? false
    end

    has_many :images, Kirbs.Resources.Image
  end
end
