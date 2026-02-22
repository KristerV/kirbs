defmodule Kirbs.Services.Ai.BagClientExtract do
  @moduledoc """
  Extracts client information from the third bag photo (handwritten info).
  Uses Gemini vision to read: name, phone, email, IBAN.
  """

  alias Kirbs.Resources.Bag

  def run(bag_id) do
    with {:ok, bag} <- load_bag(bag_id),
         {:ok, info_image} <- get_info_photo(bag),
         {:ok, image_path} <- get_full_image_path(info_image),
         {:ok, extracted} <- extract_with_ai(image_path) do
      {:ok, extracted}
    end
  end

  defp load_bag(bag_id) do
    case Ash.get(Bag, bag_id, load: [:images]) do
      {:ok, bag} -> {:ok, bag}
      {:error, _} -> {:error, :not_found}
    end
  end

  defp get_info_photo(%{images: images}) do
    # Third photo (order=2) is the client info photo
    case Enum.find(images, &(&1.order == 2)) do
      nil -> {:error, "Client info photo not found"}
      image -> {:ok, image}
    end
  end

  defp get_full_image_path(%{path: path}) do
    upload_dir = Application.get_env(:kirbs, :image_upload_dir, "/tmp/kirbs_uploads")
    full_path = Path.join(upload_dir, path)

    if File.exists?(full_path) do
      {:ok, full_path}
    else
      {:error, "Image file not found at #{full_path}"}
    end
  end

  defp extract_with_ai(image_path) do
    with {:ok, image_data} <- File.read(image_path),
         {:ok, base64_image} <- encode_image(image_data),
         {:ok, result} <- call_gemini(base64_image) do
      parse_response(result)
    end
  end

  defp encode_image(image_data) do
    {:ok, Base.encode64(image_data)}
  end

  defp call_gemini(base64_image) do
    alias LangChain.Message.ContentPart

    prompt = """
    Please extract the following information from this handwritten note:
    - Name (full name of the client)
    - Phone (phone number)
    - Email (email address, if present)
    - IBAN (bank account number)

    Return the information in JSON format with these exact keys: name, phone, email, iban.
    If any field is not present or unclear, use null for that field.
    """

    message =
      LangChain.Message.new_user!([
        ContentPart.image!(base64_image, media: :jpeg),
        ContentPart.text!(prompt)
      ])

    model = Application.get_env(:kirbs, :ai_model, "gemini-2.5-flash")

    case LangChain.Chains.LLMChain.new!(%{
           llm:
             LangChain.ChatModels.ChatGoogleAI.new!(%{
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

      {:error, _chain, %LangChain.LangChainError{} = error} ->
        {:error, format_ai_error(error)}

      {:error, reason} ->
        {:error, "AI extraction failed: #{inspect(reason)}"}
    end
  end

  defp parse_response(response_text) do
    with [json_str] <- Regex.run(~r/\{.*\}/s, response_text),
         {:ok, %{"name" => name} = data} <- Jason.decode(json_str) do
      {:ok, %{name: name, phone: data["phone"], email: data["email"], iban: data["iban"]}}
    else
      _ ->
        {:cancel,
         "Could not extract client info from photo. AI response: #{String.slice(response_text, 0..500)}"}
    end
  end

  defp format_ai_error(%LangChain.LangChainError{
         original: %{"promptFeedback" => %{"blockReason" => reason}}
       }) do
    "AI extraction blocked by Gemini safety filter: #{reason}"
  end

  defp format_ai_error(%LangChain.LangChainError{message: message, original: original}) do
    "AI extraction failed: #{message}. Original: #{inspect(original)}"
  end
end
