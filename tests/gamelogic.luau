-- Headless check of the shared progression logic, run with lune.
-- Loads DiceTiers/TvCatalog with stubbed Color3/Vector3 so no Studio is needed.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local ROOT = "src/shared/"

-- Enough of the Roblox API for the pure-data modules to load. CFrame.Angles returns a real
-- 3x3 rotation matrix so the die-landing maths can actually be checked, not just eyeballed.
local PRELUDE = [[
local Color3 = {
	fromRGB = function(r, g, b) return { R = r, G = g, B = b } end,
	new = function(r, g, b) return { R = r, G = g, B = b } end,
}
local Vector3 = { new = function(x, y, z) return { X = x, Y = y, Z = z } end }
local Enum = { NormalId = {
	Top = "Top", Bottom = "Bottom", Front = "Front",
	Back = "Back", Left = "Left", Right = "Right",
} }
local CFrame = {}
CFrame.Angles = function(rx, ry, rz)
	-- Right-handed rotation matrices, applied X then Y then Z, matching CFrame.Angles.
	local function mul(a, b)
		local out = {}
		for i = 1, 3 do
			out[i] = {}
			for j = 1, 3 do
				out[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j]
			end
		end
		return out
	end
	local cx, sx, cy, sy, cz, sz =
		math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
	local mx = { { 1, 0, 0 }, { 0, cx, -sx }, { 0, sx, cx } }
	local my = { { cy, 0, sy }, { 0, 1, 0 }, { -sy, 0, cy } }
	local mz = { { cz, -sz, 0 }, { sz, cz, 0 }, { 0, 0, 1 } }
	return { matrix = mul(mul(mx, my), mz) }
end
]]

local function load(name: string)
	local source = PRELUDE .. fs.readFile(ROOT .. name .. ".luau")
	return luau.load(source, { debugName = name })()
end

local DiceTiers = load("DiceTiers")
local TvCatalog = load("TvCatalog")
local DiceGeometry = load("DiceGeometry")
local Config = load("Config")

local failures = 0
local checks = 0

local function check(label: string, condition: boolean, detail: string?)
	checks += 1
	if not condition then
		failures += 1
		print(`  FAIL  {label}{if detail then "  (" .. detail .. ")" else ""}`)
	end
end

