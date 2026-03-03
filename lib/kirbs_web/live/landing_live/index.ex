defmodule KirbsWeb.LandingLive.Index do
  use KirbsWeb, :live_view

  alias Kirbs.Resources.Client

  on_mount {KirbsWeb.LiveUserAuth, :live_user_optional}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Käed Vabad Kirbukas - Lapse riideid müüa ilma vaevata")
     |> assign(:show_modal, nil)
     |> assign(:registration_success, false)
     |> assign(:registration_message, nil)
     |> assign(:registration_errors, %{})}
  end

  def handle_event("show_modal", %{"type" => type}, socket) do
    {:noreply,
     socket
     |> assign(:show_modal, type)
     |> assign(:registration_success, false)
     |> assign(:registration_message, nil)
     |> assign(:registration_errors, %{})}
  end

  def handle_event("close_modal", _, socket) do
    {:noreply, assign(socket, :show_modal, nil)}
  end

  def handle_event("ignore", _, socket) do
    {:noreply, socket}
  end

  def handle_event("validate_registration", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("register_client", %{"registration" => params}, socket) do
    case Client.register(params) do
      {:ok, _client} ->
        {:noreply,
         socket
         |> assign(:registration_success, true)
         |> assign(:registration_message, "Suurepärane! Sinu andmed on salvestatud.")}

      {:error, %Ash.Error.Invalid{} = error} ->
        if unique_constraint_error?(error) do
          {:noreply,
           socket
           |> assign(:registration_success, true)
           |> assign(:registration_message, "Meil on sinu andmed juba olemas!")}
        else
          errors = extract_field_errors(error)

          {:noreply, assign(socket, :registration_errors, errors)}
        end
    end
  end

  defp unique_constraint_error?(%Ash.Error.Invalid{errors: errors}) do
    Enum.any?(errors, fn
      %Ash.Error.Changes.InvalidChanges{message: "has already been taken"} ->
        true

      _ ->
        false
    end)
  end

  defp extract_field_errors(%Ash.Error.Invalid{errors: errors}) do
    Enum.reduce(errors, %{}, fn
      %{field: field, message: message}, acc when not is_nil(field) ->
        Map.put(acc, to_string(field), message)

      _, acc ->
        acc
    end)
  end
end
