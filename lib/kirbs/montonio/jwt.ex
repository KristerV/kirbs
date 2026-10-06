defmodule Kirbs.Montonio.Jwt do
  @moduledoc "HS256 JWT signing and verification with the Montonio secret key (JOSE)."

  @leeway 300

  @doc "Signs claims, adding `iat` and `exp` (now + ttl seconds)."
  def sign(claims, ttl_seconds) when is_map(claims) do
    now = System.os_time(:second)
    claims = Map.merge(claims, %{"iat" => now, "exp" => now + ttl_seconds})
    jwk = JOSE.JWK.from_oct(Kirbs.Montonio.Config.secret_key())
    jws = %{"alg" => "HS256", "typ" => "JWT"}

    {_, token} = jwk |> JOSE.JWT.sign(jws, claims) |> JOSE.JWS.compact()
    token
  end

  @doc "Verifies signature (HS256 only) and expiry. Returns `{:ok, claims}` or `{:error, reason}`."
  def verify(token) when is_binary(token) do
    jwk = JOSE.JWK.from_oct(Kirbs.Montonio.Config.secret_key())

    case JOSE.JWT.verify_strict(jwk, ["HS256"], token) do
      {true, %JOSE.JWT{fields: claims}, _jws} -> check_expiry(claims)
      _ -> {:error, :invalid_signature}
    end
  rescue
    _ -> {:error, :malformed_token}
  end

  def verify(_), do: {:error, :malformed_token}

  defp check_expiry(%{"exp" => exp} = claims) when is_number(exp) do
    if exp + @leeway >= System.os_time(:second), do: {:ok, claims}, else: {:error, :expired}
  end

  defp check_expiry(_claims), do: {:error, :missing_expiry}
end
