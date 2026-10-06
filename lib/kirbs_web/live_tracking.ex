defmodule KirbsWeb.LiveTracking do
  @moduledoc """
  on_mount hook that lifts the captured UTM attribution from the session into
  `socket.assigns.utm` and the Meta pixel config into `socket.assigns.meta_pixel_id`.

  List it after `AbFunnel.LiveView` in `live_session on_mount`.
  """
  import Phoenix.Component, only: [assign: 3]

  def on_mount(:default, _params, session, socket) do
    {:cont,
     socket
     |> assign(:utm, session[KirbsWeb.Plugs.CaptureUtm.session_key()] || %{})
     |> assign(:meta_pixel_id, KirbsWeb.Track.meta_pixel_id())}
  end
end
