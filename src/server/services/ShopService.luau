--!strict
-- Builds the TV shop the game is set in: floor, walls, shopfront, shelving stocked with
-- tellies, a video wall, a counter, and lit ceiling panels.
--
-- All generated in code from Config.Shop, so there's nothing to model in Studio and the
-- room can be resized by changing two numbers. Runs in Init, before players arrive.
--
-- Layout, looking in through the front door:
--
--   z = -60  back wall, neon sign, display podiums in front of it
--   z =   0  shop floor, shelving down both side walls, counter on the right
--   z = +30  shopfront glass with a doorway in the middle, spawn just inside

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local ShopService = {
	Name = "ShopService",
}

local SHOP = Config.Shop
local WALL = 2 -- wall thickness
local DEPTH = SHOP.FrontZ - SHOP.BackZ
local WIDTH = SHOP.HalfWidth * 2

local FLOOR = Color3.fromRGB(222, 224, 228)
local FLOOR_ALT = Color3.fromRGB(198, 202, 210)
local WALL_COLOUR = Color3.fromRGB(238, 240, 244)
local TRIM = Color3.fromRGB(38, 44, 58)
local ACCENT = Color3.fromRGB(64, 132, 255)
local WOOD = Color3.fromRGB(120, 92, 62)

local shop: Model

