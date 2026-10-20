defmodule Kirbs.Test.StubCategorizeLlm do
  @moduledoc """
  Stands in for the OpenRouter call. Tests set the response with
  `Kirbs.Test.StubCategorizeLlm.respond_with/1` (a map, JSON string, `{:error, _}` or a
  `fn images, prompt, schema -> result end`).
  """

  def respond_with(response), do: Application.put_env(:kirbs, :stub_categorize_response, response)
  def reset, do: Application.delete_env(:kirbs, :stub_categorize_response)

  def run(images, prompt, schema) do
    case Application.get_env(:kirbs, :stub_categorize_response) do
      fun when is_function(fun, 3) -> fun.(images, prompt, schema)
      {:error, _} = error -> error
      text when is_binary(text) -> {:ok, text}
      %{} = map -> {:ok, Jason.encode!(map)}
      nil -> raise "StubCategorizeLlm: no response configured"
    end
  end
end
