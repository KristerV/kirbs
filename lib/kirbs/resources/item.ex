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
    define :destroy
    define :clear_ai_data
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
      :ai_suggested_price,
      :ai_price_explanation,
      :listed_price,
      :sold_price,
      :status,
      :yaga_id,
      :yaga_slug,
      :upload_error
    ]

    defaults [:create, :read, :update, :destroy]

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

    update :clear_ai_data do
      accept []
      require_atomic? false

      change fn changeset, _context ->
        changeset
        |> Ash.Changeset.force_change_attribute(:brand, nil)
        |> Ash.Changeset.force_change_attribute(:size, nil)
        |> Ash.Changeset.force_change_attribute(:colors, nil)
        |> Ash.Changeset.force_change_attribute(:materials, nil)
        |> Ash.Changeset.force_change_attribute(:description, nil)
        |> Ash.Changeset.force_change_attribute(:quality, nil)
        |> Ash.Changeset.force_change_attribute(:suggested_category, nil)
        |> Ash.Changeset.force_change_attribute(:ai_suggested_price, nil)
        |> Ash.Changeset.force_change_attribute(:ai_price_explanation, nil)
        |> Ash.Changeset.force_change_attribute(:status, :pending)
      end
    end
  end

  attributes do
    uuid_primary_key :id

    # AI-extracted data (also used for Yaga upload via YagaTaxonomy lookup)
    attribute :brand, :string
    attribute :size, :string
    attribute :colors, {:array, :string}
    attribute :materials, {:array, :string}
    attribute :description, :string
    attribute :quality, :string
    attribute :suggested_category, :string

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
