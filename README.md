# PhoenixKitUserConnections

Social relationships module for [PhoenixKit](https://github.com/BeamLabEU/phoenix_kit) — follows, mutual connections, and blocking.

## Features

- **Follows** — One-way relationships (User A follows User B, no consent needed)
- **Connections** — Two-way mutual relationships (both users must accept)
- **Blocking** — Prevents all interaction, removes existing follows/connections
- **History logging** — Full audit trail for all relationship actions
- **Admin dashboard** — Statistics overview and module toggle
- **User LiveView** — Tabbed interface for managing personal connections

## Installation

Add to your `mix.exs` dependencies:

```elixir
{:phoenix_kit_user_connections, "~> 0.2"}
```

The module is auto-discovered by PhoenixKit at startup — no additional configuration needed.

## Usage

```elixir
# Follow a user
PhoenixKitUserConnections.follow(current_user, other_user)

# Request a mutual connection
PhoenixKitUserConnections.request_connection(current_user, other_user)

# Accept a connection request
PhoenixKitUserConnections.accept_connection(connection)

# Block a user (removes existing follows/connections)
PhoenixKitUserConnections.block(current_user, other_user, "reason")

# Get full relationship status
PhoenixKitUserConnections.get_relationship(current_user, other_user)
# => %{following: true, followed_by: false, connected: false, ...}
```

## Business Rules

- Cannot follow/connect with yourself
- Cannot follow/connect if blocked (either direction)
- If A requests B while B has pending request to A, both are auto-accepted
- Blocking removes all existing follows and connections between the users

## License

MIT — see [LICENSE](LICENSE).
