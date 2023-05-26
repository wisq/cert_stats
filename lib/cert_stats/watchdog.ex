defmodule CertStats.Watchdog do
  use GenServer
  require Logger

  @default_period_ms 60_000
  @default_statsd CertStats.Statsd.default_name()

  # To turn a timeout (milliseconds) into a deadline,
  #   add 150% (give them at least two cycles to report in)
  @default_deadline_fudge_factor 1.5
  #   add at least 30 secs
  @default_deadline_minimum 30_000

  defmodule State do
    @enforce_keys [:period_ms, :deadline_fudge_factor, :deadline_minimum, :statsd]
    defstruct(
      period_ms: nil,
      deadlines: %{},
      deadline_fudge_factor: nil,
      deadline_minimum: nil,
      statsd: nil
    )
  end

  def default_name, do: __MODULE__

  def start_link(opts \\ []) do
    {period_ms, opts} = Keyword.pop(opts, :period_ms, @default_period_ms)
    {statsd, opts} = Keyword.pop(opts, :statsd, @default_statsd)
    {dead_fudge, opts} = Keyword.pop(opts, :deadline_fudge_factor, @default_deadline_fudge_factor)
    {dead_min, opts} = Keyword.pop(opts, :deadline_minimum, @default_deadline_minimum)

    opts = Keyword.put_new(opts, :name, default_name())

    state = %State{
      period_ms: period_ms,
      deadline_fudge_factor: dead_fudge,
      deadline_minimum: dead_min,
      statsd: statsd
    }

    GenServer.start_link(__MODULE__, state, opts)
  end

  def register(id, timeout_ms, server \\ default_name()) do
    GenServer.cast(server, {:register, id, timeout_ms})
  end

  def success(id, timeout_ms, server \\ default_name()) do
    GenServer.cast(server, {:success, id, timeout_ms})
  end

  @impl true
  def init(%State{} = state) do
    Process.send_after(self(), :report, state.period_ms)
    {:ok, state}
  end

  @impl true
  def handle_cast({:register, id, ms}, state) do
    deadline = to_deadline(ms, state)
    {:noreply, %State{state | deadlines: Map.put_new(state.deadlines, id, deadline)}}
  end

  @impl true
  def handle_cast({:success, id, ms}, state) do
    deadline = to_deadline(ms, state)
    {:noreply, %State{state | deadlines: Map.put(state.deadlines, id, deadline)}}
  end

  @impl true
  def handle_info(:report, state) do
    now = DateTime.utc_now()
    healthy = Enum.count(state.deadlines, &is_healthy?(&1, now))
    total = Enum.count(state.deadlines)

    CertStats.Statsd.record_watchdog(healthy, total, state.statsd)

    Process.send_after(self(), :report, state.period_ms)
    {:noreply, state}
  end

  defp to_deadline(ms, state) do
    fudge = max(ms * state.deadline_fudge_factor, state.deadline_minimum)

    DateTime.utc_now()
    |> DateTime.add(round(ms + fudge), :millisecond)
  end

  defp is_healthy?({_id, deadline}, now) do
    DateTime.compare(deadline, now) == :gt
  end
end
