--!strict
-- Builds a TV model that looks like its name, out of parts, at runtime.
--
-- One builder per TvCatalog style. Every model is assembled around a local origin sitting
-- at the *bottom centre* of the telly, with an invisible Root as the PrimaryPart, so a
-- caller can drop it anywhere with model:PivotTo(CFrame.new(surfacePosition)).
--
-- Screen size comes from the score, so a 30 is physically enormous next to a 1.

local TvCatalog = require(script.Parent.TvCatalog)

local TvBuilder = {}

type Build = {
	Model: Model,
	Tv: TvCatalog.Tv,
	ScreenWidth: number,
	ScreenHeight: number,
	-- Seeded from the score, so a given TV always looks the same for every player and on
	-- every rebuild, while neighbouring scores differ. Never use math.random here: the same
	-- telly would change shape each time a podium rebuilt it.
	Rng: Random,
}

local function part(build: Build, name: string, size: Vector3, position: Vector3): Part
	local instance = Instance.new("Part")
	instance.Name = name
	instance.Size = size
	instance.Position = position
	instance.Anchored = true
	instance.CanCollide = false
	-- Queryable on purpose, even though nothing collides with it: DiceController raycasts
	-- forward to find what the die is about to hit, and with CanQuery off the die sailed
	-- straight through the tellies.
	instance.CanQuery = true
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth
	instance.Color = build.Tv.Body
	instance.Material = Enum.Material.SmoothPlastic
	instance.Parent = build.Model
	return instance
end

-- A Roblox cylinder's length runs along its local X axis, with the flat circular caps
-- facing +/-X. Naming the three orientations we actually use, because passing raw Euler
-- angles is exactly how every cylinder in this file ended up pointing the wrong way once:
-- dials lay flat facing the ceiling and the rollable TV's drum stood up like a pillar.
local CAPS_FACING_Z = CFrame.Angles(0, math.pi / 2, 0) -- a dial you look at head-on
local CAPS_FACING_Y = CFrame.Angles(0, 0, math.pi / 2) -- a puck lying flat on the floor
local LENGTH_ACROSS_X = CFrame.identity -- a drum lying across the width

local function cylinder(build: Build, name: string, size: Vector3, cf: CFrame): Part
	local instance = part(build, name, size, Vector3.zero)
	instance.Shape = Enum.PartType.Cylinder
	instance.CFrame = cf
	return instance
end

-- The glowing bit. Every style calls this so "screen" always means the same thing.
local function screen(
	build: Build,
	width: number,
	height: number,
	centre: Vector3,
	depth: number?
): Part
	local glass = part(build, "Screen", Vector3.new(width, height, depth or 0.16), centre)
	glass.Color = build.Tv.Screen
	glass.Material = Enum.Material.Neon
	return glass
end

local function light(build: Build, parent: Part, brightness: number, range: number)
	local glow = Instance.new("PointLight")
	glow.Color = build.Tv.Screen
	glow.Brightness = brightness
	glow.Range = range
	glow.Parent = parent
end

-- A neck-and-base stand, centred under the panel.
local function pedestal(build: Build, panelBottom: number, width: number, slim: boolean)
	local neckHeight = panelBottom
	if neckHeight <= 0.2 then
		return
	end
	local neckWidth = if slim then 0.5 else 1.1
	part(
		build,
		"Neck",
		Vector3.new(neckWidth, neckHeight, if slim then 0.5 else 1.0),
		Vector3.new(0, neckHeight / 2, 0)
	)
	local baseWidth = if slim then width * 0.5 else math.max(2.6, width * 0.34)
	part(
		build,
		"Base",
		Vector3.new(baseWidth, 0.28, if slim then 1.6 else 2.2),
		Vector3.new(0, 0.14, 0)
	)
end

