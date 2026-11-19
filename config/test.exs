import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :melody_studio, MelodyStudio.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "melody_studio_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :melody_studio, MelodyStudioWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "nsIyiI1CB6quD68b0ha9HwVuqGdnVQDC7gs5yiAxHZZv6tHe/pMrXrvICxWBtw1x",
  server: false

# In test we don't send emails
config :melody_studio, MelodyStudio.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Run Oban jobs inline-only in tests
config :melody_studio, Oban, testing: :manual

# Keep uploaded files of tests out of the app directory
config :melody_studio, MelodyStudio.Storage.Local,
  root: Path.expand("../tmp/test_uploads", __DIR__)

# External APIs are stubbed with Req.Test in tests
config :melody_studio, MelodyStudio.AI.Claude,
  req_options: [plug: {Req.Test, MelodyStudio.AI.Claude}]

config :melody_studio, MelodyStudio.Stems.Replicate,
  req_options: [plug: {Req.Test, MelodyStudio.Stems.Replicate}]
