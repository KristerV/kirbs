# Kirbs taxonomy (source of truth)

Categories live in the `categories` table, seeded idempotently by
`Kirbs.Services.Categories.SeedTree` (run by `priv/repo/seeds.exs` and `Kirbs.Release.migrate/0`).
Typed attribute enums live on `Kirbs.Resources.Item`. If this doc and the code disagree, fix the code or
this doc in the same change.

## Category tree

**Rule: category = garment type only. Season, gender, age group, condition, colour, material, brand and size
are attributes, never part of the tree.** Season in particular is not in category names (no `talvejakid`,
`talvesaapad`): the owner wants to browse "all boots" or "winter boots", "all overalls" or "winter overalls",
and to see winter jackets, boots and pants together at the start of winter. That only works when the type is
one leaf and the season is a filter on `Item.season`. A winter jacket and a summer jacket are both `joped`.
Rain gear is not a category either: `waterproof` is a boolean attribute (see below). Snow, rain, shell and
insulated outdoor trousers are their own type, `valipuksid`.

One primary category per item (plus optional extras, see "Multi-category"). Structure: audience root -> family -> type. Items attach to **leaves only**; a
family without children is a leaf itself. Slugs are ASCII, unique, and prefixed by their path.

Kids is the default audience. Root `lapsed` is kept in the DB, but is not a level in the shop: public URLs are
relative to it (`/k/valisriided/joped` = slug `lapsed-valisriided-joped`), breadcrumbs read
`Pood > Välisriided > Joped`. The audience switcher renders only when more than one audience root has published
items. Other roots (`naised`, `mehed`, `kodu`, `mangud`) are empty stubs; their URLs keep the root segment.
Legacy URLs (`/k/lapsed/poisid/pusid`, `/k/valisriided/talvejakid`, `talvesaapad`, `talvekombinesoonid`,
`vihmakombinesoonid`, `uleminekujakid-vestid`, `jakid`, `vihmariided`) redirect to the current leaf, keeping the query string.

```
Lapsed (lapsed)                       default audience, fully built
  Välisriided (valisriided):  Joped, Vestid, Välipüksid (valipuksid)
  Kombinesoonid                       leaf family
  Püksid ja lühikesed (puksid-luhikesed): Püksid, Teksad, Retuusid, Lühikesed püksid (luhikesed-puksid)
  Pluusid, särgid ja kampsunid (ulaosad): T-särgid ja pluusid (t-sargid-pluusid),
    Dressipluusid ja kampsunid (dressipluusid-kampsunid), Bodyd ja alussärgid (bodyd-alussargid)
  Kleidid ja seelikud (kleidid-seelikud)     leaf family
  Öö- ja vabaaja (oo-vabaaeg): Pidžaamad, Dressid
  Jalatsid: Saapad, Kummikud, Tossud, Kingad, Sandaalid ja sussid (sandaalid-sussid)
  Aksessuaarid: Mütsid ja sallid (mutsid-sallid), Kindad, Muu
  Muu (muu)                                   leaf family
Naised (naised)   stub    Mehed (mehed)   stub    Kodu (kodu)   stub    Mänguasjad (mangud)   stub
```

Type slug = `lapsed-<family>-<type>`, family slug = `lapsed-<family>`; `position` follows the order above.
`Kirbs.Services.Categories.SeedTree` is the code form of this tree (idempotent, never deletes).

### Shop navigation

Season is an ordinary sidebar facet block (Hooaeg: Talv · Kevad/sügis · Suvi) right after the categories.
Toggles and combine (URL `season=winter,summer`), persist across every category, breadcrumb and audience
link, and filter the grid and the sidebar counts. `all_year` items match every season filter. Season counts are
computed with all other filters applied. The sidebar lists only families (and, for the active family, types)
with available published items, with counts. Sidebar order: Kategooriad, Hooaeg, Veekindel, Sugu (Poiss / Tüdruk), Vanus (Beebi / Väikelaps / Laps),
Suurus, Bränd, Hind. `gender` and `age_group` are single-select URL params that persist across category
navigation like season; `unisex` items also match the Poiss and Tüdruk filters and count towards both (so Unisex is not offered as a
filter option of its own; the attribute value stays). There
is no condition filter or badge in the shop (everything is sold as used; JSON-LD `itemCondition` is always
`UsedCondition`); `condition` stays as an internal column. The search `category` filter matches a category and its whole subtree by slug prefix;
`Item.search` `season` takes a list.

### Migrations

1. `Kirbs.Services.Categories.MigrateTree` (gender tree -> type tree): re-points by type, copies
   gender/age_group from the old group when blank, deletes obsolete categories.
2. `Kirbs.Services.Categories.MigrateSeasonOutOfTree` (season tree -> pure type tree): `talvejakid` and
   `uleminekujakid-vestid` -> `joped` (the latter flagged: some may be vests), `talvekombinesoonid` and
   `vihmakombinesoonid` -> `kombinesoonid` (the latter flagged), `talvesaapad` -> `saapad`. Blank `season` is
   filled from the old leaf (talvejakid/talvekombinesoonid/talvesaapad -> winter, sandaalid-sussid -> summer),
   an existing season is never overwritten; items and pending proposals move, `search_text` is rebuilt.

