defmodule Kirbs.Services.Search.SeedSynonyms do
  @moduledoc """
  Idempotently seeds common Estonian clothing search synonyms. Each row is `{term, alternatives}`;
  the search treats a row as a symmetric group (searching any member also finds the others).
  """

  alias Kirbs.Resources.SearchSynonym

  @synonyms [
    {"jope", ["jakk", "jakid", "jopp", "jopesid"]},
    {"talvejope", ["talvejakk", "soe jope", "talvejakid"]},
    {"vihmajope", ["vihmakeep", "vihmariided", "tuulejope"]},
    {"püksid", ["pükse", "pükst", "dressid"]},
    {"dressipüksid", ["dressid", "spordipüksid"]},
    {"teksad", ["teksapüksid", "džiinsid", "jeans", "teksapüks"]},
    {"dressipluus", ["hupparid", "hoodie", "kapuutsiga pluus", "dressipluusid"]},
    {"kampsun", ["sviiter", "džemper", "pusa", "kampsunid"]},
    {"särk", ["tshirt", "t-shirt", "pluus"]},
    {"pluus", ["särk", "pluusid", "särgid"]},
    {"kleit", ["kleidike", "kleidid"]},
    {"seelik", ["seelikud", "seelikuke"]},
    {"kombinesoon", ["kombe", "overall", "kombinesoonid", "talvekombe"]},
    {"müts", ["mütsike", "tuukmüts", "beanie", "mütsid"]},
    {"kindad", ["labakindad", "sõrmikud", "kinnas"]},
    {"sall", ["kaelarätik", "torusall", "salli", "sallid"]},
    {"saapad", ["saapaid", "talvesaapad", "kummikud"]},
    {"tossud", ["spordijalatsid", "botased", "kedid", "jalatsid"]},
    {"kingad", ["king", "jalanõud", "jalatsid"]},
    {"pidžaama", ["pidzaama", "öösärk", "magamisriided", "pidžaamad"]},
    {"bodi", ["body", "bodyd", "alussärk", "alussärgid"]},
    {"sukkpüksid", ["põlvikud", "sukad", "sokid"]},
    {"tüdruk", ["tüdrukud", "tüdrukule", "neiu"]},
    {"poiss", ["poisid", "poisile", "noormees"]},
    {"beebi", ["beebid", "imik", "vastsündinu", "titt"]}
  ]

  def run do
    with {:ok, count} <- upsert_all() do
      {:ok, count}
    end
  end

  defp upsert_all do
    Enum.reduce_while(@synonyms, {:ok, 0}, fn {term, alternatives}, {:ok, count} ->
      alternatives = alternatives |> Enum.reject(&(&1 == term)) |> Enum.uniq()

      case SearchSynonym.upsert(%{term: term, alternatives: alternatives}) do
        {:ok, _} -> {:cont, {:ok, count + 1}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
end
