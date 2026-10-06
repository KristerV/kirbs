defmodule Kirbs.Orders.BankDetails do
  @moduledoc """
  Bank-transfer details shown to manual-payment buyers. Read from Settings
  (`shop_bank_iban`, `shop_bank_recipient`, editable on /settings), falling back to config.

  TODO(owner): the fallback IBAN is a PLACEHOLDER. Enter the real IBAN on /settings
  before accepting real orders.
  """
  alias Kirbs.Resources.Settings

  @placeholder_iban "EE00 0000 0000 0000 0000"
  @placeholder_recipient "Kirbs (TODO: omaniku nimi)"

  def get do
    %{
      iban: setting("shop_bank_iban") || config(:iban) || @placeholder_iban,
      recipient: setting("shop_bank_recipient") || config(:recipient) || @placeholder_recipient
    }
  end

  defp setting(key) do
    case Settings.get_by_key(key, not_found_error?: false) do
      {:ok, %{value: value}} when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp config(key), do: :kirbs |> Application.get_env(:bank_transfer, []) |> Keyword.get(key)
end
