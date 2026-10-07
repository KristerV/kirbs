defmodule Kirbs.Services.Ai.ItemCategorize do
  @moduledoc """
  Proposes a category (leaf of the category tree) and typed attributes for an item
  from its photos, using a vision LLM constrained by a JSON schema.

  Pure with respect to the item: returns the proposal, persisting is the caller's job.
  """

  alias Kirbs.Resources.Category
  alias Kirbs.Services.Ai.ItemCategorizeLlm
  alias Kirbs.YagaTaxonomy

  @age_groups ~w(baby toddler child teen adult)
  @genders ~w(girl boy unisex woman man)
  @seasons ~w(spring_autumn summer winter all_year)
  @conditions ~w(new_with_tags like_new good fair)
  @max_images 6

  def run(item) do
    with {:ok, item} <- load_images(item),
         {:ok, leaves} <- load_leaves(),
         {:ok, images} <- encode_images(item.images),
         {:ok, text} <- call_llm(images, prompt(item, leaves), schema(leaves)),
         {:ok, data} <- decode(text),
         {:ok, result} <- validate(data, leaves) do
      {:ok, result}
    end
  end

  defp load_images(item) do
    case Ash.load(item, [:images]) do
      {:ok, %{images: [_ | _]} = item} -> {:ok, item}
      {:ok, _} -> {:cancel, "No photos found for item"}
      {:error, error} -> {:error, error}
    end
  end

  # Leaves are categories without children below a root (family -> type, or a family that is
  # a leaf itself), keyed by slug. The audience root is not part of the shown path.
  defp load_leaves do
    all = Category.list_all!()
    by_id = Map.new(all, &{&1.id, &1})
    parent_ids = all |> Enum.map(& &1.parent_id) |> MapSet.new()

    leaves =
      all
      |> Enum.reject(&(is_nil(&1.parent_id) or MapSet.member?(parent_ids, &1.id)))
      |> Enum.map(fn leaf ->
        family = Map.get(by_id, leaf.parent_id)
        family = if family && family.parent_id, do: family
        path = [family, leaf] |> Enum.reject(&is_nil/1) |> Enum.map_join(" > ", & &1.name_et)
        %{id: leaf.id, slug: leaf.slug, path: path}
      end)

    case leaves do
      [] -> {:error, "No category leaves found, seed the category tree first"}
      _ -> {:ok, leaves}
    end
  end

  defp encode_images(images) do
    upload_dir = Application.get_env(:kirbs, :image_upload_dir, "/tmp/kirbs_uploads")

    images
    |> Enum.take(@max_images)
    |> Enum.reduce_while({:ok, []}, fn image, {:ok, acc} ->
      case File.read(Path.join(upload_dir, image.path)) do
        {:ok, data} ->
          {:cont, {:ok, [Base.encode64(data) | acc]}}

        {:error, reason} ->
          {:halt, {:error, "Failed to read image #{image.path}: #{inspect(reason)}"}}
      end
    end)
    |> case do
      {:ok, encoded} -> {:ok, Enum.reverse(encoded)}
      error -> error
    end
  end

  defp call_llm(images, prompt, schema) do
    client = Application.get_env(:kirbs, :item_categorize_llm, ItemCategorizeLlm)
    client.run(images, prompt, schema)
  end

  defp colors, do: Enum.map(YagaTaxonomy.all_colors(), & &1.name)
  defp materials, do: Enum.map(YagaTaxonomy.all_materials(), & &1.name)

  @doc false
  def schema(leaves) do
    nullable_enum = fn values -> %{"type" => ["string", "null"], "enum" => values ++ [nil]} end

    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" =>
        ~w(category_slug age_group gender season condition colors materials brand size confidence),
      "properties" => %{
        "category_slug" => %{"type" => "string", "enum" => Enum.map(leaves, & &1.slug)},
        "age_group" => nullable_enum.(@age_groups),
        "gender" => nullable_enum.(@genders),
        "season" => nullable_enum.(@seasons),
        "condition" => nullable_enum.(@conditions),
        "colors" => %{"type" => "array", "items" => %{"type" => "string", "enum" => colors()}},
        "materials" => %{
          "type" => "array",
          "items" => %{"type" => "string", "enum" => materials()}
        },
        "brand" => %{"type" => ["string", "null"]},
        "size" => %{"type" => ["string", "null"]},
        "confidence" => %{"type" => "number"}
      }
    }
  end

  defp prompt(item, leaves) do
    categories = Enum.map_join(leaves, "\n", &"- #{&1.slug}: #{&1.path}")

    hints =
      [
        {"brand", item.brand},
        {"size", item.size},
        {"description", item.description},
        {"suggested category", item.suggested_category}
      ]
      |> Enum.reject(fn {_, v} -> v in [nil, ""] end)
      |> Enum.map_join("\n", fn {k, v} -> "- #{k}: #{v}" end)

    known = if hints == "", do: "", else: "\nAlready known about this item:\n" <> hints

    """
    You classify used children's clothing for an Estonian second-hand shop from photos.
    The photos may show several items sold as one set; pick the category of the main item.

    category_slug describes ONLY what kind of garment or item it is (its type). Never let the
    child's gender, age or the season influence the category; record those separately as gender,
    age_group and season. A winter jacket and a summer jacket both belong to the same `jakid` leaf,
    winter boots and light boots to `saapad`, a winter overall and a rain overall to `kombinesoonid`
    (rain gear that is a jacket, pants or overall may use `vihmariided`).
    Choose category_slug from exactly this list (family > type):
    #{categories}

    Attributes:
    - age_group: #{Enum.join(@age_groups, ", ")} (baby = up to ~86cm, toddler ~92-104, child ~110-146, teen 152+)
    - gender: #{Enum.join(@genders, ", ")} (use unisex when neutral)
    - season: #{Enum.join(@seasons, ", ")} (judge from insulation, lining, fabric weight and use,
      independently of the category; all_year when it suits any season)
    - condition: #{Enum.join(@conditions, ", ")} (new_with_tags only if a shop tag is visible)
    - colors: at most 2 dominant colors, from the allowed Estonian list
    - materials: from the allowed Estonian list, only if visible on a label
    - brand: printed on the label only, normalized capitalization (e.g. "H&M"), else null
    - size: as printed on the label (e.g. "74/80"), else null
    - confidence: 0..1, how sure you are about category_slug
    Use null when an attribute cannot be determined.
    #{known}
    """
  end

  defp decode(text) do
    with {:error, _} <- Jason.decode(text),
         [json] <- Regex.run(~r/\{.*\}/s, text),
         {:ok, data} when is_map(data) <- Jason.decode(json) do
      {:ok, data}
    else
      {:ok, data} when is_map(data) -> {:ok, data}
      _ -> {:cancel, "Could not parse categorization response: #{String.slice(text, 0..300)}"}
    end
  end

  defp validate(data, leaves) do
    case Enum.find(leaves, &(&1.slug == data["category_slug"])) do
      nil ->
        {:cancel, "Unknown category slug: #{inspect(data["category_slug"])}"}

      leaf ->
        {:ok,
         %{
           category_id: leaf.id,
           category_slug: leaf.slug,
           age_group: enum(data["age_group"], @age_groups),
           gender: enum(data["gender"], @genders),
           season: enum(data["season"], @seasons),
           condition: enum(data["condition"], @conditions),
           colors: data["colors"] |> list(colors()) |> Enum.take(2),
           materials: list(data["materials"], materials()),
           brand: blank_to_nil(data["brand"]),
           size: blank_to_nil(data["size"]),
           confidence: confidence(data["confidence"])
         }}
    end
  end

  # Whitelisted strings, so converting to atoms is safe.
  defp enum(value, allowed) when is_binary(value) do
    if value in allowed, do: String.to_existing_atom(value)
  end

  defp enum(_, _), do: nil

  defp list(values, allowed) when is_list(values),
    do: values |> Enum.filter(&(&1 in allowed)) |> Enum.uniq()

  defp list(_, _), do: []

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_), do: nil

  defp confidence(value) when is_number(value), do: (value |> max(0.0) |> min(1.0)) * 1.0
  defp confidence(_), do: 0.0
end
