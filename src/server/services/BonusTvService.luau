--!strict
-- The hidden prize: one Infinite Screen standing in a back room of the Backrooms. Walk into
-- it and you get fireworks and Config.Bonus.Value added to your total.
--
-- Claimable once per player, ever — the flag lives in saved player data, so it survives
-- rejoining. Tracked server-side because the trigger is a Touched part, which fires many times
-- during a single walk-through and which a modified client could fire deliberately.
--
-- Runs entirely on the server, so everyone sees the fireworks, not just whoever set them off.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local TvBuilder = require(Shared:WaitForChild("TvBuilder"))
local TvCatalog = require(Shared:WaitForChild("TvCatalog"))

local BackroomsService = require(script.Parent.BackroomsService)
local PlayerDataService = require(script.Parent.PlayerDataService)

local BonusTvService = {
	Name = "BonusTvService",
}

-- The bonus telly is the top of the catalog, which is the whole point of it being hidden.
local BONUS_SCORE = 30

local ROCKET_COUNT = 9
local ROCKET_GAP = 0.16
local ROCKET_RISE_MIN = 5.5
-- Capped well under the Backrooms ceiling — a rocket that clips through the tiles looks
-- broken rather than celebratory.
local ROCKET_RISE_MAX = 8.5

local FIREWORK_COLOURS = {
	Color3.fromRGB(255, 96, 120),
	Color3.fromRGB(120, 220, 255),
	Color3.fromRGB(255, 226, 96),
	Color3.fromRGB(150, 255, 150),
	Color3.fromRGB(220, 140, 255),
}

local root: Model

local function burstEmitter(colour: Color3): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	-- Rate 0 so it only ever fires on :Emit(), rather than trickling constantly.
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.5, 1.1)
	emitter.Speed = NumberRange.new(14, 30)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 4
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Color = ColorSequence.new(colour)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.4),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	return emitter
end

local function launchRocket(origin: Vector3, colour: Color3, spread: number, rise: number)
	local rocket = Instance.new("Part")
	rocket.Name = "Firework"
	rocket.Size = Vector3.new(0.5, 0.5, 0.5)
	rocket.Shape = Enum.PartType.Ball
	rocket.Anchored = true
	rocket.CanCollide = false
	rocket.CanQuery = false
	rocket.CanTouch = false
	rocket.Color = colour
	rocket.Material = Enum.Material.Neon
	rocket.Position = origin
	rocket.Parent = root

	local apex = origin + Vector3.new(spread, rise, spread * 0.6)

	-- Tweened on the server so the position changes replicate and everyone sees the same
	-- rocket, rather than each client inventing its own.
	local climb = TweenService:Create(
		rocket,
		TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = apex }
	)
	climb:Play()

	local emitter = burstEmitter(colour)
	emitter.Parent = rocket

	local flash = Instance.new("PointLight")
	flash.Color = colour
	flash.Brightness = 0
	flash.Range = 26
	flash.Shadows = false
	flash.Parent = rocket

	climb.Completed:Connect(function()
		emitter:Emit(90)
		flash.Brightness = 5

		local bang = Instance.new("Sound")
		bang.SoundId = Config.Sounds.Firework
		bang.Volume = 0.5
		bang.PlaybackSpeed = 0.7 + (spread + 4) / 16
		bang.RollOffMaxDistance = 140
		bang.Parent = rocket
		bang:Play()

		TweenService:Create(flash, TweenInfo.new(0.5), { Brightness = 0 }):Play()
		-- Hide the shell but leave the part alive so its particles finish their lifetime.
		rocket.Transparency = 1
		Debris:AddItem(rocket, 2.5)
	end)
end

function BonusTvService:Celebrate(origin: Vector3)
	for index = 1, ROCKET_COUNT do
		task.delay((index - 1) * ROCKET_GAP, function()
			local colour = FIREWORK_COLOURS[(index - 1) % #FIREWORK_COLOURS + 1]
			-- Fan them out left to right rather than stacking them all in one column.
			local spread = ((index - 1) / (ROCKET_COUNT - 1) - 0.5) * 14
			local rise = ROCKET_RISE_MIN
				+ (ROCKET_RISE_MAX - ROCKET_RISE_MIN) * (1 - math.abs(spread) / 7)
			launchRocket(origin, colour, spread, rise)
		end)
	end
end

local function claim(player: Player, origin: Vector3)
	-- The claim flag lives in saved player data, not a table here. Once progress persists, an
	-- in-memory flag would let anyone rejoin and collect the 30,000 again on every visit.
	-- ClaimBonus returns false if it's already been taken, which also covers the repeated
	-- Touched events a single walk-through fires.
	if not PlayerDataService:ClaimBonus(player) then
		return
	end

	PlayerDataService:AddBonus(player, Config.Bonus.Value)
	BonusTvService:Celebrate(origin + Vector3.new(0, 2, 0))

	local chime = Instance.new("Sound")
	chime.SoundId = Config.Sounds.Bonus
	chime.Volume = 0.6
	chime.RollOffMaxDistance = 120
	chime.Parent = root
	chime:Play()
	Debris:AddItem(chime, 4)

	local amount = TvCatalog.formatValue(Config.Bonus.Value)
	Remotes.Events.Notice:FireClient(player, `You found the hidden TV! +{amount}`)
	for _, other in Players:GetPlayers() do
		if other ~= player then
			Remotes.Events.Notice:FireClient(other, `{player.DisplayName} found the hidden TV!`)
		end
	end
end

function BonusTvService:Init()
	root = Instance.new("Model")
	root.Name = "BonusTv"
	root.Parent = Workspace

	local origin = BackroomsService.bonusPosition()

	-- A low plinth, so it reads as displayed rather than dumped in a corridor.
	local plinth = Instance.new("Part")
	plinth.Name = "Plinth"
	plinth.Size = Vector3.new(14, 0.6, 8)
	plinth.Position = origin + Vector3.new(0, 0.3, 0)
	plinth.Anchored = true
	plinth.Color = Color3.fromRGB(38, 40, 50)
	plinth.Material = Enum.Material.Slate
	plinth.TopSurface = Enum.SurfaceType.Smooth
	plinth.Parent = root

	local tv = TvBuilder.build(BONUS_SCORE)
	tv.Name = "TheHiddenScreen"
	tv:PivotTo(CFrame.new(origin + Vector3.new(0, 0.6, 0)))
	tv.Parent = root

	local sign = Instance.new("BillboardGui")
	sign.Size = UDim2.fromOffset(300, 50)
	sign.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
	sign.AlwaysOnTop = true
	sign.MaxDistance = 120
	sign.Parent = plinth

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 226, 120)
	label.TextStrokeTransparency = 0.2
	label.Text = "BONUS TV"
	label.Parent = sign

	-- Invisible trigger volume around the whole thing. Generous, because a small collider on
	-- a low plinth is easy to walk past without touching.
	local trigger = Instance.new("Part")
	trigger.Name = "Trigger"
	trigger.Size = Vector3.new(18, 14, 12)
	trigger.Position = origin + Vector3.new(0, 7, 0)
	trigger.Anchored = true
	trigger.CanCollide = false
	trigger.CanQuery = false
	trigger.Transparency = 1
	trigger.Parent = root

	trigger.Touched:Connect(function(hit)
		local character = hit and hit.Parent
		if not character then
			return
		end
		local player = Players:GetPlayerFromCharacter(character)
		if player then
			claim(player, origin)
		end
	end)

	print(`[BonusTvService] Hidden TV placed at {math.floor(origin.X)}, {math.floor(origin.Z)}.`)
end

return BonusTvService
