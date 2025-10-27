defmodule KirbsWeb.LandingLive.Index do
  use KirbsWeb, :live_view

  on_mount {KirbsWeb.LiveUserAuth, :live_user_optional}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Käed Vabad Kirbukas - Lapse riideid müüa ilma vaevata")}
  end
end
