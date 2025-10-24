# Kirbs - Kids Clothes Resale Platform - Technical Specification

## Overview
Platform for managing kids clothes resale business. Operators photograph incoming bags of clothes, AI extracts data, items get uploaded to yaga.ee, and profits are split 50/50 with clients.

---

## Workflow

### Phase 1: Photo Capture (Mobile Phone)
**Device: Mobile phone**
1. Operator clicks "New Bag"
2. Takes 3 photos:
   - Bag itself
   - All clothes laid out
   - Handwritten client info (name, phone, email, IBAN)
3. For each item in bag:
   - Click "New Item"
   - Take multiple photos (including label/brand/size tags)
   - Click "Next Item" → auto-saves, uploads to server, creates next item
4. Click "End Bag" → redirects away from camera
5. **Photos uploaded to Kirbs server immediately after capture**
6. **At this stage**: Client is `nil`, no AI processing yet

### Phase 2: Background AI Processing (Async)
**Triggered automatically after "End Bag"**
- AI reads handwritten info → creates/finds Client → attaches Bag
- For each Item:
  - AI analyzes photos → extracts brand, size, colors, description, quality, materials
  - AI determines pricing (with explanation)
  - AI suggests yaga.ee category
- Jobs run in background via Oban
- All items marked as `ai_processed` when done

### Phase 3: Operator Review (Desktop Computer)
**Device: Desktop computer (separate from phone)**
1. Op views "Review Queue" of bags with `status = ai_processed`
2. Reviews AI-extracted client info, confirms/edits client match
3. Reviews each item's AI data:
   - Brand, size, description, price
   - Yaga category, colors, materials, condition
   - All fields editable inline
   - Can delete photos
4. For each item: operator fills in any empty Yaga fields (brand_id, category_id, etc)
5. Clicks "Ready for Yaga" on each item → triggers upload job

### Phase 4: Upload to Yaga.ee (Background)
**See YAGA_UPLOAD_SPEC.md for detailed flow**
- Oban job uploads item to yaga.ee (multi-step process)
- Uploads photos to Yaga's S3
- Creates/publishes product listing
- On success: stores yaga_id, updates status
- On failure: stores error, flags for operator attention

### Phase 5: Sales Tracking
- Op sees item sold on yaga.ee (external)
- Marks item as sold in Kirbs, enters actual selling price
- System calculates profit: `sold_price / 2`
- Or marks as discarded (not sold)

---

## Data Model

### Client
**Attributes:**
- name (string, required)
- phone (string, required)
- email (string, nullable)
- iban (string, required)

**Relationships:**
- has_many :bags

**Identities:**
- [:phone] (unique)

**Note:** Phone is primary identifier. Email optional.

### Bag
**Attributes:**
- images (array of strings) # [bag_photo, layout_photo, info_photo]
- created_at (datetime)

**Relationships:**
- belongs_to :client (nullable initially)
- has_many :items

### Item
**Attributes:**
- photo_paths (array of strings)

**AI-extracted data (human-readable):**
- brand (string, nullable) # e.g., "H&M"
- size (string, nullable) # e.g., "6-9 kuud", "110"
- colors (array of strings, nullable) # e.g., ["red", "blue"]
- materials (array of strings, nullable) # e.g., ["cotton", "polyester"]
- description (text, nullable)
- quality (string, nullable) # e.g., "like new", "used", "worn"
- suggested_category (string, nullable) # e.g., "Pluus", "Püksid"

**Yaga-specific fields (IDs for upload):**
- yaga_brand_id (integer, nullable)
- yaga_category_id (integer, nullable)
- yaga_colors_id_map (array of integers, nullable)
- yaga_materials_id_map (array of integers, nullable)
- yaga_condition_id (integer, nullable)

**Pricing:**
- ai_suggested_price (decimal, nullable)
- ai_price_explanation (text, nullable)
- listed_price (decimal, nullable)
- sold_price (decimal, nullable)

**Status:**
- status (enum: pending, ai_processed, reviewed, uploaded_to_yaga, sold, discarded, upload_failed)

**Yaga integration:**
- yaga_id (integer, nullable) # Product ID from yaga.ee
- yaga_slug (string, nullable) # Product slug from yaga.ee
- upload_error (text, nullable)

**Timestamps:**
- created_at (datetime)

