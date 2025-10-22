# Complete HAR processing script
# This processes a HAR file from Firefox to extract relevant API calls for product upload automation

input_file = "priv/data/yaga_request_log.json"
output_file = "priv/data/yaga_clean_entries.json"

# Only keep these important headers
important_headers = ["authorization", "content-type", "x-language", "x-country"]

# List of public API endpoints that can be re-fetched
public_endpoints = [
  "/api/category",
  "/api/color",
  "/api/material",
  "/api/condition",
  "/api/shipping/options",
  "/api/brand/",
  "/api/product/sizes/",
  "/api/translation"
]

IO.puts("Step 1: Reading HAR file...")
har_data = File.read!(input_file) |> Jason.decode!()

IO.puts("Step 2: Extracting and filtering entries...")
entries = har_data["log"]["entries"]
IO.puts("  Total entries: #{length(entries)}")

# Filter out polling requests
filtered_entries =
  Enum.reject(entries, fn entry ->
    entry["request"]["url"] == "https://www.yaga.ee/messaging/message/unread/all?noTimeoutHandling=true"
  end)

IO.puts("  After removing polling: #{length(filtered_entries)}")

IO.puts("Step 3: Simplifying entries to essential fields...")
simplified_entries =
  Enum.map(filtered_entries, fn entry ->
    # Extract important request headers
    request_headers =
      entry["request"]["headers"]
      |> Enum.filter(fn h -> String.downcase(h["name"]) in important_headers end)
      |> Enum.map(fn h -> {h["name"], h["value"]} end)
      |> Map.new()

    # Extract request body if present
    request_body = get_in(entry, ["request", "postData", "text"])

    # Build simplified entry
    %{
      "method" => entry["request"]["method"],
      "url" => entry["request"]["url"],
      "headers" => request_headers,
      "body" => request_body,
      "response" => %{
        "status" => entry["response"]["status"],
        "body" => get_in(entry, ["response", "content", "text"])
      }
    }
  end)

IO.puts("Step 4: Trimming to keep only up to last PATCH...")
# Find the last PATCH request
last_patch_index =
  simplified_entries
  |> Enum.with_index()
  |> Enum.reverse()
  |> Enum.find_value(fn {entry, idx} ->
    if entry["method"] == "PATCH", do: idx
  end)

trimmed_entries = Enum.take(simplified_entries, (last_patch_index || 0) + 1)
IO.puts("  Kept #{length(trimmed_entries)} entries (up to last PATCH)")

IO.puts("Step 5: Replacing large bodies with placeholders...")
clean_entries =
  Enum.map(trimmed_entries, fn entry ->
    # Replace S3 image upload body with placeholder
    entry =
      if entry["method"] == "PUT" and String.contains?(entry["url"], "s3.eu-north-1.amazonaws.com") do
        put_in(entry, ["body"], "<BINARY_IMAGE_DATA: JPEG file contents go here>")
      else
        entry
      end

    # Replace public endpoint response bodies with placeholders
    is_public =
      entry["method"] == "GET" and
        Enum.any?(public_endpoints, fn endpoint ->
          String.contains?(entry["url"], endpoint)
        end)

    entry =
      if is_public do
        put_in(entry, ["response", "body"], "<PUBLIC_ENDPOINT: Response can be fetched by making GET request to the URL>")
      else
        entry
      end

    entry
  end)

IO.puts("Step 6: Writing output file...")
File.write!(output_file, Jason.encode!(clean_entries, pretty: true))

# Show final statistics
file_size = File.stat!(output_file).size
line_count = File.read!(output_file) |> String.split("\n") |> length()

IO.puts("\n✓ Processing complete!")
IO.puts("  Output: #{output_file}")
IO.puts("  Size: #{div(file_size, 1024)} KB")
IO.puts("  Lines: #{line_count}")
IO.puts("  Entries: #{length(clean_entries)}")
