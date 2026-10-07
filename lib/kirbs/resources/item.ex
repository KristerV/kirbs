defmodule Kirbs.Resources.Item do
  use Ash.Resource,
    domain: Kirbs,
    data_layer: AshPostgres.DataLayer

  # Yaga channel data lives on YagaListing; these aggregates expose it on Item.
  @listing_fields [:yaga_id, :yaga_slug, :uploaded_at, :upload_error, :yaga_listing_status]

  @doc false
  def listing_fields, do: @listing_fields

  postgres do
    table "items"
    repo Kirbs.Repo
  end

  code_interface do
    define :get, args: [:id]
    define :list
    define :get_by_bag, args: [:bag_id]
    define :get_items_needing_review, args: []
    define :get_first_item_needing_review, args: []
    define :get_first_item_needing_review_in_bag, args: [:bag_id]
    define :create
    define :update
    define :destroy
    define :clear_ai_data
    define :top_sold_by_value, args: []
    define :fastest_sold, args: []
    define :recently_uploaded, args: []
    define :recently_sold, args: []
    define :list_reviewed_by_bag, args: [:bag_id]
    define :list_by_combination_group, args: [:combination_group]
    define :publish
    define :apply_categorization
    define :list_uncategorized, args: [:after_id, :limit]
    define :list_by_category, args: [:category_id]
    define :mark_sold
    define :mark_unsold
    define :search
    define :facets, args: [:params]
    define :get_published_by_slug, args: [:slug]
    define :list_for_sitemap, args: []
    define :reserve, args: [:reserved_until]
    define :release_reservation, args: [:held_until]
    define :extend_reservation, args: [:reserved_until]
    define :sell_on_kirbs, args: [:sold_price]
    define :list_expired_reservations, args: []
    define :list_unpublished_reviewed_by_bag, args: [:bag_id]
    define :list_sold_with_stale_kirbs_status, args: []
    define :list_kirbs_sold_with_stale_status, args: []
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
      :sold_at,
      :combination_group,
      :category_id,
      :age_group,
      :gender,
      :season,
      :condition,
      :search_text,
      :parcel_size,
      :weight_grams,
      :slug,
      :published_at,
      :kirbs_status,
      :reserved_until,
      :sales_channel
    ]

    defaults [:destroy]

    create :create do
      primary? true
      change Kirbs.Resources.Item.Changes.BuildSearchText
      change load(@listing_fields)
    end

    read :read do
      primary? true
    end

    update :update do
      primary? true
      require_atomic? false

      change Kirbs.Resources.Item.Changes.ProtectLifecycleStatus
      change Kirbs.Resources.Item.Changes.BuildSearchText
      change load(@listing_fields)
    end

    update :apply_categorization do
      accept [
        :category_id,
        :age_group,
        :gender,
        :season,
        :condition,
        :brand,
        :size,
        :colors,
        :materials
      ]

      require_atomic? false

      change Kirbs.Resources.Item.Changes.KeepExistingExtraction
      change Kirbs.Resources.Item.Changes.BuildSearchText
      change load(@listing_fields)
    end

    read :list_by_category do
      argument :category_id, :uuid, allow_nil?: false
      filter expr(category_id == ^arg(:category_id))
    end

    read :list_uncategorized do
      argument :after_id, :uuid
      argument :limit, :integer, allow_nil?: false, default: 25

      prepare fn query, _context ->
        query
        |> Ash.Query.sort(id: :asc)
        |> Ash.Query.limit(Ash.Query.get_argument(query, :limit))
      end

      filter expr(
               is_nil(category_id) and status in [:ai_processed, :reviewed] and
                 not exists(categorization_proposal, true) and
                 (is_nil(^arg(:after_id)) or id > ^arg(:after_id))
             )
    end

    # Every sale path (Yaga checker, warehouse review, kirbs shop via
    # Kirbs.Services.Channels.MarkSoldOnKirbs) goes through here, so kirbs_status
    # can never disagree with status == :sold. Pass `sales_channel` to say where it sold.
    update :mark_sold do
      accept [:sold_price, :sold_at, :sales_channel]
      require_atomic? false

      change set_attribute(:status, :sold)
      change set_attribute(:kirbs_status, :sold)
      change {Kirbs.Resources.Item.Changes.SyncListingStatus, listing_status: :sold}
      change load(@listing_fields)
    end

    update :mark_unsold do
      accept []
      require_atomic? false

      change set_attribute(:status, :reviewed)
      change set_attribute(:kirbs_status, :available)
      change set_attribute(:sales_channel, :yaga)
      change set_attribute(:sold_price, nil)
      change set_attribute(:sold_at, nil)
      change {Kirbs.Resources.Item.Changes.SyncListingStatus, listing_status: :listed}
      change load(@listing_fields)
    end

    # Kirbs shop reservation. Atomic: one UPDATE ... WHERE-style guard, so two buyers racing
    # for a qty-1 item can never both win. An expired reservation (job not yet run) may be taken.
    update :reserve do
      accept []
      argument :reserved_until, :utc_datetime_usec, allow_nil?: false

      validate Kirbs.Resources.Item.Validations.Reservable
      change set_attribute(:kirbs_status, :reserved)
      change set_attribute(:reserved_until, arg(:reserved_until))
    end

    # Pushes a held reservation out (checkout submitted -> longer payment hold).
    update :extend_reservation do
      accept []
      argument :reserved_until, :utc_datetime_usec, allow_nil?: false

      validate attribute_equals(:kirbs_status, :reserved)
      change set_attribute(:reserved_until, arg(:reserved_until))
    end

    # Idempotent and owner-safe: only releases an item that is still reserved with exactly the
    # `held_until` deadline the releasing order holds (never un-sells, never frees another
    # buyer's newer reservation).
    update :release_reservation do
      accept []
      argument :held_until, :utc_datetime_usec, allow_nil?: false

      change atomic_update(
               :kirbs_status,
               expr(
                 if kirbs_status == :reserved and reserved_until == ^arg(:held_until),
                   do: :available,
                   else: kirbs_status
               )
             )

      change atomic_update(
               :reserved_until,
               expr(
                 if kirbs_status == :reserved and reserved_until == ^arg(:held_until),
                   do: nil,
                   else: reserved_until
               )
             )
    end

    # A purchase through Kirbs: kirbs_status + lifecycle status + sold price/time in one atomic step.
    update :sell_on_kirbs do
      accept [:sold_price]

      validate attribute_does_not_equal(:kirbs_status, :sold),
        message: "ese on juba müüdud"

      change set_attribute(:kirbs_status, :sold)
      change set_attribute(:status, :sold)
      change set_attribute(:reserved_until, nil)
      change set_attribute(:sales_channel, :kirbs)
      change atomic_update(:sold_at, expr(now()))
      change {Kirbs.Resources.Item.Changes.SyncListingStatus, listing_status: :sold}

      # a shop sale must come down from Yaga too
      change Kirbs.Resources.Item.Changes.EnqueueYagaDelist
    end

    read :list_expired_reservations do
      filter expr(kirbs_status == :reserved and reserved_until < now())
    end

    update :publish do
      accept []
      require_atomic? false

      change Kirbs.Resources.Item.Changes.PublishItem
      change load(@listing_fields)
    end

    read :get do
      get_by [:id]
    end

    read :list

    # Public shop: published + available items matching the filters. See
    # Kirbs.Resources.Item.Preparations.Search for the FTS/trigram/synonym logic.
    read :search do
      pagination offset?: true,
                 default_limit: 24,
                 max_page_size: 100,
                 countable: true,
                 required?: false

      argument :q, :string
      argument :category, :string
      argument :brand, :string
      argument :size, :string

      argument :age_group, :atom do
        constraints one_of: [:baby, :toddler, :child, :teen, :adult]
      end

      argument :gender, :atom do
        constraints one_of: [:girl, :boy, :unisex, :woman, :man]
      end

      argument :season, :atom do
        constraints one_of: [:spring_autumn, :summer, :winter, :all_year]
      end

      argument :condition, :atom do
        constraints one_of: [:new_with_tags, :like_new, :good, :fair]
      end

      argument :min_price, :decimal
      argument :max_price, :decimal

      argument :sort, :atom do
        constraints one_of: [:relevance, :newest, :price_asc, :price_desc]
      end

      prepare Kirbs.Resources.Item.Preparations.Search
    end

    # Facet counts for the shop filter sidebar: %{brand: [{value, count}], ...}.
    # Each facet is counted with its own filter removed so alternatives stay visible.
    action :facets, :map do
      argument :params, :map, allow_nil?: false, default: %{}
      run Kirbs.Resources.Item.Actions.Facets
    end

    read :get_published_by_slug do
      get? true
      argument :slug, :string, allow_nil?: false

      filter expr(slug == ^arg(:slug) and not is_nil(published_at))
      prepare build(load: [:images, category: [parent: [:parent]]])
    end

    read :list_for_sitemap do
      filter expr(not is_nil(published_at) and not is_nil(slug) and kirbs_status != :sold)
      prepare build(sort: [published_at: :desc])
    end

    read :list_unpublished_reviewed_by_bag do
      argument :bag_id, :uuid, allow_nil?: false
      filter expr(bag_id == ^arg(:bag_id) and status == :reviewed and is_nil(published_at))
    end

    # Repair queries: status and kirbs_status must agree on "sold".
    read :list_sold_with_stale_kirbs_status do
      filter expr(status == :sold and kirbs_status != :sold)
    end

    read :list_kirbs_sold_with_stale_status do
      filter expr(status != :sold and kirbs_status == :sold)
    end

    read :get_by_bag do
      argument :bag_id, :uuid do
        allow_nil? false
      end

      filter expr(bag_id == ^arg(:bag_id))
    end

    read :get_items_needing_review do
      prepare build(sort: [created_at: :asc], load: :bag)
      filter expr(status in [:pending, :ai_processed])
    end

    read :get_first_item_needing_review do
      prepare build(sort: [created_at: :asc], limit: 1, load: :bag)
      filter expr(status in [:pending, :ai_processed])
    end

    read :get_first_item_needing_review_in_bag do
      argument :bag_id, :uuid do
        allow_nil? false
      end

      prepare build(sort: [created_at: :asc], limit: 1, load: :bag)
      filter expr(bag_id == ^arg(:bag_id) and status in [:pending, :ai_processed])
    end

    read :top_sold_by_value do
      prepare build(sort: [sold_price: :desc], limit: 10, load: [:images])
      filter expr(status == :sold and not is_nil(sold_price))
    end

    read :fastest_sold do
      prepare build(sort: [seconds_to_sell: :asc], limit: 10, load: [:images, :seconds_to_sell])
      filter expr(status == :sold and not is_nil(uploaded_at) and not is_nil(sold_at))
    end

    read :recently_uploaded do
      prepare build(sort: [uploaded_at: :desc], limit: 10, load: [:images])
      filter expr(yaga_listing_status == :listed and not is_nil(uploaded_at))
    end

    read :recently_sold do
      prepare build(sort: [sold_at: :desc], limit: 10, load: [:images])
      filter expr(status == :sold and not is_nil(sold_at))
    end

    read :list_reviewed_by_bag do
      argument :bag_id, :uuid, allow_nil?: false
      prepare build(sort: [created_at: :asc], load: [:images])
      filter expr(bag_id == ^arg(:bag_id) and status == :reviewed and is_nil(yaga_listing_status))
    end

    read :list_by_combination_group do
      argument :combination_group, :uuid, allow_nil?: false
      prepare build(load: [:bag])
      filter expr(combination_group == ^arg(:combination_group))
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

      change load(@listing_fields)
    end
  end

  preparations do
    prepare build(load: @listing_fields)
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
                    :sold,
                    :discarded
                  ]
    end

    # Combinations
    attribute :combination_group, :uuid

    attribute :sold_at, :utc_datetime_usec

    # Typed shop attributes (see docs/taxonomy.md)
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

    attribute :parcel_size, :atom do
      constraints one_of: [:s, :m, :l]
    end

    attribute :weight_grams, :integer do
      constraints min: 0
    end

    attribute :search_text, :string
    attribute :slug, :string
    attribute :published_at, :utc_datetime_usec

    attribute :reserved_until, :utc_datetime_usec
    # Where the sale happened. Drives accounting (fees per channel) and whether a
    # Yaga listing still has to be delisted. :warehouse = paid to us directly.
    attribute :sales_channel, :atom do
      allow_nil? false
      default :yaga
      constraints one_of: [:yaga, :kirbs, :warehouse]
    end

    attribute :kirbs_status, :atom do
      allow_nil? false
      default :available
      constraints one_of: [:available, :reserved, :sold]
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :bag, Kirbs.Resources.Bag do
      allow_nil? false
    end

    belongs_to :category, Kirbs.Resources.Category

    has_one :yaga_listing, Kirbs.Resources.YagaListing
    has_one :categorization_proposal, Kirbs.Resources.CategorizationProposal

    has_many :images, Kirbs.Resources.Image do
      sort created_at: :asc
    end
  end

  calculations do
    calculate :seconds_to_sell,
              :integer,
              expr(fragment("EXTRACT(EPOCH FROM (? - ?))::integer", sold_at, uploaded_at))

    calculate :search_rank,
              :float,
              expr(
                fragment(
                  "coalesce(word_similarity((?)::text, immutable_unaccent(lower(coalesce(?, '')))), 0)::float8",
                  ^arg(:q),
                  search_text
                )
              ) do
      argument :q, :string, allow_nil?: false
    end
  end

  aggregates do
    first :yaga_id, :yaga_listing, :yaga_id
    first :yaga_slug, :yaga_listing, :yaga_slug
    first :uploaded_at, :yaga_listing, :uploaded_at
    first :upload_error, :yaga_listing, :upload_error
    first :yaga_listing_status, :yaga_listing, :status
  end

  identities do
    identity :unique_slug, [:slug]
  end
end
