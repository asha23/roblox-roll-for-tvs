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

You spawn just inside the door of a TV shop, looking down the room at four display podiums. A
**ROLL** button sits at the bottom of the screen and a stats panel top-right. In the Output
window (**View → Output**):

```
[ShopService] Built the shop (N parts).
[BackroomsService] Built the Backrooms (N parts).
[Server] Started 6 service(s).
[Client] Started 3 controller(s).
```

Click **ROLL** (or press **R**). A 3D die is thrown out in front of you, tumbles through the
air, and lands showing your number. Only then does the result card name the TV you won — and
your podium builds that actual telly. Keep rolling until you hit a 6 and the upgrade prompt
appears.

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
- every catalog `Style` has a matching builder in `TvBuilder`, and vice versa
- **each face's landing rotation really does turn that face to `+Y`** — the stub implements
  `CFrame.Angles` as a genuine rotation matrix, so this is checked arithmetically rather than
  trusted
- the die is a real die: opposite faces sum to 7 with exactly opposite normals, all six normals
  and surfaces are distinct, face *n* has *n* pips, and no pip sits outside its face
- `GrantWithoutPaying` is off, so a build that hands out free dice upgrades can't ship
- the roll-a-1 penalty costs something but can't wipe out a whole tier in one go
- the Backrooms are at least as wide as the shop, so the flank walls aren't negative width
- the podium row fits inside the shop — no plinth pokes through a side wall, adjacent podiums
  don't overlap, and there's walking room behind them. Resize the shop and this tells you
  immediately instead of you finding it in Studio

If you add a dice tier or TVs, run this before playtesting — it catches an off-by-one in
`ScoreOffset` in a second, which is otherwise a subtle "some TVs are unobtainable" bug, and it
catches a die that would quietly land on the wrong number.

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

### Rolling a 1

Rolling the lowest face knocks every TV you already own down a level (`Config.Penalty
.DowngradeLevels`), floored at the worst TV in the game.

Two details that aren't arbitrary:

- **The penalty lands before the new TV is awarded**, so the telly you just won arrives at
  full value and only what you already had degrades. The other order would have a 1
  immediately devalue its own prize.
- **A 1 still awards its TV.** Skipping the award would make the five tier-floor TVs — scores
  1, 7, 13, 19 and 25 — permanently unobtainable, which the coverage test would catch.

`DowngradeCollection` recomputes `TotalValue` and `BestScore` from the list rather than
adjusting them by a delta, because the best TV may now be a different one entirely.

### Paying for an upgrade

There's a **Upgrade dice · 25 R$** button, so you don't have to wait for a 6.

**This needs setting up before it works.** The price is not in the code — it lives on a Roblox
Developer Product:

1. On the game's page, create a **Developer Product** priced at **25 Robux**.
2. Paste its ID into `Config.Monetisation.DiceUpgradeProductId`.
3. Keep `Config.Monetisation.DisplayPrice` in step with the real price.

Real purchases don't work on an unpublished place, so for local testing set
`Config.Monetisation.GrantWithoutPaying = true` — it grants the upgrade without taking any
Robux. **The test suite fails while that flag is on**, deliberately: shipping it would hand out
free upgrades forever and nothing in the game would look wrong.

The delicate part is `ProcessReceipt` in
[MonetisationService.luau](src/server/services/MonetisationService.luau). Roblox calls it
repeatedly until it returns `PurchaseGranted`, so it must be idempotent, and it must never
report success for something it failed to hand over — that takes the player's Robux and gives
nothing. It therefore returns `NotProcessedYet` when the player has left, when granting
errored, and when the product isn't ours.

**Known gap:** honoured `PurchaseId`s are held in memory, so a server restart mid-purchase
could grant twice. The fix is a DataStore keyed on `PurchaseId`, worth adding at the same time
as saving player data.

### Rolling a 6

`RollService` compares the roll against the dice's own `Sides` rather than hard-coding 6, so a
tier with different dice still works. On a max face the server sets `PendingUpgrade` and sends
the offer. That flag **blocks further rolls until you choose**, so a 6 can't be banked and
cashed in later. Declining is allowed and just clears the flag.

At Diamond there's no tier above, so no offer is made — a 6 is simply a 6.

### The shop

