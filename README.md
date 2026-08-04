# Roll For TVs

Repo: <https://github.com/asha23/roblox-roll-for-tvs>

Code lives in `src/` as real `.luau` files. Rojo syncs them into Roblox Studio, so you edit
in your editor and Studio updates live. Studio is only for building the map, testing, and publishing.

## One-time setup

Already done on Ash's machine. On a new machine:

1. Install [Rokit](https://github.com/rojo-rbx/rokit) (toolchain manager):

   ```sh
   curl -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
   ```

   Then add it to your PATH (`~/.bash_profile` or `~/.zshrc`) — the installer doesn't:

   ```sh
   export PATH="$HOME/.rokit/bin:$PATH"
   ```

2. Install the tools pinned in `rokit.toml`:

   ```sh
   rokit install
   ```

3. Install the **Rojo** plugin into Studio:

   ```sh
   rojo plugin install
   ```

   Lands at `~/Documents/Roblox/Plugins/RojoManagedPlugin.rbxm`.

## Testing the game

```sh
rojo serve
```

Leave that running, then in Studio:

1. **File → New** to get a baseplate (you need a place open before Rojo can sync into it).
2. Open the **Plugins** tab → click **Rojo** → **Connect** (the address `localhost:34872`
   is already filled in).
3. The Explorer now shows `ServerScriptService.Server`, `StarterPlayerScripts.Client`, and
   `ReplicatedStorage.Shared`.
4. Press **F5** (or Home → Play) to playtest.

You should see a **Coins: 0** box in the top-right corner, and in the Output window
(**View → Output**):

```
[Server] Started 1 service(s).
[Client] Started 1 controller(s).
```

That confirms the whole chain works: the loaders found their modules, the remotes were created
on the server and resolved on the client, and the HUD round-tripped a value through
`GetPlayerData`. Your character will also move at the `WalkSpeed` set in
[Config.luau](src/shared/Config.luau).

To prove the server→client path is live, open the **Command Bar** during a playtest and run:

```lua
require(game.ServerScriptService.Server.services.PlayerDataService):AddCoins(game.Players:GetPlayers()[1], 25)
```

The HUD should jump to **Coins: 25**.

While `rojo serve` runs, saving any file in `src/` updates Studio instantly — no re-sync, no
copy-paste. Edit `Config.luau` and the change is there before you switch windows.

### Without Studio syncing

`rojo build --output RollForTVs.rbxlx` writes a standalone place file you can double-click to
open in Studio. Useful for a quick check, but it's a snapshot — it won't live-update, so
`rojo serve` is what you want day to day.

## Other commands

```sh
rojo build -o RollForTVs.rbxlx   # build a place file without Studio
stylua src                       # format
stylua --check src               # verify formatting (what CI runs)
wally install                    # fetch dependencies from wally.toml
```

### Selene is CI-only on Intel Macs

`selene src` fails locally with `Bad CPU type in executable`. Selene ships an **arm64-only**
macOS binary and this machine is Intel `x86_64` — Rosetta can't help, it translates x86→arm,
not the reverse. Every recent selene version has the same problem, so downgrading won't fix it.

CI runs on Linux, so linting happens there on every push. If you want it locally, build from
source with `cargo install selene`.

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

[.github/workflows/ci.yml](.github/workflows/ci.yml) format-checks with StyLua, lints with
Selene, runs `rojo build`, and uploads the resulting `.rbxlx` as an artifact — on every push
to `main` and every PR.

GitHub blocks pushing workflow files unless your token carries the `workflow` scope. If a
push is rejected with *"refusing to allow an OAuth App to create or update workflow"*:

```sh
gh auth refresh -s workflow   # opens a browser to re-authorise
git push
```

## Notes

- Never trust the client. Validate every remote argument on the server.
- The map itself (parts, models, terrain) stays in Studio and is committed as the `.rbxlx`
  place file, or exported to `.rbxm` — Rojo handles code, not level geometry, unless you
  explicitly add model paths to `default.project.json`.
