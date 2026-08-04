--!strict
-- The roll button, the result card, and the "you rolled a 6" upgrade prompt.
--
-- Nothing here decides an outcome. The button sends RequestRoll and waits; every number
-- shown comes from the server's RollResult. DiceController then throws a 3D die that
-- lands on that number, and the card appears once it has settled.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local TvCatalog = require(Shared:WaitForChild("TvCatalog"))

local DiceController = require(script.Parent.DiceController)

local player = Players.LocalPlayer

local RollController = {
	Name = "RollController",
}

local rollButton: TextButton
local buttonSubtitle: TextLabel
local card: Frame
local cardRoll: TextLabel
local cardTvName: TextLabel
local cardDetail: TextLabel
local modal: Frame
local modalText: TextLabel
local acceptButton: TextButton
local declineButton: TextButton

-- Blocks input while a roll resolves or while the upgrade prompt is up. The server
-- enforces the same rules, so this only exists to stop the UI lying to the player.
local busy = false

-- Incremented per roll so a delayed "hide the card" can tell whether it's still the
-- owner of what's on screen. Without this, an old roll's timer hides a newer result.
local rollToken = 0

-- When the last request went out, so the button doesn't come back before the server's
-- cooldown has expired. The die lands sooner than the cooldown ends, and a click in that
-- gap would be silently dropped by the server.
local lastRequestClock = 0

local function roundCorner(instance: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function setButtonEnabled(enabled: boolean)
	rollButton.AutoButtonColor = enabled
	rollButton.BackgroundColor3 = if enabled
		then Color3.fromRGB(64, 132, 255)
		else Color3.fromRGB(58, 62, 72)
	rollButton.TextTransparency = if enabled then 0 else 0.35
end

local function showCard()
	card.Visible = true
	card.Size = UDim2.fromOffset(300, 150)
	TweenService:Create(
		card,
		TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(360, 186) }
	):Play()
end

local function onRollResult(result: any)
	if type(result) ~= "table" then
		return
	end

	rollToken += 1
	local token = rollToken

	-- Throw the die and wait for it to settle. The number is already decided; this just
	-- shows it landing. The card stays hidden until then so it can't spoil the reveal.
	DiceController:Play(result.Roll, result.DiceColor)

	-- A newer roll started while this die was in the air — let that one own the screen.
	if token ~= rollToken then
		return
	end

	showCard()
	cardRoll.Text = tostring(result.Roll)
	cardRoll.TextColor3 = if result.IsMaxFace
		then Color3.fromRGB(255, 214, 90)
		else Color3.fromRGB(255, 255, 255)

	local tv = result.Tv
	if tv then
		cardTvName.Text = tv.Name
		cardTvName.TextColor3 = tv.Screen
		cardDetail.Text = `{tv.Rarity} · {TvCatalog.formatValue(tv.Value)} · score {result.Score}`
	end

	task.delay(2.5, function()
		-- Don't yank the card away if a newer roll has already replaced it.
		if token == rollToken then
			card.Visible = false
		end
	end)

	-- Hold the button until the server would actually accept another roll.
	local remaining = Config.Roll.CooldownSeconds - (os.clock() - lastRequestClock)
	if remaining > 0 then
		task.wait(remaining)
	end

	-- An upgrade offer arrives immediately after the result, while the die is still in
	-- the air. If it's up, leave the button disabled — the modal owns input now.
	if token == rollToken and not modal.Visible then
		busy = false
		setButtonEnabled(true)
	end
end

local function requestRoll()
	if busy or modal.Visible then
		return
	end
	busy = true
	lastRequestClock = os.clock()
	setButtonEnabled(false)
	Remotes.Events.RequestRoll:FireServer()

	-- Failsafe: if the server never answers (cooldown rejected the request), re-enable.
	task.delay(Config.Roll.CooldownSeconds + 0.4, function()
		if busy and not modal.Visible then
			busy = false
			setButtonEnabled(true)
		end
	end)
end

local function onUpgradeOffered(nextTier: any)
	if type(nextTier) ~= "table" then
		return
	end
	modalText.Text = `You rolled a 6!\n\nTrade up to the <b>{nextTier.Name}</b> for better TVs?`
	modal.Visible = true
	busy = true
	setButtonEnabled(false)
end

local function resolveUpgrade(accept: boolean)
	modal.Visible = false
	busy = false
	setButtonEnabled(true)
	Remotes.Events.ChooseDiceUpgrade:FireServer(accept)
end

local function buildRollButton(gui: ScreenGui)
	rollButton = Instance.new("TextButton")
	rollButton.Name = "RollButton"
	rollButton.AnchorPoint = Vector2.new(0.5, 1)
	rollButton.Position = UDim2.new(0.5, 0, 1, -46)
	rollButton.Size = UDim2.fromOffset(240, 68)
	rollButton.BackgroundColor3 = Color3.fromRGB(64, 132, 255)
	rollButton.BorderSizePixel = 0
	rollButton.Font = Enum.Font.GothamBlack
	rollButton.TextSize = 26
	rollButton.TextColor3 = Color3.new(1, 1, 1)
	rollButton.Text = "ROLL"
	rollButton.Parent = gui
	roundCorner(rollButton, 12)

	buttonSubtitle = Instance.new("TextLabel")
	buttonSubtitle.AnchorPoint = Vector2.new(0.5, 0)
	buttonSubtitle.Position = UDim2.new(0.5, 0, 1, 6)
	buttonSubtitle.Size = UDim2.fromOffset(260, 20)
	buttonSubtitle.BackgroundTransparency = 1
	buttonSubtitle.Font = Enum.Font.Gotham
	buttonSubtitle.TextSize = 13
	buttonSubtitle.TextColor3 = Color3.fromRGB(160, 168, 180)
	buttonSubtitle.Text = "click, or press R"
	buttonSubtitle.Parent = rollButton
