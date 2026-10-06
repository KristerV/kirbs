defmodule KirbsWeb.ShopLive.Order do
  @moduledoc """
  Order confirmation / status page `/order/:token`. The unguessable token is the only
  credential, so the page is `noindex` and shows what the buyer already knows.
  """
  use KirbsWeb, :live_view

  alias Kirbs.Orders.BankDetails
  alias Kirbs.Resources.Order
  alias Kirbs.Shipping.Rates
  alias KirbsWeb.Shop.Labels

  def mount(%{"token" => token}, _session, socket) do
    case Order.get_by_token(token, not_found_error?: false) do
      {:ok, %Order{} = order} ->
        {:ok,
         socket
         |> assign(:order, order)
         |> assign(:bank, order.payment_method == :manual && BankDetails.get())
         |> assign(:page_title, "Tellimus #{order.reference} | Kirbs")
         |> assign(:meta, %{robots: "noindex,nofollow"})}

      _ ->
        {:ok, socket |> put_flash(:error, "Tellimust ei leitud") |> push_navigate(to: ~p"/")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} meta_pixel_id={@meta_pixel_id}>
      <div id="order-page" class="mx-auto max-w-2xl">
        <div class="text-center">
          <.icon name={status_icon(@order.status)} class="mx-auto size-12 text-orange-500" />
          <h1
            id="order-status"
            data-status={@order.status}
            class="mt-3 font-[ui-rounded,'Nunito',system-ui,sans-serif] text-3xl font-black tracking-tight text-stone-900 sm:text-4xl"
          >
            {status_title(@order.status)}
          </h1>
          <p class="mt-2 text-stone-500">
            Tellimus
            <span id="order-reference" class="font-bold text-stone-800">{@order.reference}</span>
          </p>
        </div>

        <section
          :if={@order.status == :reserved and @bank}
          id="bank-instructions"
          class="mt-8 rounded-3xl border-2 border-orange-300 bg-orange-50 p-6"
        >
          <h2 class="text-lg font-black text-stone-900">Maksa pangaülekandega</h2>
          <dl class="mt-4 space-y-2 text-sm">
            <.row label="Saaja" id="bank-recipient" value={@bank.recipient} />
            <.row label="IBAN" id="bank-iban" value={@bank.iban} />
            <.row label="Summa" id="bank-amount" value={Labels.cents(@order.total_cents)} />
            <.row label="Selgitus" id="bank-reference" value={@order.reference} />
          </dl>
          <p class="mt-4 text-sm text-stone-600">
            Hoiame esemeid sinu jaoks kuni {format_time(@order.reserved_until)}. Kui makset selleks ajaks ei laeku, broneering vabaneb.
          </p>
        </section>

        <section
          :if={@order.status == :pending}
          id="order-pending"
          class="mt-8 rounded-3xl bg-white p-6 text-center ring-1 ring-orange-100"
        >
          <p class="text-stone-600">Tellimus on pooleli.</p>
          <.link
            :if={first_item(@order)}
            navigate={~p"/checkout/#{first_item(@order).item.slug}?#{[order: @order.token]}"}
            id="resume-checkout"
            class="mt-4 inline-block rounded-full bg-orange-500 px-6 py-2.5 font-bold text-white transition hover:bg-orange-600"
          >
            Jätka vormistamist
          </.link>
        </section>

        <section
          :if={@order.status in [:shipped, :delivered] and @order.tracking_number}
          id="tracking"
          class="mt-8 rounded-3xl bg-white p-6 ring-1 ring-orange-100"
        >
          <p class="text-sm text-stone-500">Jälgimisnumber</p>
          <p class="text-lg font-black text-stone-900">{@order.tracking_number}</p>
          <a
            :if={@order.tracking_url}
            href={@order.tracking_url}
            target="_blank"
            rel="noopener"
            class="mt-1 inline-block text-sm font-semibold text-orange-600 underline underline-offset-2"
          >
            Jälgi saadetist
          </a>
        </section>

        <section class="mt-8 rounded-3xl border border-orange-100 bg-white p-6">
          <h2 class="text-lg font-black text-stone-900">Tellitud</h2>
          <ul id="order-items" class="mt-4 divide-y divide-orange-100">
            <li :for={oi <- @order.order_items} class="flex items-center gap-4 py-3">
              <div class="size-16 shrink-0 overflow-hidden rounded-xl bg-orange-100/60">
                <img
                  :if={List.first(oi.item.images)}
                  src={~p"/img/320/#{List.first(oi.item.images).id}"}
                  alt=""
                  class="size-full object-cover"
                />
              </div>
              <span class="flex-1 font-semibold text-stone-800">{oi.title}</span>
              <span class="font-black text-stone-900">{Labels.cents(oi.price_cents)}</span>
            </li>
          </ul>
          <dl class="mt-4 space-y-2 border-t border-orange-100 pt-4 text-sm">
            <div class="flex justify-between">
              <dt class="text-stone-500">Tarne</dt>
              <dd class="font-semibold">
                {if @order.shipping_cents == 0,
                  do: "Tasuta",
                  else: Labels.cents(@order.shipping_cents)}
              </dd>
            </div>
            <div class="flex justify-between text-base">
              <dt class="font-black text-stone-900">Kokku</dt>
              <dd id="order-total" class="font-black text-stone-900">
                {Labels.cents(@order.total_cents)}
              </dd>
            </div>
          </dl>
          <p :if={@order.delivery_method} id="order-delivery" class="mt-4 text-sm text-stone-600">
            <.icon name="hero-truck" class="size-4" />
            {delivery_text(@order)}
          </p>
        </section>

        <p class="mt-8 text-center">
          <.link navigate={~p"/"} class="font-semibold text-orange-600 hover:underline">
            Tagasi poodi
          </.link>
        </p>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :id, :string, required: true
  attr :value, :string, required: true

  defp row(assigns) do
    ~H"""
    <div class="flex justify-between gap-4">
      <dt class="text-stone-500">{@label}</dt>
      <dd id={@id} class="select-all text-right font-bold text-stone-900">{@value}</dd>
    </div>
    """
  end

  defp first_item(order), do: List.first(order.order_items)

  defp delivery_text(%{delivery_method: :pickup}),
    do: "#{Rates.label(:pickup)}: #{Rates.pickup_address()}"

  defp delivery_text(order),
    do: "#{Rates.label(order.delivery_method)}: #{order.pickup_point_name}"

  defp format_time(nil), do: "-"

  defp format_time(%DateTime{} = dt) do
    dt |> DateTime.shift_zone!("Europe/Tallinn") |> Calendar.strftime("%d.%m.%Y %H:%M")
  end

  defp status_icon(:pending), do: "hero-clock"
  defp status_icon(:reserved), do: "hero-banknotes"
  defp status_icon(:paid), do: "hero-check-circle"
  defp status_icon(:shipped), do: "hero-truck"
  defp status_icon(:delivered), do: "hero-gift"
  defp status_icon(:cancelled), do: "hero-x-circle"

  defp status_title(:pending), do: "Tellimus on pooleli"
  defp status_title(:reserved), do: "Aitäh! Ootame makset"
  defp status_title(:paid), do: "Makse laekus, aitäh!"
  defp status_title(:shipped), do: "Tellimus on teel"
  defp status_title(:delivered), do: "Tellimus on kätte antud"
  defp status_title(:cancelled), do: "Tellimus on tühistatud"
end
