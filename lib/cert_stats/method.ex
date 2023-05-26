defmodule CertStats.Method do
  @type config :: term
  @type opts :: term

  @callback init(opts) :: config
  @callback fetch_cert(config) :: {:ok, X509.Certificate.t()} | {:error, term}
  @callback statsd_tag :: binary
  @callback watchdog_id(config) :: atom

  alias __MODULE__

  defp module(:file), do: Method.File
  defp module(:https), do: Method.HTTPS
  defp module(:postgres), do: Method.Postgres
  if Mix.env() == :test, do: defp(module(:mock), do: CSTest.MockMethod)
  defp module(key), do: raise(ArgumentError, "Method not found: #{inspect(key)}")

  def configure(method, opts) do
    mod = module(method)
    config = mod.init(opts)
    wd_id = mod.watchdog_id(config)

    {wd_id, mod, config}
  end
end
