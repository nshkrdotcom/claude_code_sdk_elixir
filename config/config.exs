import Config

# Default configuration
config :claude_code_sdk,
  use_mock: false

# Import environment specific config
import_config "#{config_env()}.exs"
