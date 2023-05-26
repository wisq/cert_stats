defmodule CSTest.MockMethod do
  @behaviour CertStats.Method

  def watchdog_id({id, _cert}), do: "mock-#{id}"

  def statsd_tag, do: "mock"

  def init({id, cert}), do: {id, cert}

  def fetch_cert({_id, table}) do
    [return: rval] = :ets.lookup(table, :return)
    rval
  end

  def test_setup(rval) do
    table = :ets.new(:mock_method, [:set, :protected])
    test_replace(table, rval)
    table
  end

  def test_replace(table, rval) do
    :ets.insert(table, {:return, rval})
  end
end
