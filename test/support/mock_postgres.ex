# Very loosely based on X509.Test.Server.
#
# I've chosen to do some things differently,
# e.g. avoiding using the undocumented :prim_inet API.
defmodule CSTest.MockPostgres do
  use GenServer, restart: :temporary

  def start_link({suite, opts}) do
    {tls_mode, opts} = Keyword.pop(opts, :tls_mode, :enabled)
    GenServer.start_link(__MODULE__, {suite, tls_mode}, opts)
  end

  def get_port(pid) do
    GenServer.call(pid, :get_port)
  end

  defmodule State do
    @enforce_keys [:suite, :listener, :tls_mode]
    defstruct(
      suite: nil,
      listener: nil,
      tls_mode: nil
    )
  end

  @impl true
  def init({suite, tls_mode}) do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, {:active, false}])
    async_accept(listener)

    {:ok,
     %State{
       suite: suite,
       listener: listener,
       tls_mode: tls_mode
     }}
  end

  @impl true
  def handle_call(:get_port, _from, state) do
    {:ok, port} = :inet.port(state.listener)
    {:reply, port, state}
  end

  defp async_accept(listener) do
    server = self()

    spawn_link(fn ->
      result = :gen_tcp.accept(listener)

      case result do
        {:ok, socket} -> :gen_tcp.controlling_process(socket, server)
        _ -> :noop
      end

      send(server, {:gen_tcp_accept, result})
    end)
  end

  @impl true
  def handle_info({:gen_tcp_accept, {:ok, socket}}, state) do
    handle_connection(socket, state.suite, state.tls_mode)
    async_accept(state.listener)
    {:noreply, state}
  end

  defp handle_connection(socket, suite, tls_mode) do
    pid =
      spawn_link(fn ->
        receive do
          :start -> worker(socket, suite, tls_mode)
        after
          250 -> :gen_tcp.close(socket)
        end
      end)

    :gen_tcp.controlling_process(socket, pid)
    send(pid, :start)
  end

  defp worker(socket, suite, tls_mode) do
    {:ok, <<0, 0, 0, 8, 4, 210, 22, 47>>} = :gen_tcp.recv(socket, 0, 500)

    case tls_mode do
      :enabled ->
        :gen_tcp.send(socket, "S")
        negotiate_ssl(socket, suite)
        Process.sleep(100)
        :gen_tcp.close(socket)

      :disabled ->
        :gen_tcp.send(socket, "N")
        Process.sleep(100)
        :gen_tcp.close(socket)

      :stall ->
        # pretend to accept, but no followup
        :gen_tcp.send(socket, "S")
        Process.sleep(1000)
        :gen_tcp.close(socket)
    end
  end

  defp negotiate_ssl(socket, suite) do
    opts =
      [
        active: false,
        sni_fun: X509.Test.Suite.sni_fun(suite),
        reuse_sessions: false
      ] ++ X509.Test.Server.log_opts()

    case :ssl.handshake(socket, opts, 1000) do
      {:ok, ssl_socket} ->
        Process.sleep(100)
        :ssl.close(ssl_socket)

      {:error, _reason} ->
        :gen_tcp.close(socket)
    end
  end
end
