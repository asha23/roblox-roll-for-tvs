--!strict
-- The TV ladder: 30 entries, one per possible score. Index == score, so entry 1 is the
-- worst thing you can roll and entry 30 is the best. Six entries per dice tier.
--
-- To rebalance the game, edit the numbers here — nothing else needs to change.

export type Tv = {
	Score: number,
	Name: string,
	Value: number,
	Screen: Color3,
	Rarity: string,
}

local RARITIES = { "Junk", "Common", "Decent", "Elite", "Legendary" }

-- { name, value, screen colour } in score order.
local RAW: { { any } } = {
	-- 1-6 · Basic Dice
	{ "Smashed Portable TV", 5, Color3.fromRGB(48, 48, 52) },
	{ "Cracked CRT", 10, Color3.fromRGB(58, 58, 64) },
	{ "Dusty Black & White", 20, Color3.fromRGB(96, 96, 96) },
	{ "Wonky Portable TV", 35, Color3.fromRGB(110, 104, 92) },
	{ "Boxy Beige CRT", 55, Color3.fromRGB(138, 128, 106) },
	{ "Wood-Panel Console TV", 80, Color3.fromRGB(120, 82, 48) },

	-- 7-12 · Bronze Dice
	{ "Chunky Colour CRT", 120, Color3.fromRGB(84, 110, 140) },
	{ "Silver Trinitron", 170, Color3.fromRGB(150, 158, 168) },
	{ "Flat-Screen CRT", 230, Color3.fromRGB(120, 150, 180) },
	{ "Early Plasma", 300, Color3.fromRGB(150, 120, 190) },
	{ '32" 720p LCD', 400, Color3.fromRGB(120, 170, 210) },
	{ '37" Widescreen LCD', 520, Color3.fromRGB(130, 185, 225) },

	-- 13-18 · Silver Dice
	{ '40" 1080p LED', 680, Color3.fromRGB(110, 190, 235) },
	{ '43" Smart LED', 880, Color3.fromRGB(96, 200, 240) },
	{ '50" Curved LED', 1100, Color3.fromRGB(84, 208, 236) },
	{ '55" 4K LED', 1400, Color3.fromRGB(74, 214, 228) },
	{ '60" 4K QLED', 1800, Color3.fromRGB(66, 220, 214) },
	{ '65" 4K QLED', 2300, Color3.fromRGB(60, 226, 198) },

	-- 19-24 · Gold Dice
	{ '65" OLED', 3000, Color3.fromRGB(96, 232, 160) },
	{ '77" OLED', 3800, Color3.fromRGB(132, 238, 130) },
	{ '85" 8K Mini-LED', 4800, Color3.fromRGB(178, 242, 104) },
	{ '98" 8K QLED', 6000, Color3.fromRGB(216, 240, 88) },
	{ "Cinema Laser Projector", 7500, Color3.fromRGB(240, 226, 76) },
	{ "Rollable OLED", 9500, Color3.fromRGB(250, 200, 64) },

	-- 25-30 · Diamond Dice
	{ "Transparent MicroLED", 12000, Color3.fromRGB(255, 172, 96) },
	{ "Wall-Sized MicroLED", 15000, Color3.fromRGB(255, 140, 130) },
	{ "Holographic Display", 19000, Color3.fromRGB(255, 128, 180) },
	{ "Quantum Holo-Wall", 24000, Color3.fromRGB(226, 130, 240) },
	{ "Neural Feed Screen", 30000, Color3.fromRGB(176, 148, 255) },
	{ "The Infinite Screen", 50000, Color3.fromRGB(140, 200, 255) },
}

local TvCatalog = {}

TvCatalog.Tvs = {} :: { Tv }

for score, entry in RAW do
	TvCatalog.Tvs[score] = {
		Score = score,
		Name = entry[1] :: string,
		Value = entry[2] :: number,
		Screen = entry[3] :: Color3,
		Rarity = RARITIES[math.ceil(score / 6)],
	}
end

function TvCatalog.get(score: number): Tv
	return TvCatalog.Tvs[math.clamp(score, 1, #TvCatalog.Tvs)]
end

-- Physical screen size for a score — bigger score, bigger telly.
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
