defmodule KirbsWeb.SettingsLive.Index do
  use KirbsWeb, :live_view

  alias Kirbs.Resources.Settings

  @impl true
  def mount(_params, _session, socket) do
    jwt_setting =
      Settings.get_by_key("yaga_jwt")
      |> case do
        {:ok, setting} -> setting.value || ""
        {:error, _} -> ""
      end

    {:ok,
     socket
     |> assign(:jwt_token, jwt_setting)}
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
      </div>
    </div>
    """
  end
end
