--!strict
-- Client entry point. Mirrors the server: loads every module in
-- src/client/controllers and calls :Init() then :Start().

local controllersFolder = script:WaitForChild("controllers")

type Controller = {
	Name: string,
	Init: ((Controller) -> ())?,
	Start: ((Controller) -> ())?,
}

local controllers: { Controller } = {}

for _, module in controllersFolder:GetChildren() do
	if module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			result.Name = result.Name or module.Name
			table.insert(controllers, result)
		elseif not ok then
			warn(`[Client] Failed to load {module.Name}: {result}`)
		end
	end
end

for _, controller in controllers do
	if controller.Init then
		local ok, err = pcall(controller.Init, controller)
		if not ok then
			warn(`[Client] {controller.Name}:Init() errored: {err}`)
		end
	end
end

for _, controller in controllers do
	if controller.Start then
		task.spawn(function()
			local ok, err = pcall(controller.Start, controller)
			if not ok then
				warn(`[Client] {controller.Name}:Start() errored: {err}`)
			end
		end)
	end
end

print(`[Client] Started {#controllers} controller(s).`)
