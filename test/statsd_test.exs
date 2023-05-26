defmodule CertStats.StatsdTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias CertStats.Statsd
  alias CertStats.SSL
  alias CSTest.StatsdServer

  defmodule DummyMethod do
    def statsd_tag, do: "dummy"
  end

  test "records cert details to statsd" do
    {mock, statsd} = setup_mock_statsd()
    cert = example_cert(:valid)

    log =
      capture_log(fn ->
        Statsd.record_cert(DummyMethod, cert, statsd)
      end)

    # Received as a single (batched) packet.
    assert [
             {:g, {"tls.cert.created", created}, tags},
             {:g, {"tls.cert.expires", expires}, tags}
           ] = StatsdServer.next_message(mock)

    # Created just now:
    assert_in_delta String.to_float(created), 0.0, 0.01
    # Expires in 395 days:
    assert_in_delta String.to_float(expires), 395.0, 0.01

    assert log =~ SSL.common_name(cert)
    assert log =~ "in 395 days"
  end

  test "records watchdog percentage successful" do
    {mock, statsd} = setup_mock_statsd()

    log = capture_log(fn -> Statsd.record_watchdog(5, 5, statsd) end)

    assert [{:g, {"tls.cert.success_rate", rate}, []}] = StatsdServer.next_message(mock)
    assert_in_delta String.to_float(rate), 100.0, 0.001

    assert log =~ "[info]"
    assert log =~ "100%"
  end

  test "warns when watchdog rate is below 100%" do
    {mock, statsd} = setup_mock_statsd()

    log = capture_log(fn -> Statsd.record_watchdog(3, 9, statsd) end)

    assert [{:g, {"tls.cert.success_rate", rate}, []}] = StatsdServer.next_message(mock)
    assert_in_delta String.to_float(rate), 33.333, 0.001

    assert log =~ "[warning]"
    assert log =~ "33%"
  end

  defp setup_mock_statsd do
    {:ok, mock} = start_supervised(StatsdServer)
    port = StatsdServer.get_port(mock)
    {:ok, statsd} = start_supervised({Statsd, port: port})

    {mock, statsd}
  end

  defp example_cert(key) do
    suite = X509.Test.Suite.new(key_type: {:ec, :sect113r1})
    Map.fetch!(suite, key)
  end
end
