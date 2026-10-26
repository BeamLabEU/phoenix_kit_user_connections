# Changelog

All notable changes to PhoenixKitUserConnections will be documented in this file.

## Unreleased

### Added

- **The module supplies the manifest of its 6 tables** (`expected_schema/0`, `PhoenixKitUserConnections.ExpectedSchema`), so `mix phoenix_kit.repair` and `mix phoenix_kit.doctor` check and repair them again, now from the module's own chain instead of core's manifest. Generated from `PhoenixKitUserConnections.Migrations` by core's `dev_docs/squash/generate_module_manifest.exs`, never edited by hand. Core uses it from the first release after 2.64.1; before that nothing reads it. Repair is additive (it creates what is missing and reports the rest) and checks the tables only while the database is at the chain's current version. No migration.
- The module's own migration chain, `PhoenixKitUserConnections.Migrations`
  (`migration_module/0`). V1 adopts the six tables core's chain creates for
  this module, exactly as a fresh core install builds them (V135 plus V188's
  unique indexes), and stamps a `pkucn_schema:1` marker. Nothing changes on an
  existing install but the marker; from now on a change to these tables ships
  here instead of in core. A test proves the chain builds the tables without
  core (core's `PhoenixKit.TestSupport.ModuleChainCheck`), with a small test
  database setup the suite did not have before.

### Changed

- Requires `phoenix_kit` `>= 2.22.3 and < 3.0.0` (was `~> 2.0`): 2.22.3 is the
  first core with V188, the unique indexes the schemas name and V1 adopts.

## 0.3.0 - 2026-10-24

### Added

- `module_stats/0` — follows, connections and blocks counts for this
  module's card on the admin Modules page.

### Fixed

- **Two users connecting to each other at the same moment no longer get a
  raw "has already been taken" error.** With core's V188 unique index on the
  pair (core 2.22.3+), the losing insert is now recognised and the pair is
  re-read once: the caller gets what it would have got a moment later,
  usually the auto-accept. Against a core without V188 nothing changes; the
  pre-check stays the only guard.
- **A block reason longer than 255 characters raised `Postgrex.Error` on
  insert** instead of returning a changeset error. The limit was 500, but the
  column is `varchar(255)`. It is now 255, counted in codepoints the way
  Postgres counts, so accented text built from combining characters cannot
  slip past it. Reasons of 256–500 characters that used to crash are now
  rejected with a validation error.
- The "My Connections" tab links are built with `Routes.path/1` again, so
  they carry the host's URL prefix and locale (#8).
- `version/0` is read from `mix.exs` at compile time, so it can no longer
  drift from the package version.

### Changed

- Dependency refresh: `phoenix_kit` 2.64.1 and its transitive set.

## 0.2.3 - 2026-08-21

### Changed

- **The connections tab strip uses core's `<.nav_tabs>`** (`:patch`,
  `:badge_class`, nil-tolerant badges) instead of hand-rolled
  `tabs-boxed` markup (#7).

  **Requires `phoenix_kit` 2.13.5+ at runtime.** Tab link keys live in a
  runtime map, so against an older core this compiles and renders a
  strip of dead buttons rather than failing to compile. Upgrade core
  first.

## 0.2.2 - 2026-08-11

### Fixed

- **`PhoenixKitUserConnections.version/0` reported 0.2.0 in the 0.2.1
  release.** The version is kept in three places — `mix.exs`, the hardcoded
  `version/0`, and the test asserting it — and 0.2.1 moved only the first, so
  the published package reported a version it was not and its own version test
  failed. All three move together here.

## 0.2.1 - 2026-08-11

### Changed

- Dependency updates: `phoenix_kit` 2.2.0 and the transitive set it pulls
  (`phoenix` 1.8.10, `hackney` 4.7.3). No source changes in this package.

## 0.2.0 - 2026-08-10

### Changed

- **⚠️ Requires `phoenix_kit ~> 2.0`.** The core pin moved to `~> 2.0`, so this
  release no longer resolves against core 1.7.

  Core 2.0.0 squashes the migration chain into a single `V135` baseline and makes
  V135 the chain's floor: `mix ecto.migrate` now *refuses* on a database below it
  rather than migrating. Check `mix phoenix_kit.status` **before** upgrading. A
  host below V135 must install `phoenix_kit 1.7.236` — the migration bridge, the
  last release carrying the full pre-squash chain — migrate until the reported
  version is at least V135, and only then move to 2.0.

  This package does not call migration internals, so the change is the pin
  itself.

## 0.1.2 - 2026-06-17

### Changed
- Moved each admin page's title/subtitle into the top navbar (via the `@page_subtitle` assign forwarded by core's admin layout) and removed the in-page `admin_page_header`, matching the new PhoenixKit admin header pattern used across core's pages.
- **Mobile optimization** of both pages. The "My Connections" tab bar now scrolls horizontally and each list row truncates long emails so the action buttons stay on-screen (`min-w-0`/`truncate`/`shrink-0`). The admin "Connections" page no longer overflows horizontally on mobile: the daisyUI `.stat` and `.label` components (which don't shrink under `min-w-0`) were replaced with plain blocks that wrap.
- "My Connections" tabs now use LiveView `patch` navigation instead of `navigate`, and the redundant initial tab-data query was dropped from `mount/3` (`handle_params/3` already loads it). Switching tabs no longer re-mounts the LiveView or re-runs the five per-tab count queries.

### Fixed
- Restored the in-page heading on the user-facing "My Connections" page. Moving the title into the navbar (above) is correct for the admin "Connections" page, which renders in core's admin layout, but the authenticated user dashboard layout does not surface `@page_title`/`@page_subtitle` in its navbar — so the user page was left with no visible heading. It now renders its own header from the same assigns.
- Corrected the `css_sources/0` test to assert the atom form the callback returns (`[:phoenix_kit_user_connections]`); it had asserted the string form and was failing under `mix test`.
- Synced the `version/0` callback to `0.1.2` (it was stale at `0.1.0`).

## 0.1.1 - 2026-04-11

### Fixed
- Add routing anti-pattern warning to AGENTS.md

## v0.1.0 — 2026-03-29

### Features

- Extract user connections module from PhoenixKit core into standalone package
- One-way follow relationships (no consent required)
- Two-way mutual connections with request/accept/reject flow
- User blocking with automatic follow/connection cleanup
- Full history logging for follows, connections, and blocks
- Admin dashboard with statistics and module toggle
- User-facing LiveView for managing personal connections
- Auto-accept when both users have pending requests to each other
