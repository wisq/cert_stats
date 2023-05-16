defmodule CertStats.Method.FileTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias CertStats.Method.File
  alias CertStats.SSL
  alias X509.DateTime, as: XDT

  @certs "test/data/certs/"

  test "fetches sample certificate #1" do
    assert {:ok, cert} =
             File.init(path: "#{@certs}/ismypowerbackyet.com/cert.pem")
             |> File.fetch_cert()

    assert "ismypowerbackyet.com" == SSL.common_name(cert)
    assert {_, _, _, alt_names} = X509.Certificate.extension(cert, :subject_alt_name)
    assert [dNSName: 'ismypowerbackyet.com'] == alt_names

    assert {_, not_before, not_after} = X509.Certificate.validity(cert)
    assert XDT.to_datetime(not_before) == ~U[2023-03-19 11:04:09Z]
    assert XDT.to_datetime(not_after) == ~U[2023-06-17 11:04:08Z]
  end

  test "fetches sample certificate #2" do
    assert {:ok, cert} =
             File.init(path: "#{@certs}/google.com/cert.pem")
             |> File.fetch_cert()

    assert "*.google.com" == SSL.common_name(cert)
    assert {_, _, _, alt_names} = X509.Certificate.extension(cert, :subject_alt_name)
    assert {:dNSName, '*.google.com'} in alt_names

    assert {_, not_before, not_after} = X509.Certificate.validity(cert)
    assert XDT.to_datetime(not_before) == ~U[2023-04-24 11:56:06Z]
    assert XDT.to_datetime(not_after) == ~U[2023-07-17 11:56:05Z]
  end

  test "uses command to retrieve certificate if provided" do
    assert {:ok, cert} =
             File.init(path: "/dev/null", command: ["cat", "#{@certs}/google.com/cert.pem"])
             |> File.fetch_cert()

    assert "*.google.com" == SSL.common_name(cert)
  end

  test "handles nonexistent cert file" do
    assert {:error, :enoent} =
             File.init(path: "#{__DIR__}/nonexistent")
             |> File.fetch_cert()
  end

  test "handles empty cert file" do
    assert {:error, :not_found} =
             File.init(path: "/dev/null")
             |> File.fetch_cert()
  end

  test "handles file with non-cert data" do
    assert {:error, :not_found} =
             File.init(path: "/etc/hosts")
             |> File.fetch_cert()
  end

  test "handles command exiting with non-zero status" do
    assert {{:error, :command_failed}, log} =
             with_log(fn ->
               File.init(path: "/dev/null", command: ["false"])
               |> File.fetch_cert()
             end)

    assert log =~ "returned code 1"
  end
end
