defmodule Kirbs.Services.Yaga.Auth do
  @moduledoc """
  Get JWT token for Yaga API from settings.
  """

  alias Kirbs.Resources.Settings

  def run do
    case Settings.get_by_key("yaga_jwt") do
      {:ok, setting} ->
        validate_jwt(setting.value)

      {:error, _error} ->
        {:error, "JWT token not found in settings. Please configure it in Settings."}
    end
  end

  defp validate_jwt(nil), do: {:error, "JWT token is empty"}
  defp validate_jwt(""), do: {:error, "JWT token is empty"}
  defp validate_jwt(jwt) when is_binary(jwt), do: {:ok, String.trim(jwt)}
end
