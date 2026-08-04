--!strict
-- What's outside the shopfront: mono-yellow wallpaper, damp carpet, buzzing fluorescents
-- and a maze of identical rooms. You can see it through the glass and walk out into it.
--
-- The layout uses a FIXED seed, not math.random. It's generated on the server at startup,
-- so an unseeded maze would be a different shape every launch and nobody could learn it —
-- and two servers would disagree about a place that's supposed to feel endless.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local BackroomsService = {
	Name = "BackroomsService",
}

local B = Config.Backrooms
local WALL = 2
local FLOOR_Y = Config.Shop.FloorY

-- The carpet butts exactly up against the shop floor, which ends at FrontZ. Starting it any
-- further out leaves a hole in the floor across the doorway; any nearer and two floor slabs
-- overlap in the same place and flicker.
local CARPET_START = Config.Shop.FrontZ
local END_Z = CARPET_START + B.Depth

-- Ceiling, walls and maze start just clear of the shopfront glass, so nothing intersects it.
local SHELL_START = Config.Shop.FrontZ + 1.5

local SPAN_X = B.HalfWidth * 2

local WALLPAPER = Color3.fromRGB(198, 176, 96)
local WALLPAPER_ALT = Color3.fromRGB(184, 162, 84)
local CARPET = Color3.fromRGB(142, 126, 74)
local CARPET_DAMP = Color3.fromRGB(104, 92, 54)
local TILE = Color3.fromRGB(196, 184, 138)
local FLUORESCENT = Color3.fromRGB(255, 246, 198)

-- Any fixed number does; this one just has to stay the same.
local SEED = 20240804

local rooms: Model

local function gridSize(): (number, number)
	local cell = B.CellSize
	return math.floor(SPAN_X / cell), math.floor((END_Z - SHELL_START) / cell)
end

local function cellCentre(column: number, row: number): Vector3
	local cell = B.CellSize
	return Vector3.new(
		-B.HalfWidth + (column + 0.5) * cell,
		FLOOR_Y,
		SHELL_START + (row + 0.5) * cell
	)
end

-- Where the hidden bonus TV lives: a back corner room, far from the shop door.
--
-- Deliberately a pure function of Config with no reliance on Init having run, so
-- BonusTvService can ask for it regardless of which service starts first. Deriving the same
-- coordinates independently in both files would be a drift bug waiting to happen.
function BackroomsService.bonusCell(): (number, number)
	local columns, rowCount = gridSize()
	return math.max(columns - 2, 0), math.max(rowCount - 2, 0)
end

function BackroomsService.bonusPosition(): Vector3
	local column, row = BackroomsService.bonusCell()
	return cellCentre(column, row)
end

