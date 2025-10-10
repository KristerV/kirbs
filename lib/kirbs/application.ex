defmodule Kirbs.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      KirbsWeb.Telemetry,
      Kirbs.Repo,
      {DNSCluster, query: Application.get_env(:kirbs, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Kirbs.PubSub},
      # Start a worker by calling: Kirbs.Worker.start_link(arg)
      # {Kirbs.Worker, arg},
      # Start to serve requests, typically the last entry
      KirbsWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Kirbs.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    KirbsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
