--!strict
-- Owns every player's dice tier and TV collection. This is the only place that mutates
-- player state — RollService asks it to award things, it replicates the result.
--
-- Persists to a DataStore. Two rules matter more than anything else here:
--
--  1. A player's entry is not created until the load attempt has finished, so nothing can be
--     awarded into a blank slate that a slow load then overwrites.
--  2. If loading FAILED (as opposed to "no save yet"), the player runs on defaults but is
--     marked unsaveable. Saving defaults over a live save would wipe a real collection, and
--     the player would have no idea until they noticed everything gone.
--
-- In Studio this needs Game Settings -> Security -> Enable Studio Access to API Services.
-- Without it every call throws, which is handled: the game runs, saving is off, and it says so.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local DiceTiers = require(Shared:WaitForChild("DiceTiers"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local TvCatalog = require(Shared:WaitForChild("TvCatalog"))

export type PlayerData = {
	DiceTier: number,
	-- Scores of every TV won, in the order they were won.
	Tvs: { number },
	BestScore: number,
	TotalValue: number,
	-- Value from things that aren't TVs, e.g. the hidden Backrooms bonus. Held separately
	-- because DowngradeCollection recomputes TotalValue from the Tvs list — folding a bonus
	-- into TotalValue alone would silently erase it the next time someone rolled a 1.
	BonusValue: number,
	Rolls: number,
	-- Persisted, and it has to be: the hidden TV is worth 30,000 and claiming is one-time.
	-- Tracked in memory only, a player could rejoin and claim it again, and again.
	BonusClaimed: boolean,
	-- True between rolling a 6 and choosing whether to take the upgrade. Deliberately NOT
	-- persisted — a pending offer means nothing across sessions.
	PendingUpgrade: boolean,
}

local PlayerDataService = {
	Name = "PlayerDataService",
}

local data: { [Player]: PlayerData } = {}
local changedCallbacks: { (Player, PlayerData) -> () } = {}

-- Players whose data came back cleanly (including "no save yet"). Anyone missing from here
-- is running on defaults after a failed load and must never be written back.
local saveable: { [Player]: boolean } = {}

local store: DataStore?
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Data.StoreName)
	end)
	if ok then
		store = result
	else
		warn(`[PlayerDataService] No DataStore available, progress won't save: {result}`)
	end
end

local function keyFor(player: Player): string
	return `Player_{player.UserId}`
end

local function defaults(): PlayerData
	return {
		DiceTier = 1,
		Tvs = {},
		BestScore = 0,
		TotalValue = 0,
		BonusValue = 0,
		Rolls = 0,
		BonusClaimed = false,
		PendingUpgrade = false,
	}
end

-- Retries with backoff. DataStore calls fail transiently often enough that a single attempt
-- would mean regularly losing a session for no good reason.
local function withRetry<T>(label: string, action: () -> T): (boolean, T?)
	local attempts = math.max(Config.Data.RetryAttempts, 1)
	for attempt = 1, attempts do
		local ok, result = pcall(action)
		if ok then
			return true, result
		end
		if attempt == attempts then
			warn(`[PlayerDataService] {label} failed after {attempts} attempts: {result}`)
		else
			task.wait(Config.Data.RetryBackoffSeconds * attempt)
		end
	end
	return false, nil
end

-- Rebuilds the derived numbers from the TV list rather than trusting what was saved, so a
-- corrupted or hand-edited total can't persist forever.
local function recompute(playerData: PlayerData)
	local total, best = playerData.BonusValue, 0
	for _, score in playerData.Tvs do
		total += TvCatalog.get(score).Value
		if score > best then
			best = score
		end
	end
	playerData.TotalValue = total
	playerData.BestScore = best
end

