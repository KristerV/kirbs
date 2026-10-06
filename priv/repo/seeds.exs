# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Kirbs.Repo.insert!(%Kirbs.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

# Own-shop category tree + Yaga category mappings (idempotent)
{:ok, :seeded} = Kirbs.Services.Categories.SeedTree.run()

# Shop search synonyms (idempotent)
{:ok, _count} = Kirbs.Services.Search.SeedSynonyms.run()

# Dev-only demo shop items with generated placeholder photos
if Mix.env() == :dev do
  {:ok, _items} = Kirbs.Services.Shop.SeedDevItems.run()
end
