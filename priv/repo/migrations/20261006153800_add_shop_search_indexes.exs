defmodule Kirbs.Repo.Migrations.AddShopSearchIndexes do
  @moduledoc """
  Shop search support: an IMMUTABLE unaccent wrapper (the stock `unaccent/1` is only STABLE
  so it cannot be used in index expressions), a GIN full-text index and a GIN trigram index
  on `items.search_text`, and a partial index for the public listing.
  """

  use Ecto.Migration

  def up do
    execute """
    CREATE OR REPLACE FUNCTION immutable_unaccent(text) RETURNS text
    LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT
    AS $$ SELECT public.unaccent('public.unaccent'::regdictionary, $1) $$
    """

    execute """
    CREATE INDEX items_search_text_fts_index ON items
    USING GIN (to_tsvector('simple', immutable_unaccent(lower(coalesce(search_text, '')))))
    """

    execute """
    CREATE INDEX items_search_text_trgm_index ON items
    USING GIN (immutable_unaccent(lower(coalesce(search_text, ''))) gin_trgm_ops)
    """

    execute """
    CREATE INDEX items_shop_listing_index ON items (published_at DESC)
    WHERE kirbs_status = 'available' AND published_at IS NOT NULL
    """
  end

  def down do
    execute "DROP INDEX IF EXISTS items_shop_listing_index"
    execute "DROP INDEX IF EXISTS items_search_text_trgm_index"
    execute "DROP INDEX IF EXISTS items_search_text_fts_index"
    execute "DROP FUNCTION IF EXISTS immutable_unaccent(text)"
  end
end
