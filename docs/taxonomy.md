# Kirbs taxonomy (source of truth)

Categories live in the `categories` table, seeded idempotently by
`Kirbs.Services.Categories.SeedTree` (run by `priv/repo/seeds.exs` and `Kirbs.Release.migrate/0`).
Typed attribute enums live on `Kirbs.Resources.Item`. If this doc and the code disagree, fix the code or
this doc in the same change.

## Category tree

Categories describe **what the item is, nothing else**. Gender (`poiss`/`tüdruk`/`unisex`) and age group are
Item attributes (see below), not part of the tree, and are not public shop facets. One primary category per
item. Structure: audience root -> family -> type. Items attach to **leaves only**; a family without children
is a leaf itself. Slugs are ASCII, unique, and prefixed by their path.

Kids is the default audience. Root `lapsed` is kept in the DB, but is not a level in the shop: public URLs are
relative to it (`/k/valisriided/talvejakid` = slug `lapsed-valisriided-talvejakid`), breadcrumbs read
`Pood > Välisriided > Talvejakid`. The audience switcher in the sidebar renders only when more than one audience
root has published items. Other roots (`naised`, `mehed`, `kodu`, `mangud`) are empty stubs; their URLs keep the root
segment (`/k/naised/...`). Legacy URLs (`/k/lapsed/poisid/pusid`) redirect to the new tree.

```
Lapsed (lapsed)                       default audience, fully built
  Välisriided (valisriided)
    Talvejakid, Üleminekujakid ja vestid (uleminekujakid-vestid), Vihmariided
  Kombinesoonid
    Talvekombinesoonid, Vihmakombinesoonid
  Püksid ja lühikesed (puksid-luhikesed)
    Püksid, Teksad, Retuusid, Lühikesed püksid (luhikesed-puksid)
  Pluusid, särgid ja kampsunid (ulaosad)
    T-särgid ja pluusid (t-sargid-pluusid), Dressipluusid ja kampsunid (dressipluusid-kampsunid),
    Bodyd ja alussärgid (bodyd-alussargid)
  Kleidid ja seelikud (kleidid-seelikud)     leaf family
  Öö- ja vabaaja (oo-vabaaeg)
    Pidžaamad, Dressid
  Jalatsid
    Talvesaapad, Kummikud, Tossud, Sandaalid ja sussid (sandaalid-sussid)
  Aksessuaarid
    Mütsid ja sallid (mutsid-sallid), Kindad, Muu
  Muu (muu)                                   leaf family
Naised (naised)   stub    Mehed (mehed)   stub    Kodu (kodu)   stub    Mänguasjad (mangud)   stub
```

Type slug = `lapsed-<family>-<type>`, family slug = `lapsed-<family>`; `position` follows the order above.
`Kirbs.Services.Categories.SeedTree` is the code form of this tree (idempotent, never deletes).

### Shop navigation

The sidebar lists only families (and, for the active family, types) that have available published items, with
counts. With few items it is flat. Filters: Hooaeg, Seisukord, Suurus, Bränd, Hind; there are no Sugu/Vanus
facets. The search `category` filter matches a category and its whole subtree by slug prefix.

### Migration from the gender-split tree

The earlier tree was `lapsed-<poisid|tudrukud|beebid>-<type>`. `Kirbs.Services.Categories.MigrateTree`
(`Kirbs.Release.migrate_category_tree/0`, runs `SeedTree` first, idempotent) re-points items and categorization
proposals by type, copies gender/age_group from the old group when blank (poisid -> boy, tudrukud -> girl,
beebid -> age_group baby), then deletes the obsolete categories and their Yaga mappings. Old leaves with an unknown
type are reported and kept. Guesses to review: `kombinesoonid` -> `talvekombinesoonid`, `kingad` -> `tossud`.

### Yaga mapping (`yaga_category_mappings`)

Only used by `Kirbs.Services.Yaga.Uploader`. Yaga's kids taxonomy is coarse: every `jalatsid` type -> "Jalanõud
lastele" (370), every `muu` leaf (`lapsed-muu`, `lapsed-aksessuaarid-muu`) -> "Muu lastele" (47), everything else
-> "Riided" (438). If an item has no `category_id` (or no mapping), the uploader falls back to the legacy
`suggested_category` name lookup in `Kirbs.YagaTaxonomy`.

## Item attribute enums

| attribute      | values                                                       | Estonian |
|----------------|--------------------------------------------------------------|----------|
| `age_group`    | `baby`, `toddler`, `child`, `teen`, `adult`                  | beebi, väikelaps, laps, teismeline, täiskasvanu |
| `gender`       | `girl`, `boy`, `unisex`, `woman`, `man`                      | tüdruk, poiss, unisex, naine, mees |
| `season`       | `spring_autumn`, `summer`, `winter`, `all_year`              | kevad/sügis, suvi, talv, aastaringne |
| `condition`    | `new_with_tags`, `like_new`, `good`, `fair`                  | Uus, Uueväärne, Hea, Keskmine |
| `parcel_size`  | `s`, `m`, `l`                                                | väike, keskmine, suur pakk |
| `kirbs_status` | `available` (default), `reserved`, `sold`                    | saadaval, reserveeritud, müüdud |

`condition` mirrors the Yaga `quality` strings (Uus / Uueväärne / Hea / Keskmine); `quality` stays for Yaga.

Other typed attributes: `category_id`, `brand` and `size` (normalized strings), `colors`/`materials`
(string arrays), `weight_grams` (integer, >= 0), `search_text` (denormalized, rebuilt on every
create/update from brand, size, category, suggested_category, description, colors, materials),
`slug` (unique public id, generated by `Item.publish`), `published_at`.

## Item status vs channel status

`Item.status` is the lifecycle only: `pending`, `ai_processed`, `reviewed`, `sold`, `discarded`.
Channel state lives on the channel listing; for Yaga that is `YagaListing.status`:
`listed`, `failed`, `sold`, `delisted`. An item "on Yaga" is `status == :reviewed` with a `:listed` listing;
"needs upload" is `status == :reviewed` with no listing. `Item.kirbs_status` is the own-shop availability.

## Categorization (AI and admin)

- Items attach to **leaf** categories only (a type, or a family without types). Roots and families with types are
  never assigned; the stub audience roots have no leaves yet, so they cannot be chosen. The admin select
  (`GroupedLeafOptions`) groups leaves by family.
- `Kirbs.Services.Ai.ItemCategorize` sends the item photos to the OpenRouter vision model with a JSON schema whose
  `category_slug` enum is exactly the leaf slugs above and whose attribute enums are the ones in the table.
  The prompt tells the model that the category is the item type only; `gender` and `age_group` are still extracted
  as attributes.
  `colors` / `materials` are restricted to the Yaga taxonomy names (Estonian) so values stay valid for uploads.
  Anything outside the enums is dropped; an unknown slug cancels the categorization.
- `brand`, `size`, `colors`, `materials` already set by `ItemInfoExtract` are never overwritten by categorization
  (`Item.apply_categorization` only fills blanks); `category_id`, `age_group`, `gender`, `season`, `condition` are set.
- New items are categorized right after extraction in `ProcessItemJob` (best effort). Existing items are handled by the
  backfill (`/backfill`, `mix kirbs.backfill_categorize`, `Kirbs.Release.enqueue_categorize_backfill/1`): dry run stores
  `CategorizationProposal`s (category, attributes, confidence); nothing touches an item until a proposal is approved,
  changed and approved, or applied via "apply all above confidence".
- Admins edit category and attributes in the item review form (`/items/:id`, "Shop category and attributes").
