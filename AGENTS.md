# AGENTS.md

Guidance for AI agents working on `phoenix_kit_user_connections`.

## Overview

Social relationships between PhoenixKit users: one-way follows, two-way
mutual connections (request, accept, reject, cancel, remove), one-way blocks,
and an append-only history row for every action. `PhoenixKitUserConnections`
implements `PhoenixKit.Module` (`use PhoenixKit.Module`, so core auto-discovers
it) and is the entire public API; the two LiveViews are thin callers of it.
This is a library, not a standalone Phoenix app.

- **Depends on:** `phoenix_kit` `~> 2.0` (Hex), `phoenix_live_view` `~> 1.1`. No sibling modules.
- **Consumed by:** core only, guarded with `Code.ensure_loaded?/1` + `enabled?/0`: the admin user-details page's Connections tab (`followers_count/1`, `following_count/1`, `connections_count/1`, `pending_requests_count/1`, `list_blocked/1`) and the admin Modules page card (`get_config/0`, `module_stats/0`). No sibling module calls it.
- **Admin surface:** one tab, `:admin_connections` at `/admin/connections` (group `:admin_modules`, priority 600, `match: :prefix`, permission `"connections"`): statistics plus the enable toggle. The user-facing LiveView `Web.UserConnections` ("My Connections", five tabs) ships in the package but is not routed by the module; see Conventions.
- **Module key** `"connections"`; settings prefix `connections_`.

## What this module does NOT do

- Own migrations. Its six tables ship in core's chain and `migration_module/0` is unset.
- Route the user-facing page. There is no `user_dashboard_tabs/0` and no `route_module/0`; the host mounts `Web.UserConnections`.
- Notify anyone. No PubSub topics, notification types or emails: a request or an accept is visible on the next page load only.
- Own the uniqueness indexes. Core's chain creates them (V188); this module only names them in `unique_constraint/3` (see Landmines).
- Delete history. Every action appends a `*_history` row and nothing removes one; user deletion cascades through core's foreign keys, so `before_user_delete/1` is not implemented.
- Use core's activity log. The module's own history tables are the audit trail.

## Commands

```bash
mix deps.get
createdb phoenix_kit_user_connections_test          # once; DB-backed tests are tagged :integration and auto-skip without it
mix test
mix precommit                # compile --warnings-as-errors + format + credo --strict + dialyzer; run before every commit
```

`phoenix_kit*` deps resolve from Hex and this module does not carry the
`pk_dep/3` helper. To run against a local core checkout, temporarily change the
dep to `{:phoenix_kit, path: "../phoenix_kit", override: true}` in `mix.exs`,
run `mix deps.get`, and revert **both** `mix.exs` and `mix.lock` before
committing (switching between path and Hex resolution rewrites the lock).

`mix precommit` here also runs `deps.unlock --check-unused` and `mix hex.audit`;
`mix quality` (format + credo --strict + dialyzer) is the lighter local pass.

Repo-local aliases:

- `mix quality.ci` — `format --check-formatted` + `credo --strict` + `dialyzer`: it CHECKS formatting rather than applying it, so run `mix format` first.

## Conventions

