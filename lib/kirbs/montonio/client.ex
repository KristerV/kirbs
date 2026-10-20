defmodule Kirbs.Montonio.Client do
  @moduledoc "Builds Req clients for the Stargate (payments) and Shipping APIs."

  alias Kirbs.Montonio.{Config, Jwt}

  @shipping_token_ttl 3600

  @doc "Client for the Stargate API. Request bodies carry their own JWT (`%{data: jwt}`)."
  def stargate do
    Req.new(base_url: Config.stargate_base_url(), retry: false)
    |> Req.merge(Config.req_options())
  end

  @doc "Client for the Shipping API with a bearer JWT (accessKey claim, 1h)."
  def shipping do
    token = Jwt.sign(%{"accessKey" => Config.access_key()}, @shipping_token_ttl)

    Req.new(base_url: Config.shipping_base_url(), auth: {:bearer, token}, retry: false)
    |> Req.merge(Config.req_options())
  end

  @doc "Normalises a Req result into `{:ok, body}` or `{:error, reason}`."
  def handle({:ok, %Req.Response{status: status, body: body}}) when status in 200..299,
    do: {:ok, body}

  def handle({:ok, %Req.Response{status: status, body: body}}),
    do: {:error, {:http_error, status, body}}

  def handle({:error, reason}), do: {:error, {:request_failed, reason}}
end
