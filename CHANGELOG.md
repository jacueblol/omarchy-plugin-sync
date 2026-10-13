# Changelog

## 1.1.0

- Settings view in the panel (gear icon or `s`): choose what this machine
  syncs (installed plugins, bar layout, other shell settings), whether pulls
  remove plugins, machine-specific plugins, automatic sync mode, conflict
  handling, check interval, and notifications.
- Settings are per machine and never synced. Pushing only replaces the parts
  this machine syncs.
- Pulls are confirmed first with the exact plugins and settings they change.
  The default mode shares this machine's changes automatically and waits for
  you before applying anyone else's.
- Machine-specific plugins keep their place in the bar across pulls.
- A failed merge never writes `shell.json` or the repo.
- `settings` IPC method.

## 1.0.0

- First release.
