defmodule Kirbs.Services.Ai.OpenrouterChat do
  @moduledoc """
  Sends one chat completion to OpenRouter and returns the assistant's text.

  Options:
    * `:images` - base64-encoded JPEGs, sent before the prompt
    * `:system` - system prompt
    * `:json_schema` - strict JSON schema the answer must follow
    * `:web_search` - `true` to let the model search the web (OpenRouter server tool)
    * `:model` - defaults to `config :kirbs, :openrouter_model`
  """

  @endpoint "https://openrouter.ai/api/v1/chat/completions"
  @receive_timeout 180_000

  def run(prompt, opts \\ []) do
    with {:ok, body} <- build_body(prompt, opts),
         {:ok, response} <- post(body),
         {:ok, text} <- extract_text(response) do
      {:ok, text}
    end
  end

  defp build_body(prompt, opts) do
    body =
      %{
        "model" => Keyword.get(opts, :model, Application.fetch_env!(:kirbs, :openrouter_model)),
        "temperature" => 0,
        "messages" => system_messages(opts[:system]) ++ [user_message(prompt, opts[:images])]
      }
      |> put_json_schema(opts[:json_schema])
      |> put_web_search(opts[:web_search])

    {:ok, body}
  end

  defp system_messages(nil), do: []
  defp system_messages(system), do: [%{"role" => "system", "content" => system}]

  defp user_message(prompt, images) do
    image_parts =
      Enum.map(images || [], fn base64 ->
        %{"type" => "image_url", "image_url" => %{"url" => "data:image/jpeg;base64," <> base64}}
      end)

    %{"role" => "user", "content" => image_parts ++ [%{"type" => "text", "text" => prompt}]}
  end

  defp put_json_schema(body, nil), do: body

  defp put_json_schema(body, schema) do
    Map.put(body, "response_format", %{
      "type" => "json_schema",
      "json_schema" => %{"name" => "structured_output", "strict" => true, "schema" => schema}
    })
  end

  defp put_web_search(body, true),
    do: Map.put(body, "tools", [%{"type" => "openrouter:web_search"}])

  defp put_web_search(body, _), do: body

  defp post(body) do
    options =
      Keyword.merge(
        [
          url: @endpoint,
          json: body,
          auth: {:bearer, Application.fetch_env!(:kirbs, :openrouter_api_key)},
          receive_timeout: @receive_timeout,
          retry: false
        ],
        Application.get_env(:kirbs, :openrouter_req_options, [])
      )

    case Req.post(options) do
      {:ok, %Req.Response{status: 200, body: response}} ->
        {:ok, response}

      {:ok, %Req.Response{status: 429} = response} ->
        {:error, {:rate_limited, retry_after(response)}}

      {:ok, %Req.Response{status: status, body: response}} ->
        {:error, "OpenRouter returned #{status}: #{inspect(response)}"}

      {:error, exception} ->
        {:error, "OpenRouter request failed: #{Exception.message(exception)}"}
    end
  end

  defp retry_after(response) do
    with [value | _] <- Req.Response.get_header(response, "retry-after"),
         {seconds, _} <- Integer.parse(value) do
      seconds
    else
      _ -> 60
    end
  end

  # OpenRouter can answer 200 with an error body (e.g. upstream provider failure or throttling).
  defp extract_text(%{"error" => %{"code" => 429}}), do: {:error, {:rate_limited, 60}}
  defp extract_text(%{"error" => error}), do: {:error, "OpenRouter error: #{inspect(error)}"}

  # A choice can carry an error alongside partial content; treat it as a failure, not an answer.
  defp extract_text(%{"choices" => [%{"error" => %{"code" => 429}} | _]}),
    do: {:error, {:rate_limited, 60}}

  defp extract_text(%{"choices" => [%{"error" => error} | _]}),
    do: {:error, "OpenRouter error: #{inspect(error)}"}

  defp extract_text(%{"choices" => [%{"finish_reason" => reason} | _]})
       when reason in ["length", "error", "content_filter"],
       do: {:error, "OpenRouter completion incomplete: #{reason}"}

  defp extract_text(%{"choices" => [%{"message" => %{"content" => text}} | _]})
       when is_binary(text) and text != "",
       do: {:ok, text}

  defp extract_text(response),
    do: {:error, "OpenRouter returned no text: #{inspect(response, limit: 50)}"}
end
