--!strict
-- Top-right stats panel: current dice, best TV, collection size and total value.
-- Purely a reflection of DataChanged — it never calculates anything itself, so it can't
-- disagree with the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DiceTiers = require(Shared:WaitForChild("DiceTiers"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local TvCatalog = require(Shared:WaitForChild("TvCatalog"))

local player = Players.LocalPlayer

local HudController = {
	Name = "HudController",
}

local rows: { [string]: TextLabel } = {}

local function addRow(parent: Instance, key: string, order: number)
	local row = Instance.new("Frame")
	row.Name = key
	row.Size = UDim2.new(1, 0, 0, 26)
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	row.Parent = parent

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(0.45, 1)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.Gotham
	title.TextSize = 14
	title.TextColor3 = Color3.fromRGB(170, 178, 190)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = key
	title.Parent = row

	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.fromScale(1, 0)
	value.Size = UDim2.fromScale(0.55, 1)
	value.BackgroundTransparency = 1
	value.Font = Enum.Font.GothamBold
	value.TextSize = 15
	value.TextColor3 = Color3.new(1, 1, 1)
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.TextTruncate = Enum.TextTruncate.AtEnd
	value.Text = "—"
	value.Parent = row

	rows[key] = value
end

local function render(playerData: any)
	if type(playerData) ~= "table" then
		return
	end

	local tier = DiceTiers.get(playerData.DiceTier or 1)
	rows["Dice"].Text = tier.Name
	rows["Dice"].TextColor3 = tier.Color

	local best = playerData.BestScore or 0
	rows["Best TV"].Text = if best > 0 then TvCatalog.get(best).Name else "none yet"
	rows["Collected"].Text = tostring(#(playerData.Tvs or {}))
	rows["Total value"].Text = TvCatalog.formatValue(playerData.TotalValue or 0)
end

function HudController:Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -16, 0, 16)
	panel.Size = UDim2.fromOffset(250, 152)
	panel.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = panel

	local heading = Instance.new("TextLabel")
	heading.Size = UDim2.new(1, 0, 0, 22)
	heading.BackgroundTransparency = 1
	heading.Font = Enum.Font.GothamBlack
	heading.TextSize = 16
	heading.TextColor3 = Color3.fromRGB(120, 200, 255)
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.Text = "ROLL FOR TVs"
	heading.LayoutOrder = 0
	heading.Parent = panel

	addRow(panel, "Dice", 1)
	addRow(panel, "Best TV", 2)
	addRow(panel, "Collected", 3)
	addRow(panel, "Total value", 4)

	gui.Parent = player:WaitForChild("PlayerGui")
end

function HudController:Start()
	Remotes.Events.DataChanged.OnClientEvent:Connect(render)

	local initial = Remotes.Functions.GetPlayerData:InvokeServer()
	if initial then
		render(initial)
	end
end

return HudController
