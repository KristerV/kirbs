defmodule Kirbs.Services.Ai.OpenrouterModel do
  @moduledoc """
  Builds the LangChain chat model that talks to OpenRouter.
  """

  @endpoint "https://openrouter.ai/api/v1/chat/completions"

  def run(opts \\ []) do
    model = Keyword.get(opts, :model, Application.fetch_env!(:kirbs, :openrouter_model))

    schema = opts |> Keyword.get(:json_schema) |> wrap_schema()

    {:ok,
     LangChain.ChatModels.ChatOpenAI.new!(%{
       endpoint: @endpoint,
       api_key: Application.fetch_env!(:kirbs, :openrouter_api_key),
       model: model,
       temperature: 0,
       stream: false,
       receive_timeout: 120_000,
       json_response: not is_nil(schema),
       json_schema: schema
     })}
  end

  defp wrap_schema(nil), do: nil

  defp wrap_schema(schema),
    do: %{"name" => "structured_output", "strict" => true, "schema" => schema}
end
