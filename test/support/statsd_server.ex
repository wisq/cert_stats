defmodule CSTest.StatsdServer do
  use GenServer, restart: :temporary

  def start_link(opts) do
    GenServer.start_link(__MODULE__, nil, opts)
  end

  def get_port(pid) do
    GenServer.call(pid, :get_port)
  end

  def next_message(pid) do
    GenServer.call(pid, :next_message)
  end

  defmodule State do
    @enforce_keys [:socket]
    defstruct(
      socket: nil,
      messages: :queue.new(),
      waiting: nil
    )
  end

  @impl true
  def init(_) do
    {:ok, socket} = :gen_udp.open(0, [:binary, {:active, true}])
    {:ok, %State{socket: socket}}
  end

  @impl true
  def handle_call(:get_port, _from, state) do
    {:ok, port} = :inet.port(state.socket)
    {:reply, port, state}
  end

  @impl true
  def handle_call(:next_message, from, %State{waiting: nil} = state) do
    case :queue.out(state.messages) do
      {{:value, msg}, new_msgs} -> {:reply, msg, %State{state | messages: new_msgs}}
      {:empty, _} -> {:noreply, %State{state | waiting: from}}
    end
  end

  @impl true
  def handle_info({:udp, _, _, _, data}, state) do
    msg = parse_statsd(data)

    case state.waiting do
      nil ->
        {:noreply, %State{state | messages: :queue.in(msg, state.messages)}}

      from ->
        GenServer.reply(from, msg)
        {:noreply, %State{state | waiting: nil}}
    end
  end

  defp parse_statsd(data) do
    String.split(data, "\n")
    |> Enum.map(&parse_statsd_line/1)
  end

  defp parse_statsd_line(line) do
    case String.split(line, "|", parts: 3) do
      [stat, type, tags] -> {String.to_atom(type), parse_stat(stat), parse_tags(tags)}
      [stat, type] -> {String.to_atom(type), parse_stat(stat), []}
    end
  end

  defp parse_stat(stat) do
    [key, value] = String.split(stat, ":", parts: 2)
    {key, value}
  end

  defp parse_tags("#" <> tags) do
    tags
    |> String.split(",")
    |> Enum.map(fn tag ->
      [k, v] = String.split(tag, ":", parts: 2)
      {String.to_atom(k), v}
    end)
  end
end