The game is set inside a TV shop, built entirely in code by
[ShopService.luau](src/server/services/ShopService.luau) from the numbers in `Config.Shop` —
nothing to model in Studio, and the room resizes by changing `HalfWidth`, `BackZ` and `FrontZ`.

Looking in from the street:

```
z = -60   back wall · neon shop sign · four display podiums in front of it
z =   0   shop floor · shelving down both side walls · video wall left · counter right
z = +30   shopfront glass with a doorway · spawn just inside, facing the podiums
```

What's in there: marble floor in two shades with a runner leading your eye to the podiums,
skirting round the inside edge, twelve lit ceiling panels, a neon shop sign on the back wall,
a 4×3 video wall of demo screens each a different colour, five shelf units stocked with little
boxy tellies, a checkout counter with a till and leaflets, and a glass shopfront with sills,
mullions and a signed header that reads from both sides.

`Lighting` in [default.project.json](default.project.json) is tuned for an interior — dark
`Ambient` so the shop's own lights do the work, plus `Atmosphere`, `BloomEffect` (so the neon
and the TV screens bloom), `ColorCorrectionEffect` and a touch of `SunRaysEffect` through the
shopfront.

Two things worth knowing if you edit it:

- **Every decorative light has `Shadows = false`.** There are around two dozen of them, and under
  Future lighting each shadow-casting light is expensive. The room looks the same lit flatly;
  the TVs keep their shadows, where it actually reads.
- **`settleGround` drops Studio's baseplate by one stud.** Its top sits at `y=0`, exactly where
  the shop floor goes, and two coplanar faces flicker against each other. It also deletes any
  existing `SpawnLocation` so players can't appear outside the shop — a baseplate template ships
  with one at the origin. With no baseplate at all (a place from `rojo build`) it lays pavement
  instead.

### The 3D die

The die is a real part thrown into the world, with pips drawn on all six faces. It is
**deliberately not physics-driven**, and that's the important design decision in the whole
file — worth understanding before changing it.

The server decides the number *before* anything is drawn. A physics die would either have to
contradict that number when it came to rest, or *become* the source of truth — which would hand
outcome control to the client and make the die land differently for every player watching.

So the tumble is scripted, and lands on target *by construction* rather than by correction. The
rotation applied at time `t` is:

```lua
CFrame.Angles(2*pi * turns.X * t, 2*pi * turns.Y * t, 2*pi * turns.Z * t) * landOrientation
```

Because `turns` are whole numbers, at `t = 1` the spin term is exactly the identity, leaving
only `landOrientation`. The die comes to rest on precisely the right face with **no snap or
correction at the end** — and it's impossible for it to settle on the wrong number.

[DiceGeometry.luau](src/shared/DiceGeometry.luau) holds the maths: which axis each numbered face
points along, which part face its pips are drawn on, and the rotation that turns that face
skyward. Pips and landing maths are generated from the same table, so they can't drift apart.
The test suite verifies each `landOrientation` really does rotate its face to `+Y`.

The die is built client-side, so it isn't replicated and costs the server nothing. The flip side:
**you can't see other players' dice**, only your own. Moving it server-side would fix that at the
cost of replication traffic.

**Bouncing.** The throw raycasts forward first. With a clear path it's a single arc; with
something in the way — a telly, a podium, a wall — it flies out, stops short, and rebounds back
towards you to settle on the floor where you can still read it. Before this it sailed straight
through the screen.

That's also why every part in `TvBuilder` has `CanQuery = true` despite nothing colliding with
it: with queries off, the forward raycast didn't see the tellies at all. Both throw shapes finish
exactly at the resting point, so the exact-landing property above still holds.

### Camera and mouse

`StarterPlayer.EnableMouseLockOption` is on, so **Shift toggles mouse-look** and the mouse steers
the camera directly. Without it you're on Roblox's default third-person camera, where you have to
hold **right mouse button** to look around — which is stock behaviour, not a bug, but it surprises
everyone.

### TVs that look like their name

[TvBuilder.luau](src/shared/TvBuilder.luau) constructs each telly out of parts at runtime, from a
`Style` on the catalog entry — so the model matches the description:

