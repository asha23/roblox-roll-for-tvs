--!strict
-- The top-10 board on the shop's right-hand wall, backed by an OrderedDataStore.
--
-- Separate store from player data on purpose. A normal DataStore can't be sorted, so a
-- leaderboard needs an OrderedDataStore, which only holds integers — one score per user id.
-- It's a projection of the real data, never the source of it: if it's wrong or wiped, nobody
-- loses a TV.
--
-- Publishing is throttled to the refresh tick rather than fired on every roll. Writing on
-- every roll would burn through the DataStore write budget with a full server in minutes.
--
-- In Studio this needs Game Settings -> Security -> Enable Studio Access to API Services.
-- Without it the board says so instead of sitting there looking broken.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TvCatalog = require(Shared:WaitForChild("TvCatalog"))

local PlayerDataService = require(script.Parent.PlayerDataService)

local ScoreboardService = {
	Name = "ScoreboardService",
}

local ROWS = Config.Data.ScoreboardEntries

-- Placed on the right-hand wall in the gap between the back wall and the first shelf unit.
-- The shelving on that wall runs from z=-38 forwards, and the back wall's inner face is at
-- z=-60, so the board spans -59..-39 and touches neither.
local BOARD_WIDTH = 20
local BOARD_HEIGHT = 20
local BOARD_Z = -49

local rowLabels: { { Rank: TextLabel, Name: TextLabel, Score: TextLabel } } = {}
local statusLabel: TextLabel

local board: OrderedDataStore?
do
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(Config.Data.LeaderboardName)
	end)
	if ok then
		board = result
	else
		warn(`[ScoreboardService] No leaderboard store available: {result}`)
	end
end

-- User ids are what the ordered store holds; names have to be looked up separately, and that
-- call is rate-limited, so cache every answer for the life of the server.
local nameCache: { [number]: string } = {}

-- Last total seen for each player, kept up to date from PlayerDataService's change callback.
--
-- Needed because PlayerDataService clears its own entry on PlayerRemoving, and the two
-- handlers run in whichever order the services happened to start. Reading Get() during
-- removal is therefore a race that would sometimes publish nothing; a cached value can't lose.
local lastTotal: { [Player]: number } = {}

local function nameFor(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end

	-- Anyone in this server we already know, no web call needed.
	local player = Players:GetPlayerByUserId(userId)
	if player then
		nameCache[userId] = player.DisplayName
		return player.DisplayName
	end

	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local resolved = if ok and type(result) == "string" then result else `Player {userId}`
	nameCache[userId] = resolved
	return resolved
end

local function buildBoard()
	local model = Instance.new("Model")
	model.Name = "Scoreboard"
	model.Parent = Workspace

	-- Flush against the inside of the right-hand wall.
	local panel = Instance.new("Part")
	panel.Name = "Panel"
	panel.Size = Vector3.new(0.6, BOARD_HEIGHT, BOARD_WIDTH)
	panel.Position = Vector3.new(Config.Shop.HalfWidth - 0.4, Config.Shop.FloorY + 13, BOARD_Z)
	panel.Anchored = true
	panel.Color = Color3.fromRGB(14, 16, 22)
	panel.Material = Enum.Material.SmoothPlastic
	panel.Parent = model
	model.PrimaryPart = panel

	local trim = Instance.new("Part")
	trim.Name = "Trim"
	trim.Size = Vector3.new(0.3, BOARD_HEIGHT + 1, BOARD_WIDTH + 1)
	trim.Position = panel.Position + Vector3.new(0.2, 0, 0)
	trim.Anchored = true
	trim.CanCollide = false
	trim.CanQuery = false
	trim.Color = Color3.fromRGB(64, 132, 255)
	trim.Material = Enum.Material.Neon
	trim.Parent = model

	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(64, 132, 255)
	glow.Brightness = 0.8
	glow.Range = 22
	glow.Shadows = false
	glow.Parent = trim

	-- The right wall's inner face points at -X, which Roblox calls Left.
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Left
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 36
	surface.Parent = panel

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Parent = surface

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 18)
	padding.PaddingBottom = UDim.new(0, 18)
	padding.PaddingLeft = UDim.new(0, 24)
	padding.PaddingRight = UDim.new(0, 24)
	padding.Parent = frame

	local heading = Instance.new("TextLabel")
	heading.Size = UDim2.new(1, 0, 0, 70)
	heading.BackgroundTransparency = 1
	heading.Font = Enum.Font.GothamBlack
	heading.TextScaled = true
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.TextColor3 = Color3.fromRGB(120, 200, 255)
	heading.Text = `TOP {ROWS}`
	heading.Parent = frame

	statusLabel = Instance.new("TextLabel")
	statusLabel.AnchorPoint = Vector2.new(0, 1)
	statusLabel.Position = UDim2.fromScale(0, 1)
	statusLabel.Size = UDim2.new(1, 0, 0, 30)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextScaled = true
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextColor3 = Color3.fromRGB(150, 158, 172)
	statusLabel.Text = "loading…"
	statusLabel.Parent = frame

	local rowHeight = 46
	for index = 1, ROWS do
		local row = Instance.new("Frame")
		row.Name = `Row{index}`
		row.Position = UDim2.new(0, 0, 0, 76 + (index - 1) * rowHeight)
		row.Size = UDim2.new(1, 0, 0, rowHeight - 6)
		row.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		-- Faint banding so ten rows are readable at a glance.
		row.BackgroundTransparency = if index % 2 == 0 then 0.96 else 1
		row.BorderSizePixel = 0
		row.Parent = frame

		local rank = Instance.new("TextLabel")
		rank.Size = UDim2.new(0.1, 0, 1, 0)
		rank.BackgroundTransparency = 1
		rank.Font = Enum.Font.GothamBold
		rank.TextScaled = true
		rank.TextXAlignment = Enum.TextXAlignment.Left
		-- Gold, silver, bronze for the top three.
		rank.TextColor3 = if index == 1
			then Color3.fromRGB(255, 214, 90)
			elseif index == 2 then Color3.fromRGB(206, 212, 222)
			elseif index == 3 then Color3.fromRGB(214, 148, 92)
			else Color3.fromRGB(120, 128, 142)
		rank.Text = tostring(index)
		rank.Parent = row

		local name = Instance.new("TextLabel")
		name.Position = UDim2.fromScale(0.12, 0)
		name.Size = UDim2.new(0.53, 0, 1, 0)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.GothamMedium
		name.TextScaled = true
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.TextColor3 = Color3.new(1, 1, 1)
		name.Text = "—"
		name.Parent = row

		local score = Instance.new("TextLabel")
		score.AnchorPoint = Vector2.new(1, 0)
		score.Position = UDim2.fromScale(1, 0)
		score.Size = UDim2.new(0.33, 0, 1, 0)
		score.BackgroundTransparency = 1
		score.Font = Enum.Font.GothamBold
		score.TextScaled = true
		score.TextXAlignment = Enum.TextXAlignment.Right
		score.TextColor3 = Color3.fromRGB(120, 238, 180)
		score.Text = ""
		score.Parent = row

		rowLabels[index] = { Rank = rank, Name = name, Score = score }
	end