- Module key `"connections"`, tab id `:admin_connections`, URL segment `connections`. Multi-word segments use hyphens.
- Paths: every URL goes through `PhoenixKit.Utils.Routes.path/1` (`Routes.path("/admin")`, `Routes.path("/profile/connections?tab=…")`); never hardcode a prefix or locale. `<.nav_tabs>` passes `:patch` through verbatim, so tab URLs are wrapped in `Routes.path/1` at the call site.
- Routing: the admin page is registered with `live_view: {Web.Connections, :index}` on the tab; core compiles it into `live_session :phoenix_kit_admin` and applies the admin layout via `on_mount`. Never hand-register plugin routes in a host router, and never put `live_view:` and a route module on the same path. Core's `guides/custom-admin-pages.md` is the reference. `Web.UserConnections` is the exception: the module registers no route for it and its tab strip assumes `/profile/connections?tab=…`, so a host mounts it at that path inside core's authenticated `live_session`.
- LiveView macro: both LiveViews `use PhoenixKitWeb, :live_view` with colocated `.html.heex` templates and no `LayoutWrapper`.
- Page headers: the admin page sets `@page_title`/`@page_subtitle` and core's admin navbar renders them. The user page renders its own `<header>` from the same assigns because the authenticated dashboard layout does not surface them.
- Gettext: none. Every UI string is a literal; there is no `priv/gettext` and no extract/merge step. Translating means adopting core's `PhoenixKitWeb.Gettext` (or adding a backend) for every string at once, not half of them.
- JS hooks: none; `js_sources/0` is not declared. `css_sources/0` returns `[:phoenix_kit_user_connections]` so core's Tailwind build scans this app's templates.
- `enabled?/0` delegates to `Settings.get_boolean_setting("connections_enabled", false)`, which rescues to `false`; it adds no `catch :exit` of its own. `enable_system/0` and `disable_system/0` write the same key with `update_boolean_setting_with_module/3` so the setting is attributed to `module_key()`.
- History logging: every mutation runs inside `repo().transaction/1` and appends a history row (`log_follow_history/3`, `log_connection_history/4`, `log_block_history/4`). A failed history insert logs a warning and does not roll the action back. Connection history carries the `actor_uuid` of who acted. No PII beyond user UUIDs and the optional block `reason`.
- Soft delete: none. Follows, connections and blocks are hard-deleted; the history tables are the record.
- Every public user argument is either a `%{uuid: uuid}` struct (`PhoenixKit.Users.Auth.User`) or a raw UUID string (`get_user_uuid/1`); mixing the two is fine.
- Guards run before every write, in this order: self-action, block in either direction, existing relationship. Errors are atoms: `:self_follow`, `:already_following`, `:not_following`, `:self_connection`, `:already_connected`, `:pending_request`, `:not_pending`, `:not_requester`, `:not_found`, `:not_connected`, `:self_block`, `:already_blocked`, `:not_blocked`, and `:blocked` for either direction.
- `block/3` removes follows and connections in both directions inside the same transaction (each removal logged) before inserting the block. `unblock/2` restores nothing.
- Mutual pending requests auto-accept: `request_connection/2` from B while A→B is pending accepts A's request with B as actor.
- `reject_connection/1` and `cancel_request/2` delete the pending row (logging `rejected` / `removed`); `Connection.statuses/0` lists `"rejected"` but no persisted row carries it.
- List functions take `limit:`, `offset:` and `preload:` (default `true`); the user page passes `limit: @page_size` (25) and has no paging UI.
- The admin counts (`get_config/0`, `get_stats/0`, `module_stats/0`) rescue `Ecto.QueryError` and `DBConnection.ConnectionError` to `0` so the Modules page renders before the schema exists.
- User page: tab data loads in `handle_params/3` (never also in `mount/3`); tabs `patch`, never `navigate`; every event handler reloads the counts and the current tab.
- Authorization: the admin LV checks `Scope.has_module_access?(scope, "connections")` in `mount/3` and again in every event; the user LV requires `phoenix_kit_current_user` and `enabled?/0` and redirects to `Routes.path("/")` otherwise.
- Mobile: no daisyUI `.stat` or `.label` in these templates (neither shrinks under `min-w-0`, so they overflow the viewport); rows use `min-w-0`/`truncate`/`shrink-0` so action buttons stay on-screen.

### Landmines

