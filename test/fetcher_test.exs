defmodule CertStats.FetcherTest do
  use ExUnit.Case, async: true

  alias CertStats.Fetcher
  alias CSTest.MockWatchdog

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
    setup_fetcher(:success, :test_success_cert, watchdog: watchdog, initial_ms: 1, repeat_ms: 1)
    assert {:register, "mock-success", _} = MockWatchdog.next_message(watchdog)

    assert next_record_cert(100) == {:ok, CSTest.MockMethod, :test_success_cert}
    assert {:success, "mock-success", _} = MockWatchdog.next_message(watchdog)
    assert next_record_cert(100) == {:ok, CSTest.MockMethod, :test_success_cert}
    assert {:success, "mock-success", _} = MockWatchdog.next_message(watchdog)
    assert next_record_cert(100) == {:ok, CSTest.MockMethod, :test_success_cert}
    assert {:success, "mock-success", _} = MockWatchdog.next_message(watchdog)
  end

  defp setup_fetcher(id, cert, opts) do
    opts = [statsd: {:stub, self()}] ++ opts

    start_supervised(
      {Fetcher, [:mock, {id, cert}, opts]},
      restart: :temporary
    )
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