-- Coerces whatever came out of the store into a valid PlayerData. Anything unexpected falls
-- back to its default rather than propagating a bad type into the game.
local function deserialise(raw: any): PlayerData
	local playerData = defaults()
	if type(raw) ~= "table" then
		return playerData
	end

	if type(raw.DiceTier) == "number" then
		playerData.DiceTier = math.clamp(math.floor(raw.DiceTier), 1, #DiceTiers.Tiers)
	end
	if type(raw.BonusValue) == "number" and raw.BonusValue >= 0 then
		playerData.BonusValue = math.floor(raw.BonusValue)
	end
	if type(raw.Rolls) == "number" and raw.Rolls >= 0 then
		playerData.Rolls = math.floor(raw.Rolls)
	end
	playerData.BonusClaimed = raw.BonusClaimed == true

	if type(raw.Tvs) == "table" then
		for _, score in raw.Tvs do
			if type(score) == "number" then
				table.insert(playerData.Tvs, math.clamp(math.floor(score), 1, #TvCatalog.Tvs))
			end
		end
	end

	recompute(playerData)
	return playerData
end

local function serialise(playerData: PlayerData)
	-- Only the authoritative fields. TotalValue and BestScore are omitted on purpose: they're
	-- derived, and recompute() rebuilds them on load.
	return {
		DiceTier = playerData.DiceTier,
		Tvs = playerData.Tvs,
		BonusValue = playerData.BonusValue,
		Rolls = playerData.Rolls,
		BonusClaimed = playerData.BonusClaimed,
	}
end

function PlayerDataService:Get(player: Player): PlayerData?
	return data[player]
end

-- Register a listener for "this player's data changed". Used by TvDisplayService to
-- keep the world podiums in step without PlayerDataService needing to know about them.
function PlayerDataService:OnChanged(callback: (Player, PlayerData) -> ())
	table.insert(changedCallbacks, callback)
end

function PlayerDataService:Sync(player: Player)
	local playerData = data[player]
	if not playerData then
		return
	end

	Remotes.Events.DataChanged:FireClient(player, playerData)

	for _, callback in changedCallbacks do
		local ok, err = pcall(callback, player, playerData)
		if not ok then
			warn(`[PlayerDataService] changed listener errored: {err}`)
		end
	end
end

function PlayerDataService:AwardTv(player: Player, score: number)
	local playerData = data[player]
	if not playerData then
		return
	end

	local tv = TvCatalog.get(score)
	table.insert(playerData.Tvs, score)
	playerData.TotalValue += tv.Value
	playerData.Rolls += 1
	if score > playerData.BestScore then
		playerData.BestScore = score
	end

	self:Sync(player)
end

-- Adds value that isn't a TV. Survives a later downgrade because it's banked in BonusValue
-- as well as the running total.
function PlayerDataService:AddBonus(player: Player, amount: number)
	local playerData = data[player]
	if not playerData or amount <= 0 then
		return
	end

	playerData.BonusValue += amount
	playerData.TotalValue += amount
	self:Sync(player)
end

-- Knocks every TV already collected down `levels`, floored at the worst TV in the game.
-- Returns how many actually moved, so the client can say nothing happened to an empty
-- collection rather than claiming a penalty that didn't land.
function PlayerDataService:DowngradeCollection(player: Player, levels: number): number
	local playerData = data[player]
	if not playerData then
		return 0
	end

	local moved = 0
	for index, score in playerData.Tvs do
		local downgraded = math.max(1, score - levels)
		if downgraded ~= score then
			moved += 1
		end
		playerData.Tvs[index] = downgraded
	end

	if moved == 0 then
		return 0
	end

	-- Recompute rather than adjust: BestScore may now belong to a different TV entirely,
	-- and subtracting deltas would drift out of step with the list.
	recompute(playerData)

	self:Sync(player)
	return moved
end

function PlayerDataService:SetDiceTier(player: Player, tier: number)
	local playerData = data[player]
	if not playerData then
		return
	end

	playerData.DiceTier = math.clamp(tier, 1, #DiceTiers.Tiers)
	self:Sync(player)
end

-- Marks the bonus claimed and persists it. Returns false if it was already claimed, so the
-- caller knows not to hand out the reward twice.
function PlayerDataService:ClaimBonus(player: Player): boolean
	local playerData = data[player]
	if not playerData or playerData.BonusClaimed then
		return false
	end
	playerData.BonusClaimed = true
	return true
end

function PlayerDataService:Save(player: Player): boolean
	local playerData = data[player]
	if not playerData or not store then
		return false
	end

	-- The important guard. Writing defaults over a live save is worse than not saving.
	if not saveable[player] then
		return false
	end

	local payload = serialise(playerData)
	local activeStore = store :: DataStore
	local ok = withRetry(`save {player.Name}`, function()
		activeStore:SetAsync(keyFor(player), payload)
	end)
	return ok
end

local function loadPlayer(player: Player)
	if not store then
		data[player] = defaults()
		saveable[player] = false
		PlayerDataService:Sync(player)
		return
	end

	local ok, raw = withRetry(`load {player.Name}`, function()
		return (store :: DataStore):GetAsync(keyFor(player))
	end)

	if not player.Parent then
		-- Left while we were waiting on the store.
		return
	end

	if ok then
		data[player] = deserialise(raw)
		saveable[player] = true
	else
		data[player] = defaults()
		saveable[player] = false
		Remotes.Events.Notice:FireClient(
			player,
			"Couldn't load your progress — this session won't be saved."
		)
	end

	PlayerDataService:Sync(player)
end

function PlayerDataService:Init()
	Remotes.Functions.GetPlayerData.OnServerInvoke = function(player)
		return data[player]
	end
end

function PlayerDataService:Start()
	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid") :: Humanoid
			humanoid.WalkSpeed = Config.Player.WalkSpeed
			humanoid.JumpPower = Config.Player.JumpPower
		end)

		-- Note the entry doesn't exist until this returns. RollService already bails when
		-- Get() is nil, so a roll during the load is ignored rather than landing in a blank
		-- slate that the load then replaces.
		loadPlayer(player)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		self:Save(player)
		data[player] = nil
		saveable[player] = nil
	end)

	-- Autosave, so a server crash costs minutes rather than a whole session.
	task.spawn(function()
		while true do
			task.wait(Config.Data.AutosaveSeconds)
			for _, player in Players:GetPlayers() do
				self:Save(player)
			end
		end
	end)

	-- Shutdowns. BindToClose gets roughly 30 seconds; saving in parallel matters with a full
	-- server, because four sequential retrying saves could outlast the window.
	game:BindToClose(function()
		if RunService:IsStudio() then
			return
		end
		local pending = 0
		for _, player in Players:GetPlayers() do
			pending += 1
			task.spawn(function()
				self:Save(player)
				pending -= 1
			end)
		end
		while pending > 0 do
			task.wait(0.1)
		end
	end)
end

return PlayerDataService
