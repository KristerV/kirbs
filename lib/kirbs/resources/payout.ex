defmodule Kirbs.Resources.Payout do
  use Ash.Resource,
    domain: Kirbs,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "payouts"
    repo Kirbs.Repo
  end

  code_interface do
    define :get, args: [:id]
    define :list
    define :list_by_client, args: [:client_id]
    define :create
  end

  actions do
    default_accept [:client_id, :amount, :sent_at, :for_month]

    defaults [:create, :read, :destroy]

    read :get do
      get_by [:id]
    end

    read :list do
      prepare build(sort: [sent_at: :desc], load: [:client])
    end

    read :list_by_client do
      argument :client_id, :uuid do
        allow_nil? false
      end

      prepare build(sort: [sent_at: :desc])
      filter expr(client_id == ^arg(:client_id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :amount, :decimal do
      allow_nil? false
    end

    attribute :sent_at, :utc_datetime_usec do
      allow_nil? false
    end

    attribute :for_month, :date do
      allow_nil? false
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :client, Kirbs.Resources.Client do
      allow_nil? false
    end
  end
end
