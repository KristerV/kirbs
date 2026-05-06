defmodule Kirbs.Services.Yaga.Withdraw do
  @moduledoc """
  Withdraws all `availableForPayout` funds from the Yaga wallet to the
  linked bank account.

  Two-step:

    1. `GET /wallet/account/self` → read `availableForPayout`.
    2. `POST /api/user/withdraw` with `{ withdrawalAmount: N }`.

  `availableForPayout` is post-escrow money — the same pool that
  `SoldChecker` treats as "really ours". `pending_amount` (in-escrow buyer
  payments) is intentionally excluded.

  Returns:

    * `{:ok, %{withdrawn: amount}}` on success
    * `{:ok, :nothing_to_withdraw}` when balance is 0
    * `{:error, reason}` otherwise
  """

  alias Kirbs.Services.Yaga.Auth

  @base_url "https://www.yaga.ee"

  def run do
    with {:ok, jwt} <- Auth.run(),
         {:ok, available} <- fetch_available(jwt),
         {:ok, result} <- maybe_withdraw(jwt, available) do
      {:ok, result}
    end
  end

  defp fetch_available(jwt) do
    case Req.get("#{@base_url}/wallet/account/self", headers: headers(jwt)) do
      {:ok, %{status: 200, body: %{"status" => "success", "data" => data}}} ->
        {:ok, to_decimal(data["availableForPayout"])}

      {:ok, %{status: status, body: body}} ->
        {:error, "Failed to fetch wallet: HTTP #{status} - #{inspect(body)}"}

      {:error, error} ->
        {:error, "Network error fetching wallet: #{inspect(error)}"}
    end
  end

  defp maybe_withdraw(_jwt, amount) do
    if Decimal.compare(amount, Decimal.new(0)) in [:eq, :lt] do
      {:ok, :nothing_to_withdraw}
    else
      do_withdraw(amount)
    end
  end

  defp do_withdraw(amount) do
    {:ok, jwt} = Auth.run()

    body = %{withdrawalAmount: amount}

    case Req.post("#{@base_url}/api/user/withdraw", headers: headers(jwt), json: body) do
      {:ok, %{status: 200, body: %{"status" => "success"}}} ->
        {:ok, %{withdrawn: amount}}

      {:ok, %{status: status, body: body}} ->
        {:error, "Withdraw failed: HTTP #{status} - #{inspect(body)}"}

      {:error, error} ->
        {:error, "Network error during withdraw: #{inspect(error)}"}
    end
  end

  defp headers(jwt) do
    [
      {"authorization", "Bearer #{jwt}"},
      {"x-language", "et"},
      {"x-country", "EE"},
      {"accept", "application/json"}
    ]
  end

  defp to_decimal(nil), do: Decimal.new(0)
  defp to_decimal(n) when is_integer(n), do: Decimal.new(n)
  defp to_decimal(n) when is_float(n), do: Decimal.from_float(n)

  defp to_decimal(n) when is_binary(n) do
    case Decimal.parse(n) do
      {d, _} -> d
      :error -> Decimal.new(0)
    end
  end
end
