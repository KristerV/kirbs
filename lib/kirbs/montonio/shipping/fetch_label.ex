defmodule Kirbs.Montonio.Shipping.FetchLabel do
  @moduledoc """
  Creates a label file for registered shipments and returns its PDF url.

  `refs` is `%{shipment_ids: ["..."]}` (max 100, shipments must be `registered`).
  Requests a synchronous file (A6, one label per page); if Montonio still
  answers `pending` the file is polled a few times.
  """

  alias Kirbs.Montonio.{Client, Config}

  @max_polls 5

  def run(%{shipment_ids: [_ | _] = ids}) do
    with :ok <- ensure_configured(),
         {:ok, file} <- create(ids),
         {:ok, url} <- resolve(file, @max_polls) do
      {:ok, url}
    end
  end

  def run(_), do: {:error, :missing_shipment_ids}

  defp ensure_configured do
    if Config.configured?(), do: :ok, else: {:error, :montonio_not_configured}
  end

  defp create(ids) do
    body = %{
      "shipmentIds" => ids,
      "pageSize" => "A6",
      "labelsPerPage" => 1,
      "synchronous" => true
    }

    Client.shipping() |> Req.post(url: "/label-files", json: body) |> Client.handle()
  end

  defp resolve(%{"labelFileUrl" => url}, _polls) when is_binary(url), do: {:ok, url}
  defp resolve(%{"status" => "failed"}, _polls), do: {:error, :label_creation_failed}
  defp resolve(_file, 0), do: {:error, :label_not_ready}

  defp resolve(%{"id" => id}, polls) do
    Process.sleep(Config.label_poll_delay())

    with {:ok, file} <-
           Client.shipping() |> Req.get(url: "/label-files/#{id}") |> Client.handle() do
      resolve(file, polls - 1)
    end
  end

  defp resolve(body, _polls), do: {:error, {:unexpected_response, body}}
end
