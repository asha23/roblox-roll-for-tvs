--!strict
-- Owns every player's dice tier and TV collection. This is the only place that mutates
-- player state — RollService asks it to award things, it replicates the result.
--
-- Storage is in-memory, so collections reset when the server shuts down. Swap the `data`
-- table for DataStoreService (or ProfileService) when you want saving; the rest of the
-- game only talks to this service's methods, so nothing else has to change.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
	-- True between rolling a 6 and choosing whether to take the upgrade.
	PendingUpgrade: boolean,
}

local PlayerDataService = {
	Name = "PlayerDataService",
}

local data: { [Player]: PlayerData } = {}
local changedCallbacks: { (Player, PlayerData) -> () } = {}

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
	local total, best = playerData.BonusValue, 0
	for _, score in playerData.Tvs do
		total += TvCatalog.get(score).Value
		if score > best then
			best = score
		end
	end
	playerData.TotalValue = total
	playerData.BestScore = best

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

function PlayerDataService:Init()
	Remotes.Functions.GetPlayerData.OnServerInvoke = function(player)
		return data[player]
	end
end

function PlayerDataService:Start()
	local function onPlayerAdded(player: Player)
		data[player] = {
			DiceTier = 1,
			Tvs = {},
			BestScore = 0,
			TotalValue = 0,
			BonusValue = 0,
			Rolls = 0,
			PendingUpgrade = false,
		}

		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid") :: Humanoid
			humanoid.WalkSpeed = Config.Player.WalkSpeed
			humanoid.JumpPower = Config.Player.JumpPower
		end)

		self:Sync(player)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		-- Save here before clearing, once you add a DataStore.
		data[player] = nil
	end)
end

return PlayerDataService