local function block(name: string, size: Vector3, position: Vector3, colour: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = position
	part.Anchored = true
	part.Color = colour
	part.Material = Enum.Material.Concrete
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = rooms
	return part
end

local function carpetCentreZ(): number
	return (CARPET_START + END_Z) / 2
end

local function shellCentreZ(): number
	return (SHELL_START + END_Z) / 2
end

local function shellDepth(): number
	return END_Z - SHELL_START
end

local function buildShell()
	local floor = block(
		"Carpet",
		Vector3.new(SPAN_X, 1, END_Z - CARPET_START),
		Vector3.new(0, FLOOR_Y - 0.5, carpetCentreZ()),
		CARPET
	)
	floor.Material = Enum.Material.Fabric

	local ceiling = block(
		"CeilingTiles",
		Vector3.new(SPAN_X, WALL, shellDepth()),
		Vector3.new(0, FLOOR_Y + B.CeilingHeight + WALL / 2, shellCentreZ()),
		TILE
	)
	ceiling.Material = Enum.Material.Fabric

	local midY = FLOOR_Y + B.CeilingHeight / 2

	-- Perimeter, so you can't wander off the edge of the world.
	for _, sx in { -1, 1 } do
		block(
			"OuterWall",
			Vector3.new(WALL, B.CeilingHeight, shellDepth()),
			Vector3.new(sx * (B.HalfWidth + WALL / 2), midY, shellCentreZ()),
			WALLPAPER
		)
	end
	block(
		"FarWall",
		Vector3.new(SPAN_X + WALL * 2, B.CeilingHeight, WALL),
		Vector3.new(0, midY, END_Z + WALL / 2),
		WALLPAPER
	)

	-- Wall off only the strip either side of the shop's own front, from the shop's corner out
	-- to the perimeter. Deliberately NOT across the shopfront itself: putting wallpaper behind
	-- the glass would hide the very thing it's meant to look out on, and would also stop you
	-- walking out of the door.
	local flankWidth = B.HalfWidth - Config.Shop.HalfWidth
	if flankWidth > 0 then
		for _, sx in { -1, 1 } do
			block(
				"ShopFlank",
				Vector3.new(flankWidth, B.CeilingHeight, WALL),
				Vector3.new(sx * (Config.Shop.HalfWidth + flankWidth / 2), midY, SHELL_START),
				WALLPAPER_ALT
			)
		end
	end
end

-- Wall segments on a grid, with gaps, so it reads as rooms rather than a hedge maze.
local function buildMaze()
	local rng = Random.new(SEED)
	local midY = FLOOR_Y + B.CeilingHeight / 2
	local cell = B.CellSize

	local columns = math.floor(SPAN_X / cell)
	local rowCount = math.floor(shellDepth() / cell)
	local bonusColumn, bonusRow = BackroomsService.bonusCell()

	for column = 0, columns - 1 do
		for row = 0, rowCount - 1 do
			local x = -B.HalfWidth + (column + 0.5) * cell
			local z = SHELL_START + (row + 0.5) * cell

			-- Leave the first couple of rooms by the shop door clear, or you step out of
			-- the shop straight into a wall.
			local nearDoor = row <= 1 and math.abs(x) < cell * 1.5
			if nearDoor then
				continue
			end

			-- Leave the bonus room itself empty, so the TV isn't buried inside a wall or a
			-- pillar and the room reads as deliberately different when you find it.
			if column == bonusColumn and row == bonusRow then
				continue
			end

			-- Wall along X on this cell's far edge.
			if rng:NextNumber() < 0.34 then
				local width = cell * (if rng:NextNumber() < 0.3 then 0.55 else 1)
				block(
					"RoomWall",
					Vector3.new(width, B.CeilingHeight, WALL),
					Vector3.new(x, midY, z + cell / 2),
					if rng:NextNumber() < 0.5 then WALLPAPER else WALLPAPER_ALT
				)
			end

			-- Wall along Z on this cell's right edge.
			if rng:NextNumber() < 0.34 then
				local depth = cell * (if rng:NextNumber() < 0.3 then 0.55 else 1)
				block(
					"RoomWall",
					Vector3.new(WALL, B.CeilingHeight, depth),
					Vector3.new(x + cell / 2, midY, z),
					if rng:NextNumber() < 0.5 then WALLPAPER else WALLPAPER_ALT
				)
			end

			-- Support pillar, occasionally.
			if rng:NextNumber() < 0.12 then
				block(
					"Pillar",
					Vector3.new(3, B.CeilingHeight, 3),
					Vector3.new(x, midY, z),
					WALLPAPER_ALT
				)
			end

			-- Damp patch on the carpet.
			if rng:NextNumber() < 0.18 then
				local patch = block(
					"DampPatch",
					Vector3.new(
						cell * rng:NextNumber() * 0.7 + 3,
						0.06,
						cell * rng:NextNumber() * 0.7 + 3
					),
					Vector3.new(x, FLOOR_Y + 0.03, z),
					CARPET_DAMP
				)
				patch.Material = Enum.Material.Fabric
				patch.CanCollide = false
				patch.CanQuery = false
			end
		end
	end
end

local function buildLights()
	local rng = Random.new(SEED + 1)
	local cell = B.CellSize
	local columns = math.floor(SPAN_X / cell)
	local rowCount = math.floor(shellDepth() / cell)

	for column = 0, columns - 1 do
		for row = 0, rowCount - 1 do
			-- Every other cell, checkerboard, so the corridors go light-dark-light.
			if (column + row) % 2 ~= 0 then
				continue
			end

			local x = -B.HalfWidth + (column + 0.5) * cell
			local z = SHELL_START + (row + 0.5) * cell

			-- The odd dead one, which is most of the atmosphere.
			local dead = rng:NextNumber() < 0.16

			local strip = block(
				"Fluorescent",
				Vector3.new(9, 0.3, 2.2),
				Vector3.new(x, FLOOR_Y + B.CeilingHeight - 0.15, z),
				if dead then Color3.fromRGB(120, 116, 100) else FLUORESCENT
			)
			strip.Material = if dead then Enum.Material.SmoothPlastic else Enum.Material.Neon
			strip.CanCollide = false
			strip.CanQuery = false

			if not dead then
				local lamp = Instance.new("PointLight")
				lamp.Color = Color3.fromRGB(255, 240, 180)
				lamp.Brightness = 0.7
				lamp.Range = 30
				-- Shadows off, same reasoning as the shop: there are dozens of these.
				lamp.Shadows = false
				lamp.Parent = strip
			end
		end
	end
end

function BackroomsService:Init()
	rooms = Instance.new("Model")
	rooms.Name = "Backrooms"
	rooms.Parent = Workspace

	buildShell()
	buildMaze()
	buildLights()

	print(`[BackroomsService] Built the Backrooms ({#rooms:GetChildren()} parts).`)
end

return BackroomsService