-- Little details hung on every telly regardless of style: a shop price tag, a standby LED,
-- and for anything on a stand, a cable trailing to the floor. Cheap, and it's most of what
-- stops six flatscreens in a row looking like the same prop six times.
local function trimmings(build: Build, panelCentreY: number, panelWidth: number, panelFront: number)
	local rng = build.Rng

	local led = part(
		build,
		"StandbyLed",
		Vector3.new(0.16, 0.16, 0.1),
		Vector3.new(
			panelWidth * (if rng:NextNumber() < 0.5 then -0.42 else 0.42),
			panelCentreY - build.ScreenHeight / 2 - 0.24,
			panelFront + 0.06
		)
	)
	led.Color = if rng:NextNumber() < 0.35
		then Color3.fromRGB(255, 96, 72)
		else Color3.fromRGB(120, 255, 150)
	led.Material = Enum.Material.Neon

	-- Price tag on a short wire, off to one side.
	local side = if rng:NextNumber() < 0.5 then -1 else 1
	local tagX = side * (panelWidth / 2 + 0.7)
	local tagY = panelCentreY + build.ScreenHeight * rng:NextNumber() * 0.2

	local wire = part(
		build,
		"TagWire",
		Vector3.new(0.06, 0.9, 0.06),
		Vector3.new(tagX, tagY + 0.75, panelFront)
	)
	wire.Color = Color3.fromRGB(120, 122, 128)

	local tag =
		part(build, "PriceTag", Vector3.new(2.2, 1.1, 0.08), Vector3.new(tagX, tagY, panelFront))
	tag.Color = Color3.fromRGB(250, 238, 140)

	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Back
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 64
	surface.Parent = tag

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(28, 26, 20)
	label.Text = TvCatalog.formatValue(build.Tv.Value)
	label.Parent = surface
end

local builders: { [string]: (Build) -> () } = {}

-- Little box telly with an aerial and a carry handle. Deep, small screen, chunky bezel.
function builders.portable(build: Build)
	local w = build.ScreenWidth * 0.7
	local h = build.ScreenHeight * 0.7
	local bodyW, bodyH, bodyD = w + 1.6, h + 1.4, math.max(2.6, w * 0.8)
	local centreY = 0.6 + bodyH / 2

	part(build, "Body", Vector3.new(bodyW, bodyH, bodyD), Vector3.new(0, centreY, 0))
	screen(build, w, h, Vector3.new(0, centreY + 0.15, bodyD / 2))

	-- Handle across the top.
	part(
		build,
		"Handle",
		Vector3.new(bodyW * 0.4, 0.22, 0.3),
		Vector3.new(0, centreY + bodyH / 2 + 0.3, 0)
	)

	-- Aerial, leaning back.
	local aerial = part(build, "Aerial", Vector3.new(0.12, bodyH * 1.5, 0.12), Vector3.zero)
	aerial.CFrame = CFrame.new(bodyW * 0.32, centreY + bodyH * 0.9, -bodyD * 0.3)
		* CFrame.Angles(math.rad(-18), 0, math.rad(12))
	aerial.Color = Color3.fromRGB(180, 182, 188)
	aerial.Material = Enum.Material.Metal

	-- Two tuning dials on the right of the screen.
	for index = 1, 2 do
		local dial = cylinder(
			build,
			`Dial{index}`,
			Vector3.new(0.22, 0.5, 0.5),
			CFrame.new(bodyW / 2 - 0.5, centreY + 0.6 - (index - 1) * 0.9, bodyD / 2)
				* CAPS_FACING_Z
		)
		dial.Color = Color3.fromRGB(40, 40, 44)
	end

	part(build, "FootLeft", Vector3.new(0.5, 0.6, 0.5), Vector3.new(-bodyW * 0.32, 0.3, 0))
	part(build, "FootRight", Vector3.new(0.5, 0.6, 0.5), Vector3.new(bodyW * 0.32, 0.3, 0))
end

-- Classic deep cathode-ray box: fat backing tube, thick bezel, dials down the side.
function builders.crt(build: Build)
	local w, h = build.ScreenWidth * 0.85, build.ScreenHeight * 0.85
	local bodyW, bodyH = w + 1.8, h + 1.6
	local bodyD = math.max(3.2, w * 0.85)
	local centreY = 0.5 + bodyH / 2

	part(build, "Body", Vector3.new(bodyW, bodyH, bodyD), Vector3.new(0, centreY, 0))
	-- Tapered tube at the back is what makes a CRT read as a CRT.
	part(
		build,
		"Tube",
		Vector3.new(bodyW * 0.62, bodyH * 0.62, bodyD * 0.5),
		Vector3.new(0, centreY, -bodyD * 0.6)
	)
	local glass = screen(build, w, h, Vector3.new(0, centreY + 0.2, bodyD / 2), 0.22)
	light(build, glass, 0.6, 10)

	for index = 1, 3 do
		local dial = cylinder(
			build,
			`Dial{index}`,
			Vector3.new(0.2, 0.42, 0.42),
			CFrame.new(bodyW / 2 - 0.55, centreY - bodyH * 0.28 + (index - 1) * 0.7, bodyD / 2)
				* CAPS_FACING_Z
		)
		dial.Color = Color3.fromRGB(36, 36, 40)
	end

	part(build, "FootLeft", Vector3.new(0.7, 0.5, bodyD * 0.6), Vector3.new(-bodyW * 0.34, 0.25, 0))
	part(build, "FootRight", Vector3.new(0.7, 0.5, bodyD * 0.6), Vector3.new(bodyW * 0.34, 0.25, 0))
