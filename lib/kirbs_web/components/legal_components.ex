defmodule KirbsWeb.LegalComponents do
  @moduledoc "Shared layout for the legal pages (terms, returns, privacy) and the company details block."
  use KirbsWeb, :html

  alias KirbsWeb.Company

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :flash, :map, required: true
  slot :inner_block, required: true

  @doc "Wraps a legal page in the storefront layout with a readable text column and cross links."
  def legal_page(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <article id={@id} class="mx-auto max-w-3xl">
        <h1 class="text-3xl font-black tracking-tight text-stone-900">{@title}</h1>
        <%!-- TODO(owner/lawyer): add the "in force from" date once the wording is signed off. --%>
        <div class="mt-6 space-y-4 leading-relaxed text-stone-700 [&_h2]:mt-8 [&_h2]:text-xl [&_h2]:font-bold [&_h2]:text-stone-900 [&_ul]:list-disc [&_ul]:space-y-1 [&_ul]:pl-6 [&_a]:text-orange-600 [&_a:hover]:underline">
          {render_slot(@inner_block)}
        </div>
        <nav id="legal-nav" class="mt-10 flex flex-wrap gap-4 border-t border-orange-100 pt-4 text-sm">
          <.link navigate={~p"/tingimused"} class="text-orange-600 hover:underline">
            Müügitingimused
          </.link>
          <.link navigate={~p"/tagastus"} class="text-orange-600 hover:underline">
            Tagastus ja taganemisõigus
          </.link>
          <.link navigate={~p"/privaatsus"} class="text-orange-600 hover:underline">
            Privaatsuspoliitika
          </.link>
        </nav>
      </article>
    </Layouts.app>
    """
  end

  @doc "Seller identification block (footer and legal pages)."
  def company_details(assigns) do
    assigns = assign(assigns, :company, Company.details())

    ~H"""
    <address
      id="company-details"
      class="flex flex-col gap-3 text-sm not-italic text-stone-500 sm:flex-row sm:items-end sm:justify-between"
    >
      <div class="flex flex-col gap-1.5">
        <span class="flex items-center gap-2">
          <.icon name="hero-map-pin" class="size-4 shrink-0 text-orange-400" />
          <span>Kontor ja ladu: {@company.office_address}</span>
        </span>
        <a
          id="company-email"
          href={"mailto:#{@company.email}"}
          class="flex items-center gap-2 transition-colors hover:text-orange-600"
        >
          <.icon name="hero-envelope" class="size-4 shrink-0 text-orange-400" />
          {@company.email}
        </a>
      </div>
      <p class="text-xs leading-relaxed text-stone-400 sm:max-w-sm sm:text-right">
        {@company.name} · reg. kood {@company.registry_code}<br />
        {@company.address}
      </p>
    </address>
    """
  end
end
