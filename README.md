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

You should see a **ROLL** button at the bottom of the screen, a stats panel top-right, and four
podiums in front of you. In the Output window (**View → Output**):

```
[Server] Started 3 service(s).
[Client] Started 2 controller(s).
```

Click **ROLL** (or press **R**). A card shows the dice spinning, lands on your number, and
names the TV you won — and your podium's screen changes colour and grows to match. Keep rolling
until you hit a 6 and the upgrade prompt appears.

### Testing the 6 without waiting for luck

A 6 is a 1-in-6 chance, which is tedious to wait for when you're checking the upgrade flow.
Open the **Command Bar** during a playtest and force one:

```lua
local rs = require(game.ServerScriptService.Server.services.RollService)
local p = game.Players:GetPlayers()[1]
local pd = require(game.ServerScriptService.Server.services.PlayerDataService)
-- Jump straight to a chosen dice tier (1 = Basic … 5 = Diamond)
pd:SetDiceTier(p, 4)
-- Hand out a specific TV by score, 1..30
pd:AwardTv(p, 30)
```

`SetDiceTier(p, 5)` then rolling is the quickest way to confirm Diamond makes **no** upgrade
offer, since there's no tier above it.

### Testing 4 players

In Studio: **Test** tab → set **Players** to 4 → **Start**. You get four client windows plus a
server window, and each should claim its own podium with its name above it. Watch that a fifth
can't join — `Players.MaxPlayers` is 4.

While `rojo serve` runs, saving any file in `src/` updates Studio instantly — no re-sync, no
copy-paste. Edit `Config.luau` and the change is there before you switch windows.

### Without Studio syncing

`rojo build --output RollForTVs.rbxlx` writes a standalone place file you can double-click to
open in Studio. Useful for a quick check, but it's a snapshot — it won't live-update, so
`rojo serve` is what you want day to day.

## Tests

```sh
lune run tests/gamelogic     # run from the repo root
```

[tests/gamelogic.luau](tests/gamelogic.luau) checks the progression maths headlessly — no
Studio, no Roblox. It loads `DiceTiers` and `TvCatalog` with stubbed `Color3`/`Vector3` and
asserts the invariants that would silently break the game if the balance data drifted:

- all 30 catalog entries exist and are well-formed
- TV values strictly increase across the whole ladder
- every `(dice, face)` pair maps to a real TV, covering scores 1–30 **exactly once** — no gaps,
  no duplicates
- each dice's worst roll beats the tier below's best roll
- `get()` clamps out-of-range scores instead of returning nil
- value formatting and screen sizing

If you add a dice tier or TVs, run this before playtesting — it catches an off-by-one in
`ScoreOffset` in a second, which is otherwise a subtle "some TVs are unobtainable" bug.

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

## How the game works

Roll a dice, get a TV. Higher roll, better TV. Roll a 6 and you're offered a better dice,
which raises the floor on everything you roll after that. Four players per server.

### The score ladder

Rather than each dice having its own reward table, every dice rolls 1–6 and adds its
`ScoreOffset` to produce a **score from 1 to 30**. That score indexes straight into a single
flat list of 30 TVs:

| Dice | Rolls score | TVs you can get | Rarity |
| --- | --- | --- | --- |
| Basic | 1–6 | Smashed Portable TV → Wood-Panel Console TV | Junk |
| Bronze | 7–12 | Chunky Colour CRT → 37" Widescreen LCD | Common |
| Silver | 13–18 | 40" 1080p LED → 65" 4K QLED | Decent |
| Gold | 19–24 | 65" OLED → Rollable OLED | Elite |
| Diamond | 25–30 | Transparent MicroLED → The Infinite Screen | Legendary |

The nice property of this model: because each tier's window starts one above the last tier's
best, **a better dice can never roll worse than the dice below it at its luckiest**. Upgrading
is always strictly good, so the choice on a 6 is never a trap. Values run £5 → £50,000.

To rebalance, edit [TvCatalog.luau](src/shared/TvCatalog.luau) — names, values and colours are
all data. To add a sixth dice, add a tier to [DiceTiers.luau](src/shared/DiceTiers.luau) with
`ScoreOffset = 30` and six more TVs to the catalog.

### Rolling a 6

`RollService` compares the roll against the dice's own `Sides` rather than hard-coding 6, so a
tier with different dice still works. On a max face the server sets `PendingUpgrade` and sends
the offer. That flag **blocks further rolls until you choose**, so a 6 can't be banked and
cashed in later. Declining is allowed and just clears the flag.

At Diamond there's no tier above, so no offer is made — a 6 is simply a 6.

### Server authority

The client sends `RequestRoll` with **no arguments** and never sends a number, score, or TV.
The server rolls, picks the TV, stores it, and replicates the result; the dice-spin animation
on screen is decoration played *after* the real answer has arrived. A modified client can spam
the button but can't choose its own outcome, and a 1.5s cooldown is enforced server-side.

### What's in each file

| File | Job |
| --- | --- |
| [DiceTiers.luau](src/shared/DiceTiers.luau) | The five dice and their score windows |
| [TvCatalog.luau](src/shared/TvCatalog.luau) | 30 TVs, indexed by score, plus size/value helpers |
| [PlayerDataService.luau](src/server/services/PlayerDataService.luau) | Owns dice tier + collection; the only thing that mutates player state |
| [RollService.luau](src/server/services/RollService.luau) | Rolls, awards, cooldown, upgrade offers |
| [TvDisplayService.luau](src/server/services/TvDisplayService.luau) | Four podiums, built in code, showing each player's best TV |
| [HudController.luau](src/client/controllers/HudController.luau) | Top-right stats panel |
| [RollController.luau](src/client/controllers/RollController.luau) | Roll button, result card, upgrade prompt |

### Player cap

`Players.MaxPlayers = 4` is set in [default.project.json](default.project.json), because
`MaxPlayers` is a place property and can't be assigned from a script at runtime. `Config.MaxPlayers`
mirrors it so the podium layout builds the right number of slots — **keep the two in step**.

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
