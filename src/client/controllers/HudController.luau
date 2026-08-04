--!strict
-- Example controller: builds a coin counter in code and keeps it in sync with the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local player = Players.LocalPlayer

local HudController = {
	Name = "HudController",
}

local label: TextLabel

function HudController:Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true

	label = Instance.new("TextLabel")
	label.Name = "Coins"
	label.AnchorPoint = Vector2.new(1, 0)
	label.Position = UDim2.new(1, -16, 0, 16)
	label.Size = UDim2.fromOffset(160, 40)
	label.BackgroundTransparency = 0.4
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 20
	label.Text = "Coins: 0"
	label.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

	gui.Parent = player:WaitForChild("PlayerGui")
end

function HudController:Start()
	Remotes.Events.CoinsChanged.OnClientEvent:Connect(function(coins: number)
		label.Text = `Coins: {coins}`
	end)

	local data = Remotes.Functions.GetPlayerData:InvokeServer()
	if data then
		label.Text = `Coins: {data.Coins}`
	end
end

return HudController
