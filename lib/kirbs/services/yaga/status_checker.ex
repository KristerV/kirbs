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
      {:ok, %{status: data["status"], price: data["price"]}}
    else
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: status}} -> {:error, "HTTP #{status}"}
      {:error, error} -> {:error, error}
    end
  end
end
