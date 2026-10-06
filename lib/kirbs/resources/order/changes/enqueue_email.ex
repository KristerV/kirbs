defmodule Kirbs.Resources.Order.Changes.EnqueueEmail do
  @moduledoc """
  Enqueues a transactional email (`Kirbs.Jobs.SendOrderEmailJob`) in the action's transaction.
  Options: `kind` (:received | :paid | :shipped) and optionally `payment_method` to only
  send for that payment method.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, _context) do
    kind = Keyword.fetch!(opts, :kind)

    Ash.Changeset.after_action(changeset, fn _changeset, order ->
      if applies?(order, opts[:payment_method]) do
        {:ok, _job} =
          %{order_id: order.id, kind: kind} |> Kirbs.Jobs.SendOrderEmailJob.new() |> Oban.insert()
      end

      {:ok, order}
    end)
  end

  defp applies?(_order, nil), do: true
  defp applies?(order, payment_method), do: order.payment_method == payment_method
end
