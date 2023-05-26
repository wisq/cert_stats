defmodule CertStats.WatchdogTest do
  use ExUnit.Case, async: true

  alias CertStats.Watchdog

  test "watchdog provides regular reports" do
    setup_watchdog(period_ms: 20)
    assert next_report() == {:ok, 0, 0}
    assert next_report() == {:ok, 0, 0}
    assert next_report() == {:ok, 0, 0}
  end

  test "watchdog with registered client reports healthy until deadline expires" do
    {:ok, watchdog} = setup_watchdog(period_ms: 10)
    Watchdog.register(:my_id, 100, watchdog)
    assert_in_delta time_to_unhealthy(), 100, 15
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

    assert_in_delta time_to_unhealthy(), 100, 15
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

    assert_in_delta time_to_unhealthy(), 100, 15
  end

  test "watchdog applies a minimum deadline extension" do
    {:ok, watchdog} = setup_watchdog(period_ms: 10, deadline_minimum: 100)
    Watchdog.register(:my_id, 0, watchdog)
    assert_in_delta time_to_unhealthy(), 100, 15
  end

  test "watchdog applies a fudge factor to deadlines" do
    # multiply deadline by 3x
    {:ok, watchdog} = setup_watchdog(period_ms: 10, deadline_fudge_factor: 2.0)
    Watchdog.register(:my_id, 33, watchdog)
    assert_in_delta time_to_unhealthy(), 100, 15
  end

  defp setup_watchdog(opts) do
    opts = [statsd: {:stub, self()}, name: nil] ++ opts
    opts = Keyword.put_new(opts, :deadline_minimum, 0)
    opts = Keyword.put_new(opts, :deadline_fudge_factor, 0.0)

    start_supervised({Watchdog, opts}, restart: :temporary)
  end

  defp next_report(timeout \\ 500) do
    receive do
      {:record_watchdog, healthy, total} -> {:ok, healthy, total}
    after
      timeout -> {:error, :timeout}
    end
  end

  defp time_to_unhealthy(timeout \\ 1000) do
    start = DateTime.utc_now()

    receive do
      {:record_watchdog, 0, 1} -> DateTime.diff(DateTime.utc_now(), start, :millisecond)
    after
      timeout -> raise "timeout"
    end
  end
end
