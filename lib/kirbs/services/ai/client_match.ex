defmodule Kirbs.Services.Ai.ClientMatch do
  @moduledoc """
  Finds existing client by phone or creates a new one.
  """

  alias Kirbs.Resources.Client

  def run(%{phone: phone} = extracted_info) when not is_nil(phone) do
    with {:ok, client} <- find_or_create_client(extracted_info) do
      {:ok, client}
    end
  end

  def run(_), do: {:error, "Phone number is required"}

  defp find_or_create_client(%{phone: phone} = info) do
    case Client.find_by_phone(phone) do
      {:ok, client} ->
        {:ok, client}

      {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{} | _]}} ->
        create_client(info)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_client(%{name: name, phone: phone, email: email, iban: iban}) do
    Ash.create(Client, %{
      name: name || "Unknown",
      phone: phone,
      email: email,
      iban: iban
    })
  end
end
