import Config
config :kirbs, Oban, testing: :manual
config :kirbs, token_signing_secret: "/VHDrBw1lZOfNa3S/rUjuXeLdVqnV3v8"
config :bcrypt_elixir, log_rounds: 1

config :kirbs, :montonio,
  access_key: "test_access_key",
  secret_key: "test_secret_key_test_secret_key_1234",
  env: :sandbox,
  req_options: [plug: {Req.Test, Kirbs.Montonio}],
  label_poll_delay: 0
config :ash, policies: [show_policy_breakdowns?: true], disable_async?: true

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :kirbs, Kirbs.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "#{System.get_env("DB_NAME", "kirbs_test")}#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :kirbs, KirbsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "X7LmrsnK+iTEEl7oWoOk43Y8vRH6F17eykGacmfQiuPWy+o5pLspCY2sy3BVvmOz",
  server: false

# In test we don't send emails
config :kirbs, Kirbs.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Never hit OpenRouter in tests: categorization uses a stub (see test/support/stub_categorize_llm.ex)
config :kirbs, :item_categorize_llm, Kirbs.Test.StubCategorizeLlm
