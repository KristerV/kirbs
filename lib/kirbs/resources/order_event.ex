defmodule Kirbs.Resources.OrderEvent do
  @moduledoc """
  Append-only audit trail of everything that happens to an Order (state changes, verified
  Montonio webhooks / returns, API results, admin notes). `payload` holds verified JWT claims or
  API responses with secrets redacted.

  Webhook idempotency: (`kind`, `external_id`) is unique where `external_id` is set, so a replayed
  webhook can be detected with `get_by_external/2` before it changes anything.
  """
  use Ash.Resource,
    domain: Kirbs,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "order_events"
    repo Kirbs.Repo

    references do
      reference :order, on_delete: :delete
    end

    identity_wheres_to_sql unique_kind_external_id: "external_id IS NOT NULL"
  end

  code_interface do
    define :record
    define :add_note
    define :list_for_order, args: [:order_id]
    define :get_by_external, args: [:kind, :external_id]
  end

  actions do
    default_accept [:order_id, :kind, :source, :payload, :summary, :external_id, :occurred_at]

    defaults [:destroy]

    read :read do
      primary? true
    end

    read :list_for_order do
      argument :order_id, :uuid, allow_nil?: false
      filter expr(order_id == ^arg(:order_id))
      prepare build(sort: [occurred_at: :asc, created_at: :asc])
    end

    read :get_by_external do
      get? true
      argument :kind, :atom, allow_nil?: false
      argument :external_id, :string, allow_nil?: false
      filter expr(kind == ^arg(:kind) and external_id == ^arg(:external_id))
    end

    create :record do
      primary? true
    end

    create :add_note do
      accept [:order_id, :summary]
      change set_attribute(:kind, :manual_note)
      change set_attribute(:source, :admin)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, :atom do
      allow_nil? false

      constraints one_of: [
                    :payment_created,
                    :payment_webhook,
                    :payment_return,
                    :payment_paid,
                    :payment_failed,
                    :payment_cancelled,
                    :shipment_created,
                    :shipment_webhook,
                    :label_created,
                    :status_changed,
                    :refund_recorded,
                    :manual_note,
                    :error
                  ]
    end

    attribute :occurred_at, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
    end

    attribute :source, :atom do
      allow_nil? false
      default :system
      constraints one_of: [:montonio_webhook, :montonio_return, :api, :admin, :system]
    end

    attribute :payload, :map, allow_nil?: false, default: %{}
    attribute :summary, :string
    attribute :external_id, :string

    create_timestamp :created_at
  end

  relationships do
    belongs_to :order, Kirbs.Resources.Order, allow_nil?: false
  end

  identities do
    identity :unique_kind_external_id, [:kind, :external_id], where: expr(not is_nil(external_id))
  end
end
