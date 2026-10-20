defmodule KirbsWeb.ShopLive.Checkout do
  @moduledoc """
  Single-item checkout `/checkout/:slug`.

  The connected mount reserves the item (`Order.start`, 10 minutes) and patches to
  `?order=TOKEN` so a reload resumes the same pending order. The buyer fills in contact and
  delivery, then submits (`Order.submit`) and lands on `/order/:token`.

  Funnel tracking: `reserved` when the reservation is made, `checkout_started` when the form
  is first shown, `identify_by_email` once the buyer typed a valid email.
  """
  use KirbsWeb, :live_view

  import KirbsWeb.ShopComponents

  alias Kirbs.Montonio.Config, as: MontonioConfig
  alias Kirbs.Resources.{Item, Order}
  alias Kirbs.Services.Orders.StartMontonioPayment
  alias Kirbs.Shipping.{PickupPoints, Rates}
  alias KirbsWeb.Shop.Labels
  alias KirbsWeb.Track

  @email ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/

  def mount(%{"slug" => slug}, _session, socket) do
    case Item.get_published_by_slug(slug, not_found_error?: false) do
      {:ok, %Item{} = item} ->
        {:ok,
         socket
         |> assign(:item, item)
         |> assign(:order, nil)
         |> assign(:phase, :loading)
         |> assign(:form, nil)
         |> assign(:delivery_method, nil)
         |> assign(:pickup_points, [])
         |> assign(:point_search, "")
         |> assign(:payment_method, :manual)
         |> assign(:montonio?, MontonioConfig.configured?())
         |> assign(:identified_email, nil)
         |> assign(:page_title, "Vormista tellimus | Kirbs")
         |> assign(:meta, %{robots: "noindex,nofollow"})}

      _ ->
        {:ok, socket |> put_flash(:error, "Seda toodet ei leitud") |> push_navigate(to: ~p"/")}
    end
  end

  # The disconnected render only shows the skeleton: reserving must happen exactly once, on
  # the connected mount.
  def handle_params(params, _uri, socket) do
    cond do
      not connected?(socket) -> {:noreply, socket}
      socket.assigns.order -> {:noreply, socket}
      token = params["order"] -> {:noreply, resume(socket, token)}
      true -> {:noreply, start_order(socket)}
    end
  end

  def handle_event("validate", %{"checkout" => params} = all, socket) do
    params = params |> reset_point_on_method_change(socket) |> force_payment_method(socket)
    form = AshPhoenix.Form.validate(socket.assigns.form, params)

    {:noreply,
     socket
     |> assign(:point_search, search_text(all))
     |> assign(:payment_method, parse_payment_method(params["payment_method"]))
     |> assign_form(form)
     |> assign_delivery(params["delivery_method"])
     |> maybe_identify(params["buyer_email"])}
  end

  def handle_event("submit", %{"checkout" => params}, socket) do
    params = params |> reset_point_on_method_change(socket) |> force_payment_method(socket)

    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, order} ->
        socket = maybe_identify(socket, order.buyer_email)

        case order.payment_method do
          :montonio -> {:noreply, pay_with_montonio(socket, order)}
          :manual -> {:noreply, push_navigate(socket, to: ~p"/order/#{order.token}")}
        end

      {:error, form} ->
        {:noreply, socket |> assign_form(form) |> assign_delivery(params["delivery_method"])}
    end
  end

  def handle_info(:reservation_expired, socket) do
    case socket.assigns.phase do
      :form -> {:noreply, assign(socket, :phase, :expired)}
      _ -> {:noreply, socket}
    end
  end

  # --- order lifecycle ----------------------------------------------------

  # On any failure the service has already cancelled the order (items released): show the
  # error with a way to start over rather than leaving an unpayable reservation behind.
  defp pay_with_montonio(socket, order) do
    case StartMontonioPayment.run(order) do
      {:ok, payment_url} -> redirect(socket, external: payment_url)
      {:error, _reason} -> assign(socket, :phase, :payment_failed)
    end
  end

  defp start_order(socket) do
    item = socket.assigns.item

    attrs = %{
      ab_visitor_id: socket.assigns[:ab_funnel_visitor_id],
      ab_assignments: socket.assigns[:ab_funnel_assignments]
    }

    case Order.start([item.id], attrs) do
      {:ok, order} ->
        socket
        |> Track.event(:reserved, item_meta(item))
        |> push_patch(to: ~p"/checkout/#{item.slug}?#{[order: order.token]}", replace: true)

      {:error, _} ->
        assign(socket, :phase, :unavailable)
    end
  end

  defp resume(socket, token) do
    item = socket.assigns.item

    case Order.get_by_token(token, not_found_error?: false) do
      {:ok, %{status: :pending} = order} ->
        if Enum.any?(order.order_items, &(&1.item_id == item.id)) and not expired?(order) do
          show_form(socket, order)
        else
          assign(socket, :phase, :expired)
        end

      {:ok, order} when not is_nil(order) ->
        push_navigate(socket, to: ~p"/order/#{order.token}")

      _ ->
        start_order(socket)
    end
  end

  defp show_form(socket, order) do
    ms = max(DateTime.diff(order.reserved_until, DateTime.utc_now(), :millisecond), 0)
    Process.send_after(self(), :reservation_expired, ms)

    socket
    |> assign(:order, order)
    |> assign(:phase, :form)
    |> assign_form(AshPhoenix.Form.for_update(order, :submit, as: "checkout"))
    |> Track.event(:checkout_started, item_meta(socket.assigns.item))
  end

  defp expired?(order), do: DateTime.compare(order.reserved_until, DateTime.utc_now()) != :gt

  # --- form helpers -------------------------------------------------------

  defp assign_form(socket, form), do: assign(socket, :form, to_form(form))

  @max_points 50

  defp assign_delivery(socket, method) do
    method = parse_method(method)

    socket
    |> assign(:delivery_method, method)
    |> assign(
      :pickup_points,
      points_for(method, socket.assigns.point_search, selected_point(socket))
    )
  end

  defp selected_point(socket), do: socket.assigns.form[:pickup_point_id].value

  defp points_for(nil, _search, _selected), do: []

  defp points_for(method, search, selected) do
    if Rates.parcel_machine?(method) do
      carrier = Rates.carrier(method)
      points = PickupPoints.list(carrier, search, @max_points)
      with_selected(points, carrier, selected)
    else
      []
    end
  end

  # Keep the chosen point in the list even when the search no longer matches it.
  defp with_selected(points, _carrier, selected) when selected in [nil, ""], do: points

  defp with_selected(points, carrier, selected) do
    if Enum.any?(points, &(&1.id == selected)) do
      points
    else
      case PickupPoints.get(carrier, selected) do
        {:ok, point} -> [point | points]
        :error -> points
      end
    end
  end

  defp search_text(all), do: all |> Map.get("point_search", "") |> String.trim()

  defp parse_payment_method("montonio"), do: :montonio
  defp parse_payment_method(_), do: :manual

  # Without Montonio keys a forged "montonio" value silently falls back to bank transfer.
  defp force_payment_method(params, socket) do
    if socket.assigns.montonio?, do: params, else: Map.put(params, "payment_method", "manual")
  end

  defp parse_method(value) when is_binary(value) do
    Enum.find(Rates.methods(), &(Atom.to_string(&1) == value))
  end

  defp parse_method(_), do: nil

  # A point id from another carrier is meaningless: clear it when the method changes.
  defp reset_point_on_method_change(params, socket) do
    if parse_method(params["delivery_method"]) != socket.assigns.delivery_method do
      Map.put(params, "pickup_point_id", "")
    else
      params
    end
  end

  defp maybe_identify(socket, email) when is_binary(email) do
    email = String.trim(email)

    if Regex.match?(@email, email) and socket.assigns.identified_email != email do
      AbFunnel.identify_by_email(socket, email)
      assign(socket, :identified_email, email)
    else
      socket
    end
  end

  defp maybe_identify(socket, _), do: socket

  defp item_meta(item) do
    %{
      item_id: item.id,
      content_ids: [item.id],
      content_name: item_title(item),
      value: item.listed_price && Decimal.to_float(item.listed_price),
      currency: "EUR"
    }
  end

  defp shipping_cents(nil, _item), do: nil
  defp shipping_cents(method, item), do: Rates.cents(method, item.parcel_size)

  defp total_cents(order, method, item),
    do: order.items_total_cents + (shipping_cents(method, item) || 0)

  # --- view ---------------------------------------------------------------

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} meta_pixel_id={@meta_pixel_id}>
      <%= case @phase do %>
        <% :loading -> %>
          <.state_card
            id="checkout-loading"
            icon="hero-clock"
            title="Broneerime eset sinu jaoks..."
            text="Üks hetk."
          />
        <% :unavailable -> %>
          <.state_card
            id="checkout-unavailable"
            icon="hero-face-frown"
            title="See ese ei ole enam saadaval"
            text="Keegi jõudis sinust ette. Ühe eksemplariga esemed lähevad kiiresti."
          >
            <.link navigate={~p"/"} id="back-to-shop" class={primary_button()}>
              Vaata teisi tooteid
            </.link>
          </.state_card>
        <% :payment_failed -> %>
          <.state_card
            id="checkout-payment-failed"
            icon="hero-exclamation-triangle"
            title="Makse alustamine ebaõnnestus"
            text="Maksekeskkonnaga ei õnnestunud ühendust luua. Broneering vabastati, proovi uuesti või vali pangaülekanne."
          >
            <.link navigate={~p"/checkout/#{@item.slug}"} id="retry-checkout" class={primary_button()}>
              Proovi uuesti
            </.link>
          </.state_card>
        <% :expired -> %>
          <.state_card
            id="checkout-expired"
            icon="hero-clock"
            title="Broneering aegus"
            text="Hoidsime eset sinu jaoks 10 minutit. Proovi uuesti, kui see on veel saadaval."
          >
            <.link navigate={~p"/checkout/#{@item.slug}"} id="retry-checkout" class={primary_button()}>
              Broneeri uuesti
            </.link>
          </.state_card>
        <% :form -> %>
          {render_form(assigns)}
      <% end %>
    </Layouts.app>
    """
  end

  defp render_form(assigns) do
    ~H"""
    <div id="checkout" class="mx-auto max-w-5xl">
      <.link
        navigate={~p"/p/#{@item.slug}"}
        class="text-sm font-semibold text-stone-500 transition-colors hover:text-orange-600"
      >
        <.icon name="hero-arrow-left-micro" class="size-4" /> Tagasi toote juurde
      </.link>

      <div class="mt-3 flex flex-wrap items-end justify-between gap-3">
        <h1 class="font-[ui-rounded,'Nunito',system-ui,sans-serif] text-3xl font-black tracking-tight text-stone-900 sm:text-4xl">
          Vormista tellimus
        </h1>
        <p
          id="reservation-timer"
          class="flex items-center gap-2 rounded-full bg-orange-100 px-4 py-1.5 text-sm font-bold text-orange-700"
        >
          <.icon name="hero-clock" class="size-4" /> Hoiame eset sinu jaoks
          <span
            id="countdown"
            phx-hook="Countdown"
            phx-update="ignore"
            data-deadline={DateTime.to_iso8601(@order.reserved_until)}
            class="min-w-10 text-center font-black tabular-nums"
          >
          </span>
        </p>
      </div>

      <.form
        for={@form}
        id="checkout-form"
        phx-change="validate"
        phx-submit="submit"
        class="mt-8 grid gap-8 lg:grid-cols-[minmax(0,1fr)_22rem]"
      >
        <div class="space-y-8">
          <section class="rounded-3xl border border-orange-100 bg-white p-5 sm:p-7">
            <h2 class="text-lg font-black text-stone-900">1. Sinu andmed</h2>
            <div class="mt-4 grid gap-x-4 sm:grid-cols-2">
              <.input
                field={@form[:buyer_name]}
                label="Nimi"
                autocomplete="name"
                class={field_class()}
                error_class={field_error_class()}
                phx-debounce="300"
              />
              <.input
                field={@form[:buyer_phone]}
                type="tel"
                label="Telefon"
                autocomplete="tel"
                class={field_class()}
                error_class={field_error_class()}
                phx-debounce="300"
              />
              <div class="sm:col-span-2">
                <.input
                  field={@form[:buyer_email]}
                  type="email"
                  label="E-post"
                  autocomplete="email"
                  class={field_class()}
                  error_class={field_error_class()}
                  phx-debounce="blur"
                />
              </div>
            </div>
          </section>

          <section class="rounded-3xl border border-orange-100 bg-white p-5 sm:p-7">
            <h2 class="text-lg font-black text-stone-900">2. Kättesaamine</h2>
            <div id="delivery-options" class="mt-4 grid gap-3">
              <label
                :for={{method, label, cents} <- Rates.options(@item.parcel_size)}
                id={"delivery-#{method}"}
                class={[
                  "flex cursor-pointer items-center gap-4 rounded-2xl border-2 px-4 py-3.5 transition",
                  if(@delivery_method == method,
                    do: "border-orange-500 bg-orange-50",
                    else: "border-stone-200 hover:border-orange-300"
                  )
                ]}
              >
                <input
                  type="radio"
                  name={@form[:delivery_method].name}
                  value={method}
                  checked={@delivery_method == method}
                  class="size-4 accent-orange-500"
                />
                <span class="flex-1 font-bold text-stone-800">{label}</span>
                <span class="font-black text-stone-900">
                  {if cents == 0, do: "Tasuta", else: Labels.cents(cents)}
                </span>
              </label>
            </div>
            <p
              :if={delivery_error?(@form)}
              id="delivery-error"
              class="mt-2 text-sm font-semibold text-red-600"
            >
              Vali kättesaamise viis
            </p>

            <div
              :if={Rates.parcel_machine?(@delivery_method || :pickup)}
              id="pickup-point"
              class="mt-5"
            >
              <label for="point-search" class="mb-1 block text-sm font-semibold text-stone-700">
                Otsi pakiautomaati
              </label>
              <input
                id="point-search"
                type="search"
                name="point_search"
                value={@point_search}
                placeholder="Linn, tänav või keskuse nimi"
                autocomplete="off"
                phx-debounce="250"
                class={[field_class(), "mb-3"]}
              />
              <p
                :if={@pickup_points == []}
                id="no-pickup-points"
                class="mb-3 text-sm font-semibold text-stone-500"
              >
                Sobivaid pakiautomaate ei leitud
              </p>
              <.input
                field={@form[:pickup_point_id]}
                type="select"
                label="Pakiautomaat"
                prompt="Vali pakiautomaat"
                options={for p <- @pickup_points, do: {"#{p.name} (#{p.address})", p.id}}
                class={field_class()}
                error_class={field_error_class()}
              />
            </div>

            <p
              :if={@delivery_method == :pickup}
              id="pickup-address"
              class="mt-5 rounded-2xl bg-orange-50 px-4 py-3 text-sm text-stone-700"
            >
              {Rates.pickup_address()}
            </p>
          </section>

          <section class="rounded-3xl border border-orange-100 bg-white p-5 sm:p-7">
            <h2 class="text-lg font-black text-stone-900">3. Makse</h2>
            <div id="payment-options" class="mt-4 grid gap-3">
              <.payment_option
                :if={@montonio?}
                id="payment-montonio"
                name={@form[:payment_method].name}
                value="montonio"
                checked={@payment_method == :montonio}
                icon="hero-credit-card"
                title="Pangalink / pangamakse (Montonio)"
                text="Maksa kohe oma internetipangas. Hoiame eset sinu jaoks 30 minutit."
              />
              <.payment_option
                id="payment-manual"
                name={@form[:payment_method].name}
                value="manual"
                checked={@payment_method == :manual or not @montonio?}
                icon="hero-banknotes"
                title="Pangaülekanne"
                text="Saadame pangaandmed e-postile ja tellimuse lehele. Hoiame eset sinu jaoks 72 tundi."
              />
            </div>
          </section>
        </div>

        <aside id="order-summary" class="lg:sticky lg:top-24 lg:self-start">
          <div class="rounded-3xl border border-orange-100 bg-white p-5 sm:p-6">
            <h2 class="text-lg font-black text-stone-900">Tellimus</h2>
            <div class="mt-4 flex gap-4">
              <div class="size-20 shrink-0 overflow-hidden rounded-2xl bg-orange-100/60">
                <img
                  :if={List.first(@item.images)}
                  src={~p"/img/320/#{List.first(@item.images).id}"}
                  alt=""
                  class="size-full object-cover"
                />
              </div>
              <div class="min-w-0">
                <p class="font-bold leading-snug text-stone-800">{item_title(@item)}</p>
                <p class="mt-1 font-black text-stone-900">{Labels.cents(@order.items_total_cents)}</p>
              </div>
            </div>

            <dl class="mt-5 space-y-2 border-t border-orange-100 pt-4 text-sm">
              <div class="flex justify-between">
                <dt class="text-stone-500">Toode</dt>
                <dd id="summary-items" class="font-semibold">
                  {Labels.cents(@order.items_total_cents)}
                </dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-stone-500">Tarne</dt>
                <dd id="summary-shipping" class="font-semibold">
                  <%= cond do %>
                    <% is_nil(@delivery_method) -> %>
                      <span class="text-stone-400">vali kättesaamise viis</span>
                    <% shipping_cents(@delivery_method, @item) == 0 -> %>
                      Tasuta
                    <% true -> %>
                      {Labels.cents(shipping_cents(@delivery_method, @item))}
                  <% end %>
                </dd>
              </div>
              <div class="flex justify-between border-t border-orange-100 pt-3 text-base">
                <dt class="font-black text-stone-900">Kokku</dt>
                <dd id="summary-total" class="font-black text-stone-900">
                  {Labels.cents(total_cents(@order, @delivery_method, @item))}
                </dd>
              </div>
            </dl>

            <button
              id="checkout-submit"
              type="submit"
              phx-disable-with="Saadan..."
              class={[primary_button(), "mt-6 w-full"]}
            >
              Kinnita tellimus
            </button>
            <p class="mt-3 text-center text-xs text-stone-400">
              Tellimuse kinnitamisega nõustud ostutingimustega.
            </p>
          </div>
        </aside>
      </.form>
    </div>
    """
  end

  defp delivery_error?(form) do
    Phoenix.Component.used_input?(form[:delivery_method]) and form[:delivery_method].errors != []
  end

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :value, :string, required: true
  attr :checked, :boolean, required: true
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :text, :string, required: true

  defp payment_option(assigns) do
    ~H"""
    <label
      id={@id}
      class={[
        "flex cursor-pointer items-start gap-4 rounded-2xl border-2 px-4 py-3.5 transition",
        if(@checked,
          do: "border-orange-500 bg-orange-50",
          else: "border-stone-200 hover:border-orange-300"
        )
      ]}
    >
      <input
        type="radio"
        name={@name}
        value={@value}
        checked={@checked}
        class="mt-1 size-4 accent-orange-500"
      />
      <.icon name={@icon} class="mt-0.5 size-6 text-orange-500" />
      <div>
        <p class="font-bold text-stone-800">{@title}</p>
        <p class="text-sm text-stone-600">{@text}</p>
      </div>
    </label>
    """
  end

  attr :id, :string, required: true
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :text, :string, required: true
  slot :inner_block

  defp state_card(assigns) do
    ~H"""
    <div id={@id} class="mx-auto max-w-lg py-16 text-center">
      <.icon name={@icon} class="mx-auto size-12 text-orange-400" />
      <h1 class="mt-4 text-3xl font-black text-stone-900">{@title}</h1>
      <p class="mt-2 text-stone-500">{@text}</p>
      <div class="mt-6">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  defp primary_button do
    "inline-flex items-center justify-center gap-2 rounded-full bg-orange-500 px-6 py-3 font-extrabold text-white shadow-lg shadow-orange-500/30 transition hover:-translate-y-0.5 hover:bg-orange-600"
  end

  defp field_class do
    "w-full rounded-xl border-2 border-stone-200 bg-white px-4 py-2.5 text-stone-900 outline-none transition focus:border-orange-500"
  end

  defp field_error_class, do: "border-red-400! focus:border-red-500!"
end