end

local function buildResultCard(gui: ScreenGui)
	card = Instance.new("Frame")
	card.Name = "ResultCard"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.38)
	card.Size = UDim2.fromOffset(360, 186)
	card.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
	card.BackgroundTransparency = 0.1
	card.BorderSizePixel = 0
	card.Visible = false
	card.Parent = gui
	roundCorner(card, 14)

	cardRoll = Instance.new("TextLabel")
	cardRoll.Position = UDim2.fromOffset(0, 12)
	cardRoll.Size = UDim2.new(1, 0, 0, 86)
	cardRoll.BackgroundTransparency = 1
	cardRoll.Font = Enum.Font.GothamBlack
	cardRoll.TextSize = 72
	cardRoll.TextColor3 = Color3.new(1, 1, 1)
	cardRoll.Text = "—"
	cardRoll.Parent = card

	cardTvName = Instance.new("TextLabel")
	cardTvName.Position = UDim2.new(0, 12, 0, 100)
	cardTvName.Size = UDim2.new(1, -24, 0, 34)
	cardTvName.BackgroundTransparency = 1
	cardTvName.Font = Enum.Font.GothamBold
	cardTvName.TextSize = 22
	cardTvName.TextScaled = false
	cardTvName.TextTruncate = Enum.TextTruncate.AtEnd
	cardTvName.TextColor3 = Color3.new(1, 1, 1)
	cardTvName.Text = ""
	cardTvName.Parent = card

	cardDetail = Instance.new("TextLabel")
	cardDetail.Position = UDim2.new(0, 12, 0, 138)
	cardDetail.Size = UDim2.new(1, -24, 0, 28)
	cardDetail.BackgroundTransparency = 1
	cardDetail.Font = Enum.Font.Gotham
	cardDetail.TextSize = 15
	cardDetail.TextColor3 = Color3.fromRGB(168, 176, 190)
	cardDetail.Text = ""
	cardDetail.Parent = card
end

local function buildUpgradeModal(gui: ScreenGui)
	modal = Instance.new("Frame")
	modal.Name = "UpgradeModal"
	modal.Size = UDim2.fromScale(1, 1)
	modal.BackgroundColor3 = Color3.new(0, 0, 0)
	modal.BackgroundTransparency = 0.45
	modal.BorderSizePixel = 0
	-- Active swallows clicks so the player can't reach the roll button behind it.
	modal.Active = true
	modal.Visible = false
	modal.Parent = gui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(400, 220)
	panel.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
	panel.BorderSizePixel = 0
	panel.Parent = modal
	roundCorner(panel, 16)

	modalText = Instance.new("TextLabel")
	modalText.Position = UDim2.new(0, 20, 0, 22)
	modalText.Size = UDim2.new(1, -40, 0, 116)
	modalText.BackgroundTransparency = 1
	modalText.Font = Enum.Font.Gotham
	modalText.TextSize = 19
	modalText.TextWrapped = true
	modalText.RichText = true
	modalText.TextColor3 = Color3.new(1, 1, 1)
	modalText.Text = ""
	modalText.Parent = panel

	acceptButton = Instance.new("TextButton")
	acceptButton.AnchorPoint = Vector2.new(0, 1)
	acceptButton.Position = UDim2.new(0, 20, 1, -20)
	acceptButton.Size = UDim2.fromOffset(174, 48)
	acceptButton.BackgroundColor3 = Color3.fromRGB(72, 196, 120)
	acceptButton.BorderSizePixel = 0
	acceptButton.Font = Enum.Font.GothamBold
	acceptButton.TextSize = 17
	acceptButton.TextColor3 = Color3.new(1, 1, 1)
	acceptButton.Text = "Upgrade!"
	acceptButton.Parent = panel
	roundCorner(acceptButton, 10)

	declineButton = Instance.new("TextButton")
	declineButton.AnchorPoint = Vector2.new(1, 1)
	declineButton.Position = UDim2.new(1, -20, 1, -20)
	declineButton.Size = UDim2.fromOffset(174, 48)
	declineButton.BackgroundColor3 = Color3.fromRGB(64, 68, 80)
	declineButton.BorderSizePixel = 0
	declineButton.Font = Enum.Font.GothamBold
	declineButton.TextSize = 17
	declineButton.TextColor3 = Color3.new(1, 1, 1)
	declineButton.Text = "Keep this dice"
	declineButton.Parent = panel
	roundCorner(declineButton, 10)
end

function RollController:Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RollUi"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true

	buildRollButton(gui)
	buildResultCard(gui)
	buildUpgradeModal(gui)

	gui.Parent = player:WaitForChild("PlayerGui")
end

function RollController:Start()
	rollButton.MouseButton1Click:Connect(requestRoll)
	acceptButton.MouseButton1Click:Connect(function()
		resolveUpgrade(true)
	end)
	declineButton.MouseButton1Click:Connect(function()
		resolveUpgrade(false)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.R then
			requestRoll()
		end
	end)

	Remotes.Events.RollResult.OnClientEvent:Connect(onRollResult)
	Remotes.Events.DiceUpgradeOffered.OnClientEvent:Connect(onUpgradeOffered)

	Remotes.Events.DataChanged.OnClientEvent:Connect(function(playerData)
		if type(playerData) == "table" and playerData.Rolls then
			buttonSubtitle.Text = `{playerData.Rolls} rolls · click, or press R`
		end
	end)
end

return RollController
