Mimic.copy(Ecto.Adapter)
Mimic.copy(Ecto.Adapters.Postgres)

ExUnit.start(capture_log: true)

# Load test support modules
Code.require_file("support/bunker_test_helper.ex", __DIR__)
