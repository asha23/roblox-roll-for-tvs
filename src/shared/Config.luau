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
		-- Hidden for now. Off means no button on screen and the server refuses to prompt;
		-- the implementation stays put, so turning this on is the only step needed once a
		-- Developer Product exists.
		Enabled = false,

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

	Data = {
		-- Bump the version in these names if the saved shape ever changes in a way old
		-- saves can't satisfy. Renaming the store abandons the old data rather than
		-- crashing on it.
		StoreName = "PlayerData_v1",
		LeaderboardName = "TopScores_v1",

		-- DataStore write limits are per-key and generous but not unlimited; a minute or
		-- more between autosaves keeps well clear even with a full server.
		AutosaveSeconds = 120,
		RetryAttempts = 4,
		RetryBackoffSeconds = 1.5,

		ScoreboardRefreshSeconds = 60,
		-- GetSortedAsync page size. 100 is Roblox's ceiling.
		ScoreboardEntries = 10,
	},

	Bonus = {
		-- One hidden TV deep in the Backrooms, worth this much. Claimable once per player.
		Value = 30000,
	},

	-- Roblox's own built-in client sounds, so the game makes noise without anything needing
	-- to be uploaded first. Swap any of these for "rbxassetid://<id>" to use your own audio.
	Sounds = {
		-- There is no dice-clatter built in, so DiceController fakes one by repeating a short
		-- click at randomised pitch. RattleClicks is how many.
		DiceRattle = "rbxasset://sounds/switch3.wav",
		RattleClicks = 10,
		DiceLand = "rbxasset://sounds/bass.mp3",
		Firework = "rbxasset://sounds/bass.mp3",
		Bonus = "rbxasset://sounds/electronicpingshort.wav",
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
