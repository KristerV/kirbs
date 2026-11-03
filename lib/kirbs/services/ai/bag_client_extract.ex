defmodule Kirbs.Services.Ai.BagClientExtract do
  @moduledoc """
  Extracts client information from the third bag photo (handwritten info).
  Uses the OpenRouter vision model to read: name, phone, email, IBAN.
  """

  alias Kirbs.Resources.Bag
  alias Kirbs.Services.Ai.OpenrouterChat

  @nullable_string %{"type" => ["string", "null"]}
  @schema %{
    "type" => "object",
    "additionalProperties" => false,
    "required" => ~w(name phone email iban),
    "properties" => %{
      "name" => @nullable_string,
      "phone" => @nullable_string,
      "email" => @nullable_string,
      "iban" => @nullable_string
    }
  }

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
         {:ok, result} <- call_llm(Base.encode64(image_data)) do
      parse_response(result)
    end
  end

  defp call_llm(base64_image) do
    prompt = """
    Please extract the following information from this handwritten note:
    - Name (full name of the client)
    - Phone (phone number)
    - Email (email address, if present)
    - IBAN (bank account number)

    If any field is not present or unclear, use null for that field.
    """

    OpenrouterChat.run(prompt, images: [base64_image], json_schema: @schema)
  end

  defp parse_response(response_text) do
    case Jason.decode(response_text) do
      {:ok, %{"name" => name} = data} ->
        {:ok, %{name: name, phone: data["phone"], email: data["email"], iban: data["iban"]}}

      _ ->
        {:cancel,
         "Could not extract client info from photo. AI response: #{String.slice(response_text, 0..500)}"}
    end
  end
end
