--!strict
-- Game-wide tunables. Shared between client and server so both agree on the numbers.

local Config = {
	GameName = "Roll For TVs",

	Player = {
		WalkSpeed = 16,
		JumpPower = 50,
		StartingCoins = 0,
	},

	Round = {
		IntermissionSeconds = 10,
		RoundSeconds = 120,
	},
}

return Config
