# Changelog

All notable changes to PhoenixKitUserConnections will be documented in this file.

## 0.1.2 - 2026-06-17

### Changed
- Moved each admin page's title/subtitle into the top navbar (via the `@page_subtitle` assign forwarded by core's admin layout) and removed the in-page `admin_page_header`, matching the new PhoenixKit admin header pattern used across core's pages.
- **Mobile optimization** of both pages. The "My Connections" tab bar now scrolls horizontally and each list row truncates long emails so the action buttons stay on-screen (`min-w-0`/`truncate`/`shrink-0`). The admin "Connections" page no longer overflows horizontally on mobile: the daisyUI `.stat` and `.label` components (which don't shrink under `min-w-0`) were replaced with plain blocks that wrap.

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
