defmodule CertStats.FetcherTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias CertStats.Fetcher
  alias CSTest.MockWatchdog
  alias CSTest.MockMethod

  test "fetcher retrieves cert repeatedly" do
    setup_fetcher(:test, :test_repeat_cert, initial_ms: 1, repeat_ms: 20)
    assert next_record_cert(100) == {:ok, CSTest.MockMethod, :test_repeat_cert}
    assert next_record_cert(100) == {:ok, CSTest.MockMethod, :test_repeat_cert}
    assert next_record_cert(100) == {:ok, CSTest.MockMethod, :test_repeat_cert}
  end

  test "fetcher handles timeout ranges" do
    setup_fetcher(:test, :test_range_cert, initial_ms: 1..50, repeat_ms: 20..50)
    assert next_record_cert(100) == {:ok, CSTest.MockMethod, :test_range_cert}
    assert next_record_cert(100) == {:ok, CSTest.MockMethod, :test_range_cert}
    assert next_record_cert(100) == {:ok, CSTest.MockMethod, :test_range_cert}
  end

  test "fetcher waits for initial delay before first retrieval" do
    setup_fetcher(:test, :test_cert, initial_ms: 1_000)
    assert next_record_cert(200) == {:error, :timeout}
  end

  test "fetcher waits for repeat delay before next retrieval" do
    setup_fetcher(:test, :test_cert, initial_ms: 1, repeat_ms: 1_000)
    assert next_record_cert() == {:ok, CSTest.MockMethod, :test_cert}
    assert next_record_cert(200) == {:error, :timeout}
  end

  test "fetcher registers with watchdog at start" do
    {:ok, watchdog} = setup_watchdog()
    setup_fetcher(:some_id, :test_cert, watchdog: watchdog)
    assert {:register, "mock-some_id", _} = MockWatchdog.next_message(watchdog)
  end

  test "fetcher records succesful fetches with watchdog" do
    {:ok, watchdog} = setup_watchdog()
    table = setup_fetcher(:on_off, :cert, watchdog: watchdog, initial_ms: 20, repeat_ms: 20)

    # We get registration + repeated successes:
    assert {:register, "mock-on_off", _} = MockWatchdog.next_message(watchdog)
    assert {:success, "mock-on_off", _} = MockWatchdog.next_message(watchdog, 100)
    assert {:success, "mock-on_off", _} = MockWatchdog.next_message(watchdog, 100)
    assert {:success, "mock-on_off", _} = MockWatchdog.next_message(watchdog, 100)

    log =
      capture_log(fn ->
        # Now fetches will fail:
        mock_method_return(table, {:error, :some_error})
        MockWatchdog.flush_messages(watchdog)

        # No messages for at least 100ms.
        assert catch_exit(MockWatchdog.next_message(watchdog, 100))

        # Now fetches will succeed again:
        mock_method_return(table, {:ok, :cert})
      end)

    assert {:success, "mock-on_off", _} = MockWatchdog.next_message(watchdog, 100)
    assert {:success, "mock-on_off", _} = MockWatchdog.next_message(watchdog, 100)
    assert {:success, "mock-on_off", _} = MockWatchdog.next_message(watchdog, 100)

    assert log =~ "Failed to retrieve \"mock-on_off\" cert: :some_error"
  end

  defp setup_fetcher(id, cert, opts) do
    opts = [statsd: {:stub, self()}] ++ opts
    ref = MockMethod.test_setup({:ok, cert})

    {:ok, _pid} =
      start_supervised(
        {Fetcher, [:mock, {id, ref}, opts]},
        restart: :temporary
      )

    ref
  end

  defp mock_method_return(ref, rval) do
    MockMethod.test_replace(ref, rval)
  end

  defp setup_watchdog do
    start_supervised(MockWatchdog, restart: :temporary)
  end

  defp next_record_cert(timeout \\ 5000) do
    receive do
      {:record_cert, module, cert} -> {:ok, module, cert}
    after
      timeout -> {:error, :timeout}
    end
  end
end
