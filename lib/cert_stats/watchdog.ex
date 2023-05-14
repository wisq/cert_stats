defmodule CertStats.Watchdog do
  use GenServer
  require Logger

  @default_period_ms 60_000

  # To turn a timeout (milliseconds) into a deadline,
  #   add 150% (give them at least two cycles to report in)
  @deadline_fudge_factor 1.5
  #   add at least 30 secs
  @deadline_minimum 30_000

  defmodule State do
    @enforce_keys [:period_ms]
    defstruct(
      period_ms: nil,
      deadlines: %{}
    )
  end

  def start_link(opts \\ []) do
    {period_ms, opts} = Keyword.pop(opts, :period_ms, @default_period_ms)
    opts = Keyword.put_new(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, period_ms, opts)
  end

  def register(id, timeout_ms, server \\ __MODULE__) do
    GenServer.cast(server, {:register, id, to_deadline(timeout_ms)})
  end

  def success(id, timeout_ms, server \\ __MODULE__) do
    GenServer.cast(server, {:success, id, to_deadline(timeout_ms)})
  end

  defp to_deadline(ms) do
    fudge = max(ms * @deadline_fudge_factor, @deadline_minimum)

    DateTime.utc_now()
    |> DateTime.add(round(ms + fudge), :millisecond)
  end

  @impl true
  def init(period_ms) do
    Process.send_after(self(), :report, period_ms)
    {:ok, %State{period_ms: period_ms}}
  end

  @impl true
  def handle_cast({:register, id, deadline}, state) do
    {:noreply, %State{state | deadlines: Map.put_new(state.deadlines, id, deadline)}}
  end

  @impl true
  def handle_cast({:success, id, deadline}, state) do
    {:noreply, %State{state | deadlines: Map.put(state.deadlines, id, deadline)}}
  end

  @impl true
  def handle_info(:report, state) do
    now = DateTime.utc_now()
    healthy = Enum.count(state.deadlines, &is_healthy?(&1, now))
    total = Enum.count(state.deadlines)

    CertStats.Statsd.record_watchdog(healthy, total)

    Process.send_after(self(), :report, state.period_ms)
    {:noreply, state}
  end

  defp is_healthy?({_id, deadline}, now) do
    DateTime.compare(deadline, now) == :gt
  end
end
