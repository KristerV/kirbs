defmodule Kirbs.Resources.SearchSynonym do
  @moduledoc """
  Shop search query expansion: `term` is expanded to itself plus `alternatives`.
  Terms and alternatives are stored lowercase.
  """
  use Ash.Resource,
    domain: Kirbs,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "search_synonyms"
    repo Kirbs.Repo
  end

  code_interface do
    define :list, args: []
    define :create
    define :upsert
    define :destroy
  end

  actions do
    default_accept [:term, :alternatives]

    defaults [:create, :destroy]

    read :read do
      primary? true
    end

    read :list

    create :upsert do
      upsert? true
      upsert_identity :unique_term
      upsert_fields [:alternatives]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :term, :string, allow_nil?: false

    attribute :alternatives, {:array, :string} do
      allow_nil? false
      default []
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_term, [:term]
  end
end