- `Block.changeset/2` caps `reason` at 255 **with `count: :codepoints`** to match the column. Both halves are load-bearing: Postgres counts characters while Ecto's `validate_length/3` counts grapheme clusters by default, so 255 decomposed graphemes are 510 codepoints — accepted by a plain `max: 255` and refused by `character varying(255)` with `:string_data_right_truncation`, which is the crash the validation exists to prevent. Any new length validation on a column-backed field must read the column's real width AND count codepoints; core declares these tables, so the width lives in core's chain, not here.
- The three unique indexes the schemas name (`phoenix_kit_user_follows_unique_idx`, `phoenix_kit_user_blocks_unique_idx`, `phoenix_kit_user_connections_requester_recipient_uidx`) ship in **core's V188**, so those `unique_constraint/3` calls only work against a core that includes it. Against an older core they are inert exactly as before — the pre-check is then the only guard and a concurrent double follow or request inserts two rows. The pin stays `~> 2.0` (the conformance test refuses a three-segment pin), so this floor is documented, not enforced.
- **Follows and blocks are DIRECTED; connections are UNDIRECTED**, and their indexes differ accordingly. A follow or block indexes the ordered pair, because A→B and B→A are two different relationships. A connection is ONE relationship stored in whichever direction it was asked, so its index is an expression index on `LEAST`/`GREATEST` of the pair. An ordered index there would permit the mutual-click race — two users connecting to each other at the same instant, both passing the pre-checks, both inserting — which leaves a pending row alive between two already-connected users, survives `remove_connection/2` (it deletes only the accepted row), and can make `get_accepted_connection/2`'s `Repo.one/1` raise. Never "tidy" the three onto one shape.
- **A pair conflict is reconciled, not reported.** `create_pending_connection/2` turns the pair index's violation into `:pair_exists`, and `reconcile_pair_conflict/2` re-reads the pair and returns what the caller would have got a moment later — usually the auto-accept. So the losing side of a mutual click still ends up connected instead of seeing "has already been taken". One retry only: the winner's row is committed and the index means the pair can never hold a second row.
- `<.nav_tabs>` with `:patch`/`:badge_class` needs core 2.13.5+ at runtime; against an older core it compiles and renders a strip of dead buttons. The pin stays `~> 2.0` because the conformance test refuses a three-segment pin, so the floor is documented, not enforced: upgrade core first.
- `/profile/connections` is assumed by the template, not registered by the module; a host that mounts `Web.UserConnections` anywhere else gets a tab strip that patches to a 404.
- `mix test` runs with no database and no Repo; a change to a query or changeset is unverified until exercised in a host.
- `function_exported?/3` answers **false for a module that is merely not loaded**, not only for one missing the function, so a bare callback assertion fails intermittently under a random seed and never when run alone — the shape that reads as flaky infrastructure and gets re-run instead of fixed. The behaviour test's `setup_all` calls `Code.ensure_loaded!/1`; any new `function_exported?` assertion must be covered by it.

## Architecture

```
lib/
  phoenix_kit_user_connections.ex          # PhoenixKit.Module callbacks + the whole public API
  phoenix_kit_user_connections/
    schemas/
      follow.ex  follow_history.ex
      connection.ex  connection_history.ex
      block.ex  block_history.ex
    web/
      connections.ex (+ .html.heex)        # admin LiveView: stats + enable toggle
      user_connections.ex (+ .html.heex)   # user LiveView "My Connections": followers / following / connections / requests / blocked
config/
  config.exs                               # imports test.exs in :test
  test.exs                                 # logger level only; no Repo
test/
  phoenix_kit_user_connections_test.exs    # behaviour callbacks
  core_pin_conformance_test.exs            # :phoenix_kit requirement shape guard
  schema_prefix_conformance_test.exs       # SchemaPrefix guard
```

### Data model

| Schema | Table | Columns | Notes |
|---|---|---|---|
| `Follow` | `phoenix_kit_user_follows` | `follower_uuid`, `followed_uuid`, `inserted_at` | one row per direction |
| `FollowHistory` | `phoenix_kit_user_follows_history` | same + `action` in `follow unfollow` | |
| `Connection` | `phoenix_kit_user_connections` | `requester_uuid`, `recipient_uuid`, `status`, `requested_at`, `responded_at`, `timestamps` | one row per pair whichever side asked; `status_changeset/2` stamps `responded_at` |
| `ConnectionHistory` | `phoenix_kit_user_connections_history` | `user_a_uuid`, `user_b_uuid`, `actor_uuid`, `action` in `requested accepted rejected removed` | the changeset sorts the pair so `user_a_uuid < user_b_uuid` |
| `Block` | `phoenix_kit_user_blocks` | `blocker_uuid`, `blocked_uuid`, `reason`, `inserted_at` | one-way |
| `BlockHistory` | `phoenix_kit_user_blocks_history` | same + `action` in `block unblock` | |

All six: UUIDv7 primary key `uuid`, `use PhoenixKit.SchemaPrefix`,
`belongs_to PhoenixKit.Users.Auth.User` with `references: :uuid`, foreign keys
`ON DELETE CASCADE` in core's schema. Every schema except `Connection` has a
manual `inserted_at` and no `updated_at` because its rows never change.

