defmodule CertStats.FetcherTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias CertStats.Fetcher
  alias CSTest.{MockWatchdog, MockMethod, MockStatsd}

  test "fetcher retrieves cert repeatedly" do
    {:ok, fetcher, _} = setup_fetcher(:test, :test_repeat_cert, initial_ms: 1, repeat_ms: 20)
    assert MockStatsd.next_call(fetcher) == {:record_cert, CSTest.MockMethod, :test_repeat_cert}
    assert MockStatsd.next_call(fetcher) == {:record_cert, CSTest.MockMethod, :test_repeat_cert}
    assert MockStatsd.next_call(fetcher) == {:record_cert, CSTest.MockMethod, :test_repeat_cert}
  end

  test "fetcher handles timeout ranges" do
    {:ok, fetcher, _} =
      setup_fetcher(:test, :test_range_cert, initial_ms: 1..50, repeat_ms: 20..50)

    assert MockStatsd.next_call(fetcher) == {:record_cert, CSTest.MockMethod, :test_range_cert}
    assert MockStatsd.next_call(fetcher) == {:record_cert, CSTest.MockMethod, :test_range_cert}
    assert MockStatsd.next_call(fetcher) == {:record_cert, CSTest.MockMethod, :test_range_cert}
  end

  test "fetcher waits for initial delay before first retrieval" do
    {:ok, fetcher, _} = setup_fetcher(:test, :test_cert, initial_ms: 1_000)
    assert MockStatsd.next_call(fetcher, 200) == :timeout
  end

  test "fetcher waits for repeat delay before next retrieval" do
    {:ok, fetcher, _} = setup_fetcher(:test, :test_cert, initial_ms: 1, repeat_ms: 1_000)
    assert MockStatsd.next_call(fetcher) == {:record_cert, CSTest.MockMethod, :test_cert}
    assert MockStatsd.next_call(fetcher, 200) == :timeout
  end

  test "fetcher registers with watchdog at start" do
    {:ok, watchdog} = setup_watchdog()
    setup_fetcher(:some_id, :test_cert, watchdog: watchdog)
    assert {:register, "mock-some_id", _} = MockWatchdog.next_message(watchdog)
  end

  test "fetcher records succesful fetches with watchdog" do
    {:ok, watchdog} = setup_watchdog()

    {:ok, _, ref} =
      setup_fetcher(:on_off, :cert, watchdog: watchdog, initial_ms: 20, repeat_ms: 20)

    # We get registration + repeated successes:
    assert {:register, "mock-on_off", _} = MockWatchdog.next_message(watchdog)
    assert {:success, "mock-on_off", _} = MockWatchdog.next_message(watchdog, 100)
    assert {:success, "mock-on_off", _} = MockWatchdog.next_message(watchdog, 100)
    assert {:success, "mock-on_off", _} = MockWatchdog.next_message(watchdog, 100)

    log =
      capture_log(fn ->
        # Now fetches will fail:
        mock_method_return(ref, {:error, :some_error})
        MockWatchdog.flush_messages(watchdog)

        # No messages for at least 100ms.
        assert catch_exit(MockWatchdog.next_message(watchdog, 100))

        # Now fetches will succeed again:
        mock_method_return(ref, {:ok, :cert})
      end)

    assert {:success, "mock-on_off", _} = MockWatchdog.next_message(watchdog, 100)
    assert {:success, "mock-on_off", _} = MockWatchdog.next_message(watchdog, 100)
    assert {:success, "mock-on_off", _} = MockWatchdog.next_message(watchdog, 100)

    assert log =~ "Failed to retrieve \"mock-on_off\" cert: :some_error"
  end

  defp setup_fetcher(id, cert, opts) do
    opts = [statsd: {:stub, self()}] ++ opts
    ref = MockMethod.test_setup({:ok, cert})

    {:ok, pid} =
      start_supervised(
        {Fetcher, [:mock, {id, ref}, opts]},
        restart: :temporary
      )

    {:ok, pid, ref}
  end

  defp mock_method_return(ref, rval) do
    MockMethod.test_replace(ref, rval)
  end

  defp setup_watchdog do
    start_supervised(MockWatchdog)
  end
end