end

-- Wooden cabinet on splayed legs, screen sunk into the front panel.
function builders.console(build: Build)
	local w, h = build.ScreenWidth * 0.8, build.ScreenHeight * 0.8
	local cabinetW, cabinetH, cabinetD = w + 4.0, h + 2.4, math.max(3.4, w * 0.9)
	local legHeight = 1.6
	local centreY = legHeight + cabinetH / 2

	local cabinet = part(
		build,
		"Cabinet",
		Vector3.new(cabinetW, cabinetH, cabinetD),
		Vector3.new(0, centreY, 0)
	)
	cabinet.Material = Enum.Material.Wood

	local glass =
		screen(build, w, h, Vector3.new(-cabinetW * 0.14, centreY + 0.3, cabinetD / 2), 0.2)
	light(build, glass, 0.5, 9)

	-- Speaker grille and dials in the panel beside the screen.
	local grille = part(
		build,
		"Grille",
		Vector3.new(cabinetW * 0.18, cabinetH * 0.5, 0.14),
		Vector3.new(cabinetW * 0.3, centreY + 0.2, cabinetD / 2)
	)
	grille.Color = Color3.fromRGB(72, 60, 44)
	grille.Material = Enum.Material.Fabric

	for index = 1, 2 do
		local dial = cylinder(
			build,
			`Dial{index}`,
			Vector3.new(0.2, 0.4, 0.4),
			CFrame.new(cabinetW * 0.3, centreY - cabinetH * 0.34, cabinetD / 2)
				+ Vector3.new((index - 1.5) * 0.9, 0, 0)
		)
		dial.CFrame = dial.CFrame * CAPS_FACING_Z
		dial.Color = Color3.fromRGB(214, 190, 140)
		dial.Material = Enum.Material.Metal
	end

	-- Four splayed legs.
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local leg = part(build, "Leg", Vector3.new(0.3, legHeight, 0.3), Vector3.zero)
			leg.CFrame = CFrame.new(sx * cabinetW * 0.38, legHeight / 2, sz * cabinetD * 0.3)
				* CFrame.Angles(math.rad(sz * -6), 0, math.rad(sx * -6))
			leg.Color = Color3.fromRGB(74, 46, 24)
			leg.Material = Enum.Material.Wood
		end
	end
end

-- First-generation flat panel: still thick, heavy bezel, chunky base.
function builders.plasma(build: Build)
	local w, h = build.ScreenWidth, build.ScreenHeight
	local panelBottom = 1.5
	local centreY = panelBottom + h / 2 + 0.7

	part(build, "Panel", Vector3.new(w + 1.5, h + 1.5, 0.9), Vector3.new(0, centreY, 0))
	local glass = screen(build, w, h, Vector3.new(0, centreY, 0.5))
	light(build, glass, 0.9, 14)
	pedestal(build, panelBottom, w, false)
end

-- Ordinary modern flatscreen: moderate bezel, neck-and-base stand.
function builders.lcd(build: Build)
	local w, h = build.ScreenWidth, build.ScreenHeight
	local panelBottom = 1.8
	local centreY = panelBottom + h / 2 + 0.5

	part(build, "Panel", Vector3.new(w + 0.7, h + 0.7, 0.42), Vector3.new(0, centreY, 0))
	local glass = screen(build, w, h, Vector3.new(0, centreY, 0.26))
	light(build, glass, 1.1, 16)
	pedestal(build, panelBottom, w, false)
end

