--!strict
-- Builds one podium per player slot and shows each player's best TV on theirs.
--
-- The podiums are generated in code rather than modelled in Studio, so the game is
-- playable straight from a bare baseplate. Once Arlo wants to model proper ones, delete
-- buildPodium and point this at models in ReplicatedStorage instead.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TvCatalog = require(Shared:WaitForChild("TvCatalog"))

local PlayerDataService = require(script.Parent.PlayerDataService)

local TvDisplayService = {
	Name = "TvDisplayService",
}

type Podium = {
	Model: Model,
	Screen: Part,
	Label: TextLabel,
	Owner: TextLabel,
	Player: Player?,
}

local podiums: { Podium } = {}

local function makePart(name: string, parent: Instance, size: Vector3, position: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = size
	part.Position = position
	part.Parent = parent
	return part
end

local function buildPodium(slot: number): Podium
	local offset = (slot - (Config.MaxPlayers + 1) / 2) * Config.Podiums.Spacing
	local base = Config.Podiums.Origin + Vector3.new(offset, 0, 0)

	local model = Instance.new("Model")
	model.Name = `Podium{slot}`

	local plinth = makePart("Plinth", model, Vector3.new(14, 1, 6), base + Vector3.new(0, 0.5, 0))
	plinth.BrickColor = BrickColor.new("Dark stone grey")
	plinth.Material = Enum.Material.Concrete
	model.PrimaryPart = plinth

	local stand = makePart("Stand", model, Vector3.new(1.5, 4, 1.5), base + Vector3.new(0, 3, 0))
	stand.BrickColor = BrickColor.new("Really black")
	stand.Material = Enum.Material.Metal

	-- Sized and coloured per TV in update(); starts small and dark for an empty podium.
	local screen = makePart("Screen", model, Vector3.new(6, 4, 0.4), base + Vector3.new(0, 7, 0))
	screen.Material = Enum.Material.Neon
	screen.Color = Color3.fromRGB(20, 20, 20)
	screen.CanCollide = false

	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 48
	surface.AlwaysOnTop = false
	surface.Parent = screen

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(0, 0, 0)
	label.TextTransparency = 0.25
	label.Text = "EMPTY"
	label.Parent = surface

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(260, 44)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 200
	billboard.Parent = plinth

	local owner = Instance.new("TextLabel")
	owner.Size = UDim2.fromScale(1, 1)
	owner.BackgroundTransparency = 1
	owner.Font = Enum.Font.GothamBold
	owner.TextScaled = true
	owner.TextColor3 = Color3.new(1, 1, 1)
	owner.TextStrokeTransparency = 0.4
	owner.Text = `Slot {slot} — open`
	owner.Parent = billboard

	model.Parent = Workspace

	return {
		Model = model,
		Screen = screen,
		Label = label,
		Owner = owner,
		Player = nil,
	}
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
		podium.Label.Text = "EMPTY"
		podium.Screen.Color = Color3.fromRGB(20, 20, 20)
		podium.Screen.Size = Vector3.new(6, 4, 0.4)
		return
	end

	podium.Owner.Text = `{player.DisplayName} — {TvCatalog.formatValue(totalValue)}`

	if bestScore <= 0 then
		podium.Label.Text = "NO TV YET"
		podium.Screen.Color = Color3.fromRGB(20, 20, 20)
		podium.Screen.Size = Vector3.new(6, 4, 0.4)
		return
	end

	local tv = TvCatalog.get(bestScore)
	local size = TvCatalog.screenSize(bestScore)
	local previousCentre = podium.Screen.Position

	podium.Screen.Size = size
	-- Keep the bottom of the screen on the stand as it grows.
	podium.Screen.Position =
		Vector3.new(previousCentre.X, Config.Podiums.Origin.Y + 5 + size.Y / 2, previousCentre.Z)
	podium.Screen.Color = tv.Screen
	podium.Label.Text = `{tv.Name}\n{tv.Rarity} · {TvCatalog.formatValue(tv.Value)}`
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
