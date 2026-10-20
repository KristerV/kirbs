defmodule Kirbs.Resources.Item.Preparations.Search do
  @moduledoc """
  Builds the public shop search query for `Item.search`.

  Text matching (`q`): every word must match, either through Postgres full-text search
  (`simple` config over unaccented, lowercased `search_text`, prefix matching, expanded with
  `SearchSynonym`s) or, for words of 4+ letters, through trigram word similarity (typos).
  """
  use Ash.Resource.Preparation

  require Ash.Query

  alias Kirbs.Resources.SearchSynonym

  @fuzzy_min_length 4

  @impl true
  def prepare(query, _opts, _context) do
    q = normalize(Ash.Query.get_argument(query, :q))

    query
    |> Ash.Query.filter(kirbs_status == :available and not is_nil(published_at))
    |> filter_text(q)
    |> filter_category(Ash.Query.get_argument(query, :category))
    |> filter_equal(:brand, Ash.Query.get_argument(query, :brand))
    |> filter_equal(:size, Ash.Query.get_argument(query, :size))
    |> filter_equal(:age_group, Ash.Query.get_argument(query, :age_group))
    |> filter_gender(Ash.Query.get_argument(query, :gender))
    |> filter_season(Ash.Query.get_argument(query, :season))
    |> filter_waterproof(Ash.Query.get_argument(query, :waterproof))
    |> filter_price(
      Ash.Query.get_argument(query, :min_price),
      Ash.Query.get_argument(query, :max_price)
    )
    |> sort(q, Ash.Query.get_argument(query, :sort))
  end

  @doc "Lowercased, trimmed search string or nil."
  def normalize(nil), do: nil

  def normalize(q) do
    case q |> String.downcase() |> String.trim() do
      "" -> nil
      q -> q
    end
  end

  defp filter_text(query, nil), do: query

  defp filter_text(query, q) do
    synonyms = SearchSynonym.list!()

    q
    |> tokens()
    |> Enum.reduce(query, fn token, query ->
      tsquery = tsquery(token, synonyms)

      if String.length(token) >= @fuzzy_min_length do
        Ash.Query.filter(
          query,
          fragment(
            "to_tsvector('simple', immutable_unaccent(lower(coalesce(?, '')))) @@ to_tsquery('simple', immutable_unaccent(?))",
            search_text,
            ^tsquery
          ) or
            fragment(
              "word_similarity(immutable_unaccent((?)::text), immutable_unaccent(lower(coalesce(?, '')))) >= 0.45",
              ^token,
              search_text
            )
        )
      else
        Ash.Query.filter(
          query,
          fragment(
            "to_tsvector('simple', immutable_unaccent(lower(coalesce(?, '')))) @@ to_tsquery('simple', immutable_unaccent(?))",
            search_text,
            ^tsquery
          )
        )
      end
    end)
  end

  @doc "Words of a search string (letters and digits only)."
  def tokens(q), do: Regex.scan(~r/[\p{L}\p{N}]+/u, q) |> List.flatten()

  @doc """
  tsquery string for a single token: the token itself (prefix match) OR each synonym
  group member it belongs to. Multi-word synonyms are AND-ed.
  """
  def tsquery(token, synonyms) do
    alternatives =
      synonyms
      |> Enum.map(fn %{term: term, alternatives: alts} ->
        Enum.map([term | alts], &String.downcase/1)
      end)
      |> Enum.filter(&(token in &1))
      |> Enum.flat_map(& &1)
      |> Enum.reject(&(&1 == token))
      |> Enum.uniq()

    ([prefix_term(token)] ++ Enum.map(alternatives, &phrase_term/1))
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" | ")
    |> then(&"(#{&1})")
  end

  defp prefix_term(token), do: "#{token}:*"

  defp phrase_term(phrase) do
    case tokens(phrase) do
      [] -> nil
      words -> "(" <> Enum.map_join(words, " & ", &"#{&1}:*") <> ")"
    end
  end

  # Category slugs are prefixed by their path, so a subtree is "slug" or "slug-%".
  defp filter_category(query, nil), do: query
  defp filter_category(query, ""), do: query

  defp filter_category(query, slug) do
    pattern = String.replace(slug, ~r/[%_\\]/, "\\\\\\0") <> "-%"

    # primary category OR any extra category, subtree-aware; `exists` never duplicates rows
    Ash.Query.filter(
      query,
      category.slug == ^slug or fragment("? LIKE ?", category.slug, ^pattern) or
        exists(
          extra_categories,
          slug == ^slug or fragment("? LIKE ?", slug, ^pattern)
        )
    )
  end

  defp filter_waterproof(query, true), do: Ash.Query.filter(query, waterproof == true)
  defp filter_waterproof(query, _), do: query

  # Unisex items match the boy and girl filters too.
  defp filter_gender(query, gender) when gender in [:boy, :girl],
    do: Ash.Query.filter(query, gender in ^[gender, :unisex])

  defp filter_gender(query, gender), do: filter_equal(query, :gender, gender)

  # `all_year` items belong to every season.
  defp filter_season(query, seasons) when seasons in [nil, []], do: query

  defp filter_season(query, seasons) do
    seasons = Enum.uniq([:all_year | seasons])
    Ash.Query.filter(query, season in ^seasons)
  end

  defp filter_equal(query, _field, nil), do: query
  defp filter_equal(query, _field, ""), do: query
  defp filter_equal(query, field, value), do: Ash.Query.do_filter(query, [{field, value}])

  defp filter_price(query, min, max) do
    query
    |> then(&if(min, do: Ash.Query.filter(&1, listed_price >= ^min), else: &1))
    |> then(&if(max, do: Ash.Query.filter(&1, listed_price <= ^max), else: &1))
  end

  defp sort(query, q, nil), do: sort(query, q, if(q, do: :relevance, else: :newest))
  defp sort(query, nil, :relevance), do: sort(query, nil, :newest)

  defp sort(query, q, :relevance) do
    Ash.Query.sort(query, [{:search_rank, {%{q: q}, :desc}}, {:published_at, :desc}])
  end

  defp sort(query, _q, :price_asc),
    do: Ash.Query.sort(query, listed_price: :asc, published_at: :desc)

  defp sort(query, _q, :price_desc),
    do: Ash.Query.sort(query, listed_price: :desc, published_at: :desc)

  defp sort(query, _q, :newest), do: Ash.Query.sort(query, published_at: :desc)
end
