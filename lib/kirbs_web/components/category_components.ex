defmodule KirbsWeb.CategoryComponents do
  @moduledoc "Admin form widgets for categories."
  use Phoenix.Component

  @doc """
  Checkbox list of leaf categories grouped by family, for the extra (non-primary) categories
  of an item. Submits `name[]` (an empty hidden value keeps the param present when nothing is
  checked, so clearing works). `options` is the `GroupedLeafOptions` shape.
  """
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :options, :list, required: true
  attr :selected, :list, default: []
  attr :primary_id, :string, default: nil

  def extra_categories(assigns) do
    ~H"""
    <fieldset id={@id} class="space-y-2">
      <input type="hidden" name={"#{@name}[]"} value="" />
      <div :for={{label, options} <- @options}>
        <div class="text-xs font-bold uppercase tracking-wide opacity-60">{label}</div>
        <div class="flex flex-wrap gap-x-4 gap-y-1">
          <label
            :for={{name, category_id} <- options}
            class="flex items-center gap-1.5 text-sm cursor-pointer"
          >
            <input
              id={"#{@id}-#{category_id}"}
              type="checkbox"
              name={"#{@name}[]"}
              value={category_id}
              checked={category_id in @selected and category_id != @primary_id}
              disabled={category_id == @primary_id}
              class="checkbox checkbox-sm"
            />
            {name}
          </label>
        </div>
      </div>
    </fieldset>
    """
  end
end
