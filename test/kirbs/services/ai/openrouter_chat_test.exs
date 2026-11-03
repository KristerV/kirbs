defmodule Kirbs.Services.Ai.OpenrouterChatTest do
  use ExUnit.Case, async: true

  alias Kirbs.Services.Ai.OpenrouterChat

  defp respond(conn, status, body) do
    conn |> Plug.Conn.put_status(status) |> Req.Test.json(body)
  end

  defp completion(text), do: %{"choices" => [%{"message" => %{"content" => text}}]}

  test "sends images, system prompt, schema and web search tool; returns the text" do
    schema = %{"type" => "object"}

    Req.Test.stub(OpenrouterChat, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      body = Jason.decode!(raw)
      send(self(), {:request, conn, body})
      respond(conn, 200, completion(~s({"ok":true})))
    end)

    assert {:ok, ~s({"ok":true})} =
             OpenrouterChat.run("describe",
               images: ["AAAA"],
               system: "be brief",
               json_schema: schema,
               web_search: true
             )

    assert_received {:request, conn, body}
    assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer test-key"]

    assert [
             %{"role" => "system", "content" => "be brief"},
             %{"role" => "user", "content" => [image, text]}
           ] = body["messages"]

    assert image == %{
             "type" => "image_url",
             "image_url" => %{"url" => "data:image/jpeg;base64,AAAA"}
           }

    assert text == %{"type" => "text", "text" => "describe"}
    assert body["response_format"]["json_schema"]["schema"] == schema
    assert body["response_format"]["json_schema"]["strict"] == true
    assert body["tools"] == [%{"type" => "openrouter:web_search"}]
  end

  test "omits schema, tools and system message when not asked for" do
    Req.Test.stub(OpenrouterChat, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(self(), {:body, Jason.decode!(raw)})
      respond(conn, 200, completion("hi"))
    end)

    assert {:ok, "hi"} = OpenrouterChat.run("hello")
    assert_received {:body, body}
    refute Map.has_key?(body, "response_format")
    refute Map.has_key?(body, "tools")
    assert [%{"role" => "user"}] = body["messages"]
  end

  test "429 becomes rate_limited with the retry-after delay" do
    Req.Test.stub(OpenrouterChat, fn conn ->
      conn |> Plug.Conn.put_resp_header("retry-after", "17") |> respond(429, %{})
    end)

    assert {:error, {:rate_limited, 17}} = OpenrouterChat.run("hello")
  end

  test "error body and empty content are errors" do
    Req.Test.stub(OpenrouterChat, &respond(&1, 200, %{"error" => %{"message" => "boom"}}))
    assert {:error, "OpenRouter error: " <> _} = OpenrouterChat.run("hello")

    Req.Test.stub(OpenrouterChat, &respond(&1, 200, completion(nil)))
    assert {:error, "OpenRouter returned no text: " <> _} = OpenrouterChat.run("hello")

    Req.Test.stub(OpenrouterChat, &respond(&1, 500, %{"x" => 1}))
    assert {:error, "OpenRouter returned 500: " <> _} = OpenrouterChat.run("hello")
  end

  test "throttling reported inside a 200 body becomes rate_limited" do
    Req.Test.stub(OpenrouterChat, &respond(&1, 200, %{"error" => %{"code" => 429}}))
    assert {:error, {:rate_limited, 60}} = OpenrouterChat.run("hello")

    Req.Test.stub(
      OpenrouterChat,
      &respond(&1, 200, %{
        "choices" => [%{"error" => %{"code" => 429}, "message" => %{"content" => "{"}}]
      })
    )

    assert {:error, {:rate_limited, 60}} = OpenrouterChat.run("hello")
  end

  test "partial content with a choice error or truncation is not returned as an answer" do
    Req.Test.stub(
      OpenrouterChat,
      &respond(&1, 200, %{
        "choices" => [%{"error" => %{"code" => 502}, "message" => %{"content" => ~s({"brand")}}]
      })
    )

    assert {:error, "OpenRouter error: " <> _} = OpenrouterChat.run("hello")

    Req.Test.stub(
      OpenrouterChat,
      &respond(&1, 200, %{
        "choices" => [%{"finish_reason" => "length", "message" => %{"content" => ~s({"brand")}}]
      })
    )

    assert {:error, "OpenRouter completion incomplete: length"} = OpenrouterChat.run("hello")
  end
end
