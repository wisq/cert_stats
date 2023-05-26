defmodule CSTest.MockMethod do
  @behaviour CertStats.Method

  def watchdog_id({id, _cert}), do: "mock-#{id}"

  def statsd_tag, do: "mock"

  def init({id, cert}), do: {id, cert}

  def fetch_cert({_id, cert}) do
    {:ok, cert}
  end
end
