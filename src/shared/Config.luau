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

	Monetisation = {
		-- Paid dice upgrade. The PRICE IS NOT SET HERE — it lives on the Developer Product
		-- in Roblox's dashboard. Create a product priced at 25 Robux on the game's page and
		-- paste its ID below; until then the button explains itself rather than erroring.
		DiceUpgradeProductId = 0,
		-- What the button claims it costs. Keep it in step with the product's real price.
		DisplayPrice = 25,
		-- Local testing only: grants the paid upgrade without taking any Robux, so the flow
		-- can be exercised in Studio where real purchases don't work. NEVER ship this true.
		GrantWithoutPaying = false,
	},

	Penalty = {
		-- Rolling the lowest face knocks every TV already collected down this many levels.
		DowngradeLevels = 1,
	},

	Roll = {
		-- Server-enforced. The client greys its button out for the same duration,
		-- but the server is what actually decides.
		-- Must stay above the die's flight time in DiceController, or a second throw can
		-- start while the first die is still in the air.
		CooldownSeconds = 1.5,
	},

	-- Interior of the shop, in studs. The podium row has to fit inside these bounds with
	-- room to walk around it — tests/gamelogic.luau checks that it does.
	Shop = {
		HalfWidth = 70,
		BackZ = -60,
		FrontZ = 30,
		WallHeight = 26,
		DoorWidth = 16,
		-- Walking surface. Everything stands on this.
		FloorY = 0,
	},

	-- The Backrooms outside the shopfront. Not a nice place.
	Backrooms = {
		HalfWidth = 150,
		Depth = 260,
		CeilingHeight = 14,
		-- Maze grid pitch. Walls are placed on cell edges.
		CellSize = 26,
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