local function block(name: string, size: Vector3, position: Vector3, colour: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = position
	part.Anchored = true
	part.Color = colour
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = shop
	return part
end

-- Anything decorative that players shouldn't be able to walk into or shoot rays at.
local function decor(part: Part): Part
	part.CanCollide = false
	part.CanQuery = false
	return part
end

local function centreZ(): number
	return (SHOP.BackZ + SHOP.FrontZ) / 2
end

-- Studio's baseplate sits with its top at y=0, exactly where the shop floor goes, which
-- makes the two faces flicker against each other. Drop it a stud so ours is the only floor.
-- With no baseplate at all (a place built by `rojo build`), lay some pavement instead.
local function settleGround()
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate.Position -= Vector3.new(0, 1, 0)
		return
	end

	local ground = block(
		"Pavement",
		Vector3.new(700, 2, 700),
		Vector3.new(0, SHOP.FloorY - 2, centreZ()),
		Color3.fromRGB(150, 152, 158)
	)
	ground.Material = Enum.Material.Concrete
end

local function buildFloor()
	-- Two big slabs in slightly different shades read as a tiled shop floor without
	-- needing hundreds of individual tiles.
	for index, colour in { FLOOR, FLOOR_ALT } do
		local half = DEPTH / 2
		local slab = block(
			`Floor{index}`,
			Vector3.new(WIDTH, 1, half),
			Vector3.new(0, SHOP.FloorY - 0.5, SHOP.BackZ + half * (index - 0.5)),
			colour
		)
		slab.Material = Enum.Material.Marble
	end

	-- Runner from the door to the podiums, to pull the eye through the room.
	local runner = decor(
		block(
			"Runner",
			Vector3.new(20, 0.08, DEPTH - 10),
			Vector3.new(0, SHOP.FloorY + 0.04, centreZ()),
			Color3.fromRGB(52, 74, 128)
		)
	)
	runner.Material = Enum.Material.Fabric
end

local function buildWalls()
	local midY = SHOP.FloorY + SHOP.WallHeight / 2

	local back = block(
		"WallBack",
		Vector3.new(WIDTH + WALL * 2, SHOP.WallHeight, WALL),
		Vector3.new(0, midY, SHOP.BackZ - WALL / 2),
		WALL_COLOUR
	)
	back.Material = Enum.Material.Concrete

	for _, sx in { -1, 1 } do
		local side = block(
			"WallSide",
			Vector3.new(WALL, SHOP.WallHeight, DEPTH + WALL * 2),
			Vector3.new(sx * (SHOP.HalfWidth + WALL / 2), midY, centreZ()),
			WALL_COLOUR
		)
		side.Material = Enum.Material.Concrete
	end

	local ceiling = block(
		"Ceiling",
		Vector3.new(WIDTH + WALL * 2, WALL, DEPTH + WALL * 2),
		Vector3.new(0, SHOP.FloorY + SHOP.WallHeight + WALL / 2, centreZ()),
		Color3.fromRGB(228, 230, 236)
	)
	ceiling.Material = Enum.Material.Concrete

	-- Skirting round the inside edge, which is most of what stops a room looking like a box.
	for _, sx in { -1, 1 } do
		decor(
			block(
				"Skirting",
				Vector3.new(0.4, 1.2, DEPTH),
				Vector3.new(sx * (SHOP.HalfWidth - 0.2), SHOP.FloorY + 0.6, centreZ()),
				TRIM
			)
		)
	end
	decor(
		block(
			"SkirtingBack",
			Vector3.new(WIDTH, 1.2, 0.4),
			Vector3.new(0, SHOP.FloorY + 0.6, SHOP.BackZ + 0.2),
			TRIM
		)
	)
end

-- Glass frontage with a gap in the middle to walk through.
local function buildShopfront()
	local midY = SHOP.FloorY + SHOP.WallHeight / 2
	local doorHalf = SHOP.DoorWidth / 2
	local paneWidth = SHOP.HalfWidth - doorHalf

	for _, sx in { -1, 1 } do
		local centre = sx * (doorHalf + paneWidth / 2)

		local glass = decor(
			block(
				"Shopfront",
				Vector3.new(paneWidth, SHOP.WallHeight - 3, 0.4),
				Vector3.new(centre, midY + 1.5, SHOP.FrontZ),
				Color3.fromRGB(206, 230, 240)
			)
		)
		glass.Material = Enum.Material.Glass
		glass.Transparency = 0.72
		glass.Reflectance = 0.15

		-- Frame: sill, head and a couple of mullions.
		block(
			"Sill",
			Vector3.new(paneWidth, 3, 1.2),
			Vector3.new(centre, SHOP.FloorY + 1.5, SHOP.FrontZ),
			TRIM
		)
		block(
			"Head",
			Vector3.new(paneWidth, 1.4, 1.2),
			Vector3.new(centre, SHOP.FloorY + SHOP.WallHeight - 0.7, SHOP.FrontZ),
			TRIM
		)
		for m = 1, 2 do
			decor(
				block(
					"Mullion",
					Vector3.new(0.5, SHOP.WallHeight - 4.4, 0.8),
					Vector3.new(sx * (doorHalf + paneWidth * (m / 3)), midY + 1.5, SHOP.FrontZ),
					TRIM
				)
			)
		end
	end

	-- Header over the doorway, with the shop name facing the street.
	local header = block(
		"DoorHeader",
		Vector3.new(SHOP.DoorWidth + 2, 4, 1.2),
		Vector3.new(0, SHOP.FloorY + SHOP.WallHeight - 2, SHOP.FrontZ),
		ACCENT
	)

	-- Both faces: Back reads from the street, Front reads on the way out.
	for _, face in { Enum.NormalId.Back, Enum.NormalId.Front } do
		local surface = Instance.new("SurfaceGui")
		surface.Face = face
		surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		surface.PixelsPerStud = 48
		surface.Parent = header

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Text = Config.GameName
		label.Parent = surface
	end
end

local function buildCeilingLights()
	local rows, columns = 3, 4
	for row = 1, rows do
		for column = 1, columns do
			local x = (column - (columns + 1) / 2) * (WIDTH / columns)
			local z = SHOP.BackZ + (row - 0.5) * (DEPTH / rows)

			local panel = decor(
				block(
					"LightPanel",
					Vector3.new(14, 0.4, 6),
					Vector3.new(x, SHOP.FloorY + SHOP.WallHeight - 0.2, z),
					Color3.fromRGB(255, 252, 238)
				)
			)
			panel.Material = Enum.Material.Neon

			local lamp = Instance.new("PointLight")
			lamp.Brightness = 1.4
			lamp.Range = 42
			lamp.Color = Color3.fromRGB(255, 250, 235)
			-- Shadows off on every decorative light in here. Future lighting makes each
			-- shadow-casting light expensive, and there are two dozen of them — the room
			-- reads the same lit flatly, and the TVs keep their shadows where it matters.
			lamp.Shadows = false
			lamp.Parent = panel
		end
	end
end

-- Big neon sign on the back wall above the podium row.
local function buildSign()
	local panel = decor(
		block(
			"SignPanel",
			Vector3.new(74, 9, 0.6),
			Vector3.new(0, SHOP.FloorY + SHOP.WallHeight - 7, SHOP.BackZ + 0.4),
			Color3.fromRGB(18, 20, 28)
		)
	)

	local surface = Instance.new("SurfaceGui")
	-- The wall is behind the sign, so the readable side is the one facing +Z.
	surface.Face = Enum.NormalId.Back
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 40
	surface.Parent = panel

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(120, 200, 255)
	label.Text = Config.GameName
	label.Parent = surface

	-- Neon tubes above and below, which is what sells it as a sign.
	for _, sy in { -1, 1 } do
		local tube = decor(
			block(
				"SignTube",
				Vector3.new(76, 0.5, 0.5),
				Vector3.new(0, SHOP.FloorY + SHOP.WallHeight - 7 + sy * 5, SHOP.BackZ + 0.6),
				ACCENT
			)
		)
		tube.Material = Enum.Material.Neon

		local glow = Instance.new("PointLight")
		glow.Brightness = 1.2
		glow.Range = 26
		glow.Color = ACCENT
		glow.Shadows = false
		glow.Parent = tube
	end
end

-- Grid of demo screens on the left wall, all showing something different.
local function buildVideoWall()
	local columns, rows = 4, 3
	local screenW, screenH = 9, 5
	local x = -SHOP.HalfWidth + 0.4
	local originZ = -18

	local palette = {
		Color3.fromRGB(96, 200, 240),
		Color3.fromRGB(120, 238, 160),
		Color3.fromRGB(255, 176, 96),
		Color3.fromRGB(240, 128, 190),
		Color3.fromRGB(176, 148, 255),
		Color3.fromRGB(250, 220, 90),
	}

	local backing = decor(
		block(
			"VideoWallBacking",
			Vector3.new(0.5, rows * (screenH + 1.4) + 2, columns * (screenW + 1.4) + 2),
			Vector3.new(x - 0.2, SHOP.FloorY + 13, originZ),
			Color3.fromRGB(22, 24, 32)
		)
	)
	backing.Material = Enum.Material.Metal

	for row = 1, rows do
		for column = 1, columns do
			local z = originZ + (column - (columns + 1) / 2) * (screenW + 1.4)
			local y = SHOP.FloorY + 13 + (row - (rows + 1) / 2) * (screenH + 1.4)
			local colour = palette[((row - 1) * columns + column - 1) % #palette + 1]

			local screen = decor(
				block(
					"DemoScreen",
					Vector3.new(0.3, screenH, screenW),
					Vector3.new(x + 0.3, y, z),
					colour
				)
			)
			screen.Material = Enum.Material.Neon

			local glow = Instance.new("PointLight")
			glow.Brightness = 0.5
			glow.Range = 16
			glow.Color = colour
			glow.Shadows = false
			glow.Parent = screen
		end
	end
end

-- A shelf unit against a side wall, stocked with little tellies.
local function buildShelfUnit(sx: number, z: number)
	local unitWidth, unitHeight, unitDepth = 16, 14, 4
	local x = sx * (SHOP.HalfWidth - unitDepth / 2 - 0.3)

	local backboard = decor(
		block(
			"ShelfBack",
			Vector3.new(0.4, unitHeight, unitWidth),
			Vector3.new(sx * (SHOP.HalfWidth - 0.4), SHOP.FloorY + unitHeight / 2, z),
			Color3.fromRGB(206, 190, 168)
		)
	)
	backboard.Material = Enum.Material.WoodPlanks

	for shelf = 0, 2 do
		local shelfY = SHOP.FloorY + 1.5 + shelf * 4.4
		local plank =
			block("Shelf", Vector3.new(unitDepth, 0.4, unitWidth), Vector3.new(x, shelfY, z), WOOD)
		plank.Material = Enum.Material.WoodPlanks

		-- Two boxy tellies per shelf, screens facing into the room.
		for slot = -1, 1, 2 do
			local tvZ = z + slot * unitWidth * 0.24
			decor(
				block(
					"StockTv",
					Vector3.new(2.6, 2.4, 3.4),
					Vector3.new(x, shelfY + 1.4, tvZ),
					Color3.fromRGB(46, 48, 56)
				)
			)

			local screen = decor(
				block(
					"StockScreen",
					Vector3.new(0.2, 1.7, 2.7),
					Vector3.new(x - sx * 1.35, shelfY + 1.4, tvZ),
					Color3.fromRGB(130, 200, 235)
				)
			)
			screen.Material = Enum.Material.Neon
		end
	end
end

local function buildShelving()
	for _, sx in { -1, 1 } do
		-- Skip the stretch of left wall taken by the video wall.
		local zPositions = if sx < 0 then { 6, 24 } else { -30, -8, 14 }
		for _, z in zPositions do
			buildShelfUnit(sx, z)
		end
	end
end

local function buildCounter()
	local x = SHOP.HalfWidth - 22
	local z = SHOP.FrontZ - 16

	local counter =
		block("Counter", Vector3.new(18, 4, 5), Vector3.new(x, SHOP.FloorY + 2, z), WOOD)
	counter.Material = Enum.Material.WoodPlanks

	local top = block(
		"CounterTop",
		Vector3.new(19, 0.4, 6),
		Vector3.new(x, SHOP.FloorY + 4.2, z),
		Color3.fromRGB(40, 44, 54)
	)
	top.Material = Enum.Material.Slate

	-- Till, and a rack of leaflets.
	decor(
		block(
			"Till",
			Vector3.new(3, 1.6, 2.4),
			Vector3.new(x + 5, SHOP.FloorY + 5.2, z),
			Color3.fromRGB(210, 212, 218)
		)
	)
	local screen = decor(
		block(
			"TillScreen",
			Vector3.new(2.6, 1.8, 0.2),
			Vector3.new(x + 5, SHOP.FloorY + 6.9, z - 0.6),
			Color3.fromRGB(120, 220, 200)
		)
	)
	screen.Material = Enum.Material.Neon

	for index = 1, 3 do
		decor(
			block(
				"Leaflets",
				Vector3.new(2, 0.5, 2.6),
				Vector3.new(x - 5 + index * 0.1, SHOP.FloorY + 4.6 + (index - 1) * 0.5, z),
				Color3.fromRGB(240, 226, 120)
			)
		)
	end
end

-- Put the spawn just inside the door, facing the podiums. Existing spawns are removed so
-- players can't appear outside the shop — a baseplate template ships with one at the origin.
local function setupSpawn()
	for _, instance in Workspace:GetDescendants() do
		if instance:IsA("SpawnLocation") then
			instance:Destroy()
		end
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "ShopSpawn"
	spawn.Size = Vector3.new(14, 0.4, 8)
	spawn.Position = Vector3.new(0, SHOP.FloorY + 0.2, SHOP.FrontZ - 10)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = Color3.fromRGB(52, 74, 128)
	spawn.Material = Enum.Material.Fabric
	spawn.TopSurface = Enum.SurfaceType.Smooth
	-- A SpawnLocation's default LookVector is -Z, which points at the podiums, so players
	-- spawn already looking at the display stands. No rotation needed.
	spawn.Parent = shop
end

function ShopService:Init()
	shop = Instance.new("Model")
	shop.Name = "Shop"
	shop.Parent = Workspace

	settleGround()
	buildFloor()
	buildWalls()
	buildShopfront()
	buildCeilingLights()
	buildSign()
	buildVideoWall()
	buildShelving()
	buildCounter()
	setupSpawn()

	print(`[ShopService] Built the shop ({#shop:GetChildren()} parts).`)
end

return ShopService
