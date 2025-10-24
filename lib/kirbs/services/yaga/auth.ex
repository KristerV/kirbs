defmodule Kirbs.Services.Yaga.Auth do
  @moduledoc """
  Get JWT token for Yaga API from settings.
  """

  alias Kirbs.Resources.Settings

  def run do
    with {:ok, setting} <- Settings.get_by_key("yaga_jwt"),
         {:ok, jwt} <- validate_jwt(setting.value) do
      {:ok, jwt}
    else
      {:error, %Ash.Error.Query.NotFound{}} ->
        {:error, "JWT token not found in settings. Please configure it in Settings."}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_jwt(nil), do: {:error, "JWT token is empty"}
  defp validate_jwt(""), do: {:error, "JWT token is empty"}
  defp validate_jwt(jwt) when is_binary(jwt), do: {:ok, String.trim(jwt)}
end
