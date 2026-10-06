defmodule KirbsWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use KirbsWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders the public storefront layout (header, footer, flash group).

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div id="shop-shell" class="min-h-screen bg-[#fffaf4] text-stone-800 antialiased">
      <header class="sticky top-0 z-30 border-b border-orange-100 bg-[#fffaf4]/90 backdrop-blur">
        <div class="mx-auto flex max-w-7xl items-center justify-between gap-4 px-4 py-3 sm:px-6 lg:px-8">
          <.link
            navigate={~p"/"}
            id="shop-logo"
            class="group flex items-baseline gap-2 font-[ui-rounded,'Nunito',system-ui,sans-serif]"
          >
            <span class="text-2xl font-black tracking-tight text-orange-500 transition-transform group-hover:-rotate-2">
              Kirbs
            </span>
            <span class="hidden text-xs font-medium uppercase tracking-[0.18em] text-stone-400 sm:inline">
              lastekaup
            </span>
          </.link>
          <nav class="flex items-center gap-1 text-sm font-semibold text-stone-600">
            <.link
              navigate={~p"/"}
              id="nav-shop"
              class="rounded-full px-3 py-1.5 transition-colors hover:bg-orange-100 hover:text-orange-600"
            >
              Pood
            </.link>
            <.link
              navigate={~p"/muuda"}
              id="nav-sell"
              class="rounded-full bg-orange-500 px-4 py-1.5 text-white shadow-sm shadow-orange-500/30 transition hover:bg-orange-600"
            >
              Müü meiega
            </.link>
          </nav>
        </div>
      </header>

      <main class="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
        {render_slot(@inner_block)}
      </main>

      <footer class="mt-16 border-t border-orange-100 bg-orange-50/60">
        <div class="mx-auto flex max-w-7xl flex-col gap-3 px-4 py-8 text-sm text-stone-500 sm:flex-row sm:items-center sm:justify-between sm:px-6 lg:px-8">
          <p>
            <span class="font-bold text-orange-500">Kirbs</span>
            &middot; kvaliteetsed kasutatud lasteriided uue elu ootel
          </p>
          <div class="flex gap-4">
            <.link navigate={~p"/muuda"} class="transition-colors hover:text-orange-600">
              Müü oma riided
            </.link>
            <.link navigate={~p"/uudised"} class="transition-colors hover:text-orange-600">
              Uudised
            </.link>
          </div>
        </div>
      </footer>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
