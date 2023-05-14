defmodule CertStats.Agent.Certbot do
  @behaviour CertStats.Agent

  use Supervisor
  require Logger

  alias CertStats.Agent.Certbot.{WorkerSupervisor, Manager}

  defmodule Config do
    @log_prefix "[Certbot] "

    defstruct(
      supervisor: CertStats.Agent.Certbot.WorkerSupervisor,
      filesystem: CertStats.Agent.Certbot.FileSystem,
      path: "/etc/letsencrypt/renewal",
      enable_file: nil,
      enable_https: true,
      initial_ms: 10_000,
      repeat_ms: 120_000,
      file_opts: [],
      https_opts: [],
      fetcher_opts: []
    )

    def autodetect_enable_file(%Config{enable_file: b} = config) when is_boolean(b), do: config

    def autodetect_enable_file(%Config{enable_file: nil} = config) do
      case Path.join([config.path, "..", "live", "."]) |> File.stat() do
        {:ok, _} ->
          %Config{config | enable_file: true}

        {:error, :eacces} ->
          Logger.warning(@log_prefix <> "Cannot access certs.  File checking disabled.")
          %Config{config | enable_file: false}
      end
    end
  end

  def start_link(opts) do
    config =
      struct!(Config, opts)
      |> Config.autodetect_enable_file()

    Supervisor.start_link(__MODULE__, config, name: __MODULE__)
  end

  @impl true
  def init(config) do
    [
      {WorkerSupervisor, name: config.supervisor},
      filesystem_child_spec(config.filesystem, config.path),
      {Manager, config: config}
    ]
    |> Supervisor.init(strategy: :rest_for_one)
  end

  defp filesystem_child_spec(name, path) do
    %{
      id: name,
      start: {FileSystem, :start_link, [[name: name, dirs: [path]]]}
    }
  end
end
