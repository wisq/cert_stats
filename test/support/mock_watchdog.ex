defmodule CSTest.MockWatchdog do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, nil, opts)
  end

  def next_message(pid) do
    GenServer.call(pid, :next_message)
  end

  defmodule State do
    defstruct(
      messages: :queue.new(),
      waiting: nil
    )
  end

  @impl true
  def init(_) do
    {:ok, %State{}}
  end

  @impl true
  def handle_call(:next_message, from, %State{waiting: nil} = state) do
    case :queue.out(state.messages) do
      {{:value, msg}, new_msgs} -> {:reply, msg, %State{state | messages: new_msgs}}
      {:empty, _} -> {:noreply, %State{state | waiting: from}}
    end
  end

  @impl true
  def handle_cast(msg, state) do
    case state.waiting do
      nil ->
        {:noreply, %State{state | messages: :queue.in(msg, state.messages)}}

      from ->
        GenServer.reply(from, msg)
        {:noreply, %State{state | waiting: nil}}
    end
  end
end
