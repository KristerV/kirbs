defmodule KirbsWeb.LandingLive.Index do
  use KirbsWeb, :live_view

  on_mount {KirbsWeb.LiveUserAuth, :live_user_optional}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Käed Vabad Kirbukas - Lapse riideid müüa ilma vaevata")
     |> assign(:show_modal, nil)}
  end

  def handle_event("show_modal", %{"type" => type}, socket) do
    {:noreply, assign(socket, :show_modal, type)}
  end

  def handle_event("close_modal", _, socket) do
    {:noreply, assign(socket, :show_modal, nil)}
  end
end
