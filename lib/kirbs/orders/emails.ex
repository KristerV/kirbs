defmodule Kirbs.Orders.Emails do
  @moduledoc """
  Builds the transactional order emails (Swoosh, Estonian): `paid` and `shipped`. Delivery goes through
  `Kirbs.Services.Orders.SendOrderEmail`.

  Sender: `config :kirbs, :shop_mail, from: {"Kirbs", "kirbs@krister.ee"}`
  (TODO(owner): set the real sender address on a verified domain).
  """
  import Swoosh.Email

  alias Kirbs.Shipping.Rates
  alias KirbsWeb.Shop.Labels

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
    |> Keyword.get(:from, {"Kirbs", "kirbs@krister.ee"})
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

  defp next_step(_order), do: "Paneme saadetise peagi teele ja anname siis uuesti teada."

  defp items_block(order) do
    lines = Enum.map(order.order_items, &"- #{&1.title}: #{Labels.cents(&1.price_cents)}")
    Enum.join(["Tellitud:" | lines], "\n")
  end

  defp delivery_line(order),
    do:
      "Tarne: #{Rates.label(order.delivery_method)} – #{order.pickup_point_name}, #{shipping(order)}"

  defp shipping(%{shipping_cents: 0}), do: "tasuta"
  defp shipping(order), do: Labels.cents(order.shipping_cents)

  defp order_url(order), do: KirbsWeb.Endpoint.url() <> "/order/#{order.token}"

  defp html(text) do
    escaped = text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    ~s(<div style="font-family:system-ui,sans-serif;font-size:15px;line-height:1.6;color:#44403c;white-space:pre-wrap">#{escaped}</div>)
  end
end
