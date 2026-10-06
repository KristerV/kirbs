defmodule KirbsWeb.ShopLive.CheckoutPlaceholder do
  @moduledoc "Placeholder for `/checkout/:slug` until the real checkout (Phase 4) replaces it."
  use KirbsWeb, :live_view

  alias Kirbs.Resources.Item

  def mount(%{"slug" => slug}, _session, socket) do
    case Item.get_published_by_slug(slug, not_found_error?: false) do
      {:ok, %Item{} = item} ->
        {:ok,
         socket
         |> assign(:item, item)
         |> assign(:page_title, "Broneeri | Kirbs")
         |> assign(:meta, %{robots: "noindex,nofollow"})}

      _ ->
        {:ok, socket |> put_flash(:error, "Seda toodet ei leitud") |> push_navigate(to: ~p"/")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div id="checkout-placeholder" class="mx-auto max-w-lg py-16 text-center">
        <.icon name="hero-clock" class="mx-auto size-12 text-orange-400" />
        <h1 class="mt-4 text-3xl font-black text-stone-900">Broneerimine tuleb varsti</h1>
        <p class="mt-2 text-stone-500">
          Ostukorv ja broneerimine pole veel avatud. Tule varsti tagasi!
        </p>
        <.link
          id="back-to-item"
          navigate={~p"/p/#{@item.slug}"}
          class="mt-6 inline-block rounded-full bg-orange-500 px-6 py-2.5 font-bold text-white transition hover:bg-orange-600"
        >
          Tagasi toote juurde
        </.link>
      </div>
    </Layouts.app>
    """
  end
end
