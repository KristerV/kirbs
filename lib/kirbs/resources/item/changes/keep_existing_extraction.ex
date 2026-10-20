defmodule Kirbs.Resources.Item.Changes.KeepExistingExtraction do
  @moduledoc """
  Brand, size, colors and materials are already extracted (and validated against the
  Yaga taxonomy) by the item extraction. Categorization only fills them when blank.
  """
  use Ash.Resource.Change

  @fields [:brand, :size, :colors, :materials]

  @impl true
  def change(changeset, _opts, _context) do
    Enum.reduce(@fields, changeset, fn field, acc ->
      if present?(Map.get(acc.data, field)),
        do: Ash.Changeset.clear_change(acc, field),
        else: acc
    end)
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?([]), do: false
  defp present?(_), do: true
end
