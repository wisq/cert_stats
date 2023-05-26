defmodule CertStats do
  use Application

  @spec start(Application.start_type(), term) ::
          {:ok, pid()} | {:ok, pid(), Application.state()} | {:error, reason :: term()}
  @impl true
  def start(_type, _args) do
    children = [
      statsd(),
      resolver(),
      watchdog()
    ]

    Supervisor.start_link(children ++ agent_children(), strategy: :one_for_one)
  end

  defp agent_children do
    Application.get_env(:cert_stats, :agents, [])
    |> Enum.map(fn {agent, args} ->
      CertStats.Agent.child_spec(agent, args)
    end)
  end

  @statsd Application.compile_env(:cert_stats, :statsd, CertStats.Statsd)
  @resolver Application.compile_env(:cert_stats, :resolver, CertStats.Resolver)
  @watchdog Application.compile_env(:cert_stats, :watchdog, CertStats.Watchdog)

  def statsd, do: @statsd
  def resolver, do: @resolver
  def watchdog, do: @watchdog
end
