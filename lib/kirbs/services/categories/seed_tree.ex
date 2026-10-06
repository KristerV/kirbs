defmodule Kirbs.Services.Categories.SeedTree do
  @moduledoc """
  Idempotently seeds the own-shop category tree (see docs/taxonomy.md) and the
  Yaga category mappings. Safe to run repeatedly (upserts on slug / category).
  """

  alias Kirbs.Resources.{Category, YagaCategoryMapping}
  alias Kirbs.YagaTaxonomy

  @kids_types [
    {"talvejakid", "Talvejakid"},
    {"jakid-vestid", "Jakid ja vestid"},
    {"pusid", "Püksid"},
    {"kombinesoonid", "Kombinesoonid"},
    {"kleidid-seelikud", "Kleidid ja seelikud"},
    {"pluusid-sargid", "Pluusid ja särgid"},
    {"dressipluusid-kampsunid", "Dressipluusid ja kampsunid"},
    {"alussargid-bodyd", "Alussärgid ja bodyd"},
    {"pidzaamad", "Pidžaamad"},
    {"mutsid-sallid", "Mütsid & sallid"},
    {"kingad", "Kingad"},
    {"muu", "Muu"}
  ]

  # Estonian audience -> slug, name, types (slug, name) that don't apply are omitted
  @kids_groups [
    {"beebid", "Beebid", @kids_types |> Enum.reject(&(elem(&1, 0) == "kleidid-seelikud"))},
    {"poisid", "Poisid",
     @kids_types |> Enum.reject(&(elem(&1, 0) in ["kleidid-seelikud", "alussargid-bodyd"]))},
    {"tudrukud", "Tüdrukud", @kids_types |> Enum.reject(&(elem(&1, 0) == "alussargid-bodyd"))}
  ]

  @stub_roots [
    {"naised", "Naised"},
    {"mehed", "Mehed"},
    {"kodu", "Kodu"},
    {"mangud", "Mänguasjad"}
  ]

  # Yaga only knows coarse kids categories.
  @yaga_by_type %{
    "kingad" => "Jalanõud lastele",
    "muu" => "Muu lastele"
  }
  @yaga_default "Riided"

  def run do
    with {:ok, lapsed} <- upsert("lapsed", "Lapsed", 0, nil),
         {:ok, _groups} <- seed_kids(lapsed),
         {:ok, _stubs} <- seed_stubs() do
      {:ok, :seeded}
    end
  end

  defp seed_kids(lapsed) do
    @kids_groups
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {{slug, name, types}, idx}, {:ok, acc} ->
      with {:ok, group} <- upsert("lapsed-#{slug}", name, idx, lapsed.id),
           {:ok, _types} <- seed_types(slug, group, types) do
        {:cont, {:ok, [group | acc]}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp seed_types(group_slug, group, types) do
    types
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {{slug, name}, idx}, {:ok, acc} ->
      with {:ok, category} <- upsert("lapsed-#{group_slug}-#{slug}", name, idx, group.id),
           {:ok, _mapping} <- map_to_yaga(category, slug) do
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

  defp map_to_yaga(category, type_slug) do
    yaga_name = Map.get(@yaga_by_type, type_slug, @yaga_default)

    case YagaTaxonomy.category_to_id(yaga_name) do
      nil ->
        {:ok, nil}

      yaga_id ->
        YagaCategoryMapping.upsert(%{category_id: category.id, yaga_category_id: yaga_id})
    end
  end
end
