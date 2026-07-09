defmodule Kirbs.Services.Yaga.TokenRefresh do
  @moduledoc """
  Refresh the Yaga JWT before it expires and persist the fresh token.

  Yaga issues 30-day tokens. POSTing the current (still-valid) token to the
  refresh endpoint returns a new 30-day token. Running this on any schedule
  shorter than 30 days keeps the login alive indefinitely, so the token never
  has to be pasted in Settings again.
  """

  alias Kirbs.Resources.Settings
  alias Kirbs.Services.Yaga.Auth

  @base_url "https://www.yaga.ee"

  def run do
    with {:ok, current} <- Auth.run(),
         {:ok, token} <- refresh(current),
         {:ok, _setting} <- persist(token) do
      {:ok, token}
    end
  end

  defp refresh(current) do
    headers = [
      {"authorization", "Bearer #{current}"},
      {"content-type", "application/json"},
      {"x-country", "EE"},
      {"x-language", "et"}
    ]

    case Req.post("#{@base_url}/api/auth/token/refresh", json: %{}, headers: headers) do
      {:ok, %{status: 200, body: %{"status" => "success", "data" => %{"token" => token}}}} ->
        {:ok, strip_bearer(token)}

      {:ok, %{status: status, body: body}} ->
        {:error, "Failed to refresh Yaga token: HTTP #{status} - #{inspect(body)}"}

      {:error, error} ->
        {:error, "Network error refreshing Yaga token: #{inspect(error)}"}
    end
  end

  defp persist(token) do
    Settings.create(%{key: "yaga_jwt", value: token})
  end

  defp strip_bearer("Bearer " <> token), do: String.trim(token)
  defp strip_bearer(token), do: String.trim(token)
end
