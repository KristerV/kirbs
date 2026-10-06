defmodule Kirbs.Jobs.ExpireReservationsJob do
  @moduledoc "Every minute: releases expired reservations and cancels their unpaid orders."
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Kirbs.Services.Orders.ExpireReservations

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    with {:ok, _summary} <- ExpireReservations.run(), do: :ok
  end
end
