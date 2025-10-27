defmodule Kirbs.Services.Ai.ItemInfoExtract do
  @moduledoc """
  Extracts item information from label photos.
  Uses Claude vision to identify: brand, size, colors, materials, description, quality, suggested_category.
  """

  alias Kirbs.Resources.Item

  def run(item_id) do
    with {:ok, item} <- load_item(item_id),
         {:ok, label_images} <- get_label_photos(item),
         {:ok, _} <- validate_has_images(label_images),
         {:ok, extracted} <- extract_with_ai(label_images),
         {:ok, updated_item} <- update_item(item, extracted) do
      {:ok, updated_item}
    end
  end

  defp load_item(item_id) do
    case Ash.get(Item, item_id, load: [:images]) do
      {:ok, item} -> {:ok, item}
      {:error, _} -> {:error, "Item not found"}
    end
  end

  defp get_label_photos(%{images: images}) do
    label_images = Enum.filter(images, & &1.is_label)
    {:ok, label_images}
  end

  defp validate_has_images([]), do: {:error, "No label photos found for item"}
  defp validate_has_images(_), do: {:ok, :valid}

  defp extract_with_ai(label_images) do
    with {:ok, encoded_images} <- encode_images(label_images),
         {:ok, result} <- call_claude(encoded_images) do
      parse_response(result)
    end
  end

  defp encode_images(label_images) do
    upload_dir = Application.get_env(:kirbs, :image_upload_dir, "/tmp/kirbs_uploads")

    encoded =
      Enum.map(label_images, fn image ->
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
    prompt = """
    Please analyze these photos of a kids' clothing item label/tags and extract the following information:

    - brand: The brand name (e.g., "H&M", "Zara", "Carter's")
    - size: The size indicated (e.g., "6-9 kuud", "110", "3T", "80cm")
    - colors: Array of color names visible in the item (e.g., ["red", "blue", "white"])
    - materials: Array of materials/fabric composition (e.g., ["cotton", "polyester", "spandex"])
    - description: A brief description of the item type and appearance (e.g., "Blue striped long-sleeve shirt with buttons")
    - quality: The condition of the item (e.g., "like new", "gently used", "good condition", "worn")
    - suggested_category: The category this item belongs to in Estonian (e.g., "Pluus", "Püksid", "Kleit", "Body")

    Return the information in JSON format with these exact keys: brand, size, colors, materials, description, quality, suggested_category.
    If any field cannot be determined from the images, use null for that field.
    For arrays (colors, materials), return an empty array [] if nothing can be determined.
    """

    # Build content array with all images followed by the prompt
    image_contents =
      Enum.map(encoded_images, fn base64_image ->
        %{
          type: :image,
          source: %{
            type: :base64,
            media_type: "image/jpeg",
            data: base64_image
          }
        }
      end)

    content = image_contents ++ [%{type: :text, text: prompt}]

    message = %{
      role: :user,
      content: content
    }

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
      {:ok, _updated_chain, response} ->
        {:ok, response.content}

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

  defp update_item(item, extracted) do
    Ash.update(item, extracted)
  end
end
