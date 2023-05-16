defmodule CertStats.Method.HttpsTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias CertStats.Method.HTTPS

  @localhost {127, 0, 0, 1}

  test "fetches valid certificate" do
    {suite, port} = setup_test_server()

    assert {:ok, cert} =
             HTTPS.init(host: "valid.#{suite.domain}", port: port)
             |> HTTPS.fetch_cert()

    assert cert == suite.valid
  end

  test "fetches expired certificate" do
    {suite, port} = setup_test_server()

    assert {:ok, cert} =
             HTTPS.init(host: "expired.#{suite.domain}", port: port)
             |> HTTPS.fetch_cert()

    assert cert == suite.expired
  end

  test "handles unknown domain" do
    {suite, port} = setup_test_server(domain: "nonexistent.wisq.org")

    assert {{:error, :domain_not_found}, log} =
             with_log(fn ->
               HTTPS.init(host: "valid.#{suite.domain}", port: port)
               |> HTTPS.fetch_cert()
             end)

    assert log =~ ":nxdomain"
  end

  test "handles connection refused" do
    assert {:error, :econnrefused} =
             HTTPS.init(host: "localhost", port: closed_tcp_port())
             |> HTTPS.fetch_cert()
  end

  test "handles connection timeout" do
    assert {:error, :timeout} =
             HTTPS.init(host: "example.org", port: 9999, timeout: 100)
             |> HTTPS.fetch_cert()
  end

  test "handles stalled SSL negotiation" do
    assert {:error, :timeout} =
             HTTPS.init(host: "localhost", port: stalling_tcp_port(), timeout: 100)
             |> HTTPS.fetch_cert()
  end

  test "can override target IP" do
    {suite, port} = setup_test_server(domain: "nonexistent.wisq.org")

    assert {:ok, cert} =
             HTTPS.init(host: "valid.#{suite.domain}", ip: @localhost, port: port)
             |> HTTPS.fetch_cert()

    assert cert == suite.valid
  end

  test "can override SNI host" do
    {suite, port} = setup_test_server()

    assert {:ok, cert} =
             HTTPS.init(
               host: "valid.#{suite.domain}",
               cert_host: "expired.#{suite.domain}",
               port: port
             )
             |> HTTPS.fetch_cert()

    assert cert == suite.expired
  end

  defp setup_test_server(opts \\ []) do
    # Ran some benchmarks, and sect113r1 and r2 seem to be
    # the fastest crypto that I can use as a key type.
    opts = Keyword.put_new(opts, :key_type, {:ec, :sect113r1})
    suite = X509.Test.Suite.new(opts)
    {:ok, pid} = start_supervised({X509.Test.Server, {suite, []}})
    port = X509.Test.Server.get_port(pid)

    {suite, port}
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
