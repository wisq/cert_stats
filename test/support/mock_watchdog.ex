defmodule CSTest.MockWatchdog do
  use GenServer

  def child_spec(_) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []}
    }
  end

  def start_link do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def register(id, timeout_ms) do
    GenServer.cast(__MODULE__, {:register, self(), id, timeout_ms})
  end

  def success(id, timeout_ms) do
    GenServer.cast(__MODULE__, {:success, self(), id, timeout_ms})
  end

  def next_call(pid, timeout \\ 1000) do
    try do
      GenServer.call(__MODULE__, {:next_call, pid}, timeout)
    catch
      :exit, {:timeout, _} -> :timeout
    end
  end

  def flush_messages(pid) do
    GenServer.cast(__MODULE__, {:flush_messages, pid})
  end

  defmodule State do
    @enforce_keys [:init]
    defstruct(
      init: nil,
      messages: %{},
      waiting: %{}
    )
  end

  @impl true
  def init(nil) do
    {:ok, %State{init: true}}
  end

  @impl true
  def handle_cast({:register, pid, id, timeout_ms}, state) do
    forward_or_queue(pid, {:register, id, timeout_ms}, state)
  end

  @impl true
  def handle_cast({:success, pid, id, timeout_ms}, state) do
    forward_or_queue(pid, {:success, id, timeout_ms}, state)
  end

  @impl true
  def handle_cast({:flush_messages, pid}, state) do
    {:noreply, %State{state | messages: state.messages |> Map.delete(pid)}}
  end

  @impl true
  def handle_call({:next_call, pid}, from, state) do
    case pop_message(state.messages, pid) do
      {msg, messages} ->
        {:reply, msg, %State{state | messages: messages}}

      :no_messages ->
        {:noreply, %State{state | waiting: state.waiting |> Map.put(pid, from)}}
    end
  end

  defp forward_or_queue(pid, msg, state) do
    case Map.pop(state.waiting, pid, :not_waiting) do
      {:not_waiting, _} ->
        {:noreply, %State{state | messages: state.messages |> add_message(pid, msg)}}

      {from, waiting} ->
        GenServer.reply(from, msg)
        {:noreply, %State{state | waiting: waiting}}
    end
  end

  defp add_message(messages, pid, msg) do
    messages
    |> Map.update(pid, :queue.from_list([msg]), fn q -> :queue.in(msg, q) end)
  end

  defp pop_message(messages, pid) do
    with {:ok, queue} <- Map.fetch(messages, pid),
         {{:value, msg}, new_queue} <- :queue.out(queue) do
      {msg, Map.put(messages, pid, new_queue)}
    else
      :error -> :no_messages
      {:empty, _} -> :no_messages
    end
  end
end
