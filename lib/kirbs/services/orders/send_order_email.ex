defmodule Kirbs.Services.Orders.SendOrderEmail do
  @moduledoc "Delivers one transactional email (:paid | :shipped) for an order."

  alias Kirbs.Mailer
  alias Kirbs.Orders.Emails
  alias Kirbs.Resources.Order

  def run(order_id, kind) when kind in [:paid, :shipped] do
    with {:ok, order} <- Order.get(order_id),
         email = Emails.build(kind, order),
         {:ok, _meta} <- Mailer.deliver(email) do
      {:ok, order}
    end
  end
end
