--!strict
-- Paid dice upgrades, via a Roblox Developer Product.
--
-- SETUP: the price is not in this code. Create a Developer Product on the game's page,
-- price it at 25 Robux, and paste its ID into Config.Monetisation.DiceUpgradeProductId.
-- Real purchases also don't work on an unpublished place, so for local testing set
-- Config.Monetisation.GrantWithoutPaying = true (and put it back before shipping).
--
-- The delicate part is ProcessReceipt. Roblox calls it repeatedly until it returns
-- PurchaseGranted, so it has to be idempotent, and it must never claim success for
-- something it failed to hand over — that would take the player's Robux and give nothing.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local DiceTiers = require(Shared:WaitForChild("DiceTiers"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlayerDataService = require(script.Parent.PlayerDataService)

local MonetisationService = {
	Name = "MonetisationService",
}

-- PurchaseIds already honoured. In memory only, so a server restart mid-purchase could
-- grant twice; a DataStore keyed on PurchaseId is the durable fix, and is worth adding at
-- the same time as saving player data.
local honoured: { [string]: boolean } = {}

local function notify(player: Player, message: string)
	Remotes.Events.Notice:FireClient(player, message)
end

-- Hands over one dice tier. Returns false if it could not, so the caller knows not to
-- consume the receipt.
local function grantUpgrade(player: Player): boolean
	local playerData = PlayerDataService:Get(player)
	if not playerData then
		return false
	end

	if DiceTiers.isMax(playerData.DiceTier) then
		-- Already at the top. Nothing to give, but the money is spent, so treat it as
		-- settled rather than retrying this receipt forever.
		notify(player, "You already have the best dice — nothing to upgrade.")
		return true
	end

	PlayerDataService:SetDiceTier(player, playerData.DiceTier + 1)
	-- An unresolved free upgrade offer would otherwise still be sitting there.
	playerData.PendingUpgrade = false

	local tier = DiceTiers.get(playerData.DiceTier)
	notify(player, `Upgraded to the {tier.Name}!`)
	return true
end

function MonetisationService:Prompt(player: Player)
	local playerData = PlayerDataService:Get(player)
	if not playerData then
		return
	end

	if DiceTiers.isMax(playerData.DiceTier) then
		notify(player, "You already have the best dice.")
		return
	end

	local productId = Config.Monetisation.DiceUpgradeProductId

	if productId <= 0 then
		if Config.Monetisation.GrantWithoutPaying then
			warn("[MonetisationService] GrantWithoutPaying is on — granting a free upgrade.")
			grantUpgrade(player)
		else
			notify(player, "Paid upgrades aren't set up yet.")
			warn(
				"[MonetisationService] No product configured. Create a Developer Product and "
					.. "set Config.Monetisation.DiceUpgradeProductId."
			)
		end
		return
	end

	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, productId)
	end)
	if not ok then
		notify(player, "Couldn't open the purchase window.")
		warn(`[MonetisationService] PromptProductPurchase failed: {err}`)
	end
end

function MonetisationService:Init()
	Remotes.Events.RequestPaidUpgrade.OnServerEvent:Connect(function(player)
		self:Prompt(player)
	end)

	MarketplaceService.ProcessReceipt = function(receipt)
		local productId = Config.Monetisation.DiceUpgradeProductId

		-- Not ours. Returning NotProcessedYet leaves it for whatever does own it instead of
		-- silently swallowing someone else's purchase.
		if productId <= 0 or receipt.ProductId ~= productId then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local key = tostring(receipt.PurchaseId)
		if honoured[key] then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		local player = Players:GetPlayerByUserId(receipt.PlayerId)
		if not player then
			-- They left before it landed. Don't consume it — Roblox retries when they return.
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local granted = false
		local ok, err = pcall(function()
			granted = grantUpgrade(player)
		end)
		if not ok then
			warn(`[MonetisationService] Granting errored, leaving the receipt open: {err}`)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		if not granted then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		honoured[key] = true
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
end

return MonetisationService
