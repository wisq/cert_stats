defmodule CertStats.Agent do
  alias __MODULE__

  defp module(:static), do: Agent.Static
  defp module(:certbot), do: Agent.Certbot
  defp module(key), do: raise(ArgumentError, "Method not found: #{inspect(key)}")

  def child_spec(method, opts) do
    module(method).child_spec(opts)
  end

  @type opts :: term
  @callback child_spec(opts) :: Supervisor.child_spec()
end
