defmodule Kirbs.Orders.Config do
  @moduledoc """
  Reservation timings. Override with
  `config :kirbs, Kirbs.Orders.Config, reservation_minutes: 10`.
  """

  @defaults [reservation_minutes: 10, manual_hold_hours: 72, montonio_hold_minutes: 30]

  def reservation_minutes, do: get(:reservation_minutes)

  @doc "When a freshly started (pending) order's reservation lapses."
  def reservation_deadline(now \\ DateTime.utc_now()),
    do: DateTime.add(now, reservation_minutes() * 60, :second)

  @doc "How long items stay held after the buyer submitted checkout, per payment method."
  def hold_deadline(:manual, now), do: DateTime.add(now, get(:manual_hold_hours) * 3600, :second)

  def hold_deadline(:montonio, now),
    do: DateTime.add(now, get(:montonio_hold_minutes) * 60, :second)

  defp get(key) do
    :kirbs |> Application.get_env(__MODULE__, []) |> Keyword.get(key, @defaults[key])
  end
end
