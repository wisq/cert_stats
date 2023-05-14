defmodule CertStats do
  use Application

  @spec start(Application.start_type(), term) ::
          {:ok, pid()} | {:ok, pid(), Application.state()} | {:error, reason :: term()}
  @impl true
  def start(_type, _args) do
    children =
      [
        CertStats.Statsd,
        CertStats.Resolver,
        CertStats.Watchdog
      ] ++ agent_children()

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  defp agent_children do
    Application.get_env(:cert_stats, :agents, [])
    |> Enum.map(fn {agent, args} ->
      CertStats.Agent.child_spec(agent, args)
    end)
  end
end
