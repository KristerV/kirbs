defmodule Kirbs.Resources.Order do
  @moduledoc """
  A shop order. Lifecycle:

      pending    items reserved (10 min), buyer has not submitted checkout yet
      reserved   checkout submitted, awaiting payment (manual: 72h hold)
      paid       payment confirmed; items are sold
      shipped    handed to the carrier (tracking number optional)
      delivered  delivered / picked up
      cancelled  released (expired or cancelled); items are available again

  Public API for payment integrations (e.g. Montonio): `start/2` -> `submit/2` ->
  `set_montonio_ref/2` -> `mark_paid/1` | `cancel/2`. See docs/checkout.md.
  """
  use Ash.Resource,
    domain: Kirbs,
    data_layer: AshPostgres.DataLayer

  alias Kirbs.Resources.Order.Changes

  postgres do
    table "orders"
    repo Kirbs.Repo
  end

  code_interface do
    define :start, args: [:item_ids]
    define :submit
    define :get, args: [:id]
    define :get_by_token, args: [:token]
    define :list_recent, args: []
    define :list_to_ship, args: []
    define :list_expired, args: []
    define :set_montonio_ref
    define :mark_paid, args: []
    define :mark_shipped
    define :mark_delivered, args: []
    define :cancel
  end

  actions do
    default_accept [
      :buyer_name,
      :buyer_email,
      :buyer_phone,
      :delivery_method,
      :pickup_point_id,
      :payment_method
    ]

    defaults [:destroy]

    read :read do
      primary? true
    end

    read :get do
      get_by [:id]
      prepare build(load: [order_items: [item: :images]])
    end

    read :get_by_token do
      get? true
      argument :token, :string, allow_nil?: false
      filter expr(token == ^arg(:token))
      prepare build(load: [order_items: [item: :images]])
    end

    read :list_recent do
      prepare build(sort: [created_at: :desc], load: [:order_items])
    end

    # Paid but not yet shipped / handed over.
    read :list_to_ship do
      filter expr(status == :paid)
      prepare build(sort: [paid_at: :asc], load: [:order_items])
    end

    read :list_expired do
      filter expr(status in [:pending, :reserved] and reserved_until < now())
    end

    # Reserves the items (atomically, see Item.reserve) and opens a pending order.
    create :start do
      accept [:ab_visitor_id, :ab_assignments]
      argument :item_ids, {:array, :uuid}, allow_nil?: false, constraints: [min_length: 1]

      change Changes.ReserveItems
    end

    # Buyer submitted checkout: contact + delivery (+ payment method). Moves to :reserved and
    # extends the hold according to the payment method.
    update :submit do
      require_atomic? false

      accept [
        :buyer_name,
        :buyer_email,
        :buyer_phone,
        :delivery_method,
        :pickup_point_id,
        :payment_method
      ]

      validate attribute_equals(:status, :pending), message: "tellimus ei ole enam avatud"

      validate present([:buyer_name, :buyer_email, :buyer_phone, :delivery_method])

      validate match(:buyer_email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/),
        message: "ei ole korrektne e-posti aadress"

      change Changes.ApplyCheckout
      change {Changes.EnqueueEmail, kind: :received, payment_method: :manual}
    end

    update :set_montonio_ref do
      accept [:montonio_order_ref, :montonio_payment_url]
    end

    # Payment confirmed (admin for manual, webhook for Montonio). Sells the items.
    # Fails cleanly when the order was already paid or an item was sold elsewhere.
    update :mark_paid do
      require_atomic? false
      accept []

      validate attribute_in(:status, [:reserved, :cancelled]),
        message: "tellimust ei saa tasutuks märkida"

      validate attribute_does_not_equal(:payment_status, :paid), message: "on juba tasutud"

      change set_attribute(:status, :paid)
      change set_attribute(:payment_status, :paid)
      change set_attribute(:paid_at, &DateTime.utc_now/0)
      change set_attribute(:cancelled_at, nil)
      change set_attribute(:cancel_reason, nil)
      change Changes.SellItems
      change {Changes.EnqueueEmail, kind: :paid}
      change Changes.TrackPaid
    end

    update :mark_shipped do
      require_atomic? false
      accept [:tracking_number, :tracking_url]

      validate attribute_equals(:status, :paid), message: "tellimus ei ole tasutud"

      validate attribute_does_not_equal(:delivery_method, :pickup),
        message: "isevälja võtmist ei saadeta"

      change set_attribute(:status, :shipped)
      change set_attribute(:shipped_at, &DateTime.utc_now/0)
      change {Changes.EnqueueEmail, kind: :shipped}
    end

    update :mark_delivered do
      require_atomic? false
      accept []

      validate attribute_in(:status, [:paid, :shipped])

      change set_attribute(:status, :delivered)
      change set_attribute(:delivered_at, &DateTime.utc_now/0)
    end

    # Only unpaid orders. Releases the items.
    update :cancel do
      require_atomic? false
      accept [:cancel_reason]

      validate attribute_in(:status, [:pending, :reserved]),
        message: "tasutud tellimust ei saa tühistada"

      change set_attribute(:status, :cancelled)
      change set_attribute(:cancelled_at, &DateTime.utc_now/0)
      change Changes.ReleaseItems
    end
  end

  attributes do
    uuid_primary_key :id

    # Public, unguessable handle for the confirmation page (/order/:token).
    attribute :token, :string do
      allow_nil? false
      writable? false

      default fn -> Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false) end
    end

    # Human reference, also the bank-transfer reference number.
    attribute :reference, :string do
      allow_nil? false
      writable? false

      default fn -> "K" <> Integer.to_string(Enum.random(1_000_000..9_999_999)) end
    end

    attribute :status, :atom do
      allow_nil? false
      default :pending
      constraints one_of: [:pending, :reserved, :paid, :shipped, :delivered, :cancelled]
    end

    attribute :buyer_name, :string
    attribute :buyer_email, :string
    attribute :buyer_phone, :string

    attribute :delivery_method, :atom do
      constraints one_of: [
                    :omniva_parcel_machine,
                    :dpd_parcel_machine,
                    :smartposti_parcel_machine,
                    :pickup
                  ]
    end

    attribute :pickup_point_id, :string
    attribute :pickup_point_name, :string

    attribute :pickup_point_carrier, :atom do
      constraints one_of: [:omniva, :dpd, :smartposti]
    end

    attribute :items_total_cents, :integer, allow_nil?: false, constraints: [min: 0]
    attribute :shipping_cents, :integer, allow_nil?: false, default: 0, constraints: [min: 0]
    attribute :total_cents, :integer, allow_nil?: false, constraints: [min: 0]

    attribute :payment_method, :atom do
      allow_nil? false
      default :manual
      constraints one_of: [:manual, :montonio]
    end

    attribute :payment_status, :atom do
      allow_nil? false
      default :unpaid
      constraints one_of: [:unpaid, :paid, :failed, :refunded]
    end

    attribute :montonio_order_ref, :string
    attribute :montonio_payment_url, :string

    attribute :reserved_until, :utc_datetime_usec
    attribute :paid_at, :utc_datetime_usec
    attribute :shipped_at, :utc_datetime_usec
    attribute :delivered_at, :utc_datetime_usec
    attribute :cancelled_at, :utc_datetime_usec
    attribute :cancel_reason, :string

    attribute :tracking_number, :string
    attribute :tracking_url, :string

    # Funnel attribution, so a webhook-confirmed payment can still be tracked (docs/tracking.md).
    attribute :ab_visitor_id, :string
    attribute :ab_assignments, :map

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :order_items, Kirbs.Resources.OrderItem
  end

  identities do
    identity :unique_token, [:token]
    identity :unique_reference, [:reference]
    identity :unique_montonio_order_ref, [:montonio_order_ref]
  end
end