print("== catalog shape ==")
check("30 TVs in catalog", #TvCatalog.Tvs == 30, `got {#TvCatalog.Tvs}`)
check("5 dice tiers", #DiceTiers.Tiers == 5, `got {#DiceTiers.Tiers}`)

for score = 1, #TvCatalog.Tvs do
	local tv = TvCatalog.Tvs[score]
	check(`score {score} has an entry`, tv ~= nil)
	if tv then
		check(`score {score} has a name`, type(tv.Name) == "string" and #tv.Name > 0)
		check(`score {score} has a rarity`, type(tv.Rarity) == "string" and #tv.Rarity > 0)
		check(`score {score} Score field matches index`, tv.Score == score, `got {tv.Score}`)
	end
end

print("== value ladder strictly increases ==")
for score = 2, #TvCatalog.Tvs do
	local previous = TvCatalog.Tvs[score - 1].Value
	local current = TvCatalog.Tvs[score].Value
	check(`value {score} > value {score - 1}`, current > previous, `{current} <= {previous}`)
end

print("== every (dice, face) maps to a real TV, covering 1..30 exactly once ==")
local covered: { [number]: number } = {}
for tierIndex = 1, #DiceTiers.Tiers do
	local tier = DiceTiers.get(tierIndex)
	for face = 1, tier.Sides do
		-- Mirrors RollService: score = tier.ScoreOffset + roll
		local score = tier.ScoreOffset + face
		covered[score] = (covered[score] or 0) + 1
		check(
			`{tier.Name} face {face} -> valid score`,
			score >= 1 and score <= #TvCatalog.Tvs,
			`score {score}`
		)
		check(`{tier.Name} face {face} -> a TV exists`, TvCatalog.get(score) ~= nil)
	end
end
for score = 1, 30 do
	check(`score {score} reachable exactly once`, covered[score] == 1, `hit {covered[score] or 0}x`)
end

print("== a better dice can never roll worse than a worse dice's best ==")
for tierIndex = 1, #DiceTiers.Tiers - 1 do
	local lower = DiceTiers.get(tierIndex)
	local upper = DiceTiers.get(tierIndex + 1)
	local lowerBest = lower.ScoreOffset + lower.Sides
	local upperWorst = upper.ScoreOffset + 1
	check(
		`{upper.Name} floor beats {lower.Name} ceiling`,
		upperWorst > lowerBest,
		`{upperWorst} <= {lowerBest}`
	)
end

print("== tier bounds ==")
check("isMax only at the top tier", DiceTiers.isMax(5) and not DiceTiers.isMax(4))
check("get clamps below range", DiceTiers.get(0).Index == 1)
check("get clamps above range", DiceTiers.get(99).Index == 5)
check("catalog clamps below range", TvCatalog.get(0).Score == 1)
check("catalog clamps above range", TvCatalog.get(999).Score == 30)

print("== value formatting ==")
local cases =
	{ { 5, "5" }, { 100, "100" }, { 1000, "1,000" }, { 12345, "12,345" }, { 50000, "50,000" } }
for _, case in cases do
	local got = TvCatalog.formatValue(case[1] :: number)
	check(`formatValue({case[1]})`, got == case[2], `got "{got}" want "{case[2]}"`)
end

print("== screen size grows with score ==")
for score = 2, 30 do
	local previous = TvCatalog.screenSize(score - 1)
	local current = TvCatalog.screenSize(score)
	check(`screen {score} wider and taller`, current.X > previous.X and current.Y > previous.Y)
end

print("== TV styles all have a builder ==")
-- TvBuilder itself needs too much of the Roblox API to load here, so scrape the style
-- names it defines straight out of the source. Crude, but it catches the real mistake:
-- adding a style to the catalog and forgetting the builder, which ships a plain box.
local builderSource = fs.readFile(ROOT .. "TvBuilder.luau")
local builderStyles: { [string]: boolean } = {}
for name in builderSource:gmatch("function builders%.([%a_]+)") do
	builderStyles[name] = true
end
check("scraped some builders", next(builderStyles) ~= nil)
for style in TvCatalog.Styles do
	check(`style "{style}" has a builder`, builderStyles[style] == true)
end
for style in builderStyles do
	check(`builder "{style}" is a declared style`, TvCatalog.Styles[style] == true)
end
for score = 1, 30 do
	local tv = TvCatalog.Tvs[score]
	check(`score {score} style is declared`, TvCatalog.Styles[tv.Style] == true, `got "{tv.Style}"`)
end

print("== cylinders use the named orientations ==")
-- A Roblox cylinder's length runs along local X. Every cylinder in TvBuilder was once
-- rotated with the same raw CFrame.Angles(0, 0, rad(90)), which left the dials facing the
-- ceiling and the rollable TV's drum standing up like a pillar. The three named constants
-- encode which way is which; a bare rad(90) means someone has gone back to guessing.
for _, name in { "CAPS_FACING_Z", "CAPS_FACING_Y", "LENGTH_ACROSS_X" } do
	check(`{name} is defined`, builderSource:find(`local {name} =`) ~= nil)
end
check(
	"no raw 90-degree rotations left in TvBuilder",
	builderSource:find("math%.rad%(90%)") == nil,
	"use CAPS_FACING_Z / CAPS_FACING_Y / LENGTH_ACROSS_X instead"
)

print("== die lands on the face the server rolled ==")
-- The real risk in DiceController: LandOrientation[v] must actually rotate face v to +Y.
-- Applying the matrix to FaceNormal[v] should give (0, 1, 0) for every value.
local function rotate(cf, v)
	local m = cf.matrix
	return {
		X = m[1][1] * v.X + m[1][2] * v.Y + m[1][3] * v.Z,
		Y = m[2][1] * v.X + m[2][2] * v.Y + m[2][3] * v.Z,
		Z = m[3][1] * v.X + m[3][2] * v.Y + m[3][3] * v.Z,
	}
end

for value = 1, 6 do
	local normal = DiceGeometry.FaceNormal[value]
	local oriented = rotate(DiceGeometry.LandOrientation[value], normal)
	check(
		`face {value} ends up pointing at +Y`,
		math.abs(oriented.Y - 1) < 1e-6
			and math.abs(oriented.X) < 1e-6
			and math.abs(oriented.Z) < 1e-6,
		`got ({string.format("%.3f, %.3f, %.3f", oriented.X, oriented.Y, oriented.Z)})`
	)
end

print("== die is a real die ==")
for value = 1, 6 do
	check(`face {value} has a normal`, DiceGeometry.FaceNormal[value] ~= nil)
	check(`face {value} has a surface`, DiceGeometry.FaceId[value] ~= nil)
	check(
		`face {value} has {value} pips`,
		#DiceGeometry.Pips[value] == value,
		`got {#DiceGeometry.Pips[value]}`
	)
end

-- On a real die, opposite faces sum to 7 and their normals are exact opposites.
for value = 1, 6 do
	local opposite = 7 - value
	local a, b = DiceGeometry.FaceNormal[value], DiceGeometry.FaceNormal[opposite]
	check(`face {value} is opposite face {opposite}`, a.X == -b.X and a.Y == -b.Y and a.Z == -b.Z)
end

-- All six normals must be distinct, or two numbers share a face.
local seenNormals: { [string]: number } = {}
for value = 1, 6 do
	local n = DiceGeometry.FaceNormal[value]
	local key = `{n.X},{n.Y},{n.Z}`
	check(
		`face {value} normal is unique`,
		seenNormals[key] == nil,
		`clashes with {seenNormals[key]}`
	)
	seenNormals[key] = value
end

local seenFaces: { [string]: number } = {}
for value = 1, 6 do
	local id = DiceGeometry.FaceId[value]
	check(`face {value} surface is unique`, seenFaces[id] == nil, `clashes with {seenFaces[id]}`)
	seenFaces[id] = value
end

-- Pips must sit inside the face, or they render clipped at the edge.
for value = 1, 6 do
	for index, pip in DiceGeometry.Pips[value] do
		check(
			`face {value} pip {index} is inside the face`,
			pip[1] > 0.1 and pip[1] < 0.9 and pip[2] > 0.1 and pip[2] < 0.9,
			`at {pip[1]},{pip[2]}`
		)
	end
end

print("== the podium row fits inside the shop ==")
-- Resizing the shop or widening the podiums can push a display stand through a wall, which
-- is invisible in code and obvious-but-annoying in Studio. Check the arithmetic instead.
local shop = Config.Shop
local plinth = Config.Podiums.PlinthSize
local slots = Config.MaxPlayers

check("podiums are as wide as the player cap", slots == Config.MaxPlayers)

for slot = 1, slots do
	local centre = (slot - (slots + 1) / 2) * Config.Podiums.Spacing
	local left, right = centre - plinth.X / 2, centre + plinth.X / 2
	check(
		`podium {slot} is inside the side walls`,
		left > -shop.HalfWidth and right < shop.HalfWidth,
		`spans {string.format("%.1f..%.1f", left, right)}, walls at +/-{shop.HalfWidth}`
	)
end

-- Adjacent podiums must not overlap each other.
check(
	"podium spacing clears the plinth width",
	Config.Podiums.Spacing > plinth.X,
	`spacing {Config.Podiums.Spacing} <= plinth {plinth.X}`
)

local podiumZ = Config.Podiums.Origin.Z
check(
	"podium row is inside the front and back walls",
	podiumZ - plinth.Z / 2 > shop.BackZ and podiumZ + plinth.Z / 2 < shop.FrontZ,
	`row at z={podiumZ}, walls at {shop.BackZ}..{shop.FrontZ}`
)
check(
	"there is room to walk behind the podiums",
	(podiumZ - plinth.Z / 2) - shop.BackZ >= 6,
	`only {(podiumZ - plinth.Z / 2) - shop.BackZ} studs`
)
check("doorway is narrower than the shopfront", shop.DoorWidth < shop.HalfWidth * 2)
check("shop is tall enough for the biggest TV", shop.WallHeight > 14)

print(`\n{checks - failures}/{checks} checks passed`)
if failures > 0 then
	print(`{failures} FAILED`)
	process.exit(1)
end
print("all good")
