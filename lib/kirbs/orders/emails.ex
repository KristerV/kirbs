defmodule Kirbs.Orders.Emails do
  @moduledoc """
  Builds the transactional order emails (Swoosh, Estonian): `received` (with bank-transfer
  instructions for manual payment), `paid` and `shipped`. Delivery goes through
  `Kirbs.Services.Orders.SendOrderEmail`.

  Sender: `config :kirbs, :shop_mail, from: {"Kirbs", "pood@kirbs.ee"}`
  (TODO(owner): set the real sender address on a verified domain).
  """
  import Swoosh.Email

  alias Kirbs.Orders.BankDetails
  alias Kirbs.Shipping.Rates
  alias KirbsWeb.Shop.Labels

  def build(:received, order),
    do: base(order, "Kirbs: saime tellimuse #{order.reference} kätte", received_text(order))

  def build(:paid, order),
    do: base(order, "Kirbs: tellimus #{order.reference} on tasutud", paid_text(order))

  def build(:shipped, order),
    do: base(order, "Kirbs: tellimus #{order.reference} on teel", shipped_text(order))

  defp base(order, subject, text) do
    new()
    |> to({order.buyer_name, order.buyer_email})
    |> from(from())
    |> subject(subject)
    |> text_body(text)
    |> html_body(html(text))
  end

  defp from do
    :kirbs
    |> Application.get_env(:shop_mail, [])
    |> Keyword.get(:from, {"Kirbs", "pood@kirbs.ee"})
  end

  defp received_text(order) do
    payment =
      case order.payment_method do
        :manual ->
          bank = BankDetails.get()

          """
          Palun tasu #{Labels.cents(order.total_cents)} pangaülekandega:

          Saaja: #{bank.recipient}
          IBAN: #{bank.iban}
          Summa: #{Labels.cents(order.total_cents)}
          Selgitus: #{order.reference}

          Hoiame esemeid sinu jaoks kuni #{format_time(order.reserved_until)}. Kui makset selleks ajaks ei laeku, broneering vabaneb.
          """

        _ ->
          "Maksa tellimus ära lingil, mille said maksmise sammus.\n"
      end

    """
    Tere, #{order.buyer_name}!

    Täname tellimuse eest. Tellimuse number on #{order.reference}.

    #{items_block(order)}
    #{delivery_line(order)}
    Kokku: #{Labels.cents(order.total_cents)}

    #{payment}
    Tellimuse seisu näed siin: #{order_url(order)}

    Kirbs
    """
  end

  defp paid_text(order) do
    """
    Tere, #{order.buyer_name}!

    Saime makse kätte, aitäh! Tellimus #{order.reference} on tasutud.

    #{items_block(order)}
    #{delivery_line(order)}

    #{next_step(order)}
    Tellimuse seis: #{order_url(order)}

    Kirbs
    """
  end

  defp shipped_text(order) do
    tracking =
      case {order.tracking_number, order.tracking_url} do
        {nil, _} -> ""
        {number, nil} -> "Jälgimisnumber: #{number}\n"
        {number, url} -> "Jälgimisnumber: #{number}\nJälgi saadetist: #{url}\n"
      end

    """
    Tere, #{order.buyer_name}!

    Tellimus #{order.reference} on teele pandud.

    #{delivery_line(order)}
    #{tracking}
    Tellimuse seis: #{order_url(order)}

    Kirbs
    """
  end

  defp next_step(%{delivery_method: :pickup}),
    do: "Anname teada, kui tellimus on järeleminekuks valmis."

  defp next_step(_order), do: "Paneme saadetise peagi teele ja anname siis uuesti teada."

  defp items_block(order) do
    lines = Enum.map(order.order_items, &"- #{&1.title}: #{Labels.cents(&1.price_cents)}")
    Enum.join(["Tellitud:" | lines], "\n")
  end

  defp delivery_line(%{delivery_method: :pickup} = order),
    do: "Kättesaamine: #{Rates.label(:pickup)} (#{Rates.pickup_address()}), #{shipping(order)}"

  defp delivery_line(order),
    do:
      "Tarne: #{Rates.label(order.delivery_method)} – #{order.pickup_point_name}, #{shipping(order)}"

  defp shipping(%{shipping_cents: 0}), do: "tasuta"
  defp shipping(order), do: Labels.cents(order.shipping_cents)

  defp format_time(nil), do: "-"

  defp format_time(%DateTime{} = dt) do
    dt |> DateTime.shift_zone!("Europe/Tallinn") |> Calendar.strftime("%d.%m.%Y %H:%M")
  end

  defp order_url(order), do: KirbsWeb.Endpoint.url() <> "/order/#{order.token}"

  defp html(text) do
    escaped = text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    ~s(<div style="font-family:system-ui,sans-serif;font-size:15px;line-height:1.6;color:#44403c;white-space:pre-wrap">#{escaped}</div>)
  end
end
