defmodule CertStats.Fetcher do
  use GenServer
  require Logger

  @default_initial_ms 60_000..90_000
  @default_repeat_ms 270_000..330_000

  def child_spec([method, method_opts, fetcher_opts]) do
    {watchdog_id, _module, _config} = arg0 = CertStats.Method.configure(method, method_opts)

    %{
      id: :"fetcher_#{watchdog_id}",
      start: {__MODULE__, :start_link, [arg0, fetcher_opts]}
    }
  end

  defmodule State do
    @enforce_keys [:watchdog_id, :initial_ms, :repeat_ms, :module, :config]
    defstruct(
      watchdog_id: nil,
      initial_ms: nil,
      repeat_ms: nil,
      module: nil,
      config: nil
    )
  end

  def start_link({watchdog_id, module, config}, opts \\ []) do
    {initial_ms, opts} = Keyword.pop(opts, :initial_ms, @default_initial_ms)
    {repeat_ms, opts} = Keyword.pop(opts, :repeat_ms, @default_repeat_ms)

    state = %State{
      watchdog_id: watchdog_id,
      initial_ms: initial_ms,
      repeat_ms: repeat_ms,
      module: module,
      config: config
    }

    GenServer.start_link(__MODULE__, state, opts)
  end

  @impl true
  def init(%State{} = state) do
    CertStats.Watchdog.register(state.watchdog_id, max_timeout(state.initial_ms))
    {:ok, state, random_timeout(state.initial_ms)}
  end

  @impl true
  def handle_info(:timeout, state) do
    {:ok, cert} = state.module.fetch_cert(state.config)
    CertStats.Statsd.record_cert(state.module, cert)
    CertStats.Watchdog.success(state.watchdog_id, max_timeout(state.repeat_ms))
    {:noreply, state, random_timeout(state.repeat_ms)}
  end

  defp random_timeout(%Range{} = r), do: Enum.random(r)
  defp random_timeout(i) when is_integer(i), do: i

  defp max_timeout(%Range{last: i}), do: i
  defp max_timeout(i) when is_integer(i), do: i
end
