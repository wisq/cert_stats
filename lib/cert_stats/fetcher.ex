defmodule CertStats.Fetcher do
  use GenServer
  require Logger

  @default_initial_ms 60_000..90_000
  @default_repeat_ms 270_000..330_000
  @default_statsd CertStats.Statsd.default_name()
  @default_watchdog CertStats.Watchdog.default_name()

  def child_spec([method, method_opts, fetcher_opts]) do
    {watchdog_id, _module, _config} = arg0 = CertStats.Method.configure(method, method_opts)

    %{
      id: :"fetcher_#{watchdog_id}",
      start: {__MODULE__, :start_link, [arg0, fetcher_opts]}
    }
  end

  defmodule State do
    @enforce_keys [:watchdog_id, :initial_ms, :repeat_ms, :module, :config, :statsd, :watchdog]
    defstruct(
      watchdog_id: nil,
      initial_ms: nil,
      repeat_ms: nil,
      module: nil,
      config: nil,
      statsd: nil,
      watchdog: nil
    )
  end

  def start_link({watchdog_id, module, config}, opts \\ []) do
    {initial_ms, opts} = Keyword.pop(opts, :initial_ms, @default_initial_ms)
    {repeat_ms, opts} = Keyword.pop(opts, :repeat_ms, @default_repeat_ms)
    {statsd, opts} = Keyword.pop(opts, :statsd, @default_statsd)
    {watchdog, opts} = Keyword.pop(opts, :watchdog, @default_watchdog)

    state = %State{
      watchdog_id: watchdog_id,
      initial_ms: initial_ms,
      repeat_ms: repeat_ms,
      module: module,
      config: config,
      statsd: statsd,
      watchdog: watchdog
    }

    GenServer.start_link(__MODULE__, state, opts)
  end

  @impl true
  def init(%State{} = state) do
    CertStats.Watchdog.register(state.watchdog_id, max_timeout(state.initial_ms), state.watchdog)
    {:ok, state, random_timeout(state.initial_ms)}
  end

  @impl true
  def handle_info(:timeout, state) do
    case state.module.fetch_cert(state.config) do
      {:ok, cert} ->
        CertStats.Statsd.record_cert(state.module, cert, state.statsd)

        CertStats.Watchdog.success(
          state.watchdog_id,
          max_timeout(state.repeat_ms),
          state.watchdog
        )

      {:error, err} ->
        Logger.error("Failed to retrieve #{inspect(state.watchdog_id)} cert: #{inspect(err)}")
    end

    {:noreply, state, random_timeout(state.repeat_ms)}
  end

  defp random_timeout(%Range{} = r), do: Enum.random(r)
  defp random_timeout(i) when is_integer(i), do: i

  defp max_timeout(%Range{last: i}), do: i
  defp max_timeout(i) when is_integer(i), do: i
end