**Relationships:**
- belongs_to :bag

**Note:** Operator fills Yaga IDs during review. If AI can't map, field stays nil.

### User (Ash Authentication)
**Attributes:**
- email
- hashed_password
- is_admin (boolean, default: false)

**Note:** First user created should be admin

### Settings
**Attributes:**
- key (string) # e.g., "yaga_jwt"
- value (text)
- updated_at (datetime)

**Identities:**
- [:key] (unique)

### YagaMetadata
**Purpose:** Cache Yaga's categories, brands, colors, materials, conditions
**Attributes:**
- metadata_type (enum: brand, category, color, material, condition)
- yaga_id (integer) # ID from yaga.ee API
- name (string) # e.g., "H&M", "Punane", "Pluus"
- name_en (string, nullable) # English name if available
- parent_id (integer, nullable) # For hierarchical categories
- metadata_json (map, nullable) # Store full API response
- updated_at (datetime)

**Identities:**
- [:metadata_type, :yaga_id] (unique)

**Note:** Refreshed weekly via background job

---

## File Structure

```
lib/kirbs/
├── resources/
│   ├── bag.ex
│   ├── client.ex
│   ├── item.ex
│   ├── settings.ex
│   ├── user.ex
│   └── yaga_metadata.ex
├── services/
│   ├── photo_capture.ex              # Save bag/item photos to disk
│   ├── ai/
│   │   ├── client_info_extractor.ex  # AI: read handwritten info
│   │   ├── client_matcher.ex         # Find/create client
│   │   ├── item_analyzer.ex          # AI: analyze item photos
│   │   └── item_pricer.ex            # AI: determine price
│   ├── yaga/
│   │   ├── uploader.ex               # Upload item to yaga (multi-step)
│   │   ├── auth.ex                   # Get JWT from settings
│   │   ├── metadata_fetcher.ex       # Fetch & cache Yaga taxonomy
│   │   └── mapper.ex                 # Map text → Yaga IDs
│   ├── image_resizer.ex              # Resize old images
│   └── profit_calculator.ex          # Calculate client payouts
├── jobs/
│   ├── process_bag_job.ex            # Trigger AI for bag
│   ├── process_item_job.ex           # Trigger AI for item
│   ├── upload_item_job.ex            # Upload to yaga
│   ├── resize_images_job.ex          # Resize old images
│   └── refresh_yaga_metadata_job.ex  # Weekly refresh of Yaga taxonomy
└── kirbs.ex                          # Main domain

lib/kirbs_web/
├── live/
│   ├── bag_live/
│   │   ├── index.ex                  # List all bags
│   │   ├── capture.ex                # Single continuous camera flow
│   │   └── show.ex                   # Show bag + items
│   ├── item_live/
│   │   └── show.ex                   # Show item details + inline edit
│   ├── review_live/
│   │   └── index.ex                  # Review queue (AI-processed items)
│   ├── dashboard_live/
│   │   └── index.ex                  # Stats dashboard
│   ├── client_live/
│   │   ├── index.ex                  # List clients
│   │   └── show.ex                   # Show client + their bags/items
│   └── settings_live/
│       └── index.ex                  # Manage JWT token
├── components/
│   ├── camera_capture.ex             # LiveView camera component
│   ├── image_gallery.ex              # Display multiple images
│   └── ai_status_badge.ex            # Show AI processing status
└── router.ex

priv/
├── data/
│   └── yaga_requests.har             # HAR file with yaga.ee API examples
└── static/
    └── uploads/                      # Configurable image storage dir

config/
├── config.exs
├── dev.exs
└── runtime.exs                       # IMAGE_UPLOAD_DIR env var
```

---

## Views / LiveViews

### 1. BagLive.Index (`/bags`)
- List all bags (newest first)
- Show client name, item count, status summary
- Filter by: needs review, ready to upload, completed
- "Start New Bag" button → goes to BagLive.Capture

### 2. BagLive.Capture (`/bags/capture`)
**Single continuous camera flow - never leaves camera view:**

**Phase 1 - Bag Photos:**
1. Shows "Take Bag Photo" prompt
2. Operator takes photo → auto-advances
3. Shows "Take Layout Photo" prompt
4. Operator takes photo → auto-advances
5. Shows "Take Info Photo" prompt
6. Operator takes photo → creates Bag with 3 images
7. Automatically transitions to Phase 2

