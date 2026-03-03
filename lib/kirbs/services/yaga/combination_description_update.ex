defmodule Kirbs.Services.Yaga.CombinationDescriptionUpdate do
  @moduledoc """
  Updates Yaga descriptions for all items in a combination group
  with cross-reference links to the other items.
  """

  alias Kirbs.Resources.Item
  alias Kirbs.Services.Yaga.Auth

  @base_url "https://www.yaga.ee"

  def run(combination_group) do
    with {:ok, items} <- load_items(combination_group),
         :ok <- verify_all_uploaded(items),
         {:ok, jwt} <- Auth.run(),
         :ok <- update_all_descriptions(jwt, items) do
      {:ok, items}
    end
  end

  defp load_items(combination_group) do
    case Item.list_by_combination_group(combination_group) do
      {:ok, []} -> {:error, "No items found for combination group"}
      {:ok, items} -> {:ok, items}
      {:error, error} -> {:error, "Failed to load items: #{inspect(error)}"}
    end
  end

  defp verify_all_uploaded(items) do
    missing = Enum.filter(items, fn item -> is_nil(item.yaga_slug) end)

    case missing do
      [] -> :ok
      _ -> {:error, "Not all items uploaded yet (#{length(missing)} missing)"}
    end
  end

  defp update_all_descriptions(jwt, items) do
    results =
      Enum.map(items, fn item ->
        others = Enum.reject(items, &(&1.id == item.id))
        update_description(jwt, item, others)
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> :ok
      error -> error
    end
  end

  defp update_description(jwt, item, others) do
    description = build_description(item, others)

    headers = [
      {"authorization", "Bearer #{jwt}"},
      {"content-type", "application/json"},
      {"x-country", "EE"},
      {"x-language", "et"}
    ]

    body = %{description: description}

    case Req.patch("#{@base_url}/api/product/#{item.yaga_id}", json: body, headers: headers) do
      {:ok, %{status: 200, body: %{"status" => "success"}}} ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error,
         "Failed to update description for #{item.yaga_slug}: HTTP #{status} - #{inspect(body)}"}

      {:error, error} ->
        {:error, "Network error updating #{item.yaga_slug}: #{inspect(error)}"}
    end
  end

  defp build_description(item, others) do
    bag_label = bag_label(item)

    links =
      others
      |> Enum.map(fn other -> "- #{@base_url}/toode/#{other.yaga_slug}" end)
      |> Enum.join("\n")

    """
    #{item.description}

    See ese on osa kombinatsioonist:
    #{links}

    #{bag_label}\
    """
    |> String.trim()
  end

  defp bag_label(item) do
    if item.bag && item.bag.number do
      "B#{String.pad_leading(Integer.to_string(item.bag.number), 4, "0")}"
    else
      ""
    end
  end
end
