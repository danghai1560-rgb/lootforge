-- Đăng Răng To HUB v6.1 — GitHub RAW, bundled engine + UI.
-- Startup diagnostics stay visible if the UI fails to construct.
local BUILD="DRT-6.1-UI"
print("["..BUILD.."] Raw script received; starting")
local bootLog={build=BUILD,status="starting"}
_G.__DRT_BOOT=bootLog
local bootPlayers=game:GetService("Players")
local bootStart=os.clock()
while not bootPlayers.LocalPlayer and os.clock()-bootStart<15 do task.wait(.1) end
local bootPlayer=bootPlayers.LocalPlayer
if not bootPlayer then bootLog.status="error"; bootLog.error="LocalPlayer unavailable"; warn(bootLog.error); return end
local UIHost
if type(gethui)=="function" then
    local ok,host=pcall(gethui)
    if ok and typeof(host)=="Instance" then UIHost=host end
end
if not UIHost then UIHost=bootPlayer:WaitForChild("PlayerGui",10) end
if not UIHost then bootLog.status="error"; bootLog.error="PlayerGui unavailable"; warn(bootLog.error); return end
local previousNotice=UIHost:FindFirstChild("DangRangToStartup")
if previousNotice then previousNotice:Destroy() end
local bootGui=Instance.new("ScreenGui")
bootGui.Name="DangRangToStartup"; bootGui.ResetOnSpawn=false; bootGui.IgnoreGuiInset=true; bootGui.DisplayOrder=10001
local bootText=Instance.new("TextLabel")
bootText.Size=UDim2.new(.8,0,0,90); bootText.Position=UDim2.new(.1,0,0,25)
bootText.BackgroundColor3=Color3.fromRGB(29,24,42); bootText.TextColor3=Color3.fromRGB(231,220,255)
bootText.Font=Enum.Font.Gotham; bootText.TextSize=14; bootText.TextWrapped=true
bootText.Text="Đăng Răng To HUB · "..BUILD.."\nĐang dựng menu…"
bootText.Parent=bootGui; bootGui.Parent=UIHost
local function StartHub()
-- Đăng Răng To HUB v6: one-file GitHub raw entry point; engine and UI included.
if game.PlaceId ~= 118805555015549 then error("Sai game +1 Loot To Forge: "..tostring(game.PlaceId),0) end
local function CreateBundledEngine()
-- Đăng Răng To HUB engine v6. Static review only; game integration requires live testing.
if game.PlaceId ~= 118805555015549 then error("Wrong game") end
if _G.__LOOTTOFORGE_DBG and _G.__LOOTTOFORGE_DBG.shutdown then _G.__LOOTTOFORGE_DBG.shutdown() end
_G.__LOOTTOFORGE_DBG = nil
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local plr = Players.LocalPlayer

local GEN = (_G.__LOOTTOFORGE or 0) + 1
_G.__LOOTTOFORGE = GEN

--------------------------------------------------------------------------------
-- config
--------------------------------------------------------------------------------

local CONFIG = {
	auto = false,

	farm = false,         -- clear a stage, collect the ore, return to commit it
	stage = 0,           -- 0 = deepest stage passed; otherwise that stage number
	train = false,        -- stand in the best free train area between runs
	trainSecs = 20,      -- seconds of training between two stage runs
	forge = false,        -- forge whenever the server holds 4+ ore
	equip = false,        -- wear the weapon with the highest Train stat
	sell = false,         -- sell weapons weaker than the worn one (never enchanted)
	upgrade = false,      -- spend coins on upgrades
	orePackFirst = false, -- bag size first: more ore per run means better forges
	upgOrePack = false,
	upgTrain = false,
	upgLuck = false,
	coinKeep = 0,        -- coins never spent
	rebirth = false,      -- as soon as the level requirement is met
	antiAfk = false,

	forgeArmor = false,   -- every other forge is "Armor" (hats and armor)
	index = false,        -- claim every new index entry, then the index ranks
	tower = false,        -- spend tower tickets: all 30 rounds per ticket
	towerKeep = 0,       -- tickets never spent
	dailyTicket = false,  -- the free daily tower ticket
	enchant = false,      -- fill empty enchant slots on the worn gear
	element = "Fire",    -- preferred stone element; the tier always comes first
	race = false,         -- unlock free race slots, spend race rolls, wear the best race
}

local STATE = {
	phase = "idle", note = "",
	level = 0, power = 0, coin = 0, rebirth = 0, stagePass = 0,
	needLevel = 0, area = 0, areaMult = 1, stage = 0,
	weapon = "-", weaponTrain = 0, weapons = 0, ore = 0, orePack = 0, orePackCap = 0,
	upg = { OrePack = 0, Train = 0, Luck = 0 },
	runs = 0, oreGot = 0, forged = 0, sold = 0, coinsSold = 0, upgrades = 0, rebirths = 0,
	lastRun = "-", lastForge = "-",
	hat = "-", hatVal = 0, armor = "-", armorVal = 0,
	indexLevel = 0, indexClaimed = 0, indexRanks = 0,
	tickets = 0, towerRuns = 0, towerRound = 0, stones = 0, enchants = 0, lastTower = "-",
	forgeFlip = false,
	race = "-", raceLevel = 0, raceRolls = 0, rolled = 0, lastRoll = "-",
	busy = false,
}

local function note(t) STATE.note = tostring(t) end
local stopEpoch, activeEpoch = 0, 0
local currentFeature, automatic = nil, false
local function cancelled()
    return GEN ~= _G.__LOOTTOFORGE or stopEpoch ~= activeEpoch
        or (automatic and (not CONFIG.auto or (currentFeature and not CONFIG[currentFeature])))
end
local function checkpoint() if cancelled() then error("Stopped", 0) end end
local function pause(seconds)
    local finish = os.clock() + seconds
    repeat checkpoint(); task.wait(math.min(0.1, math.max(0, finish-os.clock()))) until os.clock() >= finish
end

--------------------------------------------------------------------------------
-- references. Every wait carries a timeout: in the wrong place an endless
-- WaitForChild parks whatever loaded this file.
--------------------------------------------------------------------------------

local function wfc(parent, name)
	return parent and parent:WaitForChild(name, 10)
end

-- A require can yield forever; run it behind a wall clock so a hung module
-- costs its own feature and nothing else.
local function safeRequire(mod)
	if not mod then return nil end
	local done, res = false, nil
	task.spawn(function()
		pcall(function() res = require(mod) end)
		done = true
	end)
	local t = 0
	while not done and t < 8 do task.wait(0.1); t = t + 0.1 end
	return res
end

pcall(function() if setthreadidentity then setthreadidentity(2) end end)

local Remote = wfc(ReplicatedStorage, "Remote")
local Config = wfc(ReplicatedStorage, "Config")
local LocalData = wfc(ReplicatedStorage, "LocalData")

local R = {
	total = wfc(wfc(Remote, "Profile"), "GetTotalDataRF"),
	forge = wfc(wfc(Remote, "Forge"), "ForgeRF"),
	rebirth = wfc(wfc(Remote, "Rebirth"), "TryRebirthRE"),
}

local Comm = safeRequire(wfc(wfc(ReplicatedStorage, "Utils"), "CommunicationUtils"))
local BackpackData = safeRequire(wfc(LocalData, "BackpackData"))
local UpgradeData = safeRequire(wfc(LocalData, "UpgradeData"))
local TrainAreaCfg = safeRequire(wfc(wfc(Config, "TrainArea"), "Config"))
local UpgradeCfg = safeRequire(wfc(wfc(Config, "Upgrade"), "Config"))
local RebirthHelper = safeRequire(wfc(wfc(Config, "Rebirth"), "Helper"))
local WeaponHelper = safeRequire(wfc(wfc(Config, "Weapon"), "Helper"))
local ArmorHelper = safeRequire(wfc(wfc(Config, "Armor"), "Helper"))
local DungeonData = safeRequire(wfc(LocalData, "DungeonData"))
local ClassData = safeRequire(wfc(LocalData, "ClassData"))
local ClassHelper = safeRequire(wfc(wfc(Config, "Class"), "Helper"))

local R_index = wfc(Remote, "Index")
R.indexExp = wfc(R_index, "TryClaimIndexExpRF")
R.indexLevel = wfc(R_index, "TryClaimLevelRewardRF")
local R_dungeonInto = wfc(wfc(Remote, "Dungeon"), "TryIntoDungeonRF")

local hitBE, exitBE
pcall(function()
	hitBE = Comm.TryGetBindableEvent("Attack", "EnemyHitBE")
	exitBE = Comm.TryGetBindableEvent("Stage", "ExitFightBE")
end)

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------

local function short(n)
	n = tonumber(n) or 0
	local units = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
	local i = 1
	while math.abs(n) >= 1000 and i < #units do n = n / 1000; i = i + 1 end
	if math.abs(n) >= 1000 then return string.format("%.2e", n) end
	return (string.format("%.2f", n):gsub("%.?0+$", "")) .. units[i]
end

local function hrp()
	local c = plr.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function dead()
	if plr:GetAttribute("Dead") then return true end
	local c = plr.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	return not h or h.Health <= 0
