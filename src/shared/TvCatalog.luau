--!strict
-- The TV ladder: 30 entries, one per possible score. Index == score, so entry 1 is the
-- worst thing you can roll and entry 30 is the best. Six entries per dice tier.
--
-- To rebalance the game, edit the numbers here — nothing else needs to change.
--
-- Style drives what TvBuilder actually constructs, so the model matches the name: a
-- "Wood-Panel Console TV" gets a wooden cabinet on legs, an OLED gets a slim panel on a
-- blade stand. Every style listed in TvCatalog.Styles must have a builder in TvBuilder,
-- and tests/gamelogic.luau checks that every entry uses a known one.

export type Tv = {
	Score: number,
	Name: string,
	Value: number,
	Screen: Color3,
	Style: string,
	Body: Color3,
	Rarity: string,
}

local RARITIES = { "Junk", "Common", "Decent", "Elite", "Legendary" }

local DEFAULT_BODY = Color3.fromRGB(46, 48, 54)

-- { name, value, screen colour, style, body colour (optional) } in score order.
local RAW: { { any } } = {
	-- 1-6 · Basic Dice · knackered hand-me-downs
	{
		"Smashed Portable TV",
		5,
		Color3.fromRGB(48, 48, 52),
		"portable",
		Color3.fromRGB(96, 92, 84),
	},
	{ "Cracked CRT", 10, Color3.fromRGB(58, 58, 64), "crt", Color3.fromRGB(74, 72, 68) },
	{ "Dusty Black & White", 20, Color3.fromRGB(96, 96, 96), "crt", Color3.fromRGB(112, 108, 96) },
	{
		"Wonky Portable TV",
		35,
		Color3.fromRGB(110, 104, 92),
		"portable",
		Color3.fromRGB(150, 60, 52),
	},
	{ "Boxy Beige CRT", 55, Color3.fromRGB(138, 128, 106), "crt", Color3.fromRGB(206, 194, 164) },
	{
		"Wood-Panel Console TV",
		80,
		Color3.fromRGB(120, 82, 48),
		"console",
		Color3.fromRGB(102, 62, 32),
	},

	-- 7-12 · Bronze Dice · the family telly, eventually
	{ "Chunky Colour CRT", 120, Color3.fromRGB(84, 110, 140), "crt", Color3.fromRGB(58, 58, 62) },
	{
		"Silver Trinitron",
		170,
		Color3.fromRGB(150, 158, 168),
		"crt",
		Color3.fromRGB(168, 172, 178),
	},
	{ "Flat-Screen CRT", 230, Color3.fromRGB(120, 150, 180), "crt", Color3.fromRGB(38, 38, 42) },
	{ "Early Plasma", 300, Color3.fromRGB(150, 120, 190), "plasma", Color3.fromRGB(30, 30, 34) },
	{ '32" 720p LCD', 400, Color3.fromRGB(120, 170, 210), "lcd", Color3.fromRGB(40, 42, 48) },
	{ '37" Widescreen LCD', 520, Color3.fromRGB(130, 185, 225), "lcd", Color3.fromRGB(36, 38, 44) },

	-- 13-18 · Silver Dice · a proper flatscreen
	{ '40" 1080p LED', 680, Color3.fromRGB(110, 190, 235), "lcd", DEFAULT_BODY },
	{ '43" Smart LED', 880, Color3.fromRGB(96, 200, 240), "lcd", DEFAULT_BODY },
	{ '50" Curved LED', 1100, Color3.fromRGB(84, 208, 236), "lcd", Color3.fromRGB(30, 32, 38) },
	{ '55" 4K LED', 1400, Color3.fromRGB(74, 214, 228), "lcd", Color3.fromRGB(28, 30, 36) },
	{ '60" 4K QLED', 1800, Color3.fromRGB(66, 220, 214), "lcd", Color3.fromRGB(26, 28, 34) },
	{ '65" 4K QLED', 2300, Color3.fromRGB(60, 226, 198), "lcd", Color3.fromRGB(24, 26, 32) },

	-- 19-24 · Gold Dice · showing off
	{ '65" OLED', 3000, Color3.fromRGB(96, 232, 160), "oled", Color3.fromRGB(20, 22, 26) },
	{ '77" OLED', 3800, Color3.fromRGB(132, 238, 130), "oled", Color3.fromRGB(18, 20, 24) },
	{ '85" 8K Mini-LED', 4800, Color3.fromRGB(178, 242, 104), "oled", Color3.fromRGB(18, 20, 24) },
	{ '98" 8K QLED', 6000, Color3.fromRGB(216, 240, 88), "oled", Color3.fromRGB(16, 18, 22) },
	{
		"Cinema Laser Projector",
		7500,
		Color3.fromRGB(240, 226, 76),
		"projector",
		Color3.fromRGB(32, 34, 40),
	},
	{
		"Rollable OLED",
		9500,
		Color3.fromRGB(250, 200, 64),
		"rollable",
		Color3.fromRGB(196, 198, 206),
	},

	-- 25-30 · Diamond Dice · not from this decade
	{
		"Transparent MicroLED",
		12000,
		Color3.fromRGB(255, 172, 96),
		"transparent",
		Color3.fromRGB(210, 214, 222),
	},
	{
		"Wall-Sized MicroLED",
		15000,
		Color3.fromRGB(255, 140, 130),
		"oled",
		Color3.fromRGB(14, 16, 20),
	},
	{
		"Holographic Display",
		19000,
		Color3.fromRGB(255, 128, 180),
		"holo",
		Color3.fromRGB(60, 64, 78),
	},
	{
		"Quantum Holo-Wall",
		24000,
		Color3.fromRGB(226, 130, 240),
		"holo",
		Color3.fromRGB(56, 60, 74),
	},
	{
		"Neural Feed Screen",
		30000,
		Color3.fromRGB(176, 148, 255),
		"holo",
		Color3.fromRGB(52, 56, 70),
	},
	{
		"The Infinite Screen",
		50000,
		Color3.fromRGB(140, 200, 255),
		"holo",
		Color3.fromRGB(48, 52, 66),
	},
}

local TvCatalog = {}

-- Every style a builder must handle. Adding one here without adding it to TvBuilder
-- makes the test fail rather than silently rendering a plain box in game.
TvCatalog.Styles = {
	portable = true,
	crt = true,
	console = true,
	plasma = true,
	lcd = true,
	oled = true,
	projector = true,
	rollable = true,
	transparent = true,
	holo = true,
}

TvCatalog.Tvs = {} :: { Tv }

for score, entry in RAW do
	TvCatalog.Tvs[score] = {
		Score = score,
		Name = entry[1] :: string,
		Value = entry[2] :: number,
		Screen = entry[3] :: Color3,
		Style = entry[4] :: string,
		Body = (entry[5] or DEFAULT_BODY) :: Color3,
		Rarity = RARITIES[math.ceil(score / 6)],
	}
end

function TvCatalog.get(score: number): Tv
	return TvCatalog.Tvs[math.clamp(score, 1, #TvCatalog.Tvs)]
end

-- Screen dimensions for a score — bigger score, bigger telly.
function TvCatalog.screenSize(score: number): Vector3
	return Vector3.new(4 + score * 0.32, 2.4 + score * 0.19, 0.4)
end

-- 12345 -> "12,345"
function TvCatalog.formatValue(value: number): string
	local text = tostring(math.floor(value))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
end

return TvCatalog
