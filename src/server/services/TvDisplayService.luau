--!strict
-- Builds one podium per player slot and stands each player's best TV on theirs.
--
-- The podium is a plinth plus a nameplate; the telly itself comes from TvBuilder, which
-- builds a different shape per catalog style. When a player beats their best score the old
-- model is destroyed and a new one built — that only happens on an improvement, so it's
-- rare enough not to bother pooling.
--
-- All generated in code, so the game is playable straight from a bare baseplate.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TvBuilder = require(Shared:WaitForChild("TvBuilder"))
local TvCatalog = require(Shared:WaitForChild("TvCatalog"))

local PlayerDataService = require(script.Parent.PlayerDataService)

local TvDisplayService = {
	Name = "TvDisplayService",
}

type Podium = {
	Model: Model,
	Plinth: Part,
	TopSurface: Vector3,
	Owner: TextLabel,
	Caption: TextLabel,
	Player: Player?,
	-- The TV model currently on show, and the score it was built from.
	Tv: Model?,
	TvScore: number,
}

local podiums: { Podium } = {}

local function buildPodium(slot: number): Podium
	local plinthSize = Config.Podiums.PlinthSize
	local offset = (slot - (Config.MaxPlayers + 1) / 2) * Config.Podiums.Spacing
	local base = Config.Podiums.Origin + Vector3.new(offset, 0, 0)

	local model = Instance.new("Model")
	model.Name = `Podium{slot}`

	local plinth = Instance.new("Part")
	plinth.Name = "Plinth"
	plinth.Size = plinthSize
	plinth.Position = base + Vector3.new(0, plinthSize.Y / 2, 0)
	plinth.Anchored = true
	plinth.TopSurface = Enum.SurfaceType.Smooth
	plinth.BottomSurface = Enum.SurfaceType.Smooth
	plinth.BrickColor = BrickColor.new("Dark stone grey")
	plinth.Material = Enum.Material.Concrete
	plinth.Parent = model
	model.PrimaryPart = plinth

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(300, 66)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 250
	billboard.Parent = plinth

	local owner = Instance.new("TextLabel")
	owner.Name = "Owner"
	owner.Size = UDim2.new(1, 0, 0.5, 0)
	owner.BackgroundTransparency = 1
	owner.Font = Enum.Font.GothamBold
	owner.TextScaled = true
	owner.TextColor3 = Color3.new(1, 1, 1)
	owner.TextStrokeTransparency = 0.3
	owner.Text = `Slot {slot} — open`
	owner.Parent = billboard

	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.Position = UDim2.fromScale(0, 0.5)
	caption.Size = UDim2.new(1, 0, 0.5, 0)
	caption.BackgroundTransparency = 1
	caption.Font = Enum.Font.Gotham
	caption.TextScaled = true
	caption.TextColor3 = Color3.fromRGB(200, 206, 216)
	caption.TextStrokeTransparency = 0.5
	caption.Text = ""
	caption.Parent = billboard

	model.Parent = Workspace

	return {
		Model = model,
		Plinth = plinth,
		TopSurface = base + Vector3.new(0, plinthSize.Y, 0),
		Owner = owner,
		Caption = caption,
		Player = nil,
		Tv = nil,
		TvScore = 0,
	}
end

local function clearTv(podium: Podium)
	if podium.Tv then
		podium.Tv:Destroy()
		podium.Tv = nil
	end
	podium.TvScore = 0
end

local function findPodium(player: Player): Podium?
	for _, podium in podiums do
		if podium.Player == player then
			return podium
		end
	end
	return nil
end

local function update(podium: Podium, bestScore: number, totalValue: number)
	local player = podium.Player
	if not player then
		podium.Owner.Text = "Open slot"
		podium.Caption.Text = ""
		clearTv(podium)
		return
	end

	podium.Owner.Text = player.DisplayName

	if bestScore <= 0 then
		podium.Caption.Text = "no TV yet"
		clearTv(podium)
		return
	end

	local tv = TvCatalog.get(bestScore)
	podium.Caption.Text = `{tv.Name} · {TvCatalog.formatValue(totalValue)}`

	-- Only rebuild when the actual TV changes; the caption above updates on every roll.
	if podium.TvScore == bestScore then
		return
	end

	clearTv(podium)
	local model = TvBuilder.build(bestScore)
	-- TvBuilder puts the model's origin at the bottom centre of the telly, so this stands
	-- it on the plinth rather than burying it halfway in.
	model:PivotTo(CFrame.new(podium.TopSurface))
	model.Parent = podium.Model
	podium.Tv = model
	podium.TvScore = bestScore
end

function TvDisplayService:Init()
	for slot = 1, Config.MaxPlayers do
		podiums[slot] = buildPodium(slot)
	end

	PlayerDataService:OnChanged(function(player, playerData)
		local podium = findPodium(player)
		if podium then
			update(podium, playerData.BestScore, playerData.TotalValue)
		end
	end)
end

function TvDisplayService:Start()
	local function claimPodium(player: Player)
		for _, podium in podiums do
			if podium.Player == nil then
				podium.Player = player
				local playerData = PlayerDataService:Get(player)
				update(
					podium,
					playerData and playerData.BestScore or 0,
					playerData and playerData.TotalValue or 0
				)
				return
			end
		end
		warn(`[TvDisplayService] No free podium for {player.Name}`)
	end

	Players.PlayerAdded:Connect(claimPodium)
	for _, player in Players:GetPlayers() do
		claimPodium(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local podium = findPodium(player)
		if podium then
			podium.Player = nil
			update(podium, 0, 0)
		end
	end)
end

return TvDisplayService
