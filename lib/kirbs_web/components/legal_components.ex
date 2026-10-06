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
    <%!-- TODO(owner): fill in registry code, VAT number, address and email (config :kirbs, :company). --%>
    <address id="company-details" class="not-italic text-xs leading-relaxed text-stone-500">
      <strong class="text-stone-600">{@company.name}</strong>
      <br /> Registrikood: {@company.registry_code}
      <br /> KMKR: {@company.vat_number}
      <br /> Aadress: {@company.address}
      <br /> E-post: {@company.email}
    </address>
    """
  end
end