-- Premium panel: almost no bezel, thin as a phone, blade stand.
function builders.oled(build: Build)
	local w, h = build.ScreenWidth, build.ScreenHeight
	local panelBottom = 1.4
	local centreY = panelBottom + h / 2 + 0.3

	part(build, "Panel", Vector3.new(w + 0.2, h + 0.2, 0.16), Vector3.new(0, centreY, 0))
	local glass = screen(build, w, h, Vector3.new(0, centreY, 0.1))
	light(build, glass, 1.6, 22)

	-- Single wide blade foot rather than a neck.
	local blade = part(
		build,
		"Blade",
		Vector3.new(w * 0.55, panelBottom, 0.2),
		Vector3.new(0, panelBottom / 2, 0)
	)
	blade.Color = Color3.fromRGB(150, 154, 162)
	blade.Material = Enum.Material.Metal
	part(build, "Base", Vector3.new(w * 0.62, 0.22, 1.8), Vector3.new(0, 0.11, 0))
end

-- Same panel as an lcd but standing on two splayed feet at the ends rather than a centre
-- neck, which is the main thing that tells two flatscreens apart at a glance.
function builders.lcdFeet(build: Build)
	local w, h = build.ScreenWidth, build.ScreenHeight
	local panelBottom = 1.6
	local centreY = panelBottom + h / 2 + 0.4

	part(build, "Panel", Vector3.new(w + 0.5, h + 0.5, 0.34), Vector3.new(0, centreY, 0))
	local glass = screen(build, w, h, Vector3.new(0, centreY, 0.22))
	light(build, glass, 1.2, 17)

	for _, sx in { -1, 1 } do
		local foot = part(build, "Foot", Vector3.new(0.4, panelBottom, 2.4), Vector3.zero)
		foot.CFrame = CFrame.new(sx * w * 0.36, panelBottom / 2, 0)
			* CFrame.Angles(0, 0, math.rad(sx * -9))
		foot.Color = Color3.fromRGB(140, 144, 152)
		foot.Material = Enum.Material.Metal
	end
end

-- Flatscreen with a soundbar sitting under it.
function builders.soundbar(build: Build)
	local w, h = build.ScreenWidth, build.ScreenHeight
	local barHeight = 1.1
	local panelBottom = barHeight + 1.4
	local centreY = panelBottom + h / 2 + 0.3

	part(build, "Panel", Vector3.new(w + 0.25, h + 0.25, 0.2), Vector3.new(0, centreY, 0))
	local glass = screen(build, w, h, Vector3.new(0, centreY, 0.13))
	light(build, glass, 1.5, 20)

	local blade = part(
		build,
		"Blade",
		Vector3.new(w * 0.4, panelBottom, 0.22),
		Vector3.new(0, panelBottom / 2, 0)
	)
	blade.Color = Color3.fromRGB(150, 154, 162)
	blade.Material = Enum.Material.Metal

	local bar = part(
		build,
		"Soundbar",
		Vector3.new(w * 0.78, barHeight, 1.6),
		Vector3.new(0, barHeight / 2, 0.6)
	)
	bar.Color = Color3.fromRGB(34, 36, 42)
	bar.Material = Enum.Material.Fabric

	-- Grille slots along the bar.
	for index = 1, 5 do
		local slot = part(
			build,
			"BarSlot",
			Vector3.new(w * 0.1, 0.4, 0.08),
			Vector3.new((index - 3) * w * 0.14, barHeight / 2, 0.6 + 0.82)
		)
		slot.Color = Color3.fromRGB(22, 24, 28)
	end
end

-- Curved screen, faked with three angled segments. Reads as a curve from the front and
-- costs three parts instead of a mesh.
function builders.curved(build: Build)
	local w, h = build.ScreenWidth, build.ScreenHeight
	local panelBottom = 1.8
	local centreY = panelBottom + h / 2 + 0.4
	local segmentW = w / 3

	for index = -1, 1 do
		local angle = math.rad(index * -11)
		local x = index * segmentW
		-- Push the outer segments back so the middle sits proudest.
		local z = -math.abs(index) * 0.5

		local panel =
			part(build, "PanelSegment", Vector3.new(segmentW + 0.3, h + 0.4, 0.3), Vector3.zero)
		panel.CFrame = CFrame.new(x, centreY, z) * CFrame.Angles(0, angle, 0)

		local glass = part(build, "Screen", Vector3.new(segmentW, h, 0.16), Vector3.zero)
		glass.CFrame = CFrame.new(x, centreY, z)
			* CFrame.Angles(0, angle, 0)
			* CFrame.new(0, 0, 0.2)
		glass.Color = build.Tv.Screen
		glass.Material = Enum.Material.Neon
		if index == 0 then
			light(build, glass, 1.4, 19)
		end
	end

	pedestal(build, panelBottom, w, true)
