# Grok Review — PR #7 "Use core's nav_tabs for the connections tab strip, and fix the daisyUI tabs class"

**Merge commit:** 63d246e
**Author:** mdon (fix/daisyui-tabs-box)
**Files:** `lib/phoenix_kit_user_connections/web/user_connections.html.heex`

## Summary of the change

The connections tab strip was the example in core `nav_tabs`' own
moduledoc, and it was still hand-rolled — `patch` links, a
`badge-warning` pending-requests count shown only when non-zero, and
daisyUI 4's `tabs-boxed`. Core 2.13.5 is what made adoption possible
(`:patch`, `:badge_class`, nil-tolerant badges). This PR is that
adoption.

Followers / following / connections / blocked still always show their
count (including zero), matching the original. Requests uses
`badge: if(@pending_count > 0, do: @pending_count)` plus
`badge_class: "badge-warning"`.

**Requires phoenix_kit 2.13.5+ at runtime.** Tab link keys live in a
runtime map, so against an older core this compiles and renders a strip
of dead buttons (`phx-click={nil}`) rather than failing to compile. The
core pin stays `~> 2.0` (a three-segment pin is the trap the 2.0 sweep
existed to fix). Hosts must upgrade core first; the CHANGELOG says so.

## Findings

None. The original `Routes.path/1` wrapping is now inside `nav_tabs`;
paths are passed raw (`/profile/connections?tab=…`) so they are not
double-prefixed.
