# Yaga.ee Upload Integration - Technical Specification

## Overview
Detailed specification for uploading items to yaga.ee marketplace. Based on HAR analysis from `priv/data/yaga_post_request_log.json`.

---

## Upload Flow

The upload process is multi-step and requires several API calls:

### Step 1: Create Draft Product
**Endpoint:** `POST https://www.yaga.ee/api/product`

**Headers:**
```
Authorization: Bearer {JWT}
Content-Type: application/json
x-country: EE
x-language: et
```

**Body:**
```json
{
  "currency": "€"
}
```

**Response:**
```json
{
  "status": "success",
  "data": {
    "id": 21589468,
    "slug": "gq450umilmg",
    "status": "draft",
    ...
  }
}
```

**Extract:** `product_id` and `slug` for subsequent steps

---

### Step 2: Upload Photos (repeat for each photo)

#### Step 2a: Get S3 Upload URL
**Endpoint:** `GET https://www.yaga.ee/api/product/uploadurl/`

**Query Params:**
- `slug`: Product slug from step 1
- `type`: "jpeg" (or file extension)
- `timestamp`: Current timestamp in milliseconds

**Headers:**
```
Authorization: Bearer {JWT}
x-country: EE
x-language: et
```

**Response:**
```json
{
  "status": "success",
  "data": {
    "url": "https://ee-prod-yaga-product-images.s3.eu-north-1.amazonaws.com/...",
    "fileName": "1c9678.jpeg"
  }
}
```

**Extract:** `url` and `fileName`

#### Step 2b: Upload to S3
**Endpoint:** The presigned S3 URL from step 2a

**Method:** `PUT`

**Headers:**
```
Content-Type: image/jpeg
```

**Body:** Binary image data

**Response:** 200 OK (empty body)

#### Step 2c: Attach Image to Product
**Endpoint:** `POST https://www.yaga.ee/api/product/{product_id}/images`

**Headers:**
```
Authorization: Bearer {JWT}
Content-Type: application/json
x-country: EE
x-language: et
```

**Body:**
```json
{
  "images": [
    {"fileName": "1c9678.jpeg"}
  ]
}
```

**Response:**
```json
{
  "status": "success",
  "data": [
    {
      "id": "1c9678",
      "fileName": "1c9678.jpeg",
      "thumbnail": "https://images.yaga.ee/gq450umilmg/1c9678.jpeg?s=300",
      "gallery": "https://images.yaga.ee/gq450umilmg/1c9678.jpeg?s=600",
      "original": "https://images.yaga.ee/gq450umilmg/1c9678.jpeg"
    }
  ]
}
```

**Repeat steps 2a-2c for all photos**

---

### Step 3: Publish Product with Metadata
**Endpoint:** `PATCH https://www.yaga.ee/api/product/{product_id}`

**Headers:**
```
Authorization: Bearer {JWT}
Content-Type: application/json
x-country: EE
x-language: et
```

**Body:**
```json
{
  "price": 10,
  "quantity": 1,
  "colors_id_map": [3, 2],
  "materials_id_map": [5, 13],
  "category_id": 438,
  "condition_id": 2,
  "attributes": {
    "size": "6-9 kuud"
  },
  "description": "Blue and red cotton baby clothes",
  "location": "Tallinn/Harjumaa",
  "address": "Saue vald",
  "brand_id": 69,
  "shipping": {
    "dpd": {
      "enabled": true,
      "selectedPrice": "small"
    },
    "omniva": {
      "enabled": true,
      "selectedPrice": "small"
    },
    "bundling": {
      "enabled": true,
      "selectedPrice": "zero"
    },
    "smartpost": {
      "enabled": true,
      "selectedPrice": "small"
    },
    "uponAgreement": {
      "enabled": false,
      "selectedPrice": "zero"
    },
    "fromHandToHand": {
      "enabled": false,
      "selectedPrice": "zero"
    }
  },
  "status": "published"
}
```

**Response:**
```json
{
  "status": "success",
  "data": {
    "id": 21589468,
    "slug": "gq450umilmg",
    "status": "published",
    ...
  }
}
```

---

## Field Mappings

### Required Fields (from Item)
- `price` → `item.listed_price`
- `category_id` → `item.yaga_category_id` (REQUIRED)
- `condition_id` → `item.yaga_condition_id` (REQUIRED)
- `description` → `item.description` (REQUIRED)

### Optional Fields
- `brand_id` → `item.yaga_brand_id`
- `colors_id_map` → `item.yaga_colors_id_map` (array)
- `materials_id_map` → `item.yaga_materials_id_map` (array)
- `attributes.size` → `item.size` (freeform string)

### Fixed/Default Fields
- `quantity`: Always `1`
- `currency`: Always `"€"`
- `location`: From shop settings or hardcoded "Tallinn/Harjumaa"
- `address`: From shop settings or hardcoded "Saue vald"
- `shipping`: Use shop's default shipping options (fetch once, cache)

---

## Shipping Configuration

Default shipping setup (can be fetched from shop settings or hardcoded):

```json
{
  "dpd": {
    "enabled": true,
    "selectedPrice": "small"
  },
  "omniva": {
    "enabled": true,
    "selectedPrice": "small"
  },
  "bundling": {
    "enabled": true,
    "selectedPrice": "zero"
  },
  "smartpost": {
    "enabled": true,
    "selectedPrice": "small"
  },
  "uponAgreement": {
    "enabled": false,
    "selectedPrice": "zero"
  },
  "fromHandToHand": {
    "enabled": true,
    "selectedPrice": "zero"
  }
}
```

