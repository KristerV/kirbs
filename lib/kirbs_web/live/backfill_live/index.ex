defmodule KirbsWeb.BackfillLive.Index do
  @moduledoc """
  Review screen for the categorization backfill: approve, change or reject proposals,
  or apply all proposals above a confidence threshold. Nothing is applied automatically.
  """
  use KirbsWeb, :live_view

  alias Kirbs.Resources.CategorizationProposal
  alias Kirbs.Services.Backfill.{ApplyProposal, ApplyProposalsAbove, EnqueueCategorize}
  alias Kirbs.Services.Categories.GroupedLeafOptions

  @default_threshold "0.9"

  @impl true
  def mount(_params, _session, socket) do
    {:ok, category_options} = GroupedLeafOptions.run()

    {:ok,
     socket
     |> assign(:page_title, "Categorization backfill")
     |> assign(:category_options, category_options)
     |> assign(:threshold, @default_threshold)
     |> load_proposals()}
  end

  @impl true
  def handle_event("start_dry_run", _params, socket) do
    case EnqueueCategorize.run() do
      {:ok, _job} ->
        {:noreply,
         put_flash(socket, :info, "Backfill enqueued (dry run). Proposals appear here.")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not enqueue: #{inspect(error)}")}
    end
  end

  def handle_event("refresh", _params, socket), do: {:noreply, load_proposals(socket)}

  def handle_event("approve", %{"id" => id}, socket) do
    with {:ok, proposal} <- CategorizationProposal.get(id),
         {:ok, _item} <- ApplyProposal.run(proposal) do
      {:noreply, socket |> update_count(-1) |> stream_delete(:proposals, proposal)}
    else
      error -> {:noreply, put_flash(socket, :error, "Could not apply: #{inspect(error)}")}
    end
  end

  def handle_event("reject", %{"id" => id}, socket) do
    with {:ok, proposal} <- CategorizationProposal.get(id),
         {:ok, proposal} <- CategorizationProposal.reject(proposal) do
      {:noreply, socket |> update_count(-1) |> stream_delete(:proposals, proposal)}
    else
      error -> {:noreply, put_flash(socket, :error, "Could not reject: #{inspect(error)}")}
    end
  end

  def handle_event("change_category", %{"id" => id, "category_id" => category_id}, socket) do
    with {:ok, proposal} <- CategorizationProposal.get(id),
         {:ok, proposal} <-
           CategorizationProposal.update(proposal, %{category_id: blank_to_nil(category_id)}),
         {:ok, proposal} <- Ash.load(proposal, [:category, item: [:images]]) do
      {:noreply, stream_insert(socket, :proposals, proposal)}
    else
      error -> {:noreply, put_flash(socket, :error, "Could not change: #{inspect(error)}")}
    end
  end

  def handle_event("apply_above", %{"threshold" => threshold}, socket) do
    case Float.parse(threshold) do
      {value, _} when value >= 0.0 and value <= 1.0 ->
        {:ok, %{applied: applied, failed: failed}} = ApplyProposalsAbove.run(value)

        {:noreply,
         socket
         |> assign(:threshold, threshold)
         |> put_flash(:info, "Applied #{applied} proposals (#{failed} failed)")
         |> load_proposals()}

      _ ->
        {:noreply, put_flash(socket, :error, "Threshold must be between 0 and 1")}
    end
  end

  defp load_proposals(socket) do
    proposals = CategorizationProposal.list_pending!()

    socket
    |> assign(:pending_count, length(proposals))
    |> stream(:proposals, proposals, reset: true)
  end

  defp update_count(socket, delta), do: update(socket, :pending_count, &(&1 + delta))

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp percent(confidence), do: "#{round(confidence * 100)}%"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div id="backfill" class="max-w-6xl mx-auto p-6">
        <div class="flex flex-wrap justify-between items-center gap-3 mb-6">
          <h1 class="text-3xl font-bold">Categorization backfill</h1>
          <div class="flex gap-2">
            <button id="refresh-proposals" class="btn btn-sm" phx-click="refresh">Refresh</button>
            <button id="start-dry-run" class="btn btn-sm btn-primary" phx-click="start_dry_run">
              Start dry run
            </button>
          </div>
        </div>

        <form
          id="apply-above-form"
          phx-submit="apply_above"
          class="card bg-base-100 shadow mb-6 p-4 flex flex-row flex-wrap items-end gap-3"
        >
          <div class="form-control">
            <label class="label" for="threshold">
              <span class="label-text">Min confidence</span>
            </label>
            <input
              id="threshold"
              type="number"
              name="threshold"
              step="0.01"
              min="0"
              max="1"
              value={@threshold}
              class="input input-bordered w-32"
            />
          </div>
          <button
            id="apply-above"
            type="submit"
            class="btn btn-success"
            data-confirm="Apply all pending proposals at or above this confidence?"
          >
            Apply all above threshold
          </button>
          <span id="pending-count" class="ml-auto text-sm opacity-70">
            {@pending_count} pending
          </span>
        </form>

        <div id="proposals" phx-update="stream" class="space-y-4">
          <div id="proposals-empty" class="hidden only:block alert">No pending proposals.</div>
          <div
            :for={{dom_id, proposal} <- @streams.proposals}
            id={dom_id}
            class="card bg-base-100 shadow"
          >
            <div class="card-body flex-row gap-4">
              <div class="flex gap-2 shrink-0">
                <img
                  :for={image <- Enum.take(proposal.item.images, 2)}
                  src={"/uploads/#{image.path}"}
                  alt="Item photo"
                  class="w-24 h-24 object-cover rounded"
                />
              </div>

              <div class="flex-1 space-y-2">
                <div class="flex items-center gap-2">
                  <span class="badge badge-primary">{percent(proposal.confidence)}</span>
                  <.link navigate={~p"/items/#{proposal.item_id}"} class="link text-sm">
                    open item
                  </.link>
                </div>

                <form id={"change-#{proposal.id}"} phx-change="change_category">
                  <input type="hidden" name="id" value={proposal.id} />
                  <select name="category_id" class="select select-bordered select-sm w-full max-w-md">
                    <option value="">-- no category --</option>
                    <optgroup :for={{label, options} <- @category_options} label={label}>
                      <option
                        :for={{name, id} <- options}
                        value={id}
                        selected={proposal.category_id == id}
                      >
                        {name}
                      </option>
                    </optgroup>
                  </select>
                </form>

                <div class="text-sm opacity-80 flex flex-wrap gap-x-4">
                  <span :if={proposal.age_group}>age: {proposal.age_group}</span>
                  <span :if={proposal.gender}>gender: {proposal.gender}</span>
                  <span :if={proposal.season}>season: {proposal.season}</span>
                  <span :if={proposal.condition}>condition: {proposal.condition}</span>
                  <span :if={proposal.brand}>brand: {proposal.brand}</span>
                  <span :if={proposal.size}>size: {proposal.size}</span>
                  <span :if={proposal.colors not in [nil, []]}>
                    colors: {Enum.join(proposal.colors, ", ")}
                  </span>
                  <span :if={proposal.materials not in [nil, []]}>
                    materials: {Enum.join(proposal.materials, ", ")}
                  </span>
                </div>
              </div>

              <div class="flex flex-col gap-2 shrink-0">
                <button
                  id={"approve-#{proposal.id}"}
                  class="btn btn-success btn-sm"
                  phx-click="approve"
                  phx-value-id={proposal.id}
                  disabled={is_nil(proposal.category_id)}
                >
                  Approve
                </button>
                <button
                  id={"reject-#{proposal.id}"}
                  class="btn btn-ghost btn-sm"
                  phx-click="reject"
                  phx-value-id={proposal.id}
                >
                  Reject
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