end

-- No stand: bracketed off a wall plate behind it, floating flush like a showroom mount.
function builders.wallmount(build: Build)
	local w, h = build.ScreenWidth, build.ScreenHeight
	local centreY = 3.4 + h / 2

	part(build, "Panel", Vector3.new(w + 0.2, h + 0.2, 0.16), Vector3.new(0, centreY, 0))
	local glass = screen(build, w, h, Vector3.new(0, centreY, 0.1))
	light(build, glass, 1.8, 24)

	-- Plate and arm behind, plus a post to the floor so it isn't floating in mid-air.
	local plate =
		part(build, "WallPlate", Vector3.new(w * 0.34, h * 0.5, 0.4), Vector3.new(0, centreY, -1.1))
	plate.Color = Color3.fromRGB(48, 50, 58)
	plate.Material = Enum.Material.Metal

	local arm = part(build, "Arm", Vector3.new(0.5, 0.5, 1.2), Vector3.new(0, centreY, -0.6))
	arm.Color = Color3.fromRGB(70, 74, 84)
	arm.Material = Enum.Material.Metal

	local post =
		part(build, "Post", Vector3.new(1.2, centreY, 0.8), Vector3.new(0, centreY / 2, -1.4))
	post.Color = Color3.fromRGB(58, 60, 70)
	post.Material = Enum.Material.Metal
end

-- A projector box throwing a beam at a floating screen.
function builders.projector(build: Build)
	local w, h = build.ScreenWidth * 1.15, build.ScreenHeight * 1.15
	local screenBottom = 2.0
	local centreY = screenBottom + h / 2

	-- The projected image: bright, frameless, floating.
	local image = screen(build, w, h, Vector3.new(0, centreY, 0), 0.1)
	image.Transparency = 0.15
	light(build, image, 2.0, 26)

	-- Thin surround so it reads as a screen rather than a floating rectangle.
	local frame =
		part(build, "Frame", Vector3.new(w + 0.3, h + 0.3, 0.06), Vector3.new(0, centreY, -0.06))
	frame.Color = Color3.fromRGB(20, 20, 24)

	-- The projector itself, sat out in front. Fixed distance rather than scaled off the
	-- screen width, so a big screen doesn't push the box off the front of the podium.
	local boxZ = 4.0
	part(build, "Projector", Vector3.new(2.6, 1.1, 3.2), Vector3.new(0, 1.2, boxZ))
	local lens = cylinder(
		build,
		"Lens",
		Vector3.new(0.5, 0.9, 0.9),
		CFrame.new(0, 1.2, boxZ - 1.7) * CAPS_FACING_Z
	)
	lens.Color = build.Tv.Screen
	lens.Material = Enum.Material.Neon

	-- The beam, widening towards the screen.
	local beam = part(
		build,
		"Beam",
		Vector3.new(w * 0.5, h * 0.4, boxZ - 1.0),
		Vector3.new(0, centreY * 0.75, boxZ / 2)
	)
	beam.Color = build.Tv.Screen
	beam.Material = Enum.Material.Neon
	beam.Transparency = 0.88
end

-- Panel rising out of a horizontal drum, half-unrolled.
function builders.rollable(build: Build)
	local w, h = build.ScreenWidth, build.ScreenHeight
	local drumHeight = 1.5
	local centreY = drumHeight + h / 2

	local drum = cylinder(
		build,
		"Drum",
		Vector3.new(w + 0.6, drumHeight, drumHeight),
		CFrame.new(0, drumHeight / 2, 0) * LENGTH_ACROSS_X
	)
	drum.Material = Enum.Material.Brick

	part(build, "Panel", Vector3.new(w + 0.15, h, 0.1), Vector3.new(0, centreY, 0))
	local glass = screen(build, w, h - 0.2, Vector3.new(0, centreY, 0.07))
	light(build, glass, 1.5, 20)
end

