defmodule Kirbs.Services.Yaga.StatusFixer do
  @moduledoc """
  Finds items stuck with status :reviewed but having a yaga_id,
  checks their actual status on Yaga, and fixes accordingly.
  """

  alias Kirbs.Resources.Item
  alias Kirbs.Services.Yaga.StatusChecker

  def run do
    with {:ok, items} <- find_broken_items(),
         {:ok, results} <- fix_items(items) do
      {:ok, results}
    end
  end

  defp find_broken_items do
    items =
      Item.list!()
      |> Enum.filter(&(&1.status == :reviewed and &1.yaga_id != nil))

    {:ok, items}
  end

  defp fix_items(items) do
    results = Enum.map(items, &fix_item/1)

    fixed_sold = Enum.count(results, &match?({:ok, :sold}, &1))
    fixed_uploaded = Enum.count(results, &match?({:ok, :uploaded_to_yaga}, &1))

    errors =
      Enum.flat_map(results, fn
        {:error, reason} -> [reason]
        _ -> []
      end)

    {:ok, %{fixed_sold: fixed_sold, fixed_uploaded: fixed_uploaded, errors: errors}}
  end

  defp fix_item(item) do
    with {:ok, %{status: yaga_status, price: price}} <- StatusChecker.run(item.yaga_slug) do
      update_item(item, yaga_status, price)
    else
      {:error, reason} -> {:error, "#{item.id}: #{inspect(reason)}"}
    end
  end

  defp update_item(item, "sold", price) do
    case Item.update(item, %{status: :sold, sold_price: price}) do
      {:ok, _} -> {:ok, :sold}
      {:error, err} -> {:error, "#{item.id}: #{inspect(err)}"}
    end
  end

  defp update_item(item, _yaga_status, _price) do
    case Item.update(item, %{status: :uploaded_to_yaga}) do
      {:ok, _} -> {:ok, :uploaded_to_yaga}
      {:error, err} -> {:error, "#{item.id}: #{inspect(err)}"}
    end
  end
end