end

-- Pushes the current totals of everyone in this server into the ordered store.
local function publish()
	if not board then
		return
	end

	for _, player in Players:GetPlayers() do
		local playerData = PlayerDataService:Get(player)
		if playerData then
			-- Ordered stores are integers only, and a negative would be meaningless here.
			local value = math.max(math.floor(playerData.TotalValue), 0)
			local activeBoard = board :: OrderedDataStore
			local ok, err = pcall(function()
				activeBoard:SetAsync(tostring(player.UserId), value)
			end)
			if not ok then
				warn(`[ScoreboardService] Couldn't publish {player.Name}: {err}`)
			end
		end
	end
end

local function render(entries: { { userId: number, value: number } }, note: string)
	for index = 1, ROWS do
		local labels = rowLabels[index]
		local entry = entries[index]
		if entry then
			labels.Name.Text = nameFor(entry.userId)
			labels.Score.Text = TvCatalog.formatValue(entry.value)
		else
			labels.Name.Text = "—"
			labels.Score.Text = ""
		end
	end
	statusLabel.Text = note
end

local function refresh()
	if not board then
		render({}, "leaderboard unavailable — API services off")
		return
	end

	local ok, pages = pcall(function()
		return (board :: OrderedDataStore):GetSortedAsync(false, ROWS)
	end)

	if not ok then
		warn(`[ScoreboardService] Couldn't read the leaderboard: {pages}`)
		-- Leave whatever was last shown rather than blanking a good board on one bad call.
		statusLabel.Text = "couldn't refresh — retrying"
		return
	end

	local entries = {}
	local ok2, page = pcall(function()
		return pages:GetCurrentPage()
	end)
	if ok2 and type(page) == "table" then
		for _, item in page do
			local userId = tonumber(item.key)
			if userId then
				table.insert(entries, { userId = userId, value = item.value })
			end
		end
	end

	render(entries, if #entries == 0 then "no scores yet" else `updated · top {#entries}`)
end

function ScoreboardService:Init()
	buildBoard()

	PlayerDataService:OnChanged(function(player, playerData)
		lastTotal[player] = math.max(math.floor(playerData.TotalValue), 0)
	end)
end

function ScoreboardService:Start()
	-- Publish before the first read so anyone already playing appears straight away.
	task.spawn(function()
		while true do
			publish()
			refresh()
			task.wait(Config.Data.ScoreboardRefreshSeconds)
		end
	end)

	-- A leaver's final total should reach the board without waiting for the next tick. Uses
	-- the cached total, not Get(), for the ordering reason noted above.
	Players.PlayerRemoving:Connect(function(player)
		local value = lastTotal[player]
		lastTotal[player] = nil
		if not board or not value then
			return
		end
		local userId = player.UserId
		local activeBoard = board :: OrderedDataStore
		task.spawn(function()
			pcall(function()
				activeBoard:SetAsync(tostring(userId), value)
			end)
		end)
	end)
end

return ScoreboardService
