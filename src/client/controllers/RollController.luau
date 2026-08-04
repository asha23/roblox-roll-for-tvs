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
local DiceTiers = require(Shared:WaitForChild("DiceTiers"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local TvCatalog = require(Shared:WaitForChild("TvCatalog"))

local DiceController = require(script.Parent.DiceController)

local player = Players.LocalPlayer

local RollController = {
	Name = "RollController",
}

local rollButton: TextButton
local buttonSubtitle: TextLabel
local paidButton: TextButton
local toast: TextLabel
local card: Frame
local cardRoll: TextLabel
local cardTvName: TextLabel
local cardDetail: TextLabel
local cardWarning: TextLabel
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

-- The bottom-left column: result card on the floor, upgrade prompt stacked on top of it.
local CARD_MARGIN = 24
local CARD_HEIGHT = 212
local CARD_WIDTH = 360

local function roundCorner(instance: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

-- Lifts a colour until it's legible on the dark card. TV screen colours run from near-black
-- (score 1) to bright neon (score 30), and the dark end was unreadable as text.
local function readable(colour: Color3): Color3
	local luminance = 0.2126 * colour.R + 0.7152 * colour.G + 0.0722 * colour.B
	if luminance >= 0.55 then
		return colour
	end
	local lift = math.clamp((0.55 - luminance) / math.max(1 - luminance, 0.01), 0, 0.85)
	return colour:Lerp(Color3.new(1, 1, 1), lift)
end

local function setButtonEnabled(enabled: boolean)
	rollButton.AutoButtonColor = enabled
	rollButton.BackgroundColor3 = if enabled
		then Color3.fromRGB(64, 132, 255)
		else Color3.fromRGB(96, 102, 116)
	-- Never fade the label. The old disabled state was white at 35% transparency on a dark
	-- grey fill, which came out as good as unreadable.
	rollButton.TextTransparency = 0
	rollButton.TextColor3 = if enabled then Color3.new(1, 1, 1) else Color3.fromRGB(216, 220, 228)
end

local function showCard()
	card.Visible = true
	card.Size = UDim2.fromOffset(CARD_WIDTH - 60, CARD_HEIGHT - 36)
	TweenService:Create(
		card,
		TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT) }
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
		-- Lifted, not raw: the low-score screen colours are near-black and vanished here.
		cardTvName.TextColor3 = readable(tv.Screen)
		cardDetail.Text = `{tv.Rarity} · {TvCatalog.formatValue(tv.Value)} · score {result.Score}`
	end

	-- Rolling a 1 costs you a level on everything you already owned.
	local downgraded = tonumber(result.Downgraded) or 0
	if result.IsMinFace and downgraded > 0 then
		local plural = if downgraded == 1 then "TV" else "TVs"
		cardWarning.Text = `Rolled a 1 — {downgraded} {plural} dropped a level!`
	elseif result.IsMinFace then
		cardWarning.Text = "Rolled a 1 — nothing to lose yet."
	else
		cardWarning.Text = ""
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
	-- Bottom right, clear of the middle of the screen.
	rollButton.AnchorPoint = Vector2.new(1, 1)
	rollButton.Position = UDim2.new(1, -24, 1, -40)
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
	buttonSubtitle.Font = Enum.Font.GothamMedium
	buttonSubtitle.TextSize = 14
	-- White on a black stroke. This label sits directly on the shop floor with no panel
	-- behind it, so mid-grey text disappeared against the pale marble.
	buttonSubtitle.TextColor3 = Color3.new(1, 1, 1)
	buttonSubtitle.TextStrokeTransparency = 0.15
	buttonSubtitle.Text = "click, or press R"
	buttonSubtitle.Parent = rollButton
end

local function buildResultCard(gui: ScreenGui)
	card = Instance.new("Frame")
	card.Name = "ResultCard"
	-- Bottom left, diagonally opposite the roll button so neither sits over the shop.
	card.AnchorPoint = Vector2.new(0, 1)
	card.Position = UDim2.new(0, CARD_MARGIN, 1, -CARD_MARGIN)
	card.Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT)
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

	cardWarning = Instance.new("TextLabel")
	cardWarning.Position = UDim2.new(0, 12, 0, 168)
	cardWarning.Size = UDim2.new(1, -24, 0, 32)
	cardWarning.BackgroundTransparency = 1
	cardWarning.Font = Enum.Font.GothamBold
	cardWarning.TextSize = 15
	cardWarning.TextWrapped = true
	cardWarning.TextColor3 = Color3.fromRGB(255, 128, 112)
	cardWarning.Text = ""
	cardWarning.Parent = card
end

-- Bottom-right stack, above the roll button: the paid upgrade and a toast for its feedback.
local function buildPaidUpgrade(gui: ScreenGui)
	paidButton = Instance.new("TextButton")
	paidButton.Name = "PaidUpgradeButton"
	paidButton.AnchorPoint = Vector2.new(1, 1)
	paidButton.Position = UDim2.new(1, -24, 1, -120)
	paidButton.Size = UDim2.fromOffset(240, 42)
	paidButton.BackgroundColor3 = Color3.fromRGB(52, 168, 96)
	paidButton.BorderSizePixel = 0
	paidButton.Font = Enum.Font.GothamBold
	paidButton.TextSize = 15
	paidButton.TextColor3 = Color3.new(1, 1, 1)
	paidButton.Text = `Upgrade dice · {Config.Monetisation.DisplayPrice} R$`
	paidButton.Parent = gui
	roundCorner(paidButton, 10)

	toast = Instance.new("TextLabel")
	toast.Name = "Toast"
	toast.AnchorPoint = Vector2.new(1, 1)
	toast.Position = UDim2.new(1, -24, 1, -172)
	toast.Size = UDim2.fromOffset(320, 38)
	toast.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
	toast.BackgroundTransparency = 0.1
	toast.BorderSizePixel = 0
	toast.Font = Enum.Font.GothamMedium
	toast.TextSize = 14
	toast.TextColor3 = Color3.new(1, 1, 1)
	toast.TextWrapped = true
	toast.Text = ""
	toast.Visible = false
	toast.Parent = gui
	roundCorner(toast, 8)
end

local toastToken = 0

local function showToast(message: string)
	if type(message) ~= "string" or message == "" then
		return
	end
	toastToken += 1
	local token = toastToken
	toast.Text = message
	toast.Visible = true
	task.delay(4, function()
		-- Only clear it if a newer message hasn't replaced this one.
		if token == toastToken then
			toast.Visible = false
		end
	end)
end

local function buildUpgradeModal(gui: ScreenGui)
	-- Sits directly above the result card in the same bottom-left column, so you can see
	-- both the TV you just won and the offer without anything covering the shop. There's
	-- deliberately no full-screen dim any more: it darkened the whole view, and the roll
	-- button is already blocked by the `modal.Visible` check plus the server's
	-- PendingUpgrade flag.
	modal = Instance.new("Frame")
	modal.Name = "UpgradePrompt"
	modal.AnchorPoint = Vector2.new(0, 1)
	modal.Position = UDim2.new(0, CARD_MARGIN, 1, -(CARD_MARGIN + CARD_HEIGHT + 10))
	modal.Size = UDim2.fromOffset(360, 176)
	modal.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
	modal.BackgroundTransparency = 0.05
	modal.BorderSizePixel = 0
	modal.Active = true
	modal.Visible = false
	modal.Parent = gui
	roundCorner(modal, 14)

	modalText = Instance.new("TextLabel")
	modalText.Position = UDim2.new(0, 16, 0, 16)
	modalText.Size = UDim2.new(1, -32, 0, 92)
	modalText.BackgroundTransparency = 1
	modalText.Font = Enum.Font.Gotham
	modalText.TextSize = 17
	modalText.TextWrapped = true
	modalText.RichText = true
	modalText.TextColor3 = Color3.new(1, 1, 1)
	modalText.Text = ""
	modalText.Parent = modal

	acceptButton = Instance.new("TextButton")
	acceptButton.AnchorPoint = Vector2.new(0, 1)
	acceptButton.Position = UDim2.new(0, 16, 1, -16)
	acceptButton.Size = UDim2.fromOffset(156, 44)
	acceptButton.BackgroundColor3 = Color3.fromRGB(72, 196, 120)
	acceptButton.BorderSizePixel = 0
	acceptButton.Font = Enum.Font.GothamBold
	acceptButton.TextSize = 17
	acceptButton.TextColor3 = Color3.new(1, 1, 1)
	acceptButton.Text = "Upgrade!"
	acceptButton.Parent = modal
	roundCorner(acceptButton, 10)

	declineButton = Instance.new("TextButton")
	declineButton.AnchorPoint = Vector2.new(1, 1)
	declineButton.Position = UDim2.new(1, -16, 1, -16)
	declineButton.Size = UDim2.fromOffset(156, 44)
	declineButton.BackgroundColor3 = Color3.fromRGB(84, 90, 104)
	declineButton.BorderSizePixel = 0
	declineButton.Font = Enum.Font.GothamBold
	declineButton.TextSize = 16
	declineButton.TextColor3 = Color3.new(1, 1, 1)
	declineButton.Text = "Keep this dice"
	declineButton.Parent = modal
	roundCorner(declineButton, 10)
end

function RollController:Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RollUi"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true

	buildRollButton(gui)
	buildResultCard(gui)
	buildPaidUpgrade(gui)
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

	paidButton.MouseButton1Click:Connect(function()
		Remotes.Events.RequestPaidUpgrade:FireServer()
	end)

	Remotes.Events.RollResult.OnClientEvent:Connect(onRollResult)
	Remotes.Events.DiceUpgradeOffered.OnClientEvent:Connect(onUpgradeOffered)
	Remotes.Events.Notice.OnClientEvent:Connect(showToast)

	Remotes.Events.DataChanged.OnClientEvent:Connect(function(playerData)
		if type(playerData) ~= "table" then
			return
		end
		if playerData.Rolls then
			local rolls = playerData.Rolls
			buttonSubtitle.Text = `{rolls} {if rolls == 1 then "roll" else "rolls"} · press R`
		end
		-- Hide the paid upgrade once there's nothing left to buy.
		if playerData.DiceTier then
			local atMax = playerData.DiceTier >= #DiceTiers.Tiers
			paidButton.Visible = not atMax
			toast.Position = UDim2.new(1, -24, 1, if atMax then -120 else -172)
		end
	end)
end

return RollController
