defmodule MelodyStudio.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MelodyStudioWeb.Telemetry,
      MelodyStudio.Repo,
      {Oban, Application.fetch_env!(:melody_studio, Oban)},
      {DNSCluster, query: Application.get_env(:melody_studio, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: MelodyStudio.PubSub},
      # Start a worker by calling: MelodyStudio.Worker.start_link(arg)
      # {MelodyStudio.Worker, arg},
      # Start to serve requests, typically the last entry
      MelodyStudioWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MelodyStudio.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MelodyStudioWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
