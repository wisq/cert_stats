defmodule CertStats.Statsd do
  require Logger

  alias X509.Certificate, as: Cert
  alias X509.DateTime, as: XDT

  alias CertStats.SSL

  @default_name __MODULE__

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(opts \\ []) do
    opts = Keyword.put_new(opts, :name, @default_name)
    dd_opts = Keyword.take(opts, [:host, :port]) |> Map.new()
    DogStatsd.start_link(dd_opts, opts)
  end

  def record_cert(module, cert, statsd \\ @default_name)

  def record_cert(module, cert, {:stub, pid}) do
    send(pid, {:record_cert, module, cert})
  end

  def record_cert(module, cert, statsd) do
    {created, expires} = cert_validity(cert)
    now = DateTime.utc_now()
    create_days = created |> days_before(now)
    expire_days = expires |> days_after(now)

    proto = module.statsd_tag
    common_name = SSL.common_name(cert)
    tags = to_tags(proto: proto, common_name: common_name)

    Logger.info(
      [
        "Got #{inspect(proto)} cert for #{inspect(common_name)}.",
        "Created: #{created} (#{ceil(create_days)} days ago).",
        "Expires: #{expires} (in #{floor(expire_days)} days)."
      ]
      |> Enum.join("\n")
    )

    DogStatsd.batch(statsd, fn s ->
      s.gauge(statsd, "tls.cert.created", create_days, tags: tags)
      s.gauge(statsd, "tls.cert.expires", expire_days, tags: tags)
    end)
  end

  def record_watchdog(healthy, total, statsd \\ @default_name)

  def record_watchdog(healthy, total, {:stub, pid}) do
    send(pid, {:record_watchdog, healthy, total})
  end

  def record_watchdog(0, 0, _) do
    Logger.warning("Watchdog: No registered clients.")
  end

  def record_watchdog(healthy, total, statsd) when total > 0 do
    percent = 100.0 * healthy / total
    msg = fn -> "Watchdog: #{healthy} healthy out of #{total} total (#{round(percent)}%)." end

    case healthy do
      ^total -> Logger.info(msg)
      _ -> Logger.warning(msg)
    end

    DogStatsd.gauge(statsd, "tls.cert.success_rate", percent)
  end

  defp cert_validity(cert) do
    {:Validity, created, expires} = Cert.validity(cert)

    {
      created |> XDT.to_datetime(),
      expires |> XDT.to_datetime()
    }
  end

  def days_before(dt, now) do
    DateTime.diff(now, dt, :second) / 86_400
  end

  def days_after(dt, now) do
    DateTime.diff(dt, now, :second) / 86_400
  end

  defp to_tags(list) do
    list
    |> Enum.map(fn {k, v} -> "#{k}:#{v}" end)
  end
end
