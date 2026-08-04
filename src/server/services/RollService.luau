--!strict
-- The game loop: a player asks to roll, the server decides what they get.
--
-- Everything that matters happens here, not on the client. The client sends "I'd like to
-- roll" and nothing more — it never sends a number, a score, or a TV. That means a modified
-- client can spam the request but can't choose its own outcome.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local DiceTiers = require(Shared:WaitForChild("DiceTiers"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local TvCatalog = require(Shared:WaitForChild("TvCatalog"))

local PlayerDataService = require(script.Parent.PlayerDataService)

local RollService = {
	Name = "RollService",
}

local rng = Random.new()
local lastRollClock: { [Player]: number } = {}

function RollService:Roll(player: Player)
	local playerData = PlayerDataService:Get(player)
	if not playerData then
		return
	end

	-- Make the upgrade choice blocking, so a 6 can't be banked and cashed in later.
	if playerData.PendingUpgrade then
		return
	end

	local now = os.clock()
	local last = lastRollClock[player]
	if last and now - last < Config.Roll.CooldownSeconds then
		return
	end
	lastRollClock[player] = now

	local tier = DiceTiers.get(playerData.DiceTier)
	local roll = rng:NextInteger(1, tier.Sides)
	local score = tier.ScoreOffset + roll

	-- Rolling a 1 knocks the existing collection down a level. Applied BEFORE the new TV is
	-- awarded, so the telly you just won arrives at full value and only what you already had
	-- degrades — otherwise a 1 would immediately devalue its own prize.
	--
	-- Note the roll still awards its TV. Skipping the award on a 1 would make the five
	-- tier-floor TVs (scores 1, 7, 13, 19, 25) permanently unobtainable.
	local isMinFace = roll == 1
	local downgraded = if isMinFace
		then PlayerDataService:DowngradeCollection(player, Config.Penalty.DowngradeLevels)
		else 0

	PlayerDataService:AwardTv(player, score)

	-- Rolling the highest face offers the next dice up. Compared against Sides rather
	-- than a hard-coded 6 so a tier with different dice still works.
	local isMaxFace = roll == tier.Sides
	local canUpgrade = isMaxFace and not DiceTiers.isMax(playerData.DiceTier)

	Remotes.Events.RollResult:FireClient(player, {
		Roll = roll,
		Sides = tier.Sides,
		Score = score,
		Tv = TvCatalog.get(score),
		DiceName = tier.Name,
		DiceColor = tier.Color,
		IsMaxFace = isMaxFace,
		IsMinFace = isMinFace,
		Downgraded = downgraded,
	})

	if canUpgrade then
		playerData.PendingUpgrade = true
		Remotes.Events.DiceUpgradeOffered:FireClient(player, DiceTiers.get(playerData.DiceTier + 1))
	end
end

function RollService:ResolveUpgrade(player: Player, accept: boolean)
	local playerData = PlayerDataService:Get(player)
	if not playerData or not playerData.PendingUpgrade then
		return
	end

	playerData.PendingUpgrade = false

	if accept and not DiceTiers.isMax(playerData.DiceTier) then
		PlayerDataService:SetDiceTier(player, playerData.DiceTier + 1)
	else
		PlayerDataService:Sync(player)
	end
end

function RollService:Init()
	Remotes.Events.RequestRoll.OnServerEvent:Connect(function(player)
		self:Roll(player)
	end)

	Remotes.Events.ChooseDiceUpgrade.OnServerEvent:Connect(function(player, accept)
		-- Never trust the argument's type, only its truthiness after a type check.
		if type(accept) ~= "boolean" then
			return
		end
		self:ResolveUpgrade(player, accept)
	end)
end

function RollService:Start()
	Players.PlayerRemoving:Connect(function(player)
		lastRollClock[player] = nil
	end)
end

return RollService
