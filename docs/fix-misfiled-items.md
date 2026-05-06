# Fix misfiled items (wrong bag on yaga)

When items get uploaded to yaga under the wrong client/bag, we need to:
1. Figure out which yaga listings are actually misfiled.
2. Move the corresponding `Item` rows in our DB to the correct bag.

The yaga listing itself does not need editing — the bag label `Bxxxx` printed
in the description was just informational. Moving the `Item.bag_id` is enough,
since the bag dictates the client.

## Inputs from the user

- A CSV of yaga product URLs (one per line; format may be messy — leading row
  numbers from a paste are fine, the script tolerates whitespace).
- The set of bag numbers that are *correct* for this batch (e.g. "78, 79, 86,
  87, 88").
- The target bag number to move the misfiled items into (e.g. 88).

Save the CSV at the repo root as `liiva-items.csv` (or any name — adjust paths).

## Step 1 — Fetch each item's actual bag code from yaga

The bag label is written into the yaga description by
`Kirbs.Services.Yaga.Uploader` as `B0078` (4-digit zero-padded). We scrape it
back from the live listing.

Script: `scripts/liiva_items_bag_codes.exs`. It:
- reads `liiva-items.csv` (extracts URLs, ignores leading row numbers),
- calls `Kirbs.Services.Yaga.ProductFetcher` for each URL,
- regex-matches `B(\d{1,6})` in `description`,
- writes `liiva-items-with-bags.csv` with `url,Bxxxx`.

Run:
```
mix run scripts/liiva_items_bag_codes.exs
```

## Step 2 — Filter to wrong rows

Given the correct bags, e.g. 78/79/86/87/88:
```
grep -vE ',B00(78|79|86|87|88)$' liiva-items-with-bags.csv > liiva-items-wrong.csv
```
Adjust the alternation to whichever bags are correct for the batch.

Sanity check counts:
```
wc -l liiva-items-with-bags.csv liiva-items-wrong.csv
```

## Step 3 — Move the misfiled items in prod

We match items by `yaga_slug` (last URL segment). The script writes a module
to `/tmp/liiva_bag_fix.exs` that gets `c`-loaded in remote iex.

Template (edit `@target_bag_number` and `@slugs`):

```elixir
defmodule LiivaBagFix do
  require Ash.Query
  alias Kirbs.Resources.{Item, Bag}

  @target_bag_number 88
  @slugs ~w(
    slug1
    slug2
    ...
  )

  def run do
    with {:ok, bag} <- find_target_bag(),
         _ <- IO.puts("Target bag: #{bag.id} (number #{bag.number})"),
         results <- Enum.map(@slugs, &move(&1, bag.id)) do
      summarize(results)
      {:ok, results}
    end
  end

  defp find_target_bag do
    case Bag |> Ash.Query.filter(number == ^@target_bag_number) |> Ash.read() do
      {:ok, [bag]} -> {:ok, bag}
      {:ok, []} -> {:error, "no bag with number #{@target_bag_number}"}
      {:ok, many} -> {:error, "multiple bags found: #{length(many)}"}
      err -> err
    end
  end

  defp move(slug, target_bag_id) do
    with {:ok, item} <- find_by_slug(slug),
         :ok <- ensure_needs_move(item, target_bag_id),
         {:ok, updated} <- Item.update(item, %{bag_id: target_bag_id}) do
      IO.puts("OK    #{slug}  item=#{item.id}  from_bag=#{item.bag_id} -> #{updated.bag_id}")
      {:ok, slug}
    else
      {:noop, reason} ->
        IO.puts("SKIP  #{slug}  #{reason}")
        {:noop, slug}
      {:error, reason} ->
        IO.puts("FAIL  #{slug}  #{inspect(reason)}")
        {:error, {slug, reason}}
    end
  end

  defp find_by_slug(slug) do
    case Item |> Ash.Query.filter(yaga_slug == ^slug) |> Ash.read() do
      {:ok, [item]} -> {:ok, item}
      {:ok, []} -> {:error, "no item with yaga_slug=#{slug}"}
      {:ok, many} -> {:error, "multiple items with yaga_slug=#{slug}: #{length(many)}"}
      err -> err
    end
  end

  defp ensure_needs_move(%{bag_id: bag_id}, bag_id), do: {:noop, "already in target bag"}
  defp ensure_needs_move(_, _), do: :ok

  defp summarize(results) do
    grouped = Enum.group_by(results, fn {status, _} -> status end)
    IO.puts("\n=== SUMMARY ===")
    IO.puts("moved:   #{length(Map.get(grouped, :ok, []))}")
    IO.puts("skipped: #{length(Map.get(grouped, :noop, []))}")
    IO.puts("failed:  #{length(Map.get(grouped, :error, []))}")
    Enum.each(Map.get(grouped, :error, []), fn {:error, {slug, reason}} ->
      IO.puts("  #{slug}: #{inspect(reason)}")
    end)
  end
end

LiivaBagFix.run()
```

Copy to clipboard then paste into remote iex (`fly ssh console` → `bin/kirbs
remote`):
```
wl-copy < /tmp/liiva_bag_fix.exs
```

In iex:
```
c "/tmp/liiva_bag_fix.exs"
```
The trailing `LiivaBagFix.run()` fires on compile. Output is `OK / SKIP /
FAIL` per row plus a summary.

## Handling failures

`yaga_slug` not found in DB usually means one of:
- Duplicate listing — the item was uploaded twice to yaga; our DB knows the
  *other* slug. Ask the user for the real slug saved in kirbs, then move that
  one (or delete the dup on yaga).
- Item uploaded outside the app / manually deleted. Ask the user how to
  handle case-by-case.

The script never aborts on per-item failure; it logs and continues.

## Notes

- `Item.update` has a status-protection guard but it only blocks status
  changes, not `bag_id` changes — so moving uploaded/sold items is fine.
- Bag label format is fixed by `lib/kirbs/services/yaga/uploader.ex` —
  `B` + 4-digit zero-padded `bag.number`. If that format changes, update the
  regex in step 1.
