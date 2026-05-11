defmodule Kirbs.Services.Yaga.StatusChecker do
  @moduledoc """
  Checks the current status of a single item on Yaga by its slug.
  """

  @base_url "https://www.yaga.ee"

  def run(slug) do
    url = "#{@base_url}/api/product/#{slug}"

    headers = [
      {"accept", "application/json"},
      {"x-language", "et"},
      {"x-country", "EE"}
    ]

    with {:ok, %{status: 200, body: %{"status" => "success", "data" => data}}} <-
           Req.get(url, headers: headers) do
      {:ok,
       %{
         status: data["status"],
         price: data["price"],
         updated_at: parse_datetime(data["updated_at"] || data["updatedAt"])
       }}
    else
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: status}} -> {:error, "HTTP #{status}"}
      {:error, error} -> {:error, error}
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end
