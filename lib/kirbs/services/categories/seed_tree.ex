defmodule Kirbs.Services.Categories.SeedTree do
  @moduledoc """
  Idempotently seeds the own-shop category tree (see docs/taxonomy.md) and the
  Yaga category mappings. Safe to run repeatedly (upserts on slug / category).
  Never deletes anything; obsolete categories are removed by `MigrateTree`.
  """

  alias Kirbs.Resources.{Category, YagaCategoryMapping}
  alias Kirbs.YagaTaxonomy

  @default_root "lapsed"

  # {family slug, family name, [{type slug, type name}]}; no types = the family is a leaf.
  @families [
    {"valisriided", "Välisriided",
     [{"joped", "Joped"}, {"vestid", "Vestid"}, {"valipuksid", "Välipüksid"}]},
    {"kombinesoonid", "Kombinesoonid", []},
    {"puksid-luhikesed", "Püksid ja lühikesed",
     [
       {"puksid", "Püksid"},
       {"teksad", "Teksad"},
       {"retuusid", "Retuusid"},
       {"luhikesed-puksid", "Lühikesed püksid"}
     ]},
    {"ulaosad", "Pluusid, särgid ja kampsunid",
     [
       {"t-sargid-pluusid", "T-särgid ja pluusid"},
       {"dressipluusid-kampsunid", "Dressipluusid ja kampsunid"},
       {"bodyd-alussargid", "Bodyd ja alussärgid"}
     ]},
    {"kleidid-seelikud", "Kleidid ja seelikud", []},
    {"oo-vabaaeg", "Öö- ja vabaaja", [{"pidzaamad", "Pidžaamad"}, {"dressid", "Dressid"}]},
    {"jalatsid", "Jalatsid",
     [
       {"saapad", "Saapad"},
       {"kummikud", "Kummikud"},
       {"tossud", "Tossud"},
       {"kingad", "Kingad"},
       {"sandaalid-sussid", "Sandaalid ja sussid"}
     ]},
    {"aksessuaarid", "Aksessuaarid",
     [{"mutsid-sallid", "Mütsid ja sallid"}, {"kindad", "Kindad"}, {"muu", "Muu"}]},
    {"muu", "Muu", []}
  ]

  @stub_roots [
    {"naised", "Naised"},
    {"mehed", "Mehed"},
    {"kodu", "Kodu"},
    {"mangud", "Mänguasjad"}
  ]

  # Yaga only knows coarse kids categories: footwear -> 370, Muu -> 47, everything else -> 438.
  @yaga_footwear_family "jalatsid"
  @yaga_footwear "Jalanõud lastele"
  @yaga_other "Muu lastele"
  @yaga_default "Riided"

  def run do
    with {:ok, lapsed} <- upsert(@default_root, "Lapsed", 0, nil),
         {:ok, _families} <- seed_families(lapsed),
         {:ok, _stubs} <- seed_stubs() do
      {:ok, :seeded}
    end
  end

  @doc "Slug of the audience root that public shop URLs are relative to."
  def default_root, do: @default_root

  @doc "Leaf slugs of the new tree (families without types count as leaves)."
  def leaf_slugs do
    Enum.flat_map(@families, fn
      {family, _name, []} ->
        ["#{@default_root}-#{family}"]

      {family, _name, types} ->
        Enum.map(types, fn {type, _} -> "#{@default_root}-#{family}-#{type}" end)
    end)
  end

  defp seed_families(lapsed) do
    @families
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {{slug, name, types}, idx}, {:ok, acc} ->
      with {:ok, family} <- upsert("#{@default_root}-#{slug}", name, idx, lapsed.id),
           {:ok, _mapping} <- maybe_map_family(family, slug, types),
           {:ok, _types} <- seed_types(slug, family, types) do
        {:cont, {:ok, [family | acc]}}
      else
        error -> {:halt, error}
      end
    end)
  end

  # A family without types is itself a leaf, so it needs a Yaga mapping.
  defp maybe_map_family(family, slug, []), do: map_to_yaga(family, slug, slug)
  defp maybe_map_family(_family, _slug, _types), do: {:ok, nil}

  defp seed_types(family_slug, family, types) do
    types
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {{slug, name}, idx}, {:ok, acc} ->
      with {:ok, category} <-
             upsert("#{@default_root}-#{family_slug}-#{slug}", name, idx, family.id),
           {:ok, _mapping} <- map_to_yaga(category, family_slug, slug) do
        {:cont, {:ok, [category | acc]}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp seed_stubs do
    @stub_roots
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {{slug, name}, idx}, {:ok, acc} ->
      case upsert(slug, name, idx, nil) do
        {:ok, category} -> {:cont, {:ok, [category | acc]}}
        error -> {:halt, error}
      end
    end)
  end

  defp upsert(slug, name_et, position, parent_id) do
    Category.upsert(%{slug: slug, name_et: name_et, position: position, parent_id: parent_id})
  end

  defp map_to_yaga(category, family_slug, type_slug) do
    case YagaTaxonomy.category_to_id(yaga_name(family_slug, type_slug)) do
      nil ->
        {:ok, nil}

      yaga_id ->
        YagaCategoryMapping.upsert(%{category_id: category.id, yaga_category_id: yaga_id})
    end
  end

  defp yaga_name(@yaga_footwear_family, _type), do: @yaga_footwear
  defp yaga_name(_family, "muu"), do: @yaga_other
  defp yaga_name(_family, _type), do: @yaga_default
end
