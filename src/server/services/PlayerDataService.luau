--!strict
-- Example service: tracks per-player data in memory and pushes changes to the client.
-- Swap the in-memory table for DataStoreService (or ProfileService) when you need saving.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

export type PlayerData = {
	Coins: number,
}

local PlayerDataService = {
	Name = "PlayerDataService",
}

local data: { [Player]: PlayerData } = {}

function PlayerDataService:Get(player: Player): PlayerData?
	return data[player]
end

function PlayerDataService:AddCoins(player: Player, amount: number)
	local playerData = data[player]
	if not playerData then
		return
	end

	playerData.Coins += amount
	Remotes.Events.CoinsChanged:FireClient(player, playerData.Coins)
end

function PlayerDataService:Init()
	Remotes.Functions.GetPlayerData.OnServerInvoke = function(player)
		return data[player]
	end
end

function PlayerDataService:Start()
	local function onPlayerAdded(player: Player)
		data[player] = {
			Coins = Config.Player.StartingCoins,
		}

		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid") :: Humanoid
			humanoid.WalkSpeed = Config.Player.WalkSpeed
			humanoid.JumpPower = Config.Player.JumpPower
		end)

		Remotes.Events.CoinsChanged:FireClient(player, data[player].Coins)
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
