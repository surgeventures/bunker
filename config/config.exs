import Config

# This file is responsible for configuring your application
# and its dependencies.

# Sample configuration:
#
# config :bunker,
#   enabled: true,
#   repos: [MyApp.Repo],
#   adapters: [Bunker.Adapters.GRPC]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
