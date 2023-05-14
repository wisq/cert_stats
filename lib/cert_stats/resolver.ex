defmodule CertStats.Resolver do
  use GenServer
  require Logger

  @log_prefix "[Resolver] "

  # 3 hour TTL
  @ttl 3_600_000 * 3

  def start_link(opts) do
    opts = Keyword.put_new(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, nil, opts)
  end

  def resolve(hostname, pid \\ __MODULE__) do
    cond do
      addrs = lookup(hostname, pid) -> {:ok, addrs}
      addrs = get_cache(hostname, pid) -> {:ok, addrs}
      true -> {:error, :domain_not_found}
    end
  end

  defp lookup(hostname, pid) do
    hostname
    |> String.to_charlist()
    |> :inet.gethostbyname()
    |> then(fn
      {:ok, {:hostent, _, _, :inet, _, addrs}} ->
        GenServer.cast(pid, {:put, hostname, addrs})
        addrs

      {:error, err} ->
        Logger.warning(@log_prefix <> "Got #{inspect(err)} looking up #{inspect(hostname)}.")
        nil
    end)
  end

  defp get_cache(hostname, pid) do
    case GenServer.call(pid, {:get, hostname}) do
      {:ok, addrs} ->
        Logger.info(@log_prefix <> "Found domain #{inspect(hostname)} in cache.")
        addrs

      {:error, :not_found} ->
        Logger.error(@log_prefix <> "Domain #{inspect(hostname)} not found in DNS cache.")
        nil
    end
  end

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:put, hostname, addrs}, cache) do
    {:noreply, Map.put(cache, hostname, {addrs, ttl_from_now()})}
  end

  @impl true
  def handle_call({:get, hostname}, _from, cache) do
    with {:ok, {addrs, ttl}} <- Map.fetch(cache, hostname),
         :fresh <- ttl_status(ttl) do
      {:reply, {:ok, addrs}, cache}
    else
      :error -> {:reply, {:error, :not_found}, cache}
      :stale -> {:reply, {:error, :not_found}, Map.delete(cache, hostname)}
    end
  end

  defp ttl_from_now, do: DateTime.utc_now() |> DateTime.add(@ttl, :millisecond)

  def ttl_status(ttl) do
    case DateTime.utc_now() |> DateTime.compare(ttl) do
      :lt -> :fresh
      :eq -> :fresh
      :gt -> :stale
    end
  end
end
