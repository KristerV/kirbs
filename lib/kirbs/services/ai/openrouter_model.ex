defmodule Kirbs.Services.Ai.OpenrouterModel do
  @moduledoc """
  Builds the LangChain chat model that talks to OpenRouter.
  """

  @endpoint "https://openrouter.ai/api/v1/chat/completions"

  def run(opts \\ []) do
    model = Keyword.get(opts, :model, Application.fetch_env!(:kirbs, :openrouter_model))

    {:ok,
     LangChain.ChatModels.ChatOpenAI.new!(%{
       endpoint: @endpoint,
       api_key: Application.fetch_env!(:kirbs, :openrouter_api_key),
       model: model,
       temperature: 0,
       stream: false,
       receive_timeout: 120_000
     })}
  end
end
