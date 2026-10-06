defmodule Kirbs.Resources.Category do
  @moduledoc """
  Own shop category tree. Audience roots (Lapsed, Naised, ...) with at most two
  levels below. See docs/taxonomy.md.
  """
  use Ash.Resource,
    domain: Kirbs,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "categories"
    repo Kirbs.Repo
  end

  code_interface do
    define :get, args: [:id]
    define :get_by_slug, args: [:slug]
    define :list_roots, args: []
    define :list_children, args: [:parent_id]
    define :list_all, args: []
    define :upsert
    define :create
    define :update
    define :destroy
  end

  actions do
    default_accept [:slug, :name_et, :position, :parent_id]

    defaults [:create, :update, :destroy]

    read :read do
      primary? true
    end

    read :get do
      get_by [:id]
    end

    read :get_by_slug do
      get? true
      argument :slug, :string, allow_nil?: false
      filter expr(slug == ^arg(:slug))
    end

    read :list_roots do
      filter expr(is_nil(parent_id))
      prepare build(sort: [position: :asc, name_et: :asc])
    end

    read :list_children do
      argument :parent_id, :uuid, allow_nil?: false
      filter expr(parent_id == ^arg(:parent_id))
      prepare build(sort: [position: :asc, name_et: :asc])
    end

    read :list_all do
      prepare build(sort: [position: :asc, name_et: :asc])
    end

    create :upsert do
      upsert? true
      upsert_identity :unique_slug
      upsert_fields [:name_et, :position, :parent_id]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :slug, :string, allow_nil?: false
    attribute :name_et, :string, allow_nil?: false
    attribute :position, :integer, allow_nil?: false, default: 0

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :parent, __MODULE__ do
      allow_nil? true
    end

    has_many :children, __MODULE__ do
      destination_attribute :parent_id
      sort position: :asc
    end

    has_one :yaga_category_mapping, Kirbs.Resources.YagaCategoryMapping
  end

  identities do
    identity :unique_slug, [:slug]
  end
end
