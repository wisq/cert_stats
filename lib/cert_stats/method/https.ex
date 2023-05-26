defmodule CertStats.Method.HTTPS do
  @behaviour CertStats.Method

  alias CertStats.SSL

  defmodule Config do
    @enforce_keys [:host]
    defstruct(
      host: nil,
      ip: nil,
      port: 443,
      cert_host: nil,
      timeout: 10_000
    )

    def validate(c) do
      is_binary(c.host) || invalid(c, :host)
      is_nil(c.ip) || :inet.is_ip_address(c.ip) || invalid(c, :ip)
      is_integer(c.port) || invalid(c, :port)
      is_nil(c.cert_host) || is_binary(c.cert_host) || invalid(c, :cert_host)
      is_integer(c.timeout) || invalid(c, :timeout)

      %Config{c | cert_host: c.cert_host || c.host}
    end

    defp invalid(config, field) do
      raise "Invalid #{field} in config: #{Map.fetch!(config, field) |> inspect()}"
    end
  end

  @impl true
  def statsd_tag, do: "https"

  @impl true
  def watchdog_id(config) do
    :"https_#{config.cert_host}"
  end

  @impl true
  def init(opts) do
    struct!(Config, opts)
    |> Config.validate()
  end

  @impl true
  def fetch_cert(%Config{} = config) do
    with {:ok, addrs} <- find_ip_addrs(config),
         addr <- Enum.random(addrs),
         {:ok, socket} <- :gen_tcp.connect(addr, config.port, [:binary], config.timeout),
         {:ok, cert} <- SSL.fetch_cert(socket, config.cert_host, config.timeout) do
      :ok = :gen_tcp.close(socket)
      {:ok, cert}
    end
  end

  defp find_ip_addrs(%Config{ip: nil, host: host}), do: CertStats.resolver().resolve(host)
  defp find_ip_addrs(%Config{ip: ip}) when is_tuple(ip), do: {:ok, [ip]}
end
