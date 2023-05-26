import Config

config :cert_stats,
  resolver: CSTest.MockResolver,
  statsd: CSTest.MockStatsd,
  watchdog: CSTest.MockWatchdog

config :logger, level: :info
