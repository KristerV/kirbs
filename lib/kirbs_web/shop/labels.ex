defmodule KirbsWeb.Shop.Labels do
  @moduledoc "Estonian labels for typed item attributes (see docs/taxonomy.md)."

  @labels %{
    age_group: [
      baby: "Beebi",
      toddler: "Väikelaps",
      child: "Laps",
      teen: "Teismeline",
      adult: "Täiskasvanu"
    ],
    gender: [
      girl: "Tüdruk",
      boy: "Poiss",
      unisex: "Unisex",
      woman: "Naine",
      man: "Mees"
    ],
    season: [
      spring_autumn: "Kevad/sügis",
      summer: "Suvi",
      winter: "Talv",
      all_year: "Aastaringne"
    ],
    condition: [
      new_with_tags: "Uus",
      like_new: "Uueväärne",
      good: "Hea",
      fair: "Keskmine"
    ],
    kirbs_status: [
      available: "Saadaval",
      reserved: "Reserveeritud",
      sold: "Müüdud"
    ]
  }

  @doc "Facets that are enum attributes (filter param name == attribute name)."
  def enum_facets, do: [:gender, :age_group, :season]

  @doc "Estonian label of an attribute value (nil-safe)."
  def label(_field, nil), do: nil

  def label(field, value) when is_binary(value) do
    case parse(field, value) do
      nil -> value
      atom -> label(field, atom)
    end
  end

  def label(field, value) when is_atom(value), do: Keyword.get(Map.fetch!(@labels, field), value)

  @doc "Parses a URL param into a known enum atom, or nil."
  def parse(field, value) when is_binary(value) do
    case Enum.find(Map.fetch!(@labels, field), fn {k, _} -> Atom.to_string(k) == value end) do
      {key, _} -> key
      nil -> nil
    end
  end

  def parse(_field, _value), do: nil

  @doc "Estonian title of a facet group."
  def facet_title(:gender), do: "Sugu"
  def facet_title(:age_group), do: "Vanus"
  def facet_title(:season), do: "Hooaeg"
  def facet_title(:brand), do: "Bränd"
  def facet_title(:size), do: "Suurus"

  @doc "Formats a price in euros, e.g. `12 €` or `12,50 €`."
  def price(nil), do: nil

  def price(%Decimal{} = amount) do
    amount = Decimal.round(amount, 2)

    text =
      if Decimal.equal?(amount, Decimal.round(amount, 0)) do
        amount |> Decimal.round(0) |> Decimal.to_string(:normal)
      else
        amount |> Decimal.to_string(:normal) |> String.replace(".", ",")
      end

    text <> " €"
  end

  def price(amount) when is_number(amount), do: price(Decimal.new("#{amount}"))

  @doc "Formats integer cents as euros."
  def cents(cents) when is_integer(cents), do: price(Decimal.div(Decimal.new(cents), 100))
end
