defmodule KirbsWeb.Company do
  @moduledoc """
  Company details shown in the storefront footer and the legal pages.

  The company is not VAT-registered, so no VAT number is shown. Any value can be overridden
  via `config :kirbs, :company, registry_code: "...", ...`.
  """

  @defaults %{
    name: "Kirbs OÜ",
    registry_code: "17423176",
    address: "Kuuseheki tn 50-9, Saue linn, 76505 Saue vald, Harju maakond",
    office_address: "Kasesalu 12, Saue linn",
    email: "kirbs@krister.ee"
  }

  def details do
    Map.merge(@defaults, Map.new(Application.get_env(:kirbs, :company, [])))
  end
end
