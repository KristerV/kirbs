# Kirbs - TODO List

## Phase 1: Photo Capture ✅
- [x] Create Client resource
- [x] Create Bag resource
- [x] Create Item resource
- [x] Create Image resource (separate table for images)
- [x] Create PhotoCapture service
- [x] Implement JavaScript camera hook
- [x] Create BagLive.Capture (continuous camera flow)
  - [x] Phase 1: Capture 3 bag photos (bag, layout, info)
  - [x] Phase 2: Capture item photos (multiple per item)
  - [x] Auto-save photos to disk
  - [x] Create Image records linked to bags/items
- [x] Create BagLive.Index (list all bags)
- [x] Configure IMAGE_UPLOAD_DIR
- [x] Add routes for bag capture flow

## Phase 2: Resources & Settings ✅
- [x] Create Settings resource
- [x] Create YagaMetadata resource
- [x] Create SettingsLive.Index (manage JWT token)

## Phase 3: Yaga Integration - Metadata ⚠️ (mostly done, manual refresh via UI works)
- [x] Create Yaga.MetadataFetcher service
  - [x] Fetch brands from Yaga API
  - [x] Fetch categories from Yaga API
  - [x] Fetch colors from Yaga API
  - [x] Fetch materials from Yaga API
  - [x] Fetch conditions from Yaga API
- [ ] Create RefreshYagaMetadataJob (Oban) - manual refresh via settings UI works
- [ ] Create seed task to populate Yaga metadata - can use settings UI
- [x] Create Yaga.Auth service (get JWT from settings)

## Phase 4: AI Integration
- [ ] Install/configure LangChain (or alternative)
- [ ] Create AI.ClientInfoExtractor service
  - [ ] Read handwritten info photo
  - [ ] Extract: name, phone, email, IBAN
- [ ] Create AI.ClientMatcher service
  - [ ] Search existing clients by phone
  - [ ] Create new client if not found
- [ ] Create AI.ItemAnalyzer service
  - [ ] Analyze item photos
  - [ ] Extract: brand, size, colors, materials, description, quality, suggested_category
- [ ] Create AI.ItemPricer service
  - [ ] Determine suggested price
  - [ ] Generate price explanation
- [ ] Create Yaga.Mapper service
  - [ ] Fuzzy match text → Yaga IDs (brand, colors, materials, condition, category)
  - [ ] Leave nil if can't match

## Phase 5: Background Processing
- [ ] Create ProcessBagJob (Oban)
  - [ ] Trigger ClientInfoExtractor
  - [ ] Trigger ClientMatcher
  - [ ] Update bag with client_id
- [ ] Create ProcessItemJob (Oban)
  - [ ] Trigger ItemAnalyzer
  - [ ] Trigger ItemPricer
  - [ ] Trigger Yaga.Mapper (best effort)
  - [ ] Update item status to ai_processed
- [ ] Wire up jobs to trigger after "End Bag"

## Phase 6: Review UI ✅ (UI complete, needs AI integration)
- [x] Create ReviewLive.Index
  - [x] List items with status = ai_processed
  - [x] Group by bag
  - [x] Show AI data summary
  - [x] Link to item details
- [x] Create ItemLive.Show
  - [x] Display all item photos (with delete button)
  - [x] Show AI-extracted text data (inline editable)
  - [x] Show Yaga ID fields (dropdowns/autocomplete)
  - [x] Show pricing (AI suggestion + listed price)
  - [ ] "Ready for Yaga" button (save button exists, upload not implemented)
  - [x] Status badge
  - [x] Error display if upload failed
- [x] Create BagLive.Show
  - [x] Display 3 bag photos
  - [x] Show client info (if matched)
  - [x] List all items with thumbnails
  - [x] Link to item details

## Phase 7: Yaga Upload
- [ ] Create Yaga.Uploader service
  - [ ] Step 1: Create draft product
  - [ ] Step 2: Upload photos to S3 (repeat for each)
  - [ ] Step 3: Publish product with metadata
  - [ ] On success: update item (status, yaga_id, yaga_slug)
  - [ ] On failure: update item (status, upload_error)
- [ ] Create UploadItemJob (Oban)
- [ ] Wire up "Ready for Yaga" button to trigger job
- [ ] Add "Retry Upload" button for failed uploads

## Phase 8: Sales Tracking
- [ ] Add "Mark as Sold" functionality to ItemLive.Show
  - [ ] Enter actual selling price
  - [ ] Calculate profit (sold_price / 2)
- [ ] Add "Mark as Discarded" functionality
- [ ] Create ProfitCalculator service
  - [ ] Calculate total payout per client

## Phase 9: Client Management
- [ ] Create ClientLive.Index
  - [ ] List all clients
  - [ ] Show: name, phone, total bags, total items, total payout
  - [ ] Search/filter
- [ ] Create ClientLive.Show
  - [ ] Display client details (inline editable)
  - [ ] List their bags
  - [ ] List their items
  - [ ] Total payout calculation

## Phase 10: Dashboard ✅ (basic metrics done)
- [x] Create DashboardLive.Index
  - [x] Total items uploaded
  - [x] Total items sold
  - [x] Total revenue
  - [x] Total client payouts
  - [x] Items pending review
  - [x] Items pending upload
  - [x] Failed uploads (needs attention)
  - [ ] Recent activity feed

## Phase 11: Image Management
- [ ] Create ImageResizer service
  - [ ] Find images older than X days
  - [ ] Resize to smaller version
  - [ ] Replace original
- [ ] Create ResizeImagesJob (Oban, weekly cron)
- [x] Add image deletion functionality (from ItemLive.Show)

## Nice to Have / Future
- [ ] Edit existing Yaga products (re-upload)
- [ ] Delete product from Yaga when marked as discarded
- [ ] Sync sold status from Yaga back to Kirbs
- [ ] Bulk upload (currently one at a time)
- [ ] Token auto-refresh for Yaga JWT
- [ ] Mobile app optimization
- [ ] Image compression before upload
- [ ] Batch approval in ReviewLive
- [ ] Export client payouts to CSV
- [ ] Client payout history tracking
