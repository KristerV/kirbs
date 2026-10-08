defmodule Kirbs.Montonio.RedactPayload do
  @moduledoc """
  Makes a verified JWT claim map / API response safe to persist: string-keys it (JSON friendly)
  and replaces values of secret-looking keys (keys, tokens, secrets, signatures, passwords).
  """

  @secret ~r/secret|token|password|signature|access_?key|api_?key|authorization/i

  def run(map) when is_map(map) and not is_struct(map) do
    Map.new(map, fn {key, value} ->
      key = to_string(key)
      {key, if(Regex.match?(@secret, key), do: "[redacted]", else: run(value))}
    end)
  end

  def run(list) when is_list(list), do: Enum.map(list, &run/1)
  def run(value) when is_atom(value) and value not in [nil, true, false], do: to_string(value)
  def run(value), do: value
end
