--!strict
-- Single place where every RemoteEvent / RemoteFunction is declared.
-- The server creates them; the client waits for them. Add a name to the lists below
-- and it exists on both sides — no manual instance wiring in Studio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	"CoinsChanged",
	"RoundStateChanged",
}

local FUNCTIONS = {
	"GetPlayerData",
}

local IS_SERVER = RunService:IsServer()

local function getFolder(): Folder
	if IS_SERVER then
		local folder = ReplicatedStorage:FindFirstChild("Remotes")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "Remotes"
			folder.Parent = ReplicatedStorage
		end
		return folder :: Folder
	end
	return ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

local function get(name: string, className: "RemoteEvent" | "RemoteFunction"): Instance
	local folder = getFolder()
	if IS_SERVER then
		local existing = folder:FindFirstChild(name)
		if existing then
			return existing
		end
		local remote = Instance.new(className)
		remote.Name = name
		remote.Parent = folder
		return remote
	end
	return folder:WaitForChild(name)
end

local Remotes = {
	Events = {} :: { [string]: RemoteEvent },
	Functions = {} :: { [string]: RemoteFunction },
}

for _, name in EVENTS do
	Remotes.Events[name] = get(name, "RemoteEvent") :: RemoteEvent
end

for _, name in FUNCTIONS do
	Remotes.Functions[name] = get(name, "RemoteFunction") :: RemoteFunction
end

return Remotes
