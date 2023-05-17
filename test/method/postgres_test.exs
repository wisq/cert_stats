defmodule CertStats.Method.PostgresTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias CertStats.Method.Postgres
  alias CSTest.MockPostgres

  @localhost {127, 0, 0, 1}

  test "fetches valid certificate" do
    {suite, port} = setup_test_server()

    assert {:ok, cert} =
             Postgres.init(host: "valid.#{suite.domain}", port: port, timeout: 1000)
             |> Postgres.fetch_cert()

    assert cert == suite.valid
  end

  test "fetches expired certificate" do
    {suite, port} = setup_test_server()

    assert {:ok, cert} =
             Postgres.init(host: "expired.#{suite.domain}", port: port)
             |> Postgres.fetch_cert()

    assert cert == suite.expired
  end

  test "handles unknown domain" do
    {suite, port} = setup_test_server(domain: "nonexistent.wisq.org")

    assert {{:error, :domain_not_found}, log} =
             with_log(fn ->
               Postgres.init(host: "valid.#{suite.domain}", port: port)
               |> Postgres.fetch_cert()
             end)

    assert log =~ ":nxdomain"
  end

  test "handles connection refused" do
    assert {:error, :econnrefused} =
             Postgres.init(host: "localhost", port: closed_tcp_port())
             |> Postgres.fetch_cert()
  end

  test "handles connection timeout" do
    assert {:error, :timeout} =
             Postgres.init(host: "example.org", port: 9999, timeout: 100)
             |> Postgres.fetch_cert()
  end

  test "handles no response from server" do
    assert {:error, :timeout} =
             Postgres.init(host: "localhost", port: stalling_tcp_port(), timeout: 100)
             |> Postgres.fetch_cert()
  end

  test "handles TLS disabled on server" do
    port = setup_mock_pg(tls_mode: :disabled)

    assert {:error, :tls_not_enabled} =
             Postgres.init(host: "localhost", port: port, timeout: 100)
             |> Postgres.fetch_cert()
  end

  test "handles TLS stalling after server accepts startTLS request" do
    port = setup_mock_pg(tls_mode: :stall)

    assert {:error, :timeout} =
             Postgres.init(host: "localhost", port: port, timeout: 100)
             |> Postgres.fetch_cert()
  end

  test "can override target IP" do
    {suite, port} = setup_test_server(domain: "nonexistent.wisq.org")

    assert {:ok, cert} =
             Postgres.init(host: "valid.#{suite.domain}", ip: @localhost, port: port)
             |> Postgres.fetch_cert()

    assert cert == suite.valid
  end

  test "can override SNI host" do
    {suite, port} = setup_test_server()

    assert {:ok, cert} =
             Postgres.init(
               host: "valid.#{suite.domain}",
               cert_host: "expired.#{suite.domain}",
               port: port
             )
             |> Postgres.fetch_cert()

    assert cert == suite.expired
  end

  defp setup_test_server(suite_opts \\ [], pg_opts \\ []) do
    suite = setup_suite(suite_opts)
    port = setup_mock_pg(pg_opts, suite)
    {suite, port}
  end

  defp setup_suite(opts) do
    opts = Keyword.put_new(opts, :key_type, {:ec, :sect113r1})
    X509.Test.Suite.new(opts)
  end

  defp setup_mock_pg(opts, suite \\ nil) do
    {:ok, pid} = start_supervised({MockPostgres, {suite, opts}})
    MockPostgres.get_port(pid)
  end

  defp closed_tcp_port do
    # Firing up a TCP listener and then immediately closing it
    # should guarantee us that the port in question is closed.
    {:ok, socket} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end

  defp stalling_tcp_port do
    # By opening the socket but never accepting the connection,
    # we create a socket that will get past the TCP connect phase,
    # but stall in the SSL negotiation phase.
    {:ok, socket} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(socket)
    on_exit(fn -> :gen_tcp.close(socket) end)
    port
  end
end