**Note:** Keep it simple - use fixed defaults or fetch once from shop API.

---

## Error Handling

### Validation Before Upload
Before starting upload, validate:
- Item has at least 1 photo in `photo_paths`
- Required Yaga fields are not nil:
  - `yaga_category_id`
  - `yaga_condition_id`
- `listed_price` is present and > 0
- `description` is not empty

If validation fails:
- Return `{:error, "Missing required fields: category_id, condition_id"}`
- Do not update item status

### During Upload
If any step fails:
- Store error message in `item.upload_error`
- Set `item.status = upload_failed`
- Return `{:error, reason}`

Common failure points:
1. **Step 1 fails**: JWT expired, network error
2. **Step 2a fails**: Invalid slug
3. **Step 2b fails**: S3 upload timeout
4. **Step 3 fails**: Invalid field values (e.g., category_id doesn't exist)

### Retry Strategy
- Operator can click "Retry Upload" in ItemLive.Show
- Re-triggers UploadItemJob with same item_id
- Previous draft may still exist on Yaga (acceptable - just creates new one)

---

## Service Implementation: Yaga.Uploader

### Structure
```elixir
defmodule Kirbs.Services.Yaga.Uploader do
  @moduledoc """
  Uploads item to yaga.ee marketplace.
  Multi-step process: create draft → upload photos → publish.
  """

  def run(item_id) do
    with {:ok, item} <- load_and_validate(item_id),
         {:ok, jwt} <- Yaga.Auth.run(),
         {:ok, product} <- create_draft(jwt),
         {:ok, product} <- upload_photos(jwt, product, item),
         {:ok, product} <- publish_product(jwt, product, item),
         {:ok, item} <- mark_uploaded(item, product) do
      {:ok, item}
    else
      {:error, reason} = error ->
        mark_failed(item_id, reason)
        error
    end
  end

  defp load_and_validate(item_id) do
    # Load item, check required fields
  end

  defp create_draft(jwt) do
    # POST /api/product with {"currency": "€"}
    # Returns %{id: ..., slug: ...}
  end

  defp upload_photos(jwt, product, item) do
    # For each photo in item.photo_paths:
    #   - Get upload URL
    #   - Upload to S3
    #   - Attach to product
  end

  defp publish_product(jwt, product, item) do
    # PATCH /api/product/{id} with all metadata + status: "published"
  end

  defp mark_uploaded(item, product) do
    # Update item: status = uploaded_to_yaga, yaga_id, yaga_slug
  end

  defp mark_failed(item_id, reason) do
    # Update item: status = upload_failed, upload_error = reason
  end
end
```

### HTTP Client
Use `Req` or `HTTPoison` for API calls.

**Example with Req:**
```elixir
Req.post!("https://www.yaga.ee/api/product",
  json: %{currency: "€"},
  headers: [
    {"authorization", "Bearer #{jwt}"},
    {"content-type", "application/json"},
    {"x-country", "EE"},
    {"x-language", "et"}
  ]
)
```

---

## Testing Strategy

### Manual Testing
1. Create test item with all fields populated
2. Run upload, verify:
   - Draft created on yaga.ee
   - Photos uploaded
   - Product published
   - Item updated with yaga_id and yaga_slug

### Error Cases to Test
- Missing required field (category_id)
- Invalid JWT token (expired)
- Network timeout during photo upload
- Invalid category_id (doesn't exist in Yaga)

### Cleanup
- Test items can be deleted manually on yaga.ee
- Or left as drafts (won't show in listings)

---

## Future Enhancements

### Not in MVP
- Edit existing product (re-upload)
- Delete product from yaga.ee when marked as discarded
- Sync sold status from yaga.ee back to Kirbs (currently manual)
- Bulk upload (currently one at a time)

### Category Hierarchy
From HAR response, we see:
```json
"category_id": 438,
"categories_map": [3, 438]
```

This suggests:
- `438` is leaf category (e.g., "Pluus")
- `3` is parent category (e.g., "Lastele")

**For simplicity:** Only store/use leaf category. Yaga API may auto-populate parent.

---

## Constants & Configuration

### Settings Keys
- `yaga_jwt`: JWT token for API authentication

### Hardcoded Values
- Base URL: `https://www.yaga.ee`
- Country: `"EE"`
- Language: `"et"`
- Currency: `"€"`
- Quantity: `1`

### Optional: Shop Location
Either hardcode or fetch once:
- Location: `"Tallinn/Harjumaa"`
- Address: `"Saue vald"`

Can add to Settings if needed, but keep simple for MVP.

---

## Notes

### Token Refresh
The HAR shows a token refresh endpoint:
```
POST /api/auth/token/refresh
```

**For MVP:** Assume operator manually updates JWT in Settings UI when expired.

**Future:** Implement auto-refresh if refresh token available.

### Photo Order
First photo in `item.photo_paths` becomes primary image on yaga.ee listing.

### Image Format
- Yaga accepts JPEG, PNG
- Our system stores full size on disk
- Upload full size to Yaga (they handle resizing)

### Status Updates
After successful upload:
- `item.status` → `uploaded_to_yaga`
- `item.yaga_id` → product ID from Yaga
- `item.yaga_slug` → product slug from Yaga

These allow future features like:
- Direct link to listing: `https://www.yaga.ee/item/{slug}`
- Edit product via API
