defmodule Kirbs.Orders.Config do
  @moduledoc """
  Reservation timings. Override with
  `config :kirbs, Kirbs.Orders.Config, reservation_minutes: 10`.
  """

  @defaults [reservation_minutes: 10, montonio_hold_minutes: 30]

  def reservation_minutes, do: get(:reservation_minutes)

  @doc "When a freshly started (pending) order's reservation lapses."
  def reservation_deadline(now \\ DateTime.utc_now()),
    do: DateTime.add(now, reservation_minutes() * 60, :second)

  @doc "How long items stay held after the buyer submitted checkout (time to pay at Montonio)."
  def hold_deadline(now), do: DateTime.add(now, get(:montonio_hold_minutes) * 60, :second)

  defp get(key) do
    :kirbs |> Application.get_env(__MODULE__, []) |> Keyword.get(key, @defaults[key])
  end
end