end

-- RemoteFunctions behind a wall clock: one that never answers must not park the
-- farm thread for good.
local pending = {}
local function invoke(rf, ...)
    checkpoint()
    if not rf then error("Missing RemoteFunction", 0) end
    local old = pending[rf]
    if old and not old.done then error("Server request still pending; wait before retrying", 0) end
    local args = table.pack(...)
    local job = {done=false}
    pending[rf] = job
    task.spawn(function()
        job.ok, job.result = pcall(function() return rf:InvokeServer(table.unpack(args,1,args.n)) end)
        job.done = true
    end)
    local started = os.clock()
    while not job.done and os.clock()-started < 8 do pause(0.1) end
    if not job.done then error("Server timeout; request may still finish",0) end
    pending[rf] = nil
    if not job.ok then error(tostring(job.result),0) end
    return job.result
end

-- The server's own view. Every decision reads this, never the client backpack
-- cache - the cache kept ore the server no longer had.
local function data()
	local d = invoke(R.total)
	if type(d) == "table" then STATE.data = d end
	return (type(d) == "table") and d or nil
end

local function trainValue(item)
	local m = item and item.MainAffix
	if m and m.Type == "Train" then return tonumber(m.Number) or 0 end
	return 0
end

-- The value of a piece of gear, computed exactly like BalanceUtils does it:
--   Weapon -> flat Train add = the config MainAffix of its ID
--   Hat    -> Train BOOST (a fraction, 0.7 = +70%)
--   Armor  -> Defence
-- "BestPercent" items (the _1001/_1002 ids) are worth MainAffix x the best NORMAL
-- item of that slot you own, capped - which is why the best normal item of every
-- slot is never sold, even when something better is worn.
local SLOT_STAT = { Weapon = "Train", Hat = "Train", Armor = "Defence" }

local function helperFor(slot)
	return slot == "Weapon" and WeaponHelper or ArmorHelper
end

local function isPercent(slot, id)
	local ok, v = pcall(function() return helperFor(slot).CheckIsBestPercent(id) end)
	return ok and v == true
end

local function baseValue(slot, id)
	local ok, v = pcall(function() return helperFor(slot).GetMainAffix(id) end)
	return (ok and tonumber(v)) or 0
end

-- best normal (non-percent) value of a slot among everything owned
local function bestNormal(have, slot)
	local best = slot == "Weapon" and 1 or 0.1
	for _, it in pairs(have) do
		if it.Type == slot and not isPercent(slot, it.ID) then
			local v
			if slot == "Weapon" then
				v = baseValue(slot, it.ID)
			else
				local ok, a = pcall(function() return ArmorHelper.GetAttriNum(it.ID) end)
				v = (ok and tonumber(a)) or 0
			end
			if v > best then best = v end
		end
	end
	return best
end

local function gearValue(have, it)
	local slot = it.Type
	if not SLOT_STAT[slot] then return 0 end
	local v = baseValue(slot, it.ID)
	if isPercent(slot, it.ID) then
		local cap
		pcall(function()
			cap = slot == "Weapon" and WeaponHelper.GetMaxTrain(it.ID) or ArmorHelper.GetMaxAttrNum(it.ID)
		end)
		v = v * bestNormal(have, slot)
		if tonumber(cap) then v = math.min(v, tonumber(cap)) end
	end
	-- bonus affixes, keyed by stat name
	if slot ~= "Weapon" and type(it.Affix) == "table" then
		for stat, add in pairs(it.Affix) do
			if stat == SLOT_STAT[slot] and tonumber(add) then v = v + tonumber(add) end
		end
	end
	return v
end

-- one pin at a time; the body belongs to whichever pass set it last
local pinConn
local function pin(pos)
	if pinConn then pinConn:Disconnect(); pinConn = nil end
	if not pos then return end
	local cf = CFrame.new(pos)
	pinConn = RunService.Heartbeat:Connect(function()
		local r = hrp()
		if r then
			r.CFrame = cf
			r.AssemblyLinearVelocity = Vector3.zero
		end
	end)
end

local function unpin() pin(nil) end

local function streamAround(pos)
	pcall(function() plr:RequestStreamAroundAsync(pos, 5) end)
end

--------------------------------------------------------------------------------
-- state refresh
--------------------------------------------------------------------------------

local function refresh(withServer)
	local eco = plr:FindFirstChild("Eco")
	if eco then
		pcall(function()
			STATE.level = eco.level.Value
			STATE.power = eco.power.Value
			STATE.coin = eco.coin.Value
			STATE.rebirth = eco.rebirth.Value
		end)
	end
	pcall(function()
		STATE.needLevel = RebirthHelper.GetNeedLevel(STATE.rebirth + 1) or 0
	end)
	pcall(function() STATE.orePackCap = UpgradeData.GetMaxNum("OrePack") end)
	if not withServer then return end

	local d = data()
	if not d then return end
	STATE.stagePass = (d.Stats and tonumber(d.Stats.StagePass)) or STATE.stagePass
	local upg = d.Upgrade or {}
	for _, k in ipairs({ "OrePack", "Train", "Luck" }) do
		STATE.upg[k] = (upg[k] and tonumber(upg[k].Level)) or 0
	end
	local bp = d.Backpack or {}
	local have = bp.have or {}
	local eq = bp.equiped or {}
	local ore, weapons, tickets, stones = 0, 0, 0, 0
	for _, it in pairs(have) do
		if it.Type == "Ore" then
			ore = ore + (tonumber(it.Number) or 1)
		elseif it.Type == "Weapon" then
			weapons = weapons + 1
		elseif it.Type == "EnchStone" then
			stones = stones + (tonumber(it.Number) or 1)
		elseif it.ID == "Dungeon_Ticket" then
			tickets = tickets + (tonumber(it.Number) or 0)
		end
	end
	local function worn(slot)
		local it = eq[slot] and have[eq[slot]]
		if it then return tostring(it.ID), gearValue(have, it) end
		return "-", 0
	end
	STATE.weapon, STATE.weaponTrain = worn("Weapon")
	STATE.hat, STATE.hatVal = worn("Hat")
	STATE.armor, STATE.armorVal = worn("Armor")
	STATE.ore, STATE.weapons, STATE.tickets, STATE.stones = ore, weapons, tickets, stones
	STATE.indexLevel = (d.Index and tonumber(d.Index.level)) or STATE.indexLevel
	STATE.towerRound = (d.Dungeon and tonumber(d.Dungeon.maxRound)) or STATE.towerRound
end

--------------------------------------------------------------------------------
-- training: stand in the best free area and let the game train
--------------------------------------------------------------------------------

_G.__LTF_POS = _G.__LTF_POS or { train = {}, stage = {} }
local POS = _G.__LTF_POS

local function bestArea()
	local best, mult = 1, 1
	if type(TrainAreaCfg) ~= "table" then return best, mult end
	for i, v in ipairs(TrainAreaCfg) do
		if not v.IsPay and (tonumber(v.NeedRebirth) or 0) <= STATE.rebirth then
			if (tonumber(v.Basic) or 0) >= mult then best, mult = i, tonumber(v.Basic) end
		end
	end
	return best, mult
end

local function trainPos(i)
	local folder = Workspace:FindFirstChild("CanAttackFolder")
	folder = folder and folder:FindFirstChild("TrainArea")
	local m = folder and folder:FindFirstChild("Train_" .. i)
	if m then
		local ok, cf = pcall(function() return m:GetPivot() end)
		if ok and cf then POS.train[i] = cf.Position + Vector3.new(0, 2, 0) end
	end
	return POS.train[i]
end

local function trainPass(secs)
	local i, mult = bestArea()
	STATE.area, STATE.areaMult = i, mult
	local pos = trainPos(i)
	if not pos then
		streamAround(Vector3.new(-50, 4, -30))
		pause(1)
		pos = trainPos(i)
	end
	if not pos then note("train area " .. i .. " not loaded"); return end
	STATE.phase = "train"
	pin(pos)
	local t0 = os.clock()
	while os.clock() - t0 < secs do pause(0.2) end
	unpin()
end

--------------------------------------------------------------------------------
-- stage run: enter, kill through the game's hit event, collect, RETURN
--------------------------------------------------------------------------------

local function targetStage()
	if CONFIG.stage and CONFIG.stage > 0 then return math.floor(CONFIG.stage) end
	return math.max(1, math.min(STATE.stagePass, 27))
end

local function stagePos(n)
	local sm = Workspace:FindFirstChild("WorldModel")
	sm = sm and sm:FindFirstChild("StageMap")
	local ap = sm and sm:FindFirstChild("AreaPart")
	local part = ap and ap:FindFirstChild("Stage_" .. n)
	if part and part:IsA("BasePart") then
		POS.stage[n] = Vector3.new(part.Position.X, 4, part.Position.Z)
	end
	-- measured spacing, only until the real part has streamed in once
	return POS.stage[n] or Vector3.new(3.24, 4, -113 - 108 * (n - 1))
end