**Phase 2 - Item Photos (loop):**
1. Shows "New Item - Take Photos" prompt
2. Operator clicks "Capture" → takes photo → adds to current item's photos
3. Can click "Capture" multiple times to add more photos to same item
4. "Next Item" button → saves current item, starts new item, loops back to step 1
5. "End Bag" button → saves current item if any, triggers AI jobs, redirects to ReviewLive.Index

**UI Elements:**
- Large camera viewfinder (full screen on mobile)
- Current step indicator: "Bag 1/3" or "Item 3 - Photo 2"
- **Only 3 buttons:** "Capture", "Next Item", "End Bag"
- Small thumbnails of captured photos at bottom
- Can't navigate away until "End Bag"

### 3. BagLive.Show (`/bags/:id`)
- Display bag photos (3 images)
- Show client info (if matched by AI)
- List all items with thumbnails and status
- Click item → goes to ItemLive.Show

### 4. ItemLive.Show (`/items/:id`)
**Primary review interface**
- Display all photos (with delete button per photo)
- Show AI-extracted text data: brand, size, colors, materials, description, quality, suggested_category
- Show Yaga ID fields (dropdowns/autocomplete):
  - yaga_brand_id
  - yaga_category_id
  - yaga_colors_id_map (multi-select)
  - yaga_materials_id_map (multi-select)
  - yaga_condition_id
- Show pricing (AI suggestion + explanation, listed_price - editable)
- All fields inline editable
- Status badge
- "Ready for Yaga" button → triggers upload job (validates required Yaga fields)
- "Mark as Sold" / "Mark as Discarded" buttons (for after sale)
- If upload_failed: show error message, "Retry Upload" button

### 5. ReviewLive.Index (`/review`)
- List all items with `status = ai_processed`
- Group by bag
- For each item: thumbnail, AI data summary, "Review" button
- Batch actions: "Approve All", "Review Selected"
- Clicking item → goes to ItemLive.Show for inline editing

### 6. DashboardLive.Index (`/dashboard`)
**Cards showing:**
- Total items uploaded
- Total items sold
- Total revenue
- Total client payouts
- Items pending review
- Items pending upload
- Failed uploads (needs attention)
- Recent activity feed

### 7. ClientLive.Index (`/clients`)
- List all clients
- Show: name, phone, total bags, total items, total payout
- Search/filter
- Click → ClientLive.Show

### 8. ClientLive.Show (`/clients/:id`)
- Client details
- List their bags
- List their items
- Total payout calculation
- Inline edit for client fields

### 9. SettingsLive.Index (`/settings`)
**Form fields:**
- Yaga JWT token (textarea)
- "Save Settings" button

---

## Services Detail

### PhotoCapture
**Input for bag:** `%{type: :bag, photos: [upload1, upload2, upload3]}`
**Input for item:** `%{type: :item, bag_id: id, photos: [upload1, upload2, ...]}`
**Output:** `{:ok, bag}` or `{:ok, item}`
- Save photos to disk (configured directory from runtime.exs)
- For bag: Create Bag record with images array
- For item: Create Item record with photo_paths array

### AI.ClientInfoExtractor
**Input:** `bag_id`
**Output:** `{:ok, %{name: ..., phone: ..., email: ..., iban: ...}}`
- Load bag.images[2] (info photo)
- Call LangChain with Claude vision
- Extract: name, phone, email, IBAN

### AI.ClientMatcher
**Input:** `extracted_info`
**Output:** `{:ok, client}`
- Search for existing client by phone + email
- If found: return existing client
- If not: create new client

### AI.ItemAnalyzer
**Input:** `item_id`
**Output:** `{:ok, item}`
- Load item.photo_paths
- Call LangChain with Claude vision (all photos)
- Extract: brand, size, colors, materials, description, quality, suggested_category
- Update item with AI data via Ash.update
- Leave yaga_* fields nil (operator fills during review)

### AI.ItemPricer
**Input:** `item_id`
**Output:** `{:ok, item}`
- Load item (brand, size, description, quality, photos)
- Call LangChain with Claude
- Prompt: "What should this item be priced at on yaga.ee? Explain."
- Parse response for price + explanation
- Update item with ai_suggested_price, ai_price_explanation, listed_price via Ash.update

