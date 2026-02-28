defmodule Kirbs.Services.Ai.ClientMatch do
  @moduledoc """
  Finds existing client by phone, email, iban, or name — or creates a new one.
  """

  alias Kirbs.Resources.Client

  def run(info) do
    with :not_found <- find_by(:phone, info[:phone]),
         :not_found <- find_by(:email, info[:email]),
         :not_found <- find_by(:iban, info[:iban]),
         :not_found <- find_by(:name, info[:name]) do
      create_client(info)
    end
  end

  defp find_by(_field, nil), do: :not_found

  defp find_by(:phone, phone), do: not_found_to_atom(Client.find_by_phone(phone))
  defp find_by(:email, email), do: not_found_to_atom(Client.find_by_email(email))
  defp find_by(:iban, iban), do: not_found_to_atom(Client.find_by_iban(iban))
  defp find_by(:name, name), do: not_found_to_atom(Client.find_by_name(name))

  defp not_found_to_atom({:ok, client}), do: {:ok, client}
  defp not_found_to_atom({:error, _}), do: :not_found

  defp create_client(info) do
    attrs = %{
      name: info[:name],
      phone: info[:phone],
      email: info[:email],
      iban: info[:iban]
    }

    if Enum.all?(Map.values(attrs), &is_nil/1) do
      {:error, "Cannot create client with no information"}
    else
      case Ash.create(Client, attrs) do
        {:ok, client} -> {:ok, client}
        {:error, _} -> find_existing(info)
      end
    end
  end

  defp find_existing(info) do
    with :not_found <- find_by(:phone, info[:phone]),
         :not_found <- find_by(:email, info[:email]),
         :not_found <- find_by(:iban, info[:iban]),
         :not_found <- find_by(:name, info[:name]) do
      {:error, "Client could not be created or found"}
    end
  end
end
