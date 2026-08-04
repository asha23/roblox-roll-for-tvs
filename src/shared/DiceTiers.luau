--!strict
-- The dice ladder. Each tier rolls the same 1-6 but shifts the score window up by
-- ScoreOffset, so a better dice can never roll worse than the tier below its best.
--
--   Basic   rolls score  1-6
--   Bronze  rolls score  7-12
--   Silver  rolls score 13-18
--   Gold    rolls score 19-24
--   Diamond rolls score 25-30
--
-- Score indexes straight into TvCatalog, so adding a tier here means adding six TVs there.

export type DiceTier = {
	Index: number,
	Name: string,
	Sides: number,
	ScoreOffset: number,
	Color: Color3,
}

local DiceTiers = {}

DiceTiers.Tiers = {
	{
		Index = 1,
		Name = "Basic Dice",
		Sides = 6,
		ScoreOffset = 0,
		Color = Color3.fromRGB(235, 235, 235),
	},
	{
		Index = 2,
		Name = "Bronze Dice",
		Sides = 6,
		ScoreOffset = 6,
		Color = Color3.fromRGB(196, 122, 58),
	},
	{
		Index = 3,
		Name = "Silver Dice",
		Sides = 6,
		ScoreOffset = 12,
		Color = Color3.fromRGB(190, 198, 210),
	},
	{
		Index = 4,
		Name = "Gold Dice",
		Sides = 6,
		ScoreOffset = 18,
		Color = Color3.fromRGB(240, 195, 62),
	},
	{
		Index = 5,
		Name = "Diamond Dice",
		Sides = 6,
		ScoreOffset = 24,
		Color = Color3.fromRGB(120, 226, 240),
	},
} :: { DiceTier }

function DiceTiers.get(index: number): DiceTier
	return DiceTiers.Tiers[math.clamp(index, 1, #DiceTiers.Tiers)]
end

function DiceTiers.isMax(index: number): boolean
	return index >= #DiceTiers.Tiers
end

return DiceTiers