### Yaga.MetadataFetcher
**Input:** none
**Output:** `{:ok, count}`
- Fetch from Yaga public APIs:
  - GET /api/brand/?groupedFlat=true&sortOtherAlphabetically=true
  - GET /api/category
  - GET /api/color
  - GET /api/material
  - GET /api/condition
- Upsert into YagaMetadata resource
- Return count of records updated

### Yaga.Mapper
**Input:** `item_id`
**Output:** `{:ok, item}` or `{:ok, item}` with warnings
- Load item with text fields (brand, colors, materials, quality, suggested_category)
- Load YagaMetadata for each type
- Fuzzy match text → IDs:
  - brand → yaga_brand_id
  - colors → yaga_colors_id_map
  - materials → yaga_materials_id_map
  - quality → yaga_condition_id
  - suggested_category → yaga_category_id
- If can't match, leave nil
- Update item with yaga_* fields via Ash.update

### Yaga.Uploader
**Input:** `item_id`
**Output:** `{:ok, item}` or `{:error, reason}`
**See YAGA_UPLOAD_SPEC.md for detailed multi-step flow**
- Validate required Yaga fields present
- Create draft product
- Upload photos to S3
- Attach images to product
- Publish product with all metadata
- On success: update item (status = uploaded_to_yaga, yaga_id, yaga_slug)
- On failure: update item (status = upload_failed, upload_error)

### Yaga.Auth
**Input:** none
**Output:** JWT string
- Query Settings for key="yaga_jwt"

### ImageResizer
**Input:** `days_old`
**Output:** `{:ok, count}`
- Find all image files older than X days
- Resize to smaller version
- Replace original

### ProfitCalculator
**Input:** `client_id`
**Output:** `{:ok, total_payout}`
- Get all sold items for client
- Sum: sold_price / 2

---

## Oban Jobs

### ProcessBagJob
**Triggered:** After bag photos uploaded (from BagLive.Capture "End Bag")
**Actions:**
- AI.ClientInfoExtractor.run(bag_id)
- AI.ClientMatcher.run(extracted_info)
- Ash.update bag with client_id

### ProcessItemJob
**Triggered:** After item photos uploaded (from BagLive.Capture "End Bag")
**Actions:**
- AI.ItemAnalyzer.run(item_id) # Extracts text data
- AI.ItemPricer.run(item_id) # Determines pricing
- Yaga.Mapper.run(item_id) # Attempts to map to Yaga IDs (best effort)
- Ash.update item with status = ai_processed

### UploadItemJob
**Triggered:** When operator clicks "Ready for Yaga" (from ItemLive.Show)
**Actions:**
- Yaga.Uploader.run(item_id) # Multi-step upload process

### RefreshYagaMetadataJob
**Triggered:** Cron job (weekly) or manual via settings UI
**Actions:**
- Yaga.MetadataFetcher.run() # Refresh all metadata from Yaga

### ResizeImagesJob
**Triggered:** Cron job (weekly)
**Actions:**
- ImageResizer.run(7) # Resize images older than 7 days

---

## Ash Actions

### Bag
**Defaults:** `defaults [:create, :read, :update]`
**Default Accept:** `default_accept [:images, :client_id]`

**Code Interface:**
- `define :get, args: [:id]`
- `define :list`
- Use Ash.update for all updates

### Item
**Defaults:** `defaults [:create, :read, :update]`
**Default Accept:** `default_accept [:bag_id, :photo_paths, :brand, :size, :colors, :materials, :description, :quality, :suggested_category, :yaga_brand_id, :yaga_category_id, :yaga_colors_id_map, :yaga_materials_id_map, :yaga_condition_id, :ai_suggested_price, :ai_price_explanation, :listed_price, :sold_price, :status, :yaga_id, :yaga_slug, :upload_error]`

**Code Interface:**
- `define :get, args: [:id]`
- `define :list`
- `define :get_by_bag, args: [:bag_id]`
- Use Ash.update for all updates

### Client
**Defaults:** `defaults [:create, :read, :update]`
**Default Accept:** `default_accept [:name, :phone, :email, :iban]`

**Identities:**
- `identity :unique_phone, [:phone]`

**Code Interface:**
- `define :get, args: [:id]`
- `define :list`
- `define :find_by_phone, args: [:phone]` (uses identity)

