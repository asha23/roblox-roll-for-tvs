# Roll For TVs

Repo: <https://github.com/asha23/roblox-roll-for-tvs> (private)

Code lives in `src/` as real `.luau` files. Rojo syncs them into Roblox Studio, so you edit
in your editor and Studio updates live. Studio is only for building the map, testing, and publishing.

## One-time setup

1. Install [Rokit](https://github.com/rojo-rbx/rokit) (toolchain manager):

   ```sh
   curl -fsSL https://github.com/rojo-rbx/rokit/releases/latest/download/rokit-installer.sh | sh
   ```

2. Install the tools pinned in `rokit.toml`:

   ```sh
   rokit install
   ```

3. Install the **Rojo** plugin into Studio:

   ```sh
   rojo plugin install
   ```

## Daily workflow

```sh
rojo serve          # start the sync server
```

Then in Studio: open a new baseplate, click the **Rojo** button in the Plugins tab, and hit
**Connect**. Your `src/` files now appear in the Explorer and update as you save.

Other commands:

```sh
rojo build -o game.rbxlx   # build a place file without Studio
stylua src                 # format
selene src                 # lint
wally install              # fetch dependencies from wally.toml
```

## Where things go

| Path | Syncs to | Use for |
| --- | --- | --- |
| `src/server/services/` | `ServerScriptService.Server.services` | Anything authoritative: data, rounds, rewards, anti-cheat |
| `src/client/controllers/` | `StarterPlayerScripts.Client.controllers` | UI, input, camera, local effects |
| `src/shared/` | `ReplicatedStorage.Shared` | Config, remotes, utilities both sides need |
| `Packages/` | `ReplicatedStorage.Packages` | Wally dependencies (gitignored, generated) |

### Adding a feature

Drop a new module into `services/` or `controllers/`. The entry-point scripts auto-require
every module in those folders and call `:Init()` on all of them, then `:Start()`. So:

```lua
--!strict
local MyService = { Name = "MyService" }

function MyService:Init() end   -- set up state, wire remote handlers
function MyService:Start() end  -- connect events, start loops

return MyService
```

`Init` runs on every module before any `Start` does, so cross-module references are safe by `Start`.

### Adding a remote

Add the name to the `EVENTS` or `FUNCTIONS` list in [src/shared/Remotes.luau](src/shared/Remotes.luau).
The server creates the instance and the client waits for it — nothing to place by hand.

## What's already wired up

- `PlayerDataService` — gives each player a coin count, applies walk/jump speed from `Config`,
  and replicates coin changes. Call `PlayerDataService:AddCoins(player, 5)` from any other service.
- `HudController` — a coin counter in the top-right, built in code, synced to the server.

Both are working examples, safe to gut and replace.

## CI

A GitHub Actions workflow sits at `.github/workflows/ci.yml`, untracked — pushing it needs a
token scope the local `gh` login doesn't have. Enable it with:

```sh
gh auth refresh -s workflow
git add .github && git commit -m "Add CI workflow" && git push
```

It formats-checks, lints, and builds a place file on every push and PR, uploading the
`.rbxlx` as a build artifact.

## Notes

- Never trust the client. Validate every remote argument on the server.
- The map itself (parts, models, terrain) stays in Studio and is committed as the `.rbxlx`
  place file, or exported to `.rbxm` — Rojo handles code, not level geometry, unless you
  explicitly add model paths to `default.project.json`.
