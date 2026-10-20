defmodule Kirbs.Services.Ai.ItemCategorizeLlm do
  @moduledoc """
  Sends item photos + prompt to the OpenRouter vision model, constrained to a JSON schema.
  Returns the raw JSON text. Swapped for a stub in tests via `:item_categorize_llm` config.
  """

  alias Kirbs.Services.Ai.OpenrouterModel
  alias LangChain.Chains.LLMChain
  alias LangChain.Message
  alias LangChain.Message.ContentPart

  def run(base64_images, prompt, schema) do
    content =
      Enum.map(base64_images, &ContentPart.image!(&1, media: :jpeg)) ++
        [ContentPart.text!(prompt)]

    with {:ok, llm} <- OpenrouterModel.run(json_schema: schema) do
      case LLMChain.new!(%{llm: llm})
           |> LLMChain.add_message(Message.new_user!(content))
           |> LLMChain.run() do
        {:ok, chain} ->
          text =
            chain.last_message.content
            |> Enum.filter(&(&1.type == :text))
            |> Enum.map_join("\n", & &1.content)

          {:ok, text}

        {:error, _chain, %LangChain.LangChainError{original: %Req.Response{status: 429}}} ->
          {:error, {:rate_limited, 60}}

        {:error, _chain, %LangChain.LangChainError{message: message}} ->
          {:error, "Categorization failed: #{message}"}

        {:error, reason} ->
          {:error, "Categorization failed: #{inspect(reason)}"}
      end
    end
  end
end
