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

    bank = Kirbs.Orders.BankDetails.get()

    {:ok,
     socket
     |> assign(:jwt_token, jwt_setting)
     |> assign(
       :bank_form,
       to_form(%{"iban" => bank.iban, "recipient" => bank.recipient}, as: :bank)
     )}
  end

  @impl true
  def handle_event(
        "save_bank",
        %{"bank" => %{"iban" => iban, "recipient" => recipient} = params},
        socket
      ) do
    with {:ok, _} <- Settings.create(%{key: "shop_bank_iban", value: String.trim(iban)}),
         {:ok, _} <- Settings.create(%{key: "shop_bank_recipient", value: String.trim(recipient)}) do
      {:noreply,
       socket
       |> put_flash(:info, "Bank details saved")
       |> assign(:bank_form, to_form(params, as: :bank))}
    else
      _ -> {:noreply, put_flash(socket, :error, "Failed to save bank details")}
    end
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

        <%!-- TODO(owner): enter the real IBAN here before taking real shop orders. --%>
        <div id="bank-settings" class="card bg-base-100 shadow-xl mb-6">
          <div class="card-body">
            <h2 class="card-title">Shop bank transfer details</h2>
            <p class="text-sm text-base-content/70 mb-4">
              Shown to buyers who pay by bank transfer (order page and confirmation email).
              Until you save real values a placeholder IBAN is used.
            </p>
            <.form for={@bank_form} id="bank-form" phx-submit="save_bank">
              <.input field={@bank_form[:recipient]} label="Account holder" />
              <.input field={@bank_form[:iban]} label="IBAN" />
              <div class="card-actions justify-end mt-4">
                <button type="submit" class="btn btn-primary">Save bank details</button>
              </div>
            </.form>
          </div>
        </div>

        <div class="card bg-base-100 shadow-xl mb-6">
          <div class="card-body">
            <h2 class="card-title">Yaga JWT Token</h2>
            <p class="text-sm text-base-content/70 mb-4">
              Enter your Yaga.ee JWT token for API authentication. <br />
              <strong>How to get it:</strong>
              Log into yaga.ee, open the Network tab in developer tools,
              refresh the page, find any request to yaga.ee/api, look in Headers for
              "authorization: Bearer ...", and copy the token (everything after "Bearer ").
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
