defmodule CertStats.Agent.Static do
  @behaviour CertStats.Agent

  use Supervisor

  def start_link(to_watch) when is_list(to_watch) do
    Supervisor.start_link(__MODULE__, to_watch, name: __MODULE__)
  end

  @impl true
  def init(to_watch) do
    to_watch
    |> Enum.map(fn spec ->
      apply(__MODULE__, :fetcher_child_spec, spec |> Tuple.to_list())
    end)
    |> Supervisor.init(strategy: :one_for_one)
  end

  def fetcher_child_spec(method, method_opts \\ [], fetcher_opts \\ []) do
    {CertStats.Fetcher, [method, method_opts, fetcher_opts]}
  end
end
