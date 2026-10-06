defmodule KirbsWeb.Plugs.CaptureUtm do
  @moduledoc """
  Persists ad attribution (utm_source, utm_medium, utm_campaign, ad id) from the landing
  request into the session, so LiveViews can attach it to every tracked event.

  The latest request carrying UTM params wins; requests without them leave the stored
  attribution untouched.
  """
  import Plug.Conn

  @session_key "kirbs_utm"
  @params ~w(utm_source utm_medium utm_campaign utm_content utm_term ad_id fbclid)
  @max_length 100

  def session_key, do: @session_key

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_query_params(conn)

    case extract(conn.query_params) do
      utm when map_size(utm) == 0 -> conn
      utm -> put_session(conn, @session_key, utm)
    end
  end

  @doc "Pull the whitelisted, scrubbed attribution params out of a params map."
  def extract(params) when is_map(params) do
    for key <- @params,
        value = params[key],
        is_binary(value),
        value = scrub(value),
        value != "",
        into: %{} do
      {key, value}
    end
  end

  defp scrub(value) do
    value
    |> String.trim()
    |> String.replace(~r/[^\p{L}\p{N}._:\- |+]/u, "")
    |> String.slice(0, @max_length)
  end
end