local function enemiesNear(z)
	local list = {}
	local ef = Workspace:FindFirstChild("EnemyFolder")
	if not ef then return list end
	for _, m in ipairs(ef:GetChildren()) do
		if not m:GetAttribute("Dead") then
			local ok, p = pcall(function() return m:GetPivot().Position end)
			if ok and math.abs(p.Z - z) < 80 then list[#list + 1] = m end
		end
	end
	return list
end

local function oreModels()
	local oc = Workspace:FindFirstChild("OreCache")
	return oc and oc:GetChildren() or {}
end

local function dropPosition(o)
    if o:IsA("Attachment") then return o.WorldPosition end
    if o:IsA("BasePart") then return o.Position end
    if o:IsA("ProximityPrompt") then
        local parent=o.Parent
        if parent then return dropPosition(parent) end
        return nil
    end
    local part=o:FindFirstChildWhichIsA("BasePart",true)
    if part then return part.Position end
    if o:IsA("Model") then return o:GetPivot().Position end
    return nil
end
local function stageDrops()
    -- OreCache is the game's drop container. Do not filter by stage Z: drops
    -- can be parented below folders or spawn outside the guessed stage position.
    local cache=Workspace:FindFirstChild("OreCache")
    if not cache then return {} end
    local result={}
    for _,o in ipairs(cache:GetDescendants()) do
        if o:IsA("ProximityPrompt") and o.Enabled then
            local pos=dropPosition(o)
            if pos then result[#result+1]={object=o,prompt=o,pos=pos} end
        end
    end
    if #result==0 then
        for _,o in ipairs(cache:GetChildren()) do
            if not o:FindFirstChildWhichIsA("ProximityPrompt",true) then
                local pos=dropPosition(o)
                if pos then result[#result+1]={object=o,pos=pos} end
            end
        end
    end
    return result
end
local function pickupDrop(drop)
    checkpoint()
    if not drop.object.Parent then return false end
    pin(drop.pos+Vector3.new(0,1.5,0)); pause(0.4)
    if drop.prompt then
        local pp=drop.prompt
        if not pp.Enabled or not pp.Parent then return false end
        local hold=math.clamp(tonumber(pp.HoldDuration) or 0,0,10)
        local begun,beginError=pcall(function() pp:InputHoldBegin() end)
        local waited,waitError=pcall(function() pause(hold+0.15) end)
        if begun then pcall(function() pp:InputHoldEnd() end) end
        if not waited then error(waitError,0) end
        if pp.Parent and pp.Enabled and type(fireproximityprompt)=="function" then
            local ok,err=pcall(function() fireproximityprompt(pp) end)
            if not ok then note("Pickup call failed: "..tostring(err)) end
        elseif not begun then
            error("No supported prompt pickup: "..tostring(beginError),0)
        end
    end
    -- Touch-only drops get time for the character/game pickup handler to react.
    pause(0.4)
    return not drop.object.Parent or (drop.prompt and not drop.prompt.Enabled) or false
end
local farmStage
local function stageRun()
    checkpoint()
    if dead() then error("Character unavailable; waiting for respawn",0) end
    if plr:GetAttribute("Dungeoning") then error("Exit tower before farming",0) end
    refresh(true)
    local oreBefore=STATE.ore
    local n = automatic and (farmStage or targetStage()) or targetStage()
    if automatic then farmStage=n end
    STATE.stage=n; STATE.phase="Entering stage "..n
    local pos=stagePos(n)
    streamAround(pos); pin(pos)
    local started=os.clock()
    while #enemiesNear(pos.Z)==0 and os.clock()-started<12 do pause(0.2) end
    if #enemiesNear(pos.Z)==0 then error("No enemies spawned in stage "..n,0) end
    local seen={}
    STATE.phase="Clearing stage "..n
    local clearStart=os.clock()
    local emptySince=nil
    while os.clock()-clearStart<45 do
        checkpoint()
        local enemies=enemiesNear(pos.Z)
        if #enemies==0 then
            emptySince=emptySince or os.clock()
            if os.clock()-emptySince>=1.5 then break end
        else
            emptySince=nil
            for _,m in ipairs(enemies) do
                checkpoint(); seen[m]=true
                hitBE:Fire(m.Name,1e30,{Damage=1e30})
            end
        end
        pause(0.25)
    end
    if #enemiesNear(pos.Z)>0 then error("Stage clear timed out",0) end
    STATE.phase="Collecting drops"
    local collectStart=os.clock()
    local quietSince=nil
    local noProgressSince=os.clock()
    local previous=nil
    local remaining=0
    while os.clock()-collectStart<35 do
        checkpoint()
        local drops=stageDrops()
        remaining=#drops
        if remaining==0 then
            quietSince=quietSince or os.clock()
            if os.clock()-quietSince>=6 then break end
        else
            quietSince=nil
            if previous~=remaining then noProgressSince=os.clock(); previous=remaining end
            local confirmed=0
            for i,drop in ipairs(drops) do
                checkpoint()
                if os.clock()-collectStart>=35 then break end
                STATE.phase=string.format("Picking drop %d/%d",i,#drops)
                if pickupDrop(drop) then confirmed=confirmed+1 end
            end
            if confirmed>0 then noProgressSince=os.clock() end
            note(string.format("Drops found: %d; pickup confirmed: %d; prompt helper: %s",
                remaining,confirmed,type(fireproximityprompt)=="function" and "yes" or "no"))
            if os.clock()-noProgressSince>8 then break end
        end
        pause(0.2)
    end
    remaining=#stageDrops()
    unpin()
    STATE.phase="Returning / confirming ore"
    exitBE:Fire(true)
    pause(2)
    local home=trainPos(bestArea()) or Vector3.new(-50,4,-30)
    local root=hrp(); if root then root.CFrame=CFrame.new(home) end
    pause(0.5)
    refresh(true)
    local got=math.max(0,STATE.ore-oreBefore)
    STATE.runs=STATE.runs+1; STATE.oreGot=STATE.oreGot+got
    STATE.lastRun=string.format("Stage %d: +%d ore, %d drops remaining",n,got,remaining)
    if remaining>0 then note(STATE.lastRun.." (bag full or pickup rejected)") else note(STATE.lastRun) end
    pause(0.5)
end

--------------------------------------------------------------------------------
-- forge, equip, sell
--------------------------------------------------------------------------------

local function oreList(d)
	local list = {}
	for uid, it in pairs((d.Backpack and d.Backpack.have) or {}) do
		if it.Type == "Ore" then
			list[#list + 1] = {
				uuid = uid, id = tostring(it.ID), n = tonumber(it.Number) or 1,
				rank = tonumber(tostring(it.ID):match("%d+")) or 0,
			}
		end
	end
	table.sort(list, function(a, b) return a.rank > b.rank end)
	return list
end

local function gearSet(d)
	local set = {}
	for uid, it in pairs((d.Backpack and d.Backpack.have) or {}) do
		if SLOT_STAT[it.Type] then set[uid] = it end
	end
	return set
end

local function forgePass()
	for _ = 1, 6 do
        checkpoint()
		local d = data()
		if not d then return end
		local ores = oreList(d)
		-- the rules the server enforces by eating the ore: category, <=4 types, >=4 ore
		local list, total, used = {}, 0, {}
		for i = 1, math.min(4, #ores) do
			list[ores[i].uuid] = ores[i].n
			total = total + ores[i].n
			used[#used + 1] = ores[i].id .. "x" .. ores[i].n
		end
		if total < 4 then return end

		-- ConfigType is the CATEGORY. Alternating gives the index both kinds of
		-- entry and keeps the hat (a Train boost) climbing beside the weapon.
		local category = "Weapon"
		if CONFIG.forgeArmor then
			STATE.forgeFlip = not STATE.forgeFlip
			if STATE.forgeFlip then category = "Armor" end
		end

		STATE.phase = "forge"
		local before = gearSet(d)
		invoke(R.forge, { ConfigType = category, UUIDList = list })
		pause(0.8)
		local d2 = data()
		local made
		if d2 then
			for uid, it in pairs(gearSet(d2)) do
				if not before[uid] then made = it end
			end
		end
		if not made then
			note("forge produced nothing (" .. category .. ": " .. table.concat(used, " ") .. ") - stopped")
			return
		end
		STATE.forged = STATE.forged + 1
		local v = gearValue(d2.Backpack.have, made)
		STATE.lastForge = string.format("%s %s %s", tostring(made.ID),
			made.Type == "Weapon" and "Train" or (made.Type == "Hat" and "boost" or "def"),
			made.Type == "Weapon" and short(v) or string.format("%.2f", v))
		note("forged " .. STATE.lastForge .. " from " .. table.concat(used, " "))
	end
end

-- wear the best piece in every slot
local function equipPass()
	local d = data()
	if not d then return end
	local have = d.Backpack.have or {}
	local eq = d.Backpack.equiped or {}
	for slot in pairs(SLOT_STAT) do
		local best, bestV = nil, -1
		for uid, it in pairs(have) do
			if it.Type == slot then
				local v = gearValue(have, it)
				if v > bestV then best, bestV = uid, v end
			end
		end
		if best and best ~= eq[slot] then
			pcall(function() BackpackData.EquipedItem(best, slot) end)
			pause(0.8)
			note(string.format("equipped %s %s", slot, tostring(have[best].ID)))
		end
	end
end

-- EnchanceNum is the number of enchant SLOTS and EnchanceList holds one table per
-- slot, empty until something is put in it. Reading either as "enchanted" kept
-- every forged weapon (they all come with slots) - only a filled slot counts.
local function enchanted(it)
	if type(it.EnchanceList) == "table" then
		for _, slot in pairs(it.EnchanceList) do
			if type(slot) ~= "table" or next(slot) ~= nil then return true end
		end
	end
	return it.Lock == true or it.Locked == true
end

-- Gear this script enchanted itself may be sold once outclassed; anything the
-- player enchanted by hand is always kept.
_G.__LTF_ENCHANTED = _G.__LTF_ENCHANTED or {}
local SCRIPT_ENCH = _G.__LTF_ENCHANTED

local function sellPass()
	local d = data()
	if not d then return end
	local have = d.Backpack.have or {}
	local eq = d.Backpack.equiped or {}
	local coin0 = STATE.coin
	local n = 0
	for slot in pairs(SLOT_STAT) do
		local worn = eq[slot] and have[eq[slot]]
		if worn then -- never sell a slot without knowing what is worn
			local wornV = gearValue(have, worn)
			-- the best NORMAL piece feeds every percent item of the slot
			local keepNormal, keepV = nil, -1
			for uid, it in pairs(have) do
				if it.Type == slot and not isPercent(slot, it.ID) then
					local v = slot == "Weapon" and baseValue(slot,it.ID) or ArmorHelper.GetAttriNum(it.ID)
                    if v > keepV then keepNormal, keepV = uid, v end
				end
			end
			for uid, it in pairs(have) do
				if it.Type == slot and uid ~= eq[slot] and uid ~= keepNormal
					and it.Lock ~= true and it.Locked ~= true
                    and (not enchanted(it) or SCRIPT_ENCH[uid])
					and gearValue(have, it) < wornV then
					checkpoint()
                    BackpackData.TrySellItem(uid,1)
                    pause(0.4)
                    local verified=data()
                    if verified and verified.Backpack and verified.Backpack.have and not verified.Backpack.have[uid] then
                        SCRIPT_ENCH[uid]=nil; n=n+1
                    end
				end
			end
		end
	end
	if n > 0 then
		pause(1)
		refresh(false)
		STATE.sold = STATE.sold + n
		STATE.coinsSold = STATE.coinsSold + math.max(0, STATE.coin - coin0)
		note(string.format("sold %d items, +%s coins", n, short(STATE.coin - coin0)))
	end
end

--------------------------------------------------------------------------------
-- upgrades: bag first, then Train and Luck by next price
--------------------------------------------------------------------------------

local function nextPrice(key)
	local ladder = type(UpgradeCfg) == "table" and UpgradeCfg[key]
	if type(ladder) ~= "table" then return nil end
	local step = ladder[(STATE.upg[key] or 0) + 1]
	return step and tonumber(step.Price) or nil
end

local function upgradePass()
	refresh(true)
	for _ = 1, 8 do
        checkpoint()
		local keys = {}
		local packOpen = CONFIG.upgOrePack and nextPrice("OrePack") ~= nil
		if CONFIG.orePackFirst and packOpen then
			keys = { "OrePack" }
		else
			if CONFIG.upgOrePack then keys[#keys + 1] = "OrePack" end
			if CONFIG.upgTrain then keys[#keys + 1] = "Train" end
			if CONFIG.upgLuck then keys[#keys + 1] = "Luck" end
		end
		local pick, price = nil, math.huge
		for _, k in ipairs(keys) do
			local p = nextPrice(k)
			if p and p < price then pick, price = k, p end
		end
		if not pick or STATE.coin - price < CONFIG.coinKeep then return end

		local lvl = STATE.upg[pick]
		pcall(function() UpgradeData.UpgradeOnce(pick) end)
		pause(1)
		refresh(true)
		if STATE.upg[pick] <= lvl then
			note(pick .. " upgrade refused at " .. short(price))
			return
		end
		STATE.upgrades = STATE.upgrades + 1
		note(string.format("%s -> level %d for %s", pick, STATE.upg[pick], short(price)))
	end
end

--------------------------------------------------------------------------------
-- rebirth
--------------------------------------------------------------------------------

local function rebirthPass()
	refresh(false)
	local need = STATE.needLevel
	if not need or need <= 0 or STATE.level < need then return end
	local r0 = STATE.rebirth
	R.rebirth:FireServer()
	pause(1.5)
	refresh(false)
	if STATE.rebirth > r0 then
		STATE.rebirths = STATE.rebirths + 1
		note("rebirth -> " .. STATE.rebirth)
	end
end

--------------------------------------------------------------------------------
-- index: every first-time item is worth EXP, and EXP buys index ranks
--------------------------------------------------------------------------------
-- The index ID is "<Type>-<ItemId>" (Weapon-K_23, Hat-LHat_14, Ore-Ore_41).
-- Measured: 22 unclaimed entries took the EXP 50 -> 1860 and six ranks followed.

local function indexPass()
	local d = data()
	local ix = d and d.Index
	if not ix or type(ix.unlocked) ~= "table" then return end
	local claimed = type(ix.claimed) == "table" and ix.claimed or {}
	local n = 0
	for key in pairs(ix.unlocked) do
		if not claimed[key] then
			local kind, id = tostring(key):match("^([^-]+)-(.+)$")
			if kind and invoke(R.indexExp, kind, id) then n = n + 1 end
			pause(0.15)
		end
	end
	local ranks = 0
	for _ = 1, 15 do
        checkpoint()
		local d1 = data()
		local before = tonumber(d1 and d1.Index and d1.Index.level) or 0
		invoke(R.indexLevel)
		pause(0.4)
		local d2 = data()
		local after = tonumber(d2 and d2.Index and d2.Index.level) or before
		if after <= before then break end
		ranks = ranks + 1
	end
	STATE.indexClaimed = STATE.indexClaimed + n
	STATE.indexRanks = STATE.indexRanks + ranks
	if n > 0 or ranks > 0 then
		note(string.format("index: %d entries, %d ranks", n, ranks))
	end
end

--------------------------------------------------------------------------------
-- tower (the "Frozen Tower", open from rebirth 2): one ticket runs all 30 rounds
--------------------------------------------------------------------------------
-- Enemies die through the same EnemyHitBE as the stages; CompleteRoundRF credits
-- the round (coins, ore, enchant stones) and the client starts the next one 3s
-- later. Measured: 1 ticket -> rounds 1-30 in 129s -> 26 enchant stones.

local function dailyTicketPass()
	if not DungeonData then return end
	local claimed = false
	pcall(function() claimed = DungeonData.CheckTodayClaimed() end)
	if not claimed then
		pcall(function() DungeonData.TryClaimDailyDunTic() end)
		pause(1)
	end
end

local function towerRun()
    checkpoint(); refresh(true)
    if dead() then error("Character unavailable",0) end
    if not plr:GetAttribute("Dungeoning") then
        if STATE.rebirth<2 then note("Tháp yêu cầu rebirth 2"); return end
        if STATE.tickets<=CONFIG.towerKeep then note("Không còn vé tháp vượt mức giữ lại"); return end
        unpin()
        invoke(R_dungeonInto,1)
        local start=os.clock()
        while not plr:GetAttribute("Dungeoning") and os.clock()-start<10 do pause(0.2) end
        if not plr:GetAttribute("Dungeoning") then error("Tower entry refused",0) end
    end
    local stones0=STATE.stones
    local start=os.clock()
    STATE.phase="Tower running"
    while plr:GetAttribute("Dungeoning") do
        checkpoint()
        if dead() then error("Character died in tower",0) end
        if os.clock()-start>300 then error("Tower timeout; resume or exit in game",0) end
        local ef=Workspace:FindFirstChild("EnemyFolder")
        if ef then
            for _,m in ipairs(ef:GetChildren()) do
                checkpoint()
                if not m:GetAttribute("Dead") then hitBE:Fire(m.Name,1e30,{Damage=1e30}) end
            end
        end
        pause(0.3)
    end
    pause(2); refresh(true)
    STATE.towerRuns=STATE.towerRuns+1
    STATE.lastTower=string.format("Exited after %ds, +%d stones; %d tickets",math.floor(os.clock()-start),STATE.stones-stones0,STATE.tickets)
    note(STATE.lastTower)
end

--------------------------------------------------------------------------------
-- enchant: fill the empty slots of the worn gear with the best stone
--------------------------------------------------------------------------------
-- EnchantRE(equipment uuid, stone uuid, slot). Costs 5,000 coins a stone. The
-- stones are COMBAT effects (burn, freeze, chain, poison) - they make fights you
-- play yourself stronger; the farm kills by client authority and gains nothing.

local function stoneRank(id)
	local tier = tonumber(tostring(id):match("_(%d+)$")) or 0
	local pref = tostring(id):find("^" .. tostring(CONFIG.element)) and 1 or 0
	return tier * 10 + pref
end

local function enchantPass()
	for _ = 1, 8 do
        checkpoint()
		local d = data()
		if not d then return end
		local have = d.Backpack.have or {}
		local eq = d.Backpack.equiped or {}
		local target, slot
		for gearSlot in pairs(SLOT_STAT) do
			local uid = eq[gearSlot]
			local it = uid and have[uid]
			if it then
				for i = 1, tonumber(it.EnchanceNum) or 0 do
					local s = type(it.EnchanceList) == "table" and it.EnchanceList[i]
					if not (type(s) == "table" and s.ID) then target, slot = uid, i; break end
				end
			end
			if target then break end
		end
		if not target then return end

		local stone, rank = nil, -1
		for uid, it in pairs(have) do
			if it.Type == "EnchStone" and (tonumber(it.Number) or 0) > 0 then
				local r = stoneRank(it.ID)
				if r > rank then stone, rank = uid, r end
			end
		end
		if not stone or STATE.coin - 5000 < CONFIG.coinKeep then return end

		local id = have[stone].ID
		pcall(function() BackpackData.EnchantEquipment(target, stone, slot) end)
		pause(1)
		local d2 = data()
		local it2 = d2 and d2.Backpack.have[target]
		local s2 = it2 and type(it2.EnchanceList) == "table" and it2.EnchanceList[slot]
		if not (type(s2) == "table" and s2.ID) then
			note("enchant refused on " .. tostring(have[target].ID))
			return
		end
		SCRIPT_ENCH[target] = true
		STATE.enchants = STATE.enchants + 1
		note(string.format("enchanted %s slot %d with %s", tostring(have[target].ID), slot, tostring(id)))
		refresh(false)
	end
end

--------------------------------------------------------------------------------
-- races (the game calls them Class): roll the worst slot, wear the best race
--------------------------------------------------------------------------------
-- Store "Class": have = {[slot] = "Class_N"}, equiped = slot, recored[Class_N]
-- .Level (kept even when the race is rolled away), lock = {[slot] = true},
-- luckTimes = rolls left. Only the EQUIPPED slot's boosts count. Slot 2 opens at
-- rebirth 4 and slot 3 at sign-in day 7 through TryUnlockIndexRE; 4-6 are Robux.
-- LuckOnceRE(slot) with 0 rolls left is where the game opens a Robux prompt, so
-- the roll count is checked before every roll.

local RACE_WEIGHT = { Train = 100, Luck = 40, Damage = 6, Crit = 5, SkillDamage = 3,
	Defence = 2, SkillCD = 1, WalkSpeed = 1 }

local function raceScore(classId, level)
	local s = 0
	local ok, boosts = pcall(function() return ClassHelper.GetClassBoosts(classId, level or 1) end)
	if ok and type(boosts) == "table" then
		for stat, v in pairs(boosts) do
			s = s + (RACE_WEIGHT[stat] or 1) * (tonumber(v) or 0)
		end
	end
	-- a rarer race wins a tie
	local okW, w = pcall(function() return ClassHelper.GetWeight(classId) end)
	if okW and tonumber(w) and tonumber(w) > 0 then s = s + 0.001 / tonumber(w) end
	return s
end

-- A roll fired from here still plays the game's LuckAnim (ShowLuckResultRE),
-- which ends in OpenScreenMain("Class") and leaves the camera Scriptable - it
-- assumes the player opened the screen first. ClassGUI.close() then does nothing
-- because its open-flag was never set, so this repeats close() by hand.
local function closeRaceUI()
	pcall(function()
		local UIC = safeRequire(ReplicatedStorage.Utils.UIController)
		local LPU = safeRequire(ReplicatedStorage.Utils.LocalPlayerUtils)
		local Cam = safeRequire(ReplicatedStorage.Utils.CameraUtils)
		local pg = plr:FindFirstChild("PlayerGui")
		UIC.CloseScreenMain("Class")
		local sm = pg and pg:FindFirstChild("ScreenMain")
		local cls = sm and sm:FindFirstChild("Class")
		local info = cls and cls:FindFirstChild("Info")
		if info then info.Visible = false end
		LPU.EnablePlrAction(true)
		for _, name in ipairs({ "Hud", "Main", "UIVFX" }) do
			local g = pg and pg:FindFirstChild(name)
			if g then g.Enabled = true end
		end
		Cam.BackToPlr(0)
	end)
end

local function racePass()
	if not ClassData then return end
	local d = data()
	local cl = d and d.Class
	if type(cl) ~= "table" then return end

	-- free slots first: 2 at rebirth 4, 3 at sign-in day 7
	local have = cl.have or {}
	if not have["2"] and STATE.rebirth >= 4 then
		pcall(function() ClassData.TryUnlockIndex("2") end)
		pause(1)
	end
	if not have["3"] and (tonumber(cl.signDay) or 0) >= 7 then
		pcall(function() ClassData.TryUnlockIndex("3") end)
		pause(1)
	end

	for _ = 1, 20 do
        checkpoint()
		d = data()
		cl = d and d.Class
		if type(cl) ~= "table" then return end
		have = cl.have or {}
		local lock = cl.lock or {}
		local rec = cl.recored or {}
		local rolls = tonumber(cl.luckTimes) or 0
		STATE.raceRolls = rolls

		local slots = {}
		for slot, id in pairs(have) do
			local lv = rec[id] and rec[id].Level or 1
			slots[#slots + 1] = { slot = slot, id = id, score = raceScore(id, lv), locked = lock[slot] == true }
		end
		table.sort(slots, function(a, b) return a.score > b.score end)
		if #slots == 0 then return end

		-- wear the best
		local best = slots[1]
		if cl.equiped ~= best.slot then
			pcall(function() ClassData.ChangeEquipedIndex(best.slot) end)
			pause(0.8)
			note("race: wearing " .. tostring(ClassHelper.GetDisName(best.id)))
		end
		local lvBest = rec[best.id] and rec[best.id].Level or 1
		STATE.race = tostring(ClassHelper.GetDisName(best.id) or best.id)
		STATE.raceLevel = lvBest

		if rolls <= 0 then return end

		-- the roll slot: the worst unlocked slot, never the best one while
		-- another exists; with one slot, only what the game itself rolls
		-- without asking (Common..Epic)
		local target
		for i = #slots, 1, -1 do
			local s = slots[i]
			if not s.locked and (#slots > 1 and i > 1 or #slots == 1) then target = s; break end
		end
		if target and #slots == 1 then
			local r = ClassHelper.GetRarity(target.id)
			if not (r == "Common" or r == "UnCommon" or r == "Rare" or r == "Epic") then target = nil end
		end
		if not target then return end

		pcall(function() ClassData.LuckOnce(target.slot) end)
		-- the result animation runs ~3s (2.72s camera tween plus the spin)
		pause(4)
		closeRaceUI()
		local d2 = data()
		local cl2 = d2 and d2.Class
		local left = cl2 and tonumber(cl2.luckTimes) or rolls
		if left >= rolls then
			note("race roll refused")
			return
		end
		local newId = cl2.have and cl2.have[target.slot]
		STATE.rolled = STATE.rolled + 1
		STATE.lastRoll = string.format("slot %s: %s -> %s", target.slot,
			tostring(ClassHelper.GetDisName(target.id)), tostring(ClassHelper.GetDisName(newId)))
		note("race " .. STATE.lastRoll)
	end
end

local function unstuck()
    stopEpoch=stopEpoch+1; CONFIG.auto=false
	unpin()
	local r = hrp()
	if r then r.Anchored = false end
	note("unstuck; current task stopping")
end


local API={CONFIG=CONFIG,STATE=STATE,POS=POS,version=6,ready=false}
local actions={stageRun=stageRun,trainPass=trainPass,forgePass=forgePass,equipPass=equipPass,
    sellPass=sellPass,upgradePass=upgradePass,rebirthPass=rebirthPass,indexPass=indexPass,
    towerRun=towerRun,dailyTicketPass=dailyTicketPass,enchantPass=enchantPass,racePass=racePass,
    refresh=function() refresh(true) end}
local queue={}
local nextAllowed={}
local connections={}
function API.stop()
    CONFIG.auto=false; stopEpoch=stopEpoch+1; table.clear(queue); unpin(); farmStage=nil
end
function API.disableAll()
    API.stop()
    for k,v in pairs(CONFIG) do if type(v)=="boolean" then CONFIG[k]=false end end
end
function API.set(k,v)
    if CONFIG[k]==nil then return false end
    if k=="auto" and not v then API.stop() else CONFIG[k]=v end
    if k=="stage" then farmStage=nil end
    if v==true and (k=="farm" or k=="tower" or k=="train") then
        CONFIG.auto=true
    end
    return true
end
function API.call(name,...)
    if not actions[name] then return false,"Unknown action" end
    if STATE.busy or #queue>0 then return false,"A task is already running" end
    if os.clock() < (nextAllowed[name] or 0) then return false,"Wait before retrying this task" end
    queue[#queue+1]={name=name,args=table.pack(...)}
    return true
end
function API.shutdown()
    API.disableAll()
    API.ready=false
    for _,c in ipairs(connections) do c:Disconnect() end
    if _G.__LOOTTOFORGE==GEN then _G.__LOOTTOFORGE=GEN+1 end
    if _G.__LOOTTOFORGE_DBG==API then _G.__LOOTTOFORGE_DBG=nil end
end
local function run(name,args,feature,isAuto)
    STATE.busy=true; activeEpoch=stopEpoch; currentFeature=feature; automatic=isAuto
    local ok,err=pcall(function() actions[name](table.unpack(args or {},1,args and args.n or 0)) end)
    unpin()
    if name=="stageRun" and not ok and not plr:GetAttribute("Dungeoning") then pcall(function() exitBE:Fire(true) end) end
    STATE.busy=false; currentFeature=nil; automatic=false; STATE.phase="idle"
    if name=="towerRun" then nextAllowed[name]=os.clock()+5 end
    if not ok then
        note(tostring(err))
        if tostring(err)~="Stopped" then nextAllowed[name]=os.clock()+5 end
    end
end
local required={total=R.total,forge=R.forge,rebirth=R.rebirth,hit=hitBE,exit=exitBE,
    backpack=BackpackData,upgrade=UpgradeData,weapon=WeaponHelper,armor=ArmorHelper}
for _,key in ipairs({"total","forge","rebirth","hit","exit","backpack","upgrade","weapon","armor"}) do
    if not required[key] then error("Engine initialization failed: "..key,0) end
end
refresh(true)
API.ready=true
_G.__LOOTTOFORGE_DBG=API
task.spawn(function()
    local support={{"forge","forgePass"},{"index","indexPass"},{"equip","equipPass"},
        {"enchant","enchantPass"},{"sell","sellPass"},{"upgrade","upgradePass"},
        {"rebirth","rebirthPass"},{"race","racePass"},{"dailyTicket","dailyTicketPass"}}
    local supportDue=0
    while GEN==_G.__LOOTTOFORGE do
        if #queue>0 then
            local job=table.remove(queue,1); run(job.name,job.args,nil,false)
        elseif CONFIG.auto then
            if os.clock()>=supportDue and not plr:GetAttribute("Dungeoning") then
                for _,job in ipairs(support) do
                    if CONFIG.auto and CONFIG[job[1]] and os.clock()>=(nextAllowed[job[2]] or 0) then run(job[2],nil,job[1],true) end
                end
                supportDue=os.clock()+5
            end
            if CONFIG.auto then
                -- Alternate body work so farm and tower cannot starve one another.
                if CONFIG.farm and not plr:GetAttribute("Dungeoning") and os.clock()>=(nextAllowed.stageRun or 0) then run("stageRun",nil,"farm",true) end
                if CONFIG.auto and CONFIG.tower and os.clock()>=(nextAllowed.towerRun or 0) then run("towerRun",nil,"tower",true) end
                if CONFIG.auto and CONFIG.train and not CONFIG.farm and not plr:GetAttribute("Dungeoning") then run("trainPass",table.pack(CONFIG.trainSecs),"train",true) end
            end
        elseif not STATE.busy then
            activeEpoch=stopEpoch
            pcall(function() refresh(false) end)
        end
        task.wait(0.25)
    end
    unpin()
end)
local VirtualUser=game:GetService("VirtualUser")
connections[#connections+1]=plr.Idled:Connect(function()
    if CONFIG.antiAfk then pcall(function() VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new()) end) end
end)
note("Engine ready; all automation disabled")
return API

end

local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local RS=game:GetService("RunService")
local Tween=game:GetService("TweenService")
local player=Players.LocalPlayer
if _G.__LTF_HUB_V6 then pcall(function() _G.__LTF_HUB_V6.destroy() end) end
local connections={}
local alive=true
local api=nil
local loading="Đang tải bộ xử lý…"
local jump,noclip=false,false
local speed=nil
local collision={}
local function connect(signal,fn)
    local c=signal:Connect(fn); connections[#connections+1]=c; return c
end
local function restoreCollision()
    for part,value in pairs(collision) do if part.Parent then part.CanCollide=value end end
    table.clear(collision)
end
local function resetPlayer()
    jump=false; noclip=false; restoreCollision()
    local h=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if speed and h then h.WalkSpeed=speed.original end
    speed=nil
end
local gui=Instance.new("ScreenGui")
gui.Name="DangRangToHubV6"; gui.ResetOnSpawn=false; gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
gui.DisplayOrder=10000; gui.Enabled=true; gui.IgnoreGuiInset=true
gui.Parent=UIHost
local function make(class,props,parent)
    local o=Instance.new(class)
    for k,v in pairs(props) do
        local ok,err=pcall(function() o[k]=v end)
        if not ok then o:Destroy(); error("UI "..class.."."..k..": "..tostring(err),0) end
    end
    o.Parent=parent; return o
end
-- Original self-contained design; Fluent/Luna examples used as visual references.
local bg=Color3.fromRGB(18,18,23)
local card=Color3.fromRGB(29,29,37)
local accent=Color3.fromRGB(167,139,250)
local white=Color3.fromRGB(241,239,249)
local muted=Color3.fromRGB(148,146,165)
local green=Color3.fromRGB(99,213,172)
local red=Color3.fromRGB(242,127,145)
local function round(o,r) make("UICorner",{CornerRadius=UDim.new(0,r or 10)},o) end
local function stroke(o,color,transparency)
    return make("UIStroke",{Color=color or Color3.fromRGB(66,63,80),Transparency=transparency or .55,Thickness=1},o)
end
local activeTweens={}
local function animate(o,props)
    if not alive or not o.Parent then return end
    if activeTweens[o] then activeTweens[o]:Cancel() end
    local t=Tween:Create(o,TweenInfo.new(.18,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),props)
    activeTweens[o]=t; t:Play()
end
local root=make("Frame",{Size=UDim2.fromOffset(800,570),Position=UDim2.fromScale(.5,.5),AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=bg,BorderSizePixel=0},gui); round(root,16); stroke(root,accent,.65)
local scale=make("UIScale",{Scale=1},root)
local top=make("Frame",{Size=UDim2.new(1,0,0,65),BackgroundColor3=Color3.fromRGB(23,22,30),BorderSizePixel=0},root); round(top,16)
make("Frame",{Size=UDim2.new(1,-32,0,1),Position=UDim2.fromOffset(16,64),BackgroundColor3=Color3.fromRGB(55,51,70),BorderSizePixel=0},root)
local emblem=make("TextLabel",{Size=UDim2.fromOffset(38,38),Position=UDim2.fromOffset(18,13),BackgroundColor3=Color3.fromRGB(53,42,78),Text="ĐR",TextColor3=accent,Font=Enum.Font.GothamBold,TextSize=17},root); round(emblem,11)
local header=make("TextLabel",{Size=UDim2.new(1,-176,0,28),Position=UDim2.fromOffset(68,10),BackgroundTransparency=1,Text="Đăng Răng To HUB",TextColor3=white,TextSize=20,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd},root)
local subtitle=make("TextLabel",{Size=UDim2.new(1,-176,0,18),Position=UDim2.fromOffset(69,37),BackgroundTransparency=1,Text="LOOT TO FORGE  /  V6",TextColor3=muted,TextSize=10,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left},root)
local function button(text,parent,size,pos)
    local o=make("TextButton",{Size=size or UDim2.new(1,0,0,44),Position=pos or UDim2.new(),Text=text,TextColor3=white,BackgroundColor3=card,BorderSizePixel=0,Font=Enum.Font.GothamMedium,TextSize=13,AutoButtonColor=false,TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd},parent)
    round(o,9); stroke(o)
    make("UIPadding",{PaddingLeft=UDim.new(0,14),PaddingRight=UDim.new(0,14)},o)
    connect(o.MouseEnter,function() animate(o,{BackgroundColor3=Color3.fromRGB(43,40,54)}) end)
    connect(o.MouseLeave,function() animate(o,{BackgroundColor3=card}) end)
    return o
end
local hide=button("−",root,UDim2.fromOffset(34,32),UDim2.new(1,-91,0,16)); hide.TextXAlignment=Enum.TextXAlignment.Center
local close=button("×",root,UDim2.fromOffset(34,32),UDim2.new(1,-49,0,16)); close.TextXAlignment=Enum.TextXAlignment.Center; close.TextColor3=red
local open=button("ĐR",gui,UDim2.fromOffset(50,50),UDim2.fromOffset(16,110)); open.Visible=false; open.TextXAlignment=Enum.TextXAlignment.Center; open.TextColor3=accent; stroke(open,accent,.2)
connect(hide.Activated,function() root.Visible=false; open.Visible=true end)
connect(open.Activated,function() root.Visible=true; open.Visible=false end)
local sidebar=make("ScrollingFrame",{Size=UDim2.fromOffset(166,380),Position=UDim2.fromOffset(14,86),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=0,CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y},root)
make("UIListLayout",{Padding=UDim.new(0,7)},sidebar)
local sideCaption=make("TextLabel",{Size=UDim2.new(1,0,0,18),BackgroundTransparency=1,Text="KHÔNG GIAN LÀM VIỆC",TextColor3=muted,TextSize=9,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left},sidebar)
local content=make("Frame",{Size=UDim2.new(1,-218,1,-155),Position=UDim2.fromOffset(200,86),BackgroundTransparency=1},root)
local pageTitle=make("TextLabel",{Size=UDim2.new(1,0,0,31),BackgroundTransparency=1,Text="Tổng quan",TextColor3=white,TextSize=23,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left},content)
local pageHost=make("Frame",{Size=UDim2.new(1,0,1,-43),Position=UDim2.fromOffset(0,43),BackgroundTransparency=1},content)
local footer=make("TextLabel",{Size=UDim2.new(1,-65,0,45),Position=UDim2.new(0,45,1,-54),BackgroundTransparency=1,Text=loading,TextColor3=muted,TextSize=11,Font=Enum.Font.Gotham,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left},root)
local connectionDot=make("Frame",{Size=UDim2.fromOffset(8,8),Position=UDim2.new(0,25,1,-35),BackgroundColor3=accent,BorderSizePixel=0},root); round(connectionDot,8)
make("Frame",{Size=UDim2.new(1,-32,0,1),Position=UDim2.new(0,16,1,-62),BackgroundColor3=Color3.fromRGB(55,51,70),BorderSizePixel=0},root)
local pages={}
local controls={}
local selected
local symbols={"◈","⚔","◇","♜","↗","☺"}
local function selectPage(p,title)
    selected=p; pageTitle.Text=title
    for _,entry in ipairs(pages) do
        local on=entry.p==p
        entry.p.Visible=on; entry.nav.TextColor3=on and accent or muted
        entry.nav.BackgroundColor3=on and Color3.fromRGB(47,38,65) or bg
        entry.line.Visible=on
    end
end
local function page(title)
    local p=make("ScrollingFrame",{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=3,ScrollBarImageColor3=accent,CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y,Visible=false},pageHost)
    make("UIListLayout",{Padding=UDim.new(0,9)},p)
    make("UIPadding",{PaddingRight=UDim.new(0,8),PaddingBottom=UDim.new(0,12)},p)
    local nav=make("TextButton",{Size=UDim2.new(1,0,0,42),BackgroundColor3=bg,BorderSizePixel=0,Text=(symbols[#pages+1] or "•").."   "..title,TextColor3=muted,TextSize=13,Font=Enum.Font.GothamMedium,TextXAlignment=Enum.TextXAlignment.Left,AutoButtonColor=false,TextTruncate=Enum.TextTruncate.AtEnd},sidebar); round(nav,8)
    make("UIPadding",{PaddingLeft=UDim.new(0,12),PaddingRight=UDim.new(0,6)},nav)
    local line=make("Frame",{Size=UDim2.fromOffset(3,20),Position=UDim2.new(0,0,.5,-10),BackgroundColor3=accent,BorderSizePixel=0,Visible=false},nav); round(line,3)
    pages[#pages+1]={p=p,nav=nav,line=line,title=title}
    connect(nav.Activated,function() selectPage(p,title) end)
    if not selected then selectPage(p,title) end
    return p
end
local function label(p,text)
    local o=make("TextLabel",{Size=UDim2.new(1,0,0,72),BackgroundColor3=Color3.fromRGB(36,30,48),BorderSizePixel=0,AutomaticSize=Enum.AutomaticSize.Y,Text=text,TextColor3=Color3.fromRGB(193,183,214),TextSize=12,Font=Enum.Font.Gotham,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left},p); round(o,10)
    make("UIPadding",{PaddingLeft=UDim.new(0,14),PaddingRight=UDim.new(0,14),PaddingTop=UDim.new(0,10),PaddingBottom=UDim.new(0,10)},o)
    return o
end
local function section(p,title)
    make("TextLabel",{Size=UDim2.new(1,0,0,26),BackgroundTransparency=1,Text=title,TextColor3=muted,TextSize=10,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left},p)
end
local lastViewport
local function resize()
    local camera=workspace.CurrentCamera
    if not camera then return end
    local v=camera.ViewportSize
    if lastViewport==v then return end
    lastViewport=v
    local w=math.min(800,math.max(300,v.X-24)); local height=math.min(570,math.max(280,v.Y-24))
    local narrow=w<570; local side=narrow and 115 or 166
    root.Size=UDim2.fromOffset(w,height); scale.Scale=math.min(1,(v.X-12)/w,(v.Y-12)/height)
    sidebar.Size=UDim2.new(0,side,1,-163)
    content.Position=UDim2.fromOffset(side+32,86); content.Size=UDim2.new(1,-side-50,1,-155)
    header.TextSize=narrow and 15 or 20; pageTitle.TextSize=narrow and 19 or 23
    sideCaption.Text=narrow and "DANH MỤC" or "KHÔNG GIAN LÀM VIỆC"
    for _,entry in ipairs(pages) do entry.nav.TextSize=narrow and 11 or 13 end
end
resize()
local messageUntil=0
local function inform(text) loading=text; footer.Text=text; messageUntil=os.clock()+4 end
local function call(name,...)
    if not api then inform("Bộ xử lý chưa sẵn sàng"); return end
    local ok,err=api.call(name,...)
    if not ok then inform(err or "Đang có tác vụ chạy") end
end
local function toggle(p,title,key)
    local row=make("TextButton",{Size=UDim2.new(1,0,0,52),BackgroundColor3=card,BorderSizePixel=0,Text="",AutoButtonColor=false},p); round(row,10); stroke(row)
    make("TextLabel",{Size=UDim2.new(1,-87,1,0),Position=UDim2.fromOffset(14,0),BackgroundTransparency=1,Text=title,TextColor3=white,TextSize=12,Font=Enum.Font.GothamMedium,TextXAlignment=Enum.TextXAlignment.Left,TextWrapped=true},row)
    local track=make("Frame",{Size=UDim2.fromOffset(38,22),Position=UDim2.new(1,-53,.5,-11),BackgroundColor3=Color3.fromRGB(59,58,70),BorderSizePixel=0},row); round(track,20)
    local knob=make("Frame",{Size=UDim2.fromOffset(16,16),Position=UDim2.fromOffset(3,3),BackgroundColor3=Color3.fromRGB(168,165,183),BorderSizePixel=0},track); round(knob,16)
    controls[#controls+1]={button=row,title=title,key=key,track=track,knob=knob,last=nil}
    connect(row.Activated,function()
        if not api then inform("Chờ bộ xử lý tải xong"); return end
        api.set(key,not api.CONFIG[key])
    end)
end
local function input(p,title,key,default,min,max)
    local row=make("Frame",{Size=UDim2.new(1,0,0,54),BackgroundColor3=card,BorderSizePixel=0},p); round(row,10); stroke(row)
    make("TextLabel",{Size=UDim2.new(1,-99,1,0),Position=UDim2.fromOffset(14,0),BackgroundTransparency=1,Text=title,TextColor3=white,TextSize=12,Font=Enum.Font.GothamMedium,TextXAlignment=Enum.TextXAlignment.Left,TextWrapped=true},row)
    local box=make("TextBox",{Size=UDim2.fromOffset(66,30),Position=UDim2.new(1,-80,.5,-15),BackgroundColor3=bg,Text=tostring(default),TextColor3=accent,TextSize=13,Font=Enum.Font.GothamBold,ClearTextOnFocus=false},row); round(box,7); stroke(box,accent,.65)
    connect(box.FocusLost,function()
        if not api then box.Text=tostring(default); inform("Chờ bộ xử lý"); return end
        local n=tonumber(box.Text)
        if not n then box.Text=tostring(api.CONFIG[key]); return end
        n=math.clamp(math.floor(n),min,max); box.Text=tostring(n); api.set(key,n)
    end)
end
local metricValues={}
local function metrics(p)
    local row=make("Frame",{Size=UDim2.new(1,0,0,86),BackgroundTransparency=1},p)
    for i,title in ipairs({"LEVEL","REBIRTH","COINS"}) do
        local tile=make("Frame",{Size=UDim2.new(1/3,-6,1,0),Position=UDim2.new((i-1)/3,0,0,0),BackgroundColor3=card,BorderSizePixel=0},row); round(tile,11); stroke(tile)
        make("TextLabel",{Size=UDim2.new(1,-18,0,16),Position=UDim2.fromOffset(10,12),BackgroundTransparency=1,Text=title,TextColor3=muted,TextSize=9,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left},tile)
        metricValues[i]=make("TextLabel",{Size=UDim2.new(1,-18,0,31),Position=UDim2.fromOffset(10,36),BackgroundTransparency=1,Text="—",TextColor3=i==3 and green or white,TextSize=20,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd},tile)
    end
end
local function compact(n)
    n=tonumber(n) or 0
    for _,v in ipairs({{1e12,"T"},{1e9,"B"},{1e6,"M"},{1e3,"K"}}) do if math.abs(n)>=v[1] then return string.format("%.1f%s",n/v[1],v[2]) end end
    return tostring(math.floor(n))
end
local general=page("Tổng quan")
metrics(general)
section(general,"ĐIỀU KHIỂN")
label(general,"Bật Farm màn, Tháp hoặc Luyện sẽ tự bật Auto tổng. Tác vụ chạy lần lượt; nút thủ công chỉ nhận khi bộ xử lý rảnh.")
toggle(general,"AUTO TỔNG","auto")
local stop=button("■  Dừng tất cả",general); stop.TextColor3=red; stop.BackgroundColor3=Color3.fromRGB(50,29,37)
connect(stop.Activated,function() if api then api.disableAll() end; resetPlayer(); inform("Đã yêu cầu dừng") end)
section(general,"HOẠT ĐỘNG GẦN ĐÂY")
local status=label(general,""); status.Size=UDim2.new(1,0,0,128)
local refresh=button("Làm mới dữ liệu",general); connect(refresh.Activated,function() call("refresh") end)
local farm=page("Farm màn")
label(farm,"Dọn màn → nhặt drop → back → quay lại cùng màn. Khi túi đầy hoặc nhặt bị từ chối, trạng thái sẽ báo số drop còn lại.")
section(farm,"VÒNG FARM")
toggle(farm,"Farm màn liên tục","farm")
input(farm,"Màn (0 = màn đã vượt sâu nhất)","stage",0,0,27)
local once=button("Farm một lượt",farm); connect(once.Activated,function() call("stageRun") end)
section(farm,"LUYỆN SỨC MẠNH")
toggle(farm,"Luyện khi không farm màn","train")
input(farm,"Thời gian luyện (giây)","trainSecs",20,5,120)
local train=button("Luyện một lượt",farm); connect(train.Activated,function() call("trainPass",api and api.CONFIG.trainSecs or 20) end)
local gear=page("Trang bị")
section(gear,"TỰ ĐỘNG TRANG BỊ")
for _,v in ipairs({{"Tự rèn","forge"},{"Rèn xen kẽ giáp","forgeArmor"},{"Mặc đồ tốt nhất","equip"},{"Bán đồ yếu","sell"},{"Tự cường hóa","enchant"}}) do toggle(gear,v[1],v[2]) end
section(gear,"THAO TÁC NHANH")
for _,v in ipairs({{"Rèn ngay","forgePass"},{"Mặc ngay","equipPass"},{"Bán ngay","sellPass"},{"Cường hóa ngay","enchantPass"}}) do local b=button(v[1],gear); local action=v[2]; connect(b.Activated,function() call(action) end) end
local element=button("Nguyên tố: Fire",gear)
connect(element.Activated,function()
    if not api then return end
    local list={"Fire","Ice","Thunder","Poison"}; local n=table.find(list,api.CONFIG.element) or 1
    api.set("element",list[n%4+1])
end)
local tower=page("Tháp băng")
label(tower,"Auto thử lượt tháp tiếp theo khi còn vé vượt mức giữ lại. Cần rebirth 2. Không mua vé; sau khi dừng giữa tháp, thoát bằng giao diện game hoặc tiếp tục lượt hiện tại.")
toggle(tower,"Chạy tháp liên tục","tower")
toggle(tower,"Nhận vé hằng ngày","dailyTicket")
input(tower,"Số vé giữ lại","towerKeep",0,0,999)
local towerOnce=button("Chạy / tiếp tục một lượt tháp",tower); connect(towerOnce.Activated,function() call("towerRun") end)
local progress=page("Phát triển")
section(progress,"NÂNG CẤP & PHẦN THƯỞNG")
for _,v in ipairs({{"Nâng cấp","upgrade"},{"Ưu tiên túi quặng","orePackFirst"},{"Nâng túi quặng","upgOrePack"},{"Nâng Train","upgTrain"},{"Nâng Luck","upgLuck"},{"Nhận Index","index"},{"Tái sinh","rebirth"},{"Quay / chọn chủng tộc","race"},{"Chống AFK","antiAfk"}}) do toggle(progress,v[1],v[2]) end
input(progress,"Coins giữ lại","coinKeep",0,0,1000000000000)
for _,v in ipairs({{"Nâng cấp ngay","upgradePass"},{"Nhận Index ngay","indexPass"},{"Tái sinh ngay","rebirthPass"},{"Chủng tộc ngay","racePass"}}) do local b=button(v[1],progress); local action=v[2]; connect(b.Activated,function() call(action) end) end
local p=page("Người chơi")
section(p,"DI CHUYỂN")
local jb=button("Nhảy vô hạn: TẮT",p); connect(jb.Activated,function() jump=not jump; jb.Text="Nhảy vô hạn: "..(jump and "BẬT" or "TẮT") end)
local nb=button("Xuyên tường: TẮT",p); connect(nb.Activated,function() noclip=not noclip; if not noclip then restoreCollision() end end)
local sp=make("TextBox",{Size=UDim2.new(1,0,0,40),BackgroundColor3=card,Text="16",PlaceholderText="Tốc độ chạy",TextColor3=white,Font=Enum.Font.Gotham,TextSize=14,ClearTextOnFocus=false},p); round(sp)
connect(sp.FocusLost,function()
    local n=tonumber(sp.Text); local h=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if not n or not h then return end
    n=math.clamp(n,1,250); speed=speed or {original=h.WalkSpeed}; speed.value=n; h.WalkSpeed=n; sp.Text=tostring(n)
end)
local reset=button("Khôi phục người chơi",p); connect(reset.Activated,resetPlayer)
connect(UIS.JumpRequest,function()
    local h=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if jump and h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
end)
connect(RS.Stepped,function()
    if noclip and player.Character then
        for _,part in ipairs(player.Character:GetDescendants()) do
            if part:IsA("BasePart") then if collision[part]==nil then collision[part]=part.CanCollide end; part.CanCollide=false end
        end
    end
end)
connect(player.CharacterAdded,function(character)
    table.clear(collision)
    local h=character:WaitForChild("Humanoid",10)
    if alive and h and speed then speed.original=h.WalkSpeed; h.WalkSpeed=speed.value end
end)
local dragging=false
local dragStart,startPos
connect(header.InputBegan,function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=true; dragStart=i.Position; startPos=root.Position end
end)
connect(UIS.InputChanged,function(i)
    if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
        local d=i.Position-dragStart; root.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
    end
end)
connect(UIS.InputEnded,function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=false end end)
local function destroy()
    alive=false
    if api then api.shutdown() end
    resetPlayer()
    for _,c in ipairs(connections) do c:Disconnect() end
    for _,t in pairs(activeTweens) do t:Cancel() end
    gui:Destroy()
end
_G.__LTF_HUB_V6={destroy=destroy}
lastViewport=nil
resize()
connect(close.Activated,destroy)
connect(UIS.InputBegan,function(i,processed)
    if not processed and i.KeyCode==Enum.KeyCode.RightControl then root.Visible=not root.Visible; open.Visible=not root.Visible end
end)
task.spawn(function()
    local ok,result=pcall(function()
        local old=_G.__LOOTTOFORGE_DBG
        if old and old.version==6 and old.ready then old.disableAll(); return old end
        return CreateBundledEngine()
    end)
    if not alive then if ok and result and result.shutdown then result.shutdown() end; return end
    if ok and type(result)=="table" and result.version==6 and result.ready then api=result; inform("Bộ xử lý sẵn sàng")
    else inform("Lỗi tải: "..tostring(result)); warn(loading) end
end)
task.spawn(function()
    while alive do
        resize()
        if api then
            for _,control in ipairs(controls) do
                local on=api.CONFIG[control.key]
                if control.last~=on then
                    control.last=on
                    animate(control.track,{BackgroundColor3=on and accent or Color3.fromRGB(59,58,70)})
                    animate(control.knob,{Position=UDim2.fromOffset(on and 19 or 3,3),BackgroundColor3=on and white or Color3.fromRGB(168,165,183)})
                end
            end
            element.Text="Nguyên tố: "..api.CONFIG.element
            local s=api.STATE
            connectionDot.BackgroundColor3=s.busy and green or accent
            metricValues[1].Text=compact(s.level); metricValues[2].Text=compact(s.rebirth); metricValues[3].Text=compact(s.coin)
            footer.Text=os.clock()<messageUntil and loading or ((s.busy and "ĐANG CHẠY · " or "SẴN SÀNG · ")..s.phase.."\n"..s.note)
            status.Text=string.format("Màn %s   •   Quặng %s   •   Vé %s\nFarm: %s lượt   /   Tháp: %s lượt thoát\n%s\n%s",s.stage,s.ore,s.tickets,s.runs,s.towerRuns,s.lastRun,s.lastTower)
        else footer.Text=loading end
        jb.Text="Nhảy vô hạn: "..(jump and "BẬT" or "TẮT")
        nb.Text="Xuyên tường: "..(noclip and "BẬT" or "TẮT")
        task.wait(.3)
    end
end)

end
local ok,err=xpcall(StartHub,function(message)
    return debug.traceback(tostring(message),2)
end)
if ok then
    bootLog.status="ui-ready"
    bootGui:Destroy()
    print("["..BUILD.."] UI ready")
else
    bootLog.status="error"; bootLog.error=tostring(err)
    warn("["..BUILD.."] "..tostring(err))
    bootText.Text="Đăng Răng To HUB · LỖI KHỞI ĐỘNG\n"..tostring(err):sub(1,550)
    bootText.TextColor3=Color3.fromRGB(255,170,180)
    pcall(function()
        if _G.__LTF_HUB_V6 and _G.__LTF_HUB_V6.destroy then _G.__LTF_HUB_V6.destroy() end
    end)
end
