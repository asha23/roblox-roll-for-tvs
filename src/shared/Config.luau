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
		CooldownSeconds = 1.5,
		-- How long the client spends spinning digits before showing the real result.
		SpinSeconds = 0.7,
	},

	Podiums = {
		-- One podium per player slot, laid out in a row facing spawn.
		Spacing = 20,
		Origin = Vector3.new(0, 0, -34),
	},
}

return Config