3. `Kirbs.Services.Categories.RenameJakidToJoped`: category `Jakid` renamed to `Joped` ("jope" is the normal
   word). Items and pending proposals move, `search_text` is rebuilt, the old category and its Yaga mapping are
   deleted; `/k/valisriided/jakid` redirects to `/k/valisriided/joped`.

4. `Kirbs.Services.Categories.MigrateVihmariidedToValipuksid`: category `Vihmariided` removed. Items and pending
   proposals move to `joped` and get `waterproof = true`; ALL of them are listed in `needs_review` (some may be
   trousers that belong in `valipuksid`). `search_text` is rebuilt, the old category and its Yaga mapping are deleted
   once unreferenced; `/k/valisriided/vihmariided` redirects to `/k/valisriided/joped` (query string kept).

All run, idempotently, from `Kirbs.Release.migrate_category_tree/0` (SeedTree first); its returned map gets one key
per step (`gender_tree`, `season_out_of_tree`, `jakid_to_joped`, `vihmariided_to_valipuksid`).

## Multi-category

An item has ONE **primary** category (`items.category_id`, unchanged) and optional **extra** categories, so a
jacket+trousers set shows up in both Joped and Välipüksid. The primary drives the breadcrumb, canonical URL,
JSON-LD, Yaga mapping and the slug. There is no "Komplektid" category and no "set" badge; the product page only
shows a small "Leiad ka: <links>" line with the extras.

- Storage: Ash resource `Kirbs.Resources.ItemCategory`, table `item_categories` (`id`, `item_id` FK on delete
  cascade, `category_id` FK on delete cascade, `created_at`), unique identity on `[item_id, category_id]`,
  index on `category_id`. `Item` has `has_many :item_categories` and `many_to_many :extra_categories`.
- API: `Item.set_extra_categories(item, [category_ids])` replaces the set atomically (and rebuilds `search_text`);
  `Item.update` and `Item.apply_categorization` take an optional `extra_category_ids` argument (nil keeps the
  extras, a list replaces them).
- Rules: an extra must be a leaf (a family without children counts as a leaf), differ from the primary, and appear
  once. When the primary is changed to a category that is currently an extra, that extra is dropped.
- Everything that matches by category matches primary OR extras, subtree-aware: the `Item.search` `category`
  filter, the sidebar counts, category pages, `search_text` (extra names are added). `Item.facets` returns
  `category_id` (distinct items per leaf, primary and extras) and `category_rollup` (distinct items per node and
  ancestor: an item in two leaves of one family counts once in the family total).
- AI: `ItemCategorize` returns `extra_category_slugs` (leaf slugs, usually empty, only when the photos show several
  distinct garments sold together; validated against the leaves, never the primary, no duplicates). The result
  carries `extra_category_ids`; `CategorizationProposal` stores `extra_category_ids` and `waterproof`, the
  `/backfill` screen shows and edits the extras, and `ApplyProposal` / `ProcessItemJob` write them to the item.
- Admin: the item form (`/items/:id`) has a checkbox list of leaves grouped by family for the extras, next to the
  primary select (the primary itself is disabled in the list).

### Waterproof

`Item.waterproof` is a boolean (default false, not null), also stored on `CategorizationProposal`. It is the only
way rain gear is expressed (there is no rain category). The sidebar block "Veekindel" (after Hooaeg, before Sugu) is
a single toggle with a count: URL `waterproof=true`, persists across category navigation, the count respects the
other filters, active filter chip. The AI sets it only when the item is clearly waterproof / rain gear; applying a
proposal only ever switches it on. It adds "veekindel" to `search_text` and shows "Veekindel: Jah" in the product
page attribute list.

### Yaga mapping (`yaga_category_mappings`)

Only used by `Kirbs.Services.Yaga.Uploader`. Yaga's kids taxonomy is coarse: every `jalatsid` type -> "Jalanõud
lastele" (370), every `muu` leaf (`lapsed-muu`, `lapsed-aksessuaarid-muu`) -> "Muu lastele" (47), everything else
(including `valipuksid`) -> "Riided" (438). Only the primary category is mapped. If an item has no `category_id` (or no mapping), the uploader falls back to the legacy
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
  The prompt tells the model that the category is the item type only (winter and summer jackets share `joped`);
  `gender`, `age_group` and `season` are extracted independently as attributes.
  `waterproof` is true only for clearly waterproof / rain gear; `extra_category_slugs` only for sets.
  `colors` / `materials` are restricted to the Yaga taxonomy names (Estonian) so values stay valid for uploads.
  Anything outside the enums is dropped; an unknown slug cancels the categorization.
- `brand`, `size`, `colors`, `materials` already set by `ItemInfoExtract` are never overwritten by categorization
  (`Item.apply_categorization` only fills blanks); `category_id`, `age_group`, `gender`, `season`, `condition` are set.
- New items are categorized right after extraction in `ProcessItemJob` (best effort). Existing items are handled by the
  backfill (`/backfill`, `mix kirbs.backfill_categorize`, `Kirbs.Release.enqueue_categorize_backfill/1`): dry run stores
  `CategorizationProposal`s (category, attributes, confidence); nothing touches an item until a proposal is approved,
  changed and approved, or applied via "apply all above confidence".
- Admins edit category and attributes in the item review form (`/items/:id`, "Shop category and attributes").