- `get_relationship/2` returns `%{following, followed_by, connected, connection_pending: nil | :sent | :received, blocked, blocked_by}` in three queries (follows, connections, blocks between the pair); use it for profile buttons instead of the six predicate calls.
- Settings: `connections_enabled` (boolean, default `false`). No other keys.
- Permissions: `"connections"` (module access, also the admin tab's permission). No sub-permissions.
- PubSub topics: none.
- Behaviour callbacks implemented: `module_key`, `module_name`, `version`, `enabled?`, `enable_system`, `disable_system`, `get_config`, `permission_metadata`, `admin_tabs`, `css_sources`. Non-behaviour helpers core reads: `module_stats/0`, `get_stats/0`.

## Database & migrations

None. Tables `phoenix_kit_user_follows`, `phoenix_kit_user_follows_history`,
`phoenix_kit_user_connections`, `phoenix_kit_user_connections_history`,
`phoenix_kit_user_blocks`, `phoenix_kit_user_blocks_history` ship in core's
chain (V135 baseline, `owner: :core` in core's ExpectedSchema), and so do the
three unique indexes the schemas name (V188);
`migration_module/0` is unset. A schema change is a core migration first (with
its ExpectedSchema entry), then schema edits here. UUIDv7 PKs; `use
PhoenixKit.SchemaPrefix` on every table-backed schema
(`schema_prefix_conformance_test.exs` enforces it).

## Testing

- No test database. `config/test.exs` sets only the logger level; no Repo is configured and no test touches Postgres. The `createdb` line in Commands is the ecosystem convention, ready for the day DB-backed tests arrive.
- `mix test` runs three files without any service: the behaviour test (`@phoenix_kit_module` attribute, callbacks, tab shape, `version/0` against `Mix.Project.config()[:version]`, `css_sources/0`), the core-pin guard (the `:phoenix_kit` requirement must admit every core 2.x and reject 1.x and 3.x; a committed `path:` dep fails it), and the SchemaPrefix guard.
- No `test/support`, `DataCase`, `LiveCase` or test Endpoint; `elixirc_paths(:test)` already lists `test/support`.
- The business logic (follow/connect/block flows, auto-accept, block cleanup, history rows) and both LiveViews have no tests; verify them in a host.
- PG env vars: none honoured (nothing connects).

## Feature notes

None. Feature behaviour is documented in `@moduledoc`s
(`PhoenixKitUserConnections` carries the business rules).

## Versioning & releases

SemVer. The version is single-sourced in `mix.exs` (`@version`); `version/0`
reads it at compile time and the behaviour test asserts against
`Mix.Project.config()[:version]`, so nothing else needs bumping.

Release procedure (the steps the maintainer runs):

1. Bump `@version` in `mix.exs`; add a `CHANGELOG.md` entry headed `## x.y.z - YYYY-MM-DD`.
2. `mix precommit` clean.
3. Commit (`"Bump version to x.y.z"`) and push; verify the push landed.
4. `mix hex.publish`.
5. Tag, matching the form of the newest existing tag (`git tag --sort=-creatordate | head -1` shows it), and push the tag.
6. GitHub release via `gh release create` if the repo does those (`gh release list` shows whether it does).

Tags are immutable pointers: never tag before the commit is pushed and the
publish has succeeded.

## Pull requests & commits

- Commit messages start with an action verb (`Add`, `Update`, `Fix`, `Remove`, `Merge`). No AI attribution and no `Co-Authored-By` trailers.
- Version bumps and CHANGELOG entries land with the release commit on upstream, not in feature PRs.
- Review files live in `dev_docs/pull_requests/{year}/{pr_number}-{slug}/{AGENT}_REVIEW.md`, one file per reviewing agent, never edited by another agent; `FOLLOW_UP.md` records how each finding was resolved. Severities: `BUG - CRITICAL/HIGH/MEDIUM`, `IMPROVEMENT - HIGH/MEDIUM`, `NITPICK`.

## TODOs

- Routing the user page through `user_dashboard_tabs/0` so core mounts it under `/dashboard/…`. The five `Routes.path("/profile/connections?tab=…")` links in the template must move with it, and hosts mounting it at `/profile/connections` today must be told.
- Tests for the business logic. Unblocked by a Repo in `config/test.exs` and `PhoenixKit.Migration.ensure_current/2` in `test_helper.exs` (core's chain owns the tables); tag them `:integration`.
