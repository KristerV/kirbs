defmodule Kirbs.Slug do
  @moduledoc "ASCII URL slugs (handles Estonian characters)."

  @replacements %{
    "õ" => "o",
    "ä" => "a",
    "ö" => "o",
    "ü" => "u",
    "š" => "s",
    "ž" => "z"
  }

  def slugify(nil), do: ""

  def slugify(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace(Map.keys(@replacements), &Map.fetch!(@replacements, &1))
    |> String.normalize(:nfd)
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end
end
