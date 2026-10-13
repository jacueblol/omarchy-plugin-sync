# Plugin Sync

Keep your Omarchy plugins and bar layout the same on every machine. Plugin
Sync records which plugins you have installed and your bar layout in a private
git repo. Other machines read that repo and install, remove, and arrange their
plugins to match.

It works alongside [Omaplug](https://github.com/fross100/omaplug): install,
update, or remove plugins and arrange the bar in Omaplug as usual, and Plugin
Sync notices the change and pushes it. After a pull, Omaplug's list refreshes
on its own.

## Install

```sh
omarchy plugin add https://github.com/jacueblol/omarchy-plugin-sync --enable
```

### Set up the sync repo

Open the panel and click **Set up sync repo**. A terminal opens and creates a
private `<your-github-user>/omarchy-sync` repo using the GitHub CLI (`gh`),
then pushes this machine's plugins and layout to it. To use a different
repo or host, set the widget's **Sync repo** setting first (`owner/name`, or
any git URL you can push to).

### Add another machine

Install the plugin on the other machine (command above), open the panel, and
click **Set up sync repo**. It finds the existing repo and connects to it
instead of creating a new one. If you used a custom repo name, set it first:

```sh
omarchy bar set io.github.jacueblol.plugin-sync repo yourname/omarchy-sync
```

Then click **Pull**. This machine adopts the shared plugins and bar layout.
From then on both machines stay in sync.

## Usage

The bar icon spins while syncing and shows a dot when one side has changes.

| State | Meaning | What happens |
|---|---|---|
| In sync | Both machines match | Nothing |
| Changes to push | You changed plugins or the bar here | Auto-sync pushes them |
| Changes to pull | The other machine changed | Auto-sync pulls them |
| Both changed | Each machine changed since the last sync | You choose **Push** (this machine wins) or **Pull** (the repo wins) |
| First sync here | This machine has never synced | You choose, usually **Pull** |

| Action | Mouse | Keyboard |
|---|---|---|
| Make the repo match this machine | **Push** | `p` |
| Make this machine match the repo | **Pull** | `l` |
| Open Omaplug | **Omaplug** | `m` |
| Close | click outside | `Esc` |

From a terminal or keybinding:

```sh
omarchy-shell io.github.jacueblol.plugin-sync sync    # push or pull, whichever side changed
omarchy-shell io.github.jacueblol.plugin-sync push
omarchy-shell io.github.jacueblol.plugin-sync pull
omarchy-shell shell toggle io.github.jacueblol.plugin-sync
```

The helper script also works on its own:
`plugin-sync status | push | pull | auto | init [owner/name]`.

## Configure

| Setting | Default | |
|---|---|---|
| `repo` | empty | `owner/name` on GitHub, or any git URL |
| `autoSync` | `true` | Push or pull automatically when only one side changed |
| `intervalMinutes` | `15` | How often to check the remote. Local changes are checked every minute |

```sh
omarchy bar set io.github.jacueblol.plugin-sync autoSync false
omarchy bar move io.github.jacueblol.plugin-sync --section right
```

## What gets synced

- **Plugins**: the id and git URL of every git-managed plugin in
  `~/.config/omarchy/plugins/`. Pulling installs missing plugins with
  `omarchy plugin add` and removes dropped ones with `omarchy plugin remove`.
  A plugin with uncommitted local changes is never removed, and plugins
  without a git origin (hand-made or symlinked development plugins) are left
  alone and listed as not synced.
- **Bar layout and settings**: all of `~/.config/omarchy/shell.json`,
  including widget settings, enabled plugins, and idle timings. A pull backs
  up the old file to `shell.json.bak.<timestamp>` before replacing it.

Plugin versions are not pinned. Each machine updates plugins on its own,
through Omaplug or `omarchy plugin update`.

## Security

Plugins run unsandboxed. A pull installs whatever plugins the sync repo lists,
so keep the repo private and only give write access to yourself. Plugin Sync
never uses sudo. It runs `git`, `gh` (only during setup), `jq`, the
`omarchy plugin` commands, and `omarchy-shell` IPC.

## Dependencies

`git`, `jq`, `flock`, and `notify-send` ship with Omarchy. `gh` is needed
only to create the repo during setup, and it also lets git push to GitHub
over HTTPS.

## Remove

```sh
omarchy plugin remove io.github.jacueblol.plugin-sync
rm -rf ~/.local/state/omarchy-plugin-sync   # local clone of the sync repo
```

The sync repo itself stays on GitHub. Delete it there if you no longer want
it.

## License

[MIT](LICENSE)
