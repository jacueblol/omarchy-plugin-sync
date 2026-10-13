# Plugin Sync

Keep your Omarchy plugins and bar layout the same on every machine. Plugin
Sync records which plugins you have installed and how your bar is arranged in
a private git repo you own. Your other machines read that repo and install,
remove, and arrange their plugins to match.

Each machine chooses what it syncs and when. Nothing changes on a machine
without your say-so: by default a machine only shares its own changes, and
applying changes from elsewhere is a **Pull** you confirm after seeing exactly
what it will do.

It works alongside [Omaplug](https://github.com/fross100/omaplug): install,
update, or remove plugins and arrange the bar in Omaplug as usual, and Plugin
Sync notices and shares the change. After a pull, Omaplug's list refreshes on
its own.

![Plugin Sync panel](preview.png)

## Install

```sh
omarchy plugin add https://github.com/jacueblol/omarchy-plugin-sync --enable
```

### Set up the sync repo

Open the panel and click **Set up sync repo**. A terminal opens and, after
asking, creates a private `<your-github-user>/omarchy-sync` repo with the
GitHub CLI (`gh`), then pushes this machine's plugins and layout to it.

To use another name or host, enter it under **Settings › Sync repo** first
(`owner/name` on GitHub, or any git URL you can push to, such as
`git@gitlab.com:you/omarchy-sync.git` or a path to a bare repo on a shared
drive). `gh` is only needed to create a GitHub repo for you.

### Add another machine

Install the plugin there, open the panel, and click **Set up sync repo**. It
finds the existing repo and connects to it instead of creating one. Review
**Settings** on that machine, then click **Pull**: the panel lists the
plugins it will install or remove and the settings it will replace, and
nothing happens until you confirm.

## Usage

The bar icon spins while syncing and shows a dot when there is something to
push or pull.

| State | Meaning |
|---|---|
| In sync | Everything this machine syncs matches the repo |
| Changes to push | You changed plugins or the bar here |
| Changes to pull | Another machine shared changes |
| Both changed | Each side changed since this machine last synced. Choose **Push** or **Pull** |
| First sync here | This machine has never synced. Usually **Pull** |

| Action | Mouse | Keyboard |
|---|---|---|
| Share this machine's changes | **Push** | `p` |
| Apply changes from other machines | **Pull** (confirm) | `l` |
| Open Omaplug | **Omaplug** | `m` |
| Settings | gear icon | `s` |
| Back / close | click outside | `Esc` |

From a terminal or a keybinding:

```sh
omarchy-shell shell toggle io.github.jacueblol.plugin-sync
omarchy-shell io.github.jacueblol.plugin-sync settings
omarchy-shell io.github.jacueblol.plugin-sync sync    # does what the Automatic sync setting allows
omarchy-shell io.github.jacueblol.plugin-sync push
omarchy-shell io.github.jacueblol.plugin-sync pull    # applies without the confirmation step
```

## Configure

Open the panel and click the gear (or press `s`). Settings are saved in this
machine's `~/.config/omarchy/shell.json` and are never synced, so each machine
can sync different things.

| Setting | Default | What it does |
|---|---|---|
| Installed plugins | on | Install plugins another machine added, and sync which plugins are enabled |
| Remove plugins removed elsewhere | on | Let a pull remove plugins the repo no longer lists. Plugins with uncommitted local changes are never removed |
| Bar layout | on | Widget order, bar position, and widget settings |
| Other shell settings | off | Everything else in `shell.json`, such as idle and lock timers |
| Notify after automatic pulls | on | Desktop notification when a pull ran on its own |
| Automatic sync | Push automatically | **Manual**: only shows the state. **Push automatically**: shares this machine's changes, but other machines' changes wait for your Pull. **Push and pull automatically**: also applies other machines' changes without asking |
| When both machines changed | Ask | **Ask**, **Keep this machine** (push), or **Use the repo** (pull, only in Push and pull mode) |
| Check other machines every | 15 minutes | Local changes are noticed within a minute |
| Machine-specific plugins | none | Plugins that stay on this machine only: never installed, removed, or moved by a sync, and their bar position is kept |
| Sync repo | empty | `owner/name` on GitHub, or any git URL |

Pushing only replaces the parts this machine syncs, so a laptop that doesn't
sync shell settings never overwrites the desktop's.

The same settings can be scripted:

```sh
omarchy bar set io.github.jacueblol.plugin-sync mode "Push and pull automatically"
omarchy bar set io.github.jacueblol.plugin-sync syncShellSettings true --json
omarchy bar set io.github.jacueblol.plugin-sync localOnly "omarchy.battery,acme.vpn"
omarchy bar move io.github.jacueblol.plugin-sync --section right
```

## What gets synced

- **plugins.json**: the id and git URL of every git-managed plugin in
  `~/.config/omarchy/plugins/`. A pull installs missing ones with
  `omarchy plugin add` and removes dropped ones with `omarchy plugin remove`.
  Plugins without a git origin (hand-made or symlinked development plugins)
  are left alone and listed as not synced.
- **shell.json**: the parts each machine chooses to sync. A pull backs up the
  old file to `shell.json.bak.<timestamp>` before changing it.

Plugin versions are not pinned. Each machine updates plugins on its own,
through Omaplug or `omarchy plugin update`.

## Security

Plugins run unsandboxed, and a pull installs the plugins the sync repo lists.
Keep the repo private, and only give yourself write access. With the default
settings, every pull shows that list first and waits for you.

No sudo or pkexec is required. Plugin Sync runs `git`, `jq`, `flock`,
`notify-send`, `gh` (only when creating the repo during setup), the
`omarchy plugin` and `omarchy bar` commands, and `omarchy-shell` IPC. It
writes only to `~/.config/omarchy/shell.json` (on a pull, after a backup),
`~/.config/omarchy/plugins/` (through `omarchy plugin`), and its own state in
`~/.local/state/omarchy-plugin-sync/`.

## Dependencies

`git`, `jq`, `flock` (util-linux), and `notify-send` (libnotify) ship with
Omarchy.

The GitHub CLI is optional. It is only needed to have setup create a GitHub
repo for you, and it lets git push to GitHub over HTTPS:

```sh
omarchy pkg add github-cli
gh auth login
```

Without it, create the repo yourself and enter its SSH URL under
**Settings › Sync repo**.

## Remove

```sh
omarchy plugin remove io.github.jacueblol.plugin-sync
rm -rf ~/.local/state/omarchy-plugin-sync   # local copy of the sync repo
```

Removing the plugin leaves your plugins and bar as they are. The sync repo
stays on GitHub; delete it there if you no longer want it.

## License

[MIT](LICENSE)
