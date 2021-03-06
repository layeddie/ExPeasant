# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
import Config

config :peasant_nerves, target: Mix.target()

# Customize non-Elixir parts of the firmware. See
# https://hexdocs.pm/nerves/advanced-configuration.html for details.

config :nerves, :firmware,
  rootfs_overlay: "rootfs_overlay",
  provisioning: :nerves_hub_link

# Set the SOURCE_DATE_EPOCH date for reproducible builds.
# See https://reproducible-builds.org/docs/source-date-epoch/ for more information

config :nerves, source_date_epoch: "1577975236"

config :nerves_hub_link,
  fwup_public_keys: [:devkey],
  remote_iex: true

config :vintage_net_wizard,
  port: 8080,
  captive_portal: false

# Use Ringlogger as the logger backend and remove :console.
# See https://hexdocs.pm/ring_logger/readme.html for more information on
# configuring ring_logger.

config :logger, backends: [RingLogger]

import_config "../../peasant/config/config.exs"
# import_config "../../peasant/config/prod.exs"

config :phoenix, :json_library, Jason

if Mix.target() != :host do
  import_config "target.exs"
end
