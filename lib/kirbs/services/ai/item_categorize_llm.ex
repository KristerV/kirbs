defmodule Kirbs.Services.Ai.ItemCategorizeLlm do
  @moduledoc """
  Sends item photos + prompt to the OpenRouter vision model, constrained to a JSON schema.
  Returns the raw JSON text. Swapped for a stub in tests via `:item_categorize_llm` config.
  """

  alias Kirbs.Services.Ai.OpenrouterChat

  def run(base64_images, prompt, schema) do
    case OpenrouterChat.run(prompt, images: base64_images, json_schema: schema) do
      {:ok, text} -> {:ok, text}
      {:error, {:rate_limited, _}} = error -> error
      {:error, reason} -> {:error, "Categorization failed: #{reason}"}
    end
  end
end
