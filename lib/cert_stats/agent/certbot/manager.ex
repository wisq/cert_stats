defmodule CertStats.Agent.Certbot.Manager do
  use GenServer
  require Logger

  alias CertStats.Agent.Certbot.WorkerSupervisor
  alias CertStats.Fetcher

  @log_prefix "[Certbot.Manager] "

  def start_link(opts) do
    {config, opts} = Keyword.pop!(opts, :config)
    GenServer.start_link(__MODULE__, config, opts)
  end

  @impl true
  def init(config) do
    FileSystem.subscribe(config.filesystem)
    {:ok, config, config.initial_ms}
  end

  @impl true
  def handle_info(:timeout, config) do
    Logger.info(@log_prefix <> "Updating workers (periodic) ...")
    update_workers(config)
    {:noreply, config, config.repeat_ms}
  end

  @impl true
  def handle_info({:file_event, _, _}, config) do
    Logger.info(@log_prefix <> "Updating workers (change detected) ...")
    update_workers(config)
    {:noreply, config, config.repeat_ms}
  end

  defp update_workers(config) do
    read_certbot_configs(config.path)
    |> generate_worker_configs(config)
    |> update_supervisor(config.supervisor)
  end

  defp read_certbot_configs(path) do
    File.ls!(path)
    |> Enum.filter(&(&1 =~ ~r/\.conf$/))
    |> Enum.map(&Path.join(path, &1))
    |> Enum.flat_map(fn path ->
      case File.read(path) do
        {:ok, data} ->
          [data]

        {:error, err} ->
          Logger.error(@log_prefix <> "Failed to read #{path}: #{inspect(err)}")
          []
      end
    end)
  end

  defp generate_worker_configs(certbot_configs, config) do
    [
      {config.enable_file, &generate_file_child_spec/2},
      {config.enable_https, &generate_https_child_spec/2}
    ]
    |> Enum.filter(fn {enabled, _} -> enabled end)
    |> Enum.flat_map(fn {_, fun} ->
      certbot_configs |> Enum.map(&fun.(&1, config))
    end)
  end

  @cert_regex ~r{^cert = (?<cert>\S+)$}m
  @host_regex ~r{^archive_dir = .*/archive/(?<host>[^[:space:]/]+)$}m

  defp generate_file_child_spec(cb_conf, config) do
    %{"cert" => path} = Regex.named_captures(@cert_regex, cb_conf)

    file_opts =
      config.file_opts
      |> Keyword.put(:path, path)
      |> Keyword.update(:command, nil, &modify_file_command(&1, path))

    fetcher_child_spec(:file, file_opts, config.fetcher_opts)
  end

  defp modify_file_command(command, path) do
    command
    |> Enum.map(fn
      :path -> path
      arg when is_binary(arg) -> arg
    end)
  end

  defp generate_https_child_spec(cb_conf, config) do
    %{"host" => host} = Regex.named_captures(@host_regex, cb_conf)

    fetcher_child_spec(
      :https,
      Keyword.put(config.https_opts, :host, host),
      config.fetcher_opts
    )
  end

  defp fetcher_child_spec(method, method_opts, fetcher_opts) do
    Fetcher.child_spec([method, method_opts, fetcher_opts])
  end

  defp update_supervisor(child_specs, supervisor) do
    by_id = child_specs |> Map.new(fn spec -> {spec.id, spec} end)

    wanted = Map.keys(by_id) |> MapSet.new()
    actual = supervisor_child_ids(supervisor) |> MapSet.new()

    MapSet.symmetric_difference(wanted, actual)
    |> Enum.each(fn id ->
      case {id in wanted, id in actual} do
        {true, false} -> Map.fetch!(by_id, id) |> start_worker(supervisor)
        {false, true} -> stop_worker(id, supervisor)
      end
    end)

    Logger.info(@log_prefix <> "Currently managing #{Enum.count(wanted)} workers.")
  end

  defp supervisor_child_ids(pid) do
    Supervisor.which_children(pid)
    |> Enum.map(fn {id, _, _, _} -> id end)
  end

  defp start_worker(config, supervisor) do
    {:ok, _} = WorkerSupervisor.start_worker(supervisor, config)
  end

  defp stop_worker(id, supervisor) do
    :ok = WorkerSupervisor.stop_worker(supervisor, id)
  end
end
