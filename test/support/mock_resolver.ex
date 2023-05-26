defmodule CSTest.MockResolver do
  defdelegate child_spec(opts), to: CertStats.Resolver
  defdelegate resolve(hostname), to: CertStats.Resolver
  defdelegate resolve(hostname, pid), to: CertStats.Resolver
end
