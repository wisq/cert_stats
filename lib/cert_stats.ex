defmodule CertStats do
  use Application

  @spec start(Application.start_type(), term) ::
          {:ok, pid()} | {:ok, pid(), Application.state()} | {:error, reason :: term()}
  @impl true
  def start(_type, _args) do
    children =
      [
        enabled?(:statsd) && CertStats.Statsd,
        enabled?(:resolver) && CertStats.Resolver,
        enabled?(:watchdog) && CertStats.Watchdog
      ]
      |> Enum.reject(&is_nil/1)

    Supervisor.start_link(children ++ agent_children(), strategy: :one_for_one)
  end

  defp agent_children do
    Application.get_env(:cert_stats, :agents, [])
    |> Enum.map(fn {agent, args} ->
      CertStats.Agent.child_spec(agent, args)
    end)
  end

  defp enabled?(key) do
    case Application.get_env(:cert_stats, key, true) do
      false -> nil
      _ -> true
    end
  end
end
