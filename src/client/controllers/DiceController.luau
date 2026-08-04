--!strict
-- Throws a physical-looking 3D die that lands on the face the server already rolled.
--
-- Deliberately NOT physics-driven. The server decides the number before anything is
-- drawn, so a simulated die would either contradict it or would have to *be* the source
-- of truth — which would hand outcome control to the client and desync across players.
--
-- Instead the tumble is scripted, and lands exactly on target by construction: the spin
-- applied at time t is CFrame.Angles(2*pi*n*t, ...) for whole numbers of turns, so at
-- t=1 the spin term is the identity and all that remains is the target orientation.
-- No snap at the end, and it can never come to rest on the wrong number.
--
-- The die is created locally, so it isn't replicated and costs the server nothing.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DiceGeometry = require(Shared:WaitForChild("DiceGeometry"))

local player = Players.LocalPlayer

local DiceController = {
	Name = "DiceController",
}

local DIE_SIZE = 3
local THROW_DISTANCE = 11
local ARC_HEIGHT = 7
local FLIGHT_SECONDS = 1.35
local LINGER_SECONDS = 2.6
local TWO_PI = math.pi * 2

-- Bounce geometry. If something is in the way, the die stops just short of it, then rebounds
-- back towards the thrower instead of passing through it.
local IMPACT_GAP = 1.4 -- how far short of the obstacle the die turns around
local BOUNCE_BACK = 4.0 -- how far back towards the player it rebounds
local BOUNCE_HEIGHT = 2.6
local MIN_REST_OFFSET = 2.0 -- never come to rest inside the thrower
local IMPACT_FRACTION = 0.55 -- share of the flight spent travelling outwards

-- Whole turns per axis. Integers matter — see the note at the top of the file.
local SPIN_TURNS = { X = 3, Y = 2, Z = 4 }

local function buildPips(die: Part)
	for value, positions in DiceGeometry.Pips do
		local surface = Instance.new("SurfaceGui")
		surface.Name = `Face{value}`
		surface.Face = DiceGeometry.FaceId[value]
		surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		surface.PixelsPerStud = 64
		surface.Parent = die

		for index, position in positions do
			local pip = Instance.new("Frame")
			pip.Name = `Pip{index}`
			pip.AnchorPoint = Vector2.new(0.5, 0.5)
			pip.Position = UDim2.fromScale(position[1], position[2])
			pip.Size = UDim2.fromScale(0.19, 0.19)
			pip.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
			pip.BorderSizePixel = 0
			pip.Parent = surface

			local round = Instance.new("UICorner")
			round.CornerRadius = UDim.new(1, 0)
			round.Parent = pip
		end
	end
end

local function buildDie(bodyColor: Color3): Part
	local die = Instance.new("Part")
	die.Name = "RollingDie"
	die.Size = Vector3.new(DIE_SIZE, DIE_SIZE, DIE_SIZE)
	die.Anchored = true
	die.CanCollide = false
	-- Local-only decoration; must never block anyone's character.
	die.CanQuery = false
	die.CanTouch = false
	die.Color = bodyColor
	die.Material = Enum.Material.SmoothPlastic
	die.TopSurface = Enum.SurfaceType.Smooth
	die.BottomSurface = Enum.SurfaceType.Smooth

	buildPips(die)
	return die
end

type Throw = {
	Start: Vector3,
	Forward: Vector3,
	-- Distance from Start to whatever is in the way, or nil for a clear throw.
	ImpactOffset: number?,
	-- Distance from Start to where the die finishes.
	RestOffset: number,
	RestY: number,
}

-- Works out where the die starts, what it's going to hit, and where it settles.
local function resolveThrow(): Throw
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?

	local origin: Vector3
	local forward: Vector3

	if root then
		origin = root.Position
		forward = root.CFrame.LookVector
	elseif camera then
		origin = camera.CFrame.Position
		forward = camera.CFrame.LookVector
	else
		origin = Vector3.new(0, 5, 0)
		forward = Vector3.new(0, 0, -1)
	end

	-- Flatten so the die never gets thrown into the sky or the floor.
	local flat = Vector3.new(forward.X, 0, forward.Z)
	forward = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)

	local start = origin + Vector3.new(0, 1.5, 0) + forward * 2

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character :: any }

	-- What's in the way? Standing at a podium, this is the telly, and without it the die
	-- flew straight through the screen.
	local ahead = Workspace:Raycast(start, forward * THROW_DISTANCE, params)
	local impactOffset = if ahead then ahead.Distance else nil

	local restOffset = if impactOffset
		then math.clamp(impactOffset - BOUNCE_BACK, MIN_REST_OFFSET, THROW_DISTANCE)
		else THROW_DISTANCE

	-- Drop the resting point onto whatever surface is under it — floor, plinth, whatever.
	local restPoint = start + forward * restOffset
	local below =
		Workspace:Raycast(restPoint + Vector3.new(0, 20, 0), Vector3.new(0, -60, 0), params)
	local groundY = if below then below.Position.Y else origin.Y - 2.5

	return {
		Start = start,
		Forward = forward,
		ImpactOffset = impactOffset,
		RestOffset = restOffset,
		RestY = groundY + DIE_SIZE / 2,
	}
