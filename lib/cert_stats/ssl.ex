defmodule CertStats.SSL do
  require Logger

  def fetch_cert(socket, hostname) do
    with {:ok, _} <- ssl_connect_for_cert(socket, hostname),
         {:ok, cert} <- receive_cert() do
      {:ok, cert}
    end
  end

  defp ssl_connect_for_cert(socket, hostname) do
    :ssl.connect(socket,
      versions: [:"tlsv1.2"],
      ciphers: :ssl.cipher_suites(:default, :"tlsv1.2"),
      depth: 3,
      verify: :verify_none,
      verify_fun: {&verify/3, self()},
      server_name_indication: String.to_charlist(hostname),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    )
  end

  defp receive_cert do
    receive do
      {:peer_cert, cert} -> {:ok, cert}
    after
      0 -> {:error, :no_cert_found}
    end
  end

  defp verify(_cert, {:extension, _}, state) do
    {:unknown, state}
  end

  defp verify(cert, msg, state) when is_pid(state) do
    Logger.debug("SSL.verify(#{common_name(cert) |> inspect()}, #{msg |> inspect()})")
    if msg == :valid_peer, do: send(state, {:peer_cert, cert})
    {:valid, state}
  end

  def common_name(cert) do
    [cn] =
      cert
      |> X509.Certificate.subject()
      |> X509.RDNSequence.get_attr("commonName")

    cn
  end
end
