defmodule CertStats.Agent.Certbot.WorkerSupervisor do
  use Supervisor
  require Logger

  @log_prefix "[Certbot.WorkerSupervisor] "

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, nil, opts)
  end

  def start_worker(pid, spec) do
    Logger.info(@log_prefix <> "Starting worker: #{inspect(spec.id)}")
    Supervisor.start_child(pid, spec)
  end

  def stop_worker(pid, worker_id) do
    Logger.info(@log_prefix <> "Terminating worker: #{inspect(worker_id)}")
    :ok = Supervisor.terminate_child(pid, worker_id)
    :ok = Supervisor.delete_child(pid, worker_id)
  end

  @impl true
  def init(_) do
    Supervisor.init([], strategy: :one_for_one)
  end
end
