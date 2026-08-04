--!strict
-- Which way is up, for a real six-sided die.
--
-- A die's opposite faces always sum to 7. Pick where face 1 lives and the other five
-- follow. FACE_NORMAL records the direction each numbered face points in the part's own
-- local space; LAND_ORIENTATION is the rotation that turns that face towards the sky.
--
-- Kept in shared/ so the pips a player sees and the maths that lands the die can never
-- drift apart — they're generated from the same table.

local DiceGeometry = {}

-- value -> the local axis that face's pips sit on. 1+6, 2+5 and 3+4 each sum to 7.
DiceGeometry.FaceNormal = {
	[1] = Vector3.new(0, 1, 0),
	[2] = Vector3.new(0, 0, -1),
	[3] = Vector3.new(1, 0, 0),
	[4] = Vector3.new(-1, 0, 0),
	[5] = Vector3.new(0, 0, 1),
	[6] = Vector3.new(0, -1, 0),
}

-- value -> the part face to draw those pips on. Roblox calls -Z "Front" and +Z "Back".
DiceGeometry.FaceId = {
	[1] = Enum.NormalId.Top,
	[2] = Enum.NormalId.Front,
	[3] = Enum.NormalId.Right,
	[4] = Enum.NormalId.Left,
	[5] = Enum.NormalId.Back,
	[6] = Enum.NormalId.Bottom,
}

-- value -> rotation that leaves that face pointing at +Y.
--
-- Rotating by pi/2 about X sends local -Z to +Y, which lands face 2. Rotating by pi/2
-- about Z sends local +X to +Y, which lands face 3. The rest are the same idea negated.
DiceGeometry.LandOrientation = {
	[1] = CFrame.Angles(0, 0, 0),
	[2] = CFrame.Angles(math.pi / 2, 0, 0),
	[3] = CFrame.Angles(0, 0, math.pi / 2),
	[4] = CFrame.Angles(0, 0, -math.pi / 2),
	[5] = CFrame.Angles(-math.pi / 2, 0, 0),
	[6] = CFrame.Angles(math.pi, 0, 0),
}

-- Pip positions as fractions of a face, on the usual 3x3 grid.
local TL, TR = { 0.25, 0.25 }, { 0.75, 0.25 }
local ML, MC, MR = { 0.25, 0.5 }, { 0.5, 0.5 }, { 0.75, 0.5 }
local BL, BR = { 0.25, 0.75 }, { 0.75, 0.75 }

DiceGeometry.Pips = {
	[1] = { MC },
	[2] = { TL, BR },
	[3] = { TL, MC, BR },
	[4] = { TL, TR, BL, BR },
	[5] = { TL, TR, MC, BL, BR },
	[6] = { TL, TR, ML, MR, BL, BR },
}

return DiceGeometry
