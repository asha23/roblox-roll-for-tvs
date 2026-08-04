-- Headless check of the shared progression logic, run with lune.
-- Loads DiceTiers/TvCatalog with stubbed Color3/Vector3 so no Studio is needed.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local ROOT = "src/shared/"

local PRELUDE = [[
local Color3 = {
	fromRGB = function(r, g, b) return { R = r, G = g, B = b } end,
	new = function(r, g, b) return { R = r, G = g, B = b } end,
}
local Vector3 = { new = function(x, y, z) return { X = x, Y = y, Z = z } end }
]]

local function load(name: string)
	local source = PRELUDE .. fs.readFile(ROOT .. name .. ".luau")
	return luau.load(source, { debugName = name })()
end

local DiceTiers = load("DiceTiers")
local TvCatalog = load("TvCatalog")

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

print(`\n{checks - failures}/{checks} checks passed`)
if failures > 0 then
	print(`{failures} FAILED`)
	process.exit(1)
end
print("all good")
