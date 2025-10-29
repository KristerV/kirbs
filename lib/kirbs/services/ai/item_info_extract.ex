defmodule Kirbs.Services.Ai.ItemInfoExtract do
  @moduledoc """
  Extracts item information from ALL item photos.
  Uses Claude vision to identify: brand, size, colors, materials, description, quality, suggested_category.
  """

  alias Kirbs.Resources.Item
  alias Kirbs.YagaTaxonomy

  def run(item_id) do
    with {:ok, item} <- load_item(item_id),
         {:ok, images} <- get_item_photos(item),
         {:ok, _} <- validate_has_images(images),
         {:ok, extracted} <- extract_with_ai(images),
         {:ok, validated} <- validate_extracted_data(extracted),
         {:ok, updated_item} <- update_item(item, validated) do
      {:ok, updated_item}
    end
  end

  defp load_item(item_id) do
    case Ash.get(Item, item_id, load: [:images]) do
      {:ok, item} -> {:ok, item}
      {:error, _} -> {:error, "Item not found"}
    end
  end

  defp get_item_photos(%{images: images}) do
    {:ok, images}
  end

  defp validate_has_images([]), do: {:error, "No photos found for item"}
  defp validate_has_images(_), do: {:ok, :valid}

  defp extract_with_ai(images) do
    with {:ok, encoded_images} <- encode_images(images),
         {:ok, result} <- call_claude(encoded_images) do
      parse_response(result)
    end
  end

  defp encode_images(images) do
    upload_dir = Application.get_env(:kirbs, :image_upload_dir, "/tmp/kirbs_uploads")

    encoded =
      Enum.map(images, fn image ->
        full_path = Path.join(upload_dir, image.path)

        case File.read(full_path) do
          {:ok, image_data} ->
            {:ok, Base.encode64(image_data)}

          {:error, reason} ->
            {:error, "Failed to read image #{image.path}: #{inspect(reason)}"}
        end
      end)

    # Check if any encoding failed
    case Enum.find(encoded, &match?({:error, _}, &1)) do
      {:error, reason} -> {:error, reason}
      nil -> {:ok, Enum.map(encoded, fn {:ok, data} -> data end)}
    end
  end

  defp call_claude(encoded_images) do
    alias LangChain.Message.ContentPart

    # Get valid options from taxonomy
    kids_categories = YagaTaxonomy.kids_categories() |> Enum.map(& &1.name) |> Enum.uniq()
    colors = YagaTaxonomy.all_colors() |> Enum.map(& &1.name)
    materials = YagaTaxonomy.all_materials() |> Enum.map(& &1.name)
    conditions = YagaTaxonomy.all_conditions() |> Enum.map(& &1.name)
    sizes = YagaTaxonomy.all_sizes() |> Enum.map(& &1.name)
    brands = YagaTaxonomy.all_brands() |> Enum.map(& &1.name) |> Enum.sort()

    prompt = """
    Analüüsi neid laste rõivaste fotosid ja eralda järgmine informatsioon:

    - brand: AINULT trükitud brändisildilt. Vaata kas on TÄPSELT loendis: #{Enum.join(brands, ", ")}. Kui ei ole loendis VÕI on käsitsi kirjutatud VÕI puudub, kasuta "Muu".
    - size: Suurus. Vaata sildilt ja vali kõige lähedasem neist: #{Enum.join(sizes, ", ")}
    - colors: Värvide loend EESTI KEELES. Vali ainult nendest: #{Enum.join(colors, ", ")}
    - materials: Materjalide loend EESTI KEELES. Vali ainult nendest: #{Enum.join(materials, ", ")}
    - description: EESTI KEELES lühike kirjeldus (1-2 lauset): mis ese on ja seisukorra kohta. Maini defekte, plekke või muid puudusi kui on.
    - quality: Seisukord. Vali TÄPSELT üks nendest: #{Enum.join(conditions, ", ")}
    - suggested_category: Kategooria EESTI KEELES. Vali TÄPSELT üks nendest: #{Enum.join(kids_categories, ", ")}

    Tagasta JSON formaadis täpselt nende võtmetega: brand, size, colors, materials, description, quality, suggested_category.
    Kui mingit välja ei saa piltidelt määrata, kasuta null.
    Massiivide puhul (colors, materials) tagasta tühi massiiv [] kui ei saa määrata.

    OLULINE:
    - Bränd: IGNOREERI käsitsi kirjutatud teksti! Kasuta AINULT trükitud brändisildilt. Kui käsitsi kirjutatud VÕI ei ole loendis → "Muu"
    - Suurus: vali kõige lähedasem loendist (nt kui sildil on "80cm", vali "74/80")
    - Värvid ja materjalid AINULT eestikeelsed valikud ülaltoodud loendist
    - Kirjeldus: lihtsalt mis ese on + seisukord/defektid (ei pea välja nägema kirjeldama)
    - Kvaliteet ja kategooria TÄPSELT loendist, mitte sinu enda sõnadega
    """

    # Build content array with all images followed by the prompt
    image_contents =
      Enum.map(encoded_images, fn base64_image ->
        ContentPart.image!(base64_image, media: "image/jpeg")
      end)

    content = image_contents ++ [ContentPart.text!(prompt)]

    message = LangChain.Message.new_user!(content)

    model = Application.get_env(:kirbs, :ai_model, "claude-haiku-4-5")

    case LangChain.Chains.LLMChain.new!(%{
           llm:
             LangChain.ChatModels.ChatAnthropic.new!(%{
               model: model,
               temperature: 0,
               stream: false
             })
         })
         |> LangChain.Chains.LLMChain.add_message(message)
         |> LangChain.Chains.LLMChain.run() do
      {:ok, updated_chain} ->
        # Extract text from ContentParts
        text_content =
          updated_chain.last_message.content
          |> Enum.find(&(&1.type == :text))
          |> case do
            %{content: text} -> text
            _ -> ""
          end

        {:ok, text_content}

      {:error, reason} ->
        {:error, "AI extraction failed: #{inspect(reason)}"}
    end
  end

  defp parse_response(response_text) do
    # Try to extract JSON from the response
    case Jason.decode(response_text) do
      {:ok, data} ->
        parse_extracted_data(data)

      {:error, _} ->
        # Try to find JSON in the text
        case Regex.run(~r/\{.*\}/s, response_text) do
          [json_str] ->
            case Jason.decode(json_str) do
              {:ok, data} -> parse_extracted_data(data)
              _ -> {:error, "Could not parse AI response"}
            end

          _ ->
            {:error, "Could not find JSON in AI response"}
        end
    end
  end

  defp parse_extracted_data(data) do
    {:ok,
     %{
       brand: data["brand"],
       size: data["size"],
       colors: data["colors"] || [],
       materials: data["materials"] || [],
       description: data["description"],
       quality: data["quality"],
       suggested_category: data["suggested_category"]
     }}
  end

  defp validate_extracted_data(extracted) do
    valid_sizes = YagaTaxonomy.all_sizes() |> Enum.map(& &1.name)

    validated = %{
      brand: validate_brand(extracted.brand),
      size: validate_size(extracted.size, valid_sizes),
      colors: validate_colors(extracted.colors),
      materials: validate_materials(extracted.materials),
      description: extracted.description,
      quality: validate_quality(extracted.quality),
      suggested_category: validate_category(extracted.suggested_category)
    }

    {:ok, validated}
  end

  defp validate_brand(nil), do: nil

  defp validate_brand(brand) do
    if YagaTaxonomy.brand_to_id(brand), do: brand, else: nil
  end

  defp validate_size(nil, _), do: nil

  defp validate_size(size, valid_sizes) do
    if size in valid_sizes, do: size, else: nil
  end

  defp validate_colors(nil), do: []

  defp validate_colors(colors) when is_list(colors) do
    colors
    |> Enum.filter(fn color -> YagaTaxonomy.color_to_id(color) != nil end)
  end

  defp validate_materials(nil), do: []

  defp validate_materials(materials) when is_list(materials) do
    materials
    |> Enum.filter(fn material -> YagaTaxonomy.material_to_id(material) != nil end)
  end

  defp validate_quality(nil), do: nil

  defp validate_quality(quality) do
    if YagaTaxonomy.condition_to_id(quality), do: quality, else: nil
  end

  defp validate_category(nil), do: nil

  defp validate_category(category) do
    if YagaTaxonomy.category_to_id(category), do: category, else: nil
  end

  defp update_item(item, extracted) do
    Ash.update(item, extracted)
  end
end