| Style | What gets built |
| --- | --- |
| `portable` | Small deep box, carry handle, leaning aerial, tuning dials |
| `crt` | Fat cathode-ray body with a tapered tube out the back, thick bezel, three dials |
| `console` | Wooden cabinet on four splayed legs, speaker grille, screen sunk into the panel |
| `plasma` | Early flat panel — still thick, heavy bezel, chunky base |
| `lcd` | Ordinary flatscreen, moderate bezel, neck-and-base stand |
| `oled` | Near-bezel-less panel 0.16 studs thick on a blade foot |
| `projector` | Projector box with a lens, a translucent beam, and a floating frameless image |
| `rollable` | Panel rising out of a horizontal drum |
| `transparent` | See-through glass panel lit by neon edge strips |
| `lcdFeet` | Same panel on two splayed end feet rather than a centre neck |
| `soundbar` | Flatscreen with a soundbar and grille slots beneath it |
| `curved` | Curved screen faked with three angled segments — reads as a curve for three parts |
| `wallmount` | Bracketed off a wall plate, no floor stand |
| `holo` | Floating pane above an emitter puck, no stand at all |

Screens use `Neon` and carry a `PointLight` tinted to the screen colour, brighter up the ladder —
a Diamond TV lights the ground around its podium. Every model is assembled around an origin at
its **bottom centre** with an invisible `Root` as the `PrimaryPart`, so `PivotTo` stands it on a
surface rather than burying it halfway in.

Styles are spread across the ladder so no long run of neighbouring scores shares a shape —
without that, the six Silver-tier flatscreens read as the same prop six times at different
sizes.

Every telly also gets **seeded detail**: a price tag showing its value, a standby LED, and
jitter on where those sit. The seed is `Random.new(score * 7919)`, **not `math.random`** — a
given TV has to look the same for every player and on every rebuild, or a podium would silently
reshuffle its own telly each time it refreshed.

Adding a style to `TvCatalog.Styles` without writing its builder **fails the test suite** rather
than silently shipping a plain grey box.

### The Backrooms

Outside the shopfront is [BackroomsService.luau](src/server/services/BackroomsService.luau):
mono-yellow wallpaper, damp carpet, low ceiling tiles, buzzing fluorescents with the odd dead
one, and a maze of identical rooms on a 26-stud grid. You can see it through the glass and walk
out into it.

The layout uses a **fixed seed**, not `math.random`. It's generated at server startup, so an
unseeded maze would be a different shape every launch and two servers would disagree about a
place that's meant to feel endless.

Two boundary details that were wrong first time and are easy to break again:

- **The carpet starts exactly at `Shop.FrontZ`**, where the shop floor ends. Further out leaves
  a hole in the floor across the doorway; nearer and two floor slabs overlap and flicker.
- **The flank walls cover only the strip either side of the shop**, from the shop's corner out
  to the perimeter — *not* across the shopfront. Wallpaper behind the glass would hide the very
  thing the window looks out on, and would block the door.

### Server authority

The client sends `RequestRoll` with **no arguments** and never sends a number, score, or TV.
The server rolls, picks the TV, stores it, and replicates the result; the dice-spin animation
on screen is decoration played *after* the real answer has arrived. A modified client can spam
the button but can't choose its own outcome, and a 1.5s cooldown is enforced server-side.

### What's in each file

| File | Job |
| --- | --- |
| [DiceTiers.luau](src/shared/DiceTiers.luau) | The five dice and their score windows |
| [DiceGeometry.luau](src/shared/DiceGeometry.luau) | Face normals, pip layouts, and landing rotations for the die |
| [TvCatalog.luau](src/shared/TvCatalog.luau) | 30 TVs, indexed by score, plus size/value helpers |
| [TvBuilder.luau](src/shared/TvBuilder.luau) | Builds each TV out of parts, one builder per style |
| [DiceController.luau](src/client/controllers/DiceController.luau) | Throws the 3D die and lands it on the server's number |
| [ShopService.luau](src/server/services/ShopService.luau) | Builds the whole shop interior, lighting props and spawn |
| [BackroomsService.luau](src/server/services/BackroomsService.luau) | Builds the Backrooms maze outside the shopfront |
| [MonetisationService.luau](src/server/services/MonetisationService.luau) | Paid dice upgrades and receipt handling |
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
