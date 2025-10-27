defmodule KirbsWeb.SettingsLive.Index do
  use KirbsWeb, :live_view

  alias Kirbs.Resources.Settings
  alias Kirbs.Resources.YagaMetadata
  alias Kirbs.Services.Yaga.MetadataFetcher

  @impl true
  def mount(_params, _session, socket) do
    jwt_setting =
      Settings.get_by_key("yaga_jwt")
      |> case do
        {:ok, setting} -> setting.value || ""
        {:error, _} -> ""
      end

    yaga_metadata =
      case YagaMetadata.list() do
        {:ok, metadata} -> metadata
        {:error, _} -> []
      end

    {:ok,
     socket
     |> assign(:jwt_token, jwt_setting)
     |> assign(:loading, false)
     |> assign(:message, nil)
     |> assign(:yaga_metadata, yaga_metadata)}
  end

  @impl true
  def handle_event("save_jwt", %{"jwt_token" => jwt_token}, socket) do
    case Settings.create(%{key: "yaga_jwt", value: jwt_token}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "JWT token saved successfully")
         |> assign(:jwt_token, jwt_token)}

      {:error, _error} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to save JWT token")}
    end
  end

  @impl true
  def handle_event("refresh_metadata", _params, socket) do
    send(self(), :do_refresh_metadata)
    {:noreply, assign(socket, :loading, true)}
  end

  @impl true
  def handle_info(:do_refresh_metadata, socket) do
    case MetadataFetcher.run() do
      {:ok, count} ->
        yaga_metadata =
          case YagaMetadata.list() do
            {:ok, metadata} -> metadata
            {:error, _} -> []
          end

        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:yaga_metadata, yaga_metadata)
         |> put_flash(:info, "Successfully fetched #{count} metadata records from Yaga")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> put_flash(:error, "Failed to fetch metadata: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-base-300 min-h-screen">
      <div class="max-w-4xl mx-auto p-6">
        <h1 class="text-3xl font-bold mb-6">Settings</h1>

        <div class="card bg-base-100 shadow-xl mb-6">
          <div class="card-body">
            <h2 class="card-title">Yaga JWT Token</h2>
            <p class="text-sm text-base-content/70 mb-4">
              Enter your Yaga.ee JWT token for API authentication
            </p>

            <form phx-submit="save_jwt">
              <div class="form-control">
                <textarea
                  name="jwt_token"
                  class="textarea textarea-bordered h-32 font-mono text-sm"
                  placeholder="Paste your JWT token here..."
                  value={@jwt_token}
                ><%= @jwt_token %></textarea>
              </div>

              <div class="card-actions justify-end mt-4">
                <button type="submit" class="btn btn-primary">
                  Save JWT Token
                </button>
              </div>
            </form>
          </div>
        </div>

        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <h2 class="card-title">Yaga Metadata</h2>
            <p class="text-sm text-base-content/70 mb-4">
              Fetch brands, categories, colors, materials, and conditions from Yaga.ee
            </p>

            <div class="card-actions justify-end mb-4">
              <button
                type="button"
                phx-click="refresh_metadata"
                class="btn btn-secondary"
                disabled={@loading}
              >
                <%= if @loading do %>
                  <span class="loading loading-spinner loading-sm"></span> Fetching...
                <% else %>
                  Refresh Metadata
                <% end %>
              </button>
            </div>

            <div class="collapse collapse-arrow bg-base-200">
              <input type="checkbox" />
              <div class="collapse-title text-xl font-medium">
                View Raw Database Data ({length(@yaga_metadata)} records)
              </div>
              <div class="collapse-content">
                <div class="overflow-x-auto">
                  <pre class="bg-base-300 p-4 rounded-lg text-xs overflow-auto max-h-96"><%= inspect(@yaga_metadata, pretty: true) %></pre>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
