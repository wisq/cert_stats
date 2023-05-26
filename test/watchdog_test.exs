defmodule CertStats.WatchdogTest do
  use ExUnit.Case, async: true

  alias CertStats.Watchdog
  alias CSTest.MockStatsd

  test "watchdog provides regular reports" do
    {:ok, watchdog} = setup_watchdog(period_ms: 20)
    assert MockStatsd.next_call(watchdog) == {:record_watchdog, 0, 0}
    assert MockStatsd.next_call(watchdog) == {:record_watchdog, 0, 0}
    assert MockStatsd.next_call(watchdog) == {:record_watchdog, 0, 0}
  end

  test "watchdog with registered client reports healthy until deadline expires" do
    {:ok, watchdog} = setup_watchdog(period_ms: 10)
    Watchdog.register(:my_id, 100, watchdog)
    assert_in_delta time_to_unhealthy(watchdog), 100, 15
  end

  test "watchdog success messages refresh deadline" do
    {:ok, watchdog} = setup_watchdog(period_ms: 10)
    Watchdog.register(:my_id, 10, watchdog)

    # Will refresh at approx [0, 30, 60], then expire at 100.
    spawn_link(fn ->
      Watchdog.success(:my_id, 40, watchdog)
      Process.sleep(30)
      Watchdog.success(:my_id, 40, watchdog)
      Process.sleep(30)
      Watchdog.success(:my_id, 40, watchdog)
    end)

    assert_in_delta time_to_unhealthy(watchdog), 100, 15
  end

  test "multiple watchdog register messages do not refresh deadline" do
    {:ok, watchdog} = setup_watchdog(period_ms: 10)
    Watchdog.register(:my_id, 100, watchdog)

    spawn_link(fn ->
      1..10
      |> Enum.each(fn _ ->
        Watchdog.register(:my_id, 100, watchdog)
        Process.sleep(30)
      end)
    end)

    assert_in_delta time_to_unhealthy(watchdog), 100, 15
  end

  test "watchdog applies a minimum deadline extension" do
    {:ok, watchdog} = setup_watchdog(period_ms: 10, deadline_minimum: 100)
    Watchdog.register(:my_id, 0, watchdog)
    assert_in_delta time_to_unhealthy(watchdog), 100, 15
  end

  test "watchdog applies a fudge factor to deadlines" do
    # multiply deadline by 3x
    {:ok, watchdog} = setup_watchdog(period_ms: 10, deadline_fudge_factor: 2.0)
    Watchdog.register(:my_id, 33, watchdog)
    assert_in_delta time_to_unhealthy(watchdog), 100, 15
  end

  defp setup_watchdog(opts) do
    opts =
      opts
      |> Keyword.put(:name, nil)
      |> Keyword.put_new(:deadline_minimum, 0)
      |> Keyword.put_new(:deadline_fudge_factor, 0.0)

    start_supervised({Watchdog, opts}, restart: :temporary)
  end

  defp time_to_unhealthy(watchdog, timeout \\ 1000) do
    start = DateTime.utc_now()
    test_pid = self()

    spawn_link(fn ->
      wait_for_unhealthy(watchdog)
      send(test_pid, :unhealthy)
    end)

    receive do
      :unhealthy -> DateTime.diff(DateTime.utc_now(), start, :millisecond)
    after
      timeout -> raise "timeout"
    end
  end

  defp wait_for_unhealthy(watchdog) do
    case MockStatsd.next_call(watchdog) do
      {:record_watchdog, 0, 1} -> :ok
      {:record_watchdog, _, _} -> wait_for_unhealthy(watchdog)
      other -> raise "unexpected MockWatchdog call: #{inspect(other)}"
    end
  end
end