end

-- Position along the throw at eased progress `t`. Two shapes: a clean arc when nothing is in
-- the way, or out-then-rebound when there is. Continuous at the join, and both finish exactly
-- at the resting point so the landing orientation still holds.
local function positionAt(throw: Throw, t: number): Vector3
	local startY = throw.Start.Y
	local impact = throw.ImpactOffset

	if not impact then
		local offset = throw.RestOffset * t
		local height = startY + (throw.RestY - startY) * t + ARC_HEIGHT * math.sin(math.pi * t)
		return throw.Start + throw.Forward * offset + Vector3.new(0, height - startY, 0)
	end

	local turnOffset = math.max(impact - IMPACT_GAP, 0)
	-- Height at the moment of contact, roughly chest height on the telly.
	local contactY = startY + 1.5

	local offset, height
	if t <= IMPACT_FRACTION then
		local p = t / IMPACT_FRACTION
		offset = turnOffset * p
		height = startY + (contactY - startY) * p + ARC_HEIGHT * 0.7 * math.sin(math.pi * p)
	else
		local p = (t - IMPACT_FRACTION) / (1 - IMPACT_FRACTION)
		offset = turnOffset + (throw.RestOffset - turnOffset) * p
		height = contactY
			+ (throw.RestY - contactY) * p
			-- Rebound hop that flattens out as it settles.
			+ BOUNCE_HEIGHT * math.sin(math.pi * p) * (1 - p * 0.5)
	end

	return throw.Start + throw.Forward * offset + Vector3.new(0, height - startY, 0)
end

-- Throws the die and yields until it has landed. Returns immediately if `value` is junk.
function DiceController:Play(value: number, bodyColor: Color3?)
	if type(value) ~= "number" or not DiceGeometry.LandOrientation[value] then
		return
	end

	local die = buildDie(bodyColor or Color3.fromRGB(240, 240, 240))
	local throw = resolveThrow()
	local landOrientation = DiceGeometry.LandOrientation[value]
	local landing = throw.Start
		+ throw.Forward * throw.RestOffset
		+ Vector3.new(0, throw.RestY - throw.Start.Y, 0)

	die.CFrame = CFrame.new(throw.Start) * landOrientation
	die.Parent = Workspace

	local startClock = os.clock()
	local connection: RBXScriptConnection

	connection = RunService.RenderStepped:Connect(function()
		local t = math.min((os.clock() - startClock) / FLIGHT_SECONDS, 1)

		-- Ease out so it slows as it settles, like a die losing momentum.
		local eased = 1 - (1 - t) ^ 3

		local position = positionAt(throw, eased)

		local spin = CFrame.Angles(
			TWO_PI * SPIN_TURNS.X * eased,
			TWO_PI * SPIN_TURNS.Y * eased,
			TWO_PI * SPIN_TURNS.Z * eased
		)

		die.CFrame = CFrame.new(position) * spin * landOrientation

		if t >= 1 then
			connection:Disconnect()
		end
	end)

	task.wait(FLIGHT_SECONDS)

	-- Belt and braces: if the frame loop was cut short, put it exactly on target anyway.
	if connection.Connected then
		connection:Disconnect()
	end
	die.CFrame = CFrame.new(landing) * landOrientation

	-- Fade out rather than vanish. A part's Transparency has no effect on a SurfaceGui
	-- drawn on it, so the pips have to be switched off separately or they'd hang in the
	-- air as floating dots while the cube behind them faded away.
	task.delay(LINGER_SECONDS, function()
		if not die.Parent then
			return
		end
		for _, child in die:GetChildren() do
			if child:IsA("SurfaceGui") then
				child.Enabled = false
			end
		end
		TweenService:Create(die, TweenInfo.new(0.4), { Transparency = 1 }):Play()
	end)
	Debris:AddItem(die, LINGER_SECONDS + 0.5)
end

return DiceController
