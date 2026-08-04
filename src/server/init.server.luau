--!strict
-- Server entry point. Loads every module in src/server/services and calls
-- :Init() then :Start() on each. Add a new file to that folder and it runs.

local servicesFolder = script:WaitForChild("services")

type Service = {
	Name: string,
	Init: ((Service) -> ())?,
	Start: ((Service) -> ())?,
}

local services: { Service } = {}

for _, module in servicesFolder:GetChildren() do
	if module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			result.Name = result.Name or module.Name
			table.insert(services, result)
		elseif not ok then
			warn(`[Server] Failed to load {module.Name}: {result}`)
		end
	end
end

for _, service in services do
	if service.Init then
		local ok, err = pcall(service.Init, service)
		if not ok then
			warn(`[Server] {service.Name}:Init() errored: {err}`)
		end
	end
end

for _, service in services do
	if service.Start then
		task.spawn(function()
			local ok, err = pcall(service.Start, service)
			if not ok then
				warn(`[Server] {service.Name}:Start() errored: {err}`)
			end
		end)
	end
end

print(`[Server] Started {#services} service(s).`)
