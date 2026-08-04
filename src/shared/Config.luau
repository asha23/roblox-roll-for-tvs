--!strict
-- Game-wide tunables. Shared between client and server so both agree on the numbers.

local Config = {
	GameName = "Roll For TVs",

	-- Enforced by Players.MaxPlayers in default.project.json. Kept here so the
	-- podium layout and the server guard agree on the same number.
	MaxPlayers = 4,

	Player = {
		WalkSpeed = 18,
		JumpPower = 50,
	},

	Roll = {
		-- Server-enforced. The client greys its button out for the same duration,
		-- but the server is what actually decides.
		-- Must stay above the die's flight time in DiceController, or a second throw can
		-- start while the first die is still in the air.
		CooldownSeconds = 1.5,
	},

	Podiums = {
		-- One podium per player slot, laid out in a row facing spawn. Spacing has to clear
		-- the widest TV in the catalog — a Diamond-tier screen is roughly 15 studs across.
		Spacing = 26,
		Origin = Vector3.new(0, 0, -40),
		PlinthSize = Vector3.new(20, 1, 10),
	},
}

return Config