### Settings
**Defaults:** `defaults [:create, :read, :update]`
**Default Accept:** `default_accept [:key, :value]`

**Identities:**
- `identity :unique_key, [:key]`

**Code Interface:**
- `define :get_by_key, args: [:key]`
- Use upsert for saving settings

### YagaMetadata
**Defaults:** `defaults [:create, :read, :update]`
**Default Accept:** `default_accept [:metadata_type, :yaga_id, :name, :name_en, :parent_id, :metadata_json]`

**Identities:**
- `identity :unique_metadata, [:metadata_type, :yaga_id]`

**Code Interface:**
- `define :list_by_type, args: [:metadata_type]`
- Use upsert for refreshing metadata

---

## Configuration

### Dependencies (mix.exs)
- langchain: `{:langchain, github: "brainlid/langchain", ref: "177ac13"}`
- ash, ash_postgres, ash_authentication (already installed)
- oban (already installed)

### Environment Variables (runtime.exs)
- `IMAGE_UPLOAD_DIR` - Where to store uploaded photos (default: /tmp/kirbs_uploads)
- `ANTHROPIC_API_KEY` - Claude API key for LangChain

### Settings (stored in database via Settings resource)
- `yaga_jwt` - JWT token for yaga.ee API

---

## Phase 1 Implementation Priority

1. **Resources** - Bag, Client, Item, Settings, YagaMetadata with all attributes
2. **Photo Capture Flow** - BagLive.Capture single continuous camera view (mobile)
3. **PhotoCapture Service** - Save photos to disk, create Bag/Item records
4. **Yaga Metadata** - Yaga.MetadataFetcher + RefreshYagaMetadataJob + seed task
5. **AI Integration** - LangChain services (ClientInfoExtractor, ItemAnalyzer, ItemPricer)
6. **Yaga Mapper** - Yaga.Mapper for text → ID mapping (best effort)
7. **Background Jobs** - Oban jobs for AI processing (ProcessBagJob, ProcessItemJob with mapping)
8. **Review UI** - ReviewLive.Index, ItemLive.Show with Yaga field dropdowns (desktop)
9. **Yaga Upload** - Yaga.Uploader service (multi-step) + UploadItemJob
10. **Sales Tracking** - Mark sold/discarded via ItemLive.Show
11. **Dashboard** - DashboardLive.Index with stats
12. **Image Resizing** - ResizeImagesJob (weekly cron)

---

## Notes

### Photo Management
- All photos saved at full size initially to configured IMAGE_UPLOAD_DIR
- Weekly ResizeImagesJob resizes images older than 7 days (replaces originals)
- First photo in item.photo_paths becomes primary for yaga.ee
- Bag always has exactly 3 images: [bag_photo, layout_photo, info_photo]

### Device Separation
- **Mobile phone**: Photo capture only (BagLive.Capture)
- **Desktop computer**: Review, Yaga field management, upload triggering
- Photos uploaded to Kirbs server immediately during capture
- Review happens later on different device

### Camera Flow
- Single continuous BagLive.Capture view for entire bag processing
- Only 3 buttons: Capture, Next Item, End Bag
- Never leaves camera view until operator clicks "End Bag"
- Photos auto-upload to server as captured
- AI processing triggered in background after "End Bag"

### Code Organization
- Resources in resources/ directory, single domain (Kirbs)
- Services in services/ with subdirectories: ai/, yaga/
- Services follow pattern: run() entry point, with {:ok, result} <- step() internally
- Jobs (not workers) in jobs/ directory
- Use Ash.update directly, minimal custom actions

### External Integrations
- HAR reference in priv/data/yaga_post_request_log.json
- Yaga.Uploader implements multi-step upload flow (see YAGA_UPLOAD_SPEC.md)
- Yaga metadata cached locally, refreshed weekly
- Use LangChain for all LLM interactions
- JWT token stored in Settings resource, configured via UI

### Image Upload Directory
- Configured in config/runtime.exs via IMAGE_UPLOAD_DIR env var
- Not configurable via UI (Settings resource is only for JWT)

### Yaga Field Mapping
- AI attempts best-effort mapping via Yaga.Mapper
- If mapping fails, fields left nil
- Operator fills missing fields during review
- Validation on "Ready for Yaga" ensures required fields present
