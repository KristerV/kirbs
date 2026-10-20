defmodule KirbsWeb.Track do
  @moduledoc """
  Single entry point for funnel events. Wraps `AbFunnel.track/3`, merging UTM attribution
  into the metadata and pushing the matching Meta pixel event to the browser when a pixel
  is configured.

  See docs/tracking.md for which event to fire from where.

      socket = KirbsWeb.Track.event(socket, :item_viewed, %{item_id: item.id})
  """

  # funnel event => {ab_funnel event name, Meta pixel standard event}
  @events %{
    shop_viewed: {"shop_viewed", "PageView"},
    item_viewed: {"item_viewed", "ViewContent"},
    reserved: {"reserved", "AddToCart"},
    checkout_started: {"checkout_started", "InitiateCheckout"},
    paid: {"paid", "Purchase"}
  }

  def events, do: Map.keys(@events)

  @doc """
  Track `name` (an atom from `events/0`) for the socket's visitor and push the Meta pixel
  event when a pixel id is configured. Returns the socket. Pass `pixel: false` to skip the
  pixel push (e.g. `:shop_viewed`, since the MetaPixel hook already sends PageView on mount).
  """
  def event(socket, name, metadata \\ %{}, opts \\ []) when is_atom(name) do
    {ab_name, meta_name} = Map.fetch!(@events, name)
    utm = Map.get(socket.assigns, :utm, %{})

    AbFunnel.track(socket, ab_name, Map.merge(utm, stringify(metadata)))

    if Keyword.get(opts, :pixel, true), do: push_meta(socket, meta_name, metadata), else: socket
  end

  @doc "Same as `event/3` for a Plug.Conn (controllers/plugs); no pixel push."
  def conn_event(conn, name, metadata \\ %{}) when is_atom(name) do
    {ab_name, _} = Map.fetch!(@events, name)
    utm = Plug.Conn.get_session(conn, KirbsWeb.Plugs.CaptureUtm.session_key()) || %{}
    AbFunnel.track(conn, ab_name, Map.merge(utm, stringify(metadata)))
    conn
  end

  @doc "Configured Meta pixel id, or nil when disabled (the default)."
  def meta_pixel_id do
    config = Application.get_env(:kirbs, :meta_pixel, [])

    if Keyword.get(config, :enabled, false), do: Keyword.get(config, :pixel_id)
  end

  defp push_meta(socket, meta_name, metadata) do
    if socket.assigns[:meta_pixel_id] && Phoenix.LiveView.connected?(socket) do
      Phoenix.LiveView.push_event(socket, "meta_pixel", %{
        event: meta_name,
        data: pixel_data(metadata)
      })
    else
      socket
    end
  end

  defp pixel_data(metadata) do
    metadata |> Map.take([:value, :currency, :content_ids, :content_name]) |> stringify()
  end

  defp stringify(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)
end
