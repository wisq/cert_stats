defmodule CertStats.Method.File do
  @behaviour CertStats.Method
  require Logger

  defmodule Config do
    @enforce_keys [:path]
    defstruct(
      path: nil,
      command: nil
    )

    def validate(c) do
      is_binary(c.path) || invalid(c, :path)

      is_nil(c.command) ||
        (is_list(c.command) && !Enum.empty?(c.command) && Enum.all?(c.command, &is_binary/1)) ||
        invalid(c, :command)

      c
    end

    defp invalid(config, field) do
      raise "Invalid #{field} in config: #{Map.fetch!(config, field) |> inspect()}"
    end
  end

  @impl true
  def statsd_tag, do: "file"

  @impl true
  def watchdog_id(config) do
    :"file_#{config.path}"
  end

  @impl true
  def init(opts) do
    struct!(Config, opts)
    |> Config.validate()
  end

  @impl true
  def fetch_cert(config) do
    with {:ok, pem} <- read_file(config),
         {:ok, cert} <- X509.Certificate.from_pem(pem) do
      {:ok, cert}
    end
  end

  def read_file(%Config{command: [cmd | args]}) do
    case System.cmd(cmd, args) do
      {output, 0} ->
        {:ok, output}

      {_, code} ->
        Logger.error("Command #{inspect([cmd | args])} returned code #{code}")
        {:error, :command_failed}
    end
  end

  def read_file(%Config{path: path, command: nil}) do
    File.read(path)
  end
end
