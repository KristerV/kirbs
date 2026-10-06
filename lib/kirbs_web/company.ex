defmodule KirbsWeb.Company do
  @moduledoc """
  Company details shown in the storefront footer and the legal pages.

  The owner must fill in the registry code, VAT number, address and contact email, either here
  or via `config :kirbs, :company, registry_code: "...", ...`. Until then the clearly marked
  `TODO` placeholders are rendered so they cannot be missed.
  """

  @defaults %{
    name: "Täp OÜ",
    registry_code: "TODO registrikood",
    vat_number: "TODO KMKR number (kui käibemaksukohustuslane)",
    address: "TODO aadress",
    email: "TODO tellimused@kirbs.ee"
  }

  def details do
    Map.merge(@defaults, Map.new(Application.get_env(:kirbs, :company, [])))
  end
end