-- Glass you can see through, lit from a frame of neon edges.
function builders.transparent(build: Build)
	local w, h = build.ScreenWidth, build.ScreenHeight
	local panelBottom = 1.8
	local centreY = panelBottom + h / 2

	local glass = screen(build, w, h, Vector3.new(0, centreY, 0), 0.12)
	glass.Transparency = 0.55
	glass.Material = Enum.Material.Glass
	light(build, glass, 1.4, 20)

	-- Neon edge strips top and bottom do the "it's powered" work.
	for _, sy in { -1, 1 } do
		local edge = part(
			build,
			"Edge",
			Vector3.new(w + 0.4, 0.16, 0.3),
			Vector3.new(0, centreY + sy * h / 2, 0)
		)
		edge.Color = build.Tv.Screen
		edge.Material = Enum.Material.Neon
	end

	local post =
		part(build, "Post", Vector3.new(0.3, panelBottom, 0.3), Vector3.new(0, panelBottom / 2, 0))
	post.Material = Enum.Material.Metal
	part(build, "Base", Vector3.new(w * 0.5, 0.2, 1.6), Vector3.new(0, 0.1, 0))
end

-- No stand at all: a floating pane above an emitter puck.
function builders.holo(build: Build)
	local w, h = build.ScreenWidth * 1.1, build.ScreenHeight * 1.1
	local floatHeight = 2.6
	local centreY = floatHeight + h / 2

	local glass = screen(build, w, h, Vector3.new(0, centreY, 0), 0.1)
	glass.Transparency = 0.35
	light(build, glass, 2.4, 30)

	-- Frame of neon rails around the pane.
	for _, sy in { -1, 1 } do
		local rail = part(
			build,
			"Rail",
			Vector3.new(w + 0.5, 0.14, 0.28),
			Vector3.new(0, centreY + sy * h / 2, 0)
		)
		rail.Color = build.Tv.Screen
		rail.Material = Enum.Material.Neon
	end
	for _, sx in { -1, 1 } do
		local rail = part(
			build,
			"Rail",
			Vector3.new(0.14, h + 0.5, 0.28),
			Vector3.new(sx * w / 2, centreY, 0)
		)
		rail.Color = build.Tv.Screen
		rail.Material = Enum.Material.Neon
	end

	-- Emitter, with a cone of light up to the pane.
	local puck = cylinder(
		build,
		"Emitter",
		Vector3.new(0.5, w * 0.42, w * 0.42),
		CFrame.new(0, 0.25, 0) * CAPS_FACING_Y
	)
	puck.Material = Enum.Material.Metal

	local ring = cylinder(
		build,
		"EmitterRing",
		Vector3.new(0.16, w * 0.3, w * 0.3),
		CFrame.new(0, 0.55, 0) * CAPS_FACING_Y
	)
	ring.Color = build.Tv.Screen
	ring.Material = Enum.Material.Neon

	local beam = part(
		build,
		"Beam",
		Vector3.new(w * 0.28, floatHeight, w * 0.28),
		Vector3.new(0, floatHeight / 2, 0)
	)
	beam.Color = build.Tv.Screen
	beam.Material = Enum.Material.Neon
	beam.Transparency = 0.86
end

-- Builds the TV for a score. Origin is the bottom centre; PrimaryPart is an invisible Root.
function TvBuilder.build(score: number): Model
	local tv = TvCatalog.get(score)
	local size = TvCatalog.screenSize(score)

	local model = Instance.new("Model")
	model.Name = tv.Name

	local build: Build = {
		Model = model,
		Tv = tv,
		ScreenWidth = size.X,
		ScreenHeight = size.Y,
		-- Fixed multiplier so consecutive scores get well-separated seeds.
		Rng = Random.new(score * 7919),
	}

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.CFrame = CFrame.new(0, 0, 0)
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.Transparency = 1
	root.Parent = model
	model.PrimaryPart = root

	local builder = builders[tv.Style]
	if not builder then
		-- Shouldn't happen: tests/gamelogic.luau asserts every style has a builder.
		warn(`[TvBuilder] No builder for style "{tv.Style}" (score {score}), using lcd`)
		builder = builders.lcd
	end
	builder(build)

	-- Hang the shop dressing on whatever the builder produced. Positioned off the screen it
	-- found, so it works for every style without each one having to place tags itself.
	local glass = model:FindFirstChild("Screen")
	if glass and glass:IsA("BasePart") then
		trimmings(build, glass.Position.Y, math.max(glass.Size.X, 2), glass.Position.Z)
	end

	return model
end

-- Exposed so the test can check it covers every style in TvCatalog.Styles.
function TvBuilder.styles(): { [string]: boolean }
	local names = {}
	for name in builders do
		names[name] = true
	end
	return names
end

return TvBuilder
