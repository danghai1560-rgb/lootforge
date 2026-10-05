-- Đăng Răng To HUB v7 — GitHub RAW, bundled engine + UI.
-- Startup diagnostics stay visible if the UI fails to construct.
local BUILD="DRT-7.6-LUNA"
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
bootGui.Name="DangRangToStartup"; bootGui.ResetOnSpawn=false; bootGui.IgnoreGuiInset=true; bootGui.DisplayOrder=2147483647
local bootText=Instance.new("TextLabel")
bootText.Size=UDim2.new(.8,0,0,90); bootText.Position=UDim2.new(.1,0,0,25)
bootText.BackgroundColor3=Color3.fromRGB(29,24,42); bootText.TextColor3=Color3.fromRGB(231,220,255)
bootText.Font=Enum.Font.Gotham; bootText.TextSize=14; bootText.TextWrapped=true
bootText.Text="Đăng Răng To HUB · "..BUILD.."\nĐang dựng menu…"
bootText.Parent=bootGui; bootGui.Parent=UIHost
local function StartHub()
if game.PlaceId~=118805555015549 then error("Sai game +1 Loot To Forge",0) end
local function CreateBundledEngine()
-- Đăng Răng To HUB engine v7 Luna. Static review only; game integration requires live testing.
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
    autoWorldBoss = false,
    killaura = false,
    killauraRange = 100,
    pickupMode = "Nhanh",
    pickupFallback = true,
    pickupTimeout = 12,
    backTimeout = 5,
    runGap = 0.15,
    orePerForge = 0,
    raceProfile = "Train",
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

STATE.startedAt=os.clock()
STATE.log={}
STATE.pickupSecs=0; STATE.backSecs=0; STATE.runSecs=0; STATE.pickupRequests=0
local function note(t)
    STATE.note=tostring(t)
    STATE.log[#STATE.log+1]=string.format("[%ds] %s",math.floor(os.clock()-STATE.startedAt),STATE.note)
    if #STATE.log>80 then table.remove(STATE.log,1) end
end
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
    local cache=Workspace:FindFirstChild("OreCache")
    if not cache then return {} end
    local result,owners={},{}
    for _,pp in ipairs(cache:GetDescendants()) do
        if pp:IsA("ProximityPrompt") then
            local owner=pp:FindFirstAncestorOfClass("Model")
            if owner and not owner:IsDescendantOf(cache) then owner=nil end
            if not owner then
                local parent=pp.Parent
                while parent and parent~=cache do
                    if parent:IsA("BasePart") then owner=parent; break end
                    parent=parent.Parent
                end
            end
            owner=owner or pp
            local pos=dropPosition(pp)
            if pos and not owners[owner] then
                owners[owner]=true
                -- Disabled prompts remain drops until the item actually leaves
                -- OreCache. Enabled=false alone is not pickup confirmation.
                result[#result+1]={object=owner,prompt=pp,pos=pos}
            end
        end
    end
    for _,o in ipairs(cache:GetChildren()) do
        if not o:FindFirstChildWhichIsA("ProximityPrompt",true) then
            local pos=dropPosition(o)
            if pos then result[#result+1]={object=o,pos=pos} end
        end
    end
    return result
end
local function pickupNear(drop)
    checkpoint()
    if not drop.object.Parent then return end
    pin(drop.pos+Vector3.new(0,1.5,0)); pause(0.2)
    if drop.prompt and drop.prompt.Parent and drop.prompt.Enabled then
        local pp=drop.prompt
        local begun,err=pcall(function() pp:InputHoldBegin() end)
        if begun then
            local ok,waitError=pcall(function() pause(math.clamp(tonumber(pp.HoldDuration) or 0,0,10)+0.05) end)
            pcall(function() pp:InputHoldEnd() end)
            if not ok then error(waitError,0) end
        end
        if pp.Parent and pp.Enabled and type(fireproximityprompt)=="function" then
            local ok,fireError=pcall(function() fireproximityprompt(pp) end)
            if not ok then error("Pickup failed: "..tostring(fireError),0) end
        elseif not begun and type(fireproximityprompt)~="function" then
            error("Không kích hoạt được prompt: "..tostring(err),0)
        end
    end
    pause(0.12)
end
local function pickupFast(drops)
    checkpoint()
    if type(fireproximityprompt)~="function" then
        note("Executor thiếu nhặt nhanh; chọn Gần hoặc bật tự đến drop")
        return 0
    end
    local requests=0
    for _,drop in ipairs(drops) do
        checkpoint()
        local pp=drop.prompt
        if pp and pp.Parent and pp.Enabled then
            local ok,err=pcall(function() fireproximityprompt(pp) end)
            if ok then requests=requests+1 else note("Pickup: "..tostring(err)) end
        end
    end
    STATE.pickupRequests=STATE.pickupRequests+requests
    return requests
end
local function collectDrops()
    local started=os.clock()
    local lastProgress=started
    local emptySince=nil
    local seen=false
    local previousSet={}
    local confirmedSet={}
    local confirmed=0
    local fallback=false
    while os.clock()-started<CONFIG.pickupTimeout do
        checkpoint()
        local drops=stageDrops()
        local currentSet={}
        for _,drop in ipairs(drops) do currentSet[drop.object]=true end
        for object in pairs(previousSet) do
            if not currentSet[object] and not confirmedSet[object] then
                confirmedSet[object]=true; confirmed=confirmed+1; lastProgress=os.clock()
            end
        end
        previousSet=currentSet
        if #drops==0 then
            emptySince=emptySince or os.clock()
            if seen and confirmed>0 and os.clock()-emptySince>=.5 then break end
        else
            if not seen then seen=true; lastProgress=os.clock() end
            emptySince=nil
            STATE.phase=string.format("Nhặt · còn %d / đã biến mất %d",#drops,confirmed)
            if CONFIG.pickupMode=="Gần" or fallback then
                local r=hrp()
                if r then table.sort(drops,function(x,y) return (x.pos-r.Position).Magnitude<(y.pos-r.Position).Magnitude end) end
                for _,drop in ipairs(drops) do
                    if os.clock()-started>=CONFIG.pickupTimeout then break end
                    pickupNear(drop)
                end
            else
                pickupFast(drops)
            end
            if not fallback and CONFIG.pickupMode=="Nhanh" and CONFIG.pickupFallback and os.clock()-lastProgress>.8 then
                fallback=true
                note("Nhặt tại chỗ chưa được xác nhận; thử gần drop, không Back ngay")
            end
        end
        pause(.15)
    end
    STATE.pickupSecs=os.clock()-started
    STATE.pickupConfirmed=confirmed
    local remaining=#stageDrops()
    if confirmed==0 then
        STATE.pickupBlocked=true; CONFIG.auto=false
        local cache=Workspace:FindFirstChild("OreCache")
        local children=cache and #cache:GetChildren() or 0
        error(string.format("Chưa nhặt được drop: còn %d, OreCache %d mục. Đã dừng Auto và KHÔNG Back; chọn Gần hoặc nhặt bằng game.",remaining,children),0)
    end
    return remaining
end
local function countOre(d)
    local total=0
    for _,it in pairs((d and d.Backpack and d.Backpack.have) or {}) do
        if it.Type=="Ore" then total=total+(tonumber(it.Number) or 1) end
    end
    return total
end
local function returnStage(oreBefore,pos)
    unpin(); checkpoint()
    STATE.phase="Back · chờ game xác nhận"
    local started=os.clock()
    local initialRoot=hrp()
    local returnFrom=initialRoot and initialRoot.Position or pos
    exitBE:Fire(true)
    local got=0
    local left=false
    repeat
        pause(.15)
        local ok,snapshot=pcall(data)
        if not ok then STATE.backSecs=os.clock()-started; error("Back chưa được xác nhận: "..tostring(snapshot),0) end
        if snapshot then got=math.max(0,countOre(snapshot)-oreBefore) end
        local r=hrp()
        left=r and (r.Position-returnFrom).Magnitude>35 or false
        -- Ore gain is server confirmation. Moving home is only used if the
        -- client's Return did not move the character after committing the bag.
        if got>0 or (left and os.clock()-started>=.35) then break end
    until os.clock()-started>=CONFIG.backTimeout
    STATE.backSecs=os.clock()-started
    if got==0 and not left then error("Back chưa được xác nhận; đã dừng Auto để tránh vào màn chồng",0) end
    if not left then
        local home=trainPos(bestArea()) or Vector3.new(-50,4,-30)
        local root=hrp(); if root then root.CFrame=CFrame.new(home) end
        pause(.15)
    end
    return got
end
local farmStage
local function stageRun()
    STATE.pickupBlocked=false
    local runStart=os.clock()
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
    STATE.phase="Nhặt drop"
    local remaining=collectDrops()
    local got=returnStage(oreBefore,pos)
    refresh(false)
    STATE.ore=oreBefore+got
    STATE.runSecs=os.clock()-runStart
    STATE.runs=STATE.runs+1; STATE.oreGot=STATE.oreGot+got
    STATE.lastRun=string.format("Màn %d: +%d quặng · %.1fs · nhặt %.1fs / back %.1fs · còn %d drop",n,got,STATE.runSecs,STATE.pickupSecs,STATE.backSecs,remaining)
    if remaining>0 then note(STATE.lastRun.." (bag full or pickup rejected)") else note(STATE.lastRun) end
    pause(CONFIG.runGap)
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
			local budget=CONFIG.orePerForge>0 and math.max(4,CONFIG.orePerForge) or math.huge
            local amount=math.min(ores[i].n,math.max(0,budget-total))
            if amount>0 then
                list[ores[i].uuid]=amount; total=total+amount
                used[#used+1]=ores[i].id.."x"..amount
            end
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
    local weights=RACE_WEIGHT
    if CONFIG.raceProfile=="Luck" then weights={Train=40,Luck=100,Damage=6,Crit=5,Defence=2}
    elseif CONFIG.raceProfile=="Combat" then weights={Train=10,Luck=10,Damage=100,Crit=60,SkillDamage=50,Defence=40,SkillCD=10} end
	local s = 0
	local ok, boosts = pcall(function() return ClassHelper.GetClassBoosts(classId, level or 1) end)
	if ok and type(boosts) == "table" then
		for stat, v in pairs(boosts) do
			s = s + (weights[stat] or 1) * (tonumber(v) or 0)
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


local API={CONFIG=CONFIG,STATE=STATE,POS=POS,version=7,ready=false}
local actions={stageRun=stageRun,trainPass=trainPass,forgePass=forgePass,equipPass=equipPass,
    sellPass=sellPass,upgradePass=upgradePass,rebirthPass=rebirthPass,indexPass=indexPass,
    towerRun=towerRun,dailyTicketPass=dailyTicketPass,enchantPass=enchantPass,racePass=racePass,
    refresh=function() refresh(true) end,
    prepare=function() equipPass(); indexPass(); refresh(true) end,
    pickupCurrent=function()
        STATE.pickupBlocked=false; refresh(true)
        local before=STATE.ore; local root=hrp()
        if not root then error("Character unavailable",0) end
        local pos=root.Position
        collectDrops(); returnStage(before,pos); refresh(true)
        note("Đã nhặt lại tại màn hiện tại; +"..math.max(0,STATE.ore-before).." quặng")
    end}
local queue={}
local nextAllowed={}
local connections={}
local worldBossRemote=ReplicatedStorage:FindFirstChild("Remote")
worldBossRemote=worldBossRemote and worldBossRemote:FindFirstChild("WorldBoss")
local bossAvailable,bossSeen=false,nil
local bossAttempts,bossRetryAt,bossPendingUntil=0,0,0
local function liveWorldBoss()
    local folder=Workspace:FindFirstChild("EnemyFolder_Server")
    if not folder then return end
    for _,enemy in ipairs(folder:GetChildren()) do
        local id=enemy:GetAttribute("EnemyID")
        if enemy:IsA("Model") and type(id)=="string" and id:match("^WorldBoss_") and not enemy:GetAttribute("Dead") then return enemy end
    end
end
local function atWorldBoss()
    local boss,root=liveWorldBoss(),hrp()
    if not boss or not root then return false end
    local ok,pos=pcall(function() return boss:GetPivot().Position end)
    return ok and (pos-root.Position).Magnitude<180
end
local function bossEntryHold()
    return CONFIG.autoWorldBoss and bossAvailable and
        (atWorldBoss() or os.clock()<bossPendingUntil or bossAttempts<3)
end
local function worldBossEntryPass()
    if not CONFIG.autoWorldBoss or GEN~=_G.__LOOTTOFORGE then return end
    local boss=liveWorldBoss()
    if boss and boss~=bossSeen then
        bossSeen=boss;bossAvailable=true;bossAttempts=0;bossRetryAt=0
    end
    if not bossAvailable or atWorldBoss() or STATE.busy or dead() or plr:GetAttribute("Dungeoning") then return end
    if bossAttempts>=3 or os.clock()<bossRetryAt then return end
    local enter=worldBossRemote and worldBossRemote:FindFirstChild("IntoWorldBossFight")
    if not enter or not enter:IsA("RemoteEvent") then return end
    bossAttempts=bossAttempts+1;bossRetryAt=os.clock()+20;bossPendingUntil=os.clock()+10
    enter:FireServer()
    note("World Boss: đã gửi yêu cầu vào trận ("..bossAttempts.."/3)")
end
if worldBossRemote then
    for _,name in ipairs({"BossSpawnRE","BossDeadRE","BossEscapeRE"}) do
        local event=worldBossRemote:FindFirstChild(name)
        if event and event:IsA("RemoteEvent") then
            connections[#connections+1]=event.OnClientEvent:Connect(function()
                if GEN~=_G.__LOOTTOFORGE then return end
                bossAvailable=name=="BossSpawnRE"
                bossSeen=liveWorldBoss();bossAttempts=0;bossRetryAt=0;bossPendingUntil=0
            end)
        end
    end
end
local function nearbyWorldBosses()
    local root=hrp()
    local folder=Workspace:FindFirstChild("EnemyFolder_Server")
    local ids={}
    if not root or not folder then return ids end
    local radius=math.clamp(tonumber(CONFIG.killauraRange) or 100,10,150)
    for _,enemy in ipairs(folder:GetChildren()) do
        local id=enemy:GetAttribute("EnemyID")
        if enemy:IsA("Model") and type(id)=="string" and id:match("^WorldBoss_") and not enemy:GetAttribute("Dead") then
            local ok,pos=pcall(function() return enemy:GetPivot().Position end)
            if ok and (pos-root.Position).Magnitude<=radius then ids[#ids+1]=enemy.Name end
        end
    end
    return ids
end
local function bossAuraPass()
    if not CONFIG.killaura or GEN~=_G.__LOOTTOFORGE or dead() then return end
    local ids=nearbyWorldBosses()
    if #ids==0 then return end
    if STATE.bossAuraStatus~="direct-hit" then
        note("Killaura boss: đang thử EnemyHitBE với damage 1e30 như farm màn")
    end
    STATE.bossAuraStatus="direct-hit"
    for _,id in ipairs(ids) do
        if not CONFIG.killaura or GEN~=_G.__LOOTTOFORGE or dead() then return end
        hitBE:Fire(id,1e30,{Damage=1e30})
    end
end
local function killauraPass()
    if not CONFIG.killaura or GEN~=_G.__LOOTTOFORGE or dead() then return end
    local root=hrp()
    local folder=Workspace:FindFirstChild("EnemyFolder")
    if not root or not folder then return end
    local radius=math.clamp(tonumber(CONFIG.killauraRange) or 100,10,150)
    for _,enemy in ipairs(folder:GetChildren()) do
        if not CONFIG.killaura or GEN~=_G.__LOOTTOFORGE then return end
        if enemy:IsA("Model") and not enemy:GetAttribute("Dead") then
            local ok,pos=pcall(function() return enemy:GetPivot().Position end)
            if ok and math.abs(pos.Z-root.Position.Z)<80 and (pos-root.Position).Magnitude<=radius then
                pcall(function() hitBE:Fire(enemy.Name,1e30,{Damage=1e30}) end)
            end
        end
    end
end
function API.stop()
    CONFIG.auto=false; stopEpoch=stopEpoch+1; table.clear(queue); unpin(); farmStage=nil
end
function API.disableAll()
    API.stop()
    for k,v in pairs(CONFIG) do if type(v)=="boolean" and k~="pickupFallback" then CONFIG[k]=false end end
end
function API.set(k,v)
    if CONFIG[k]==nil then return false end
    if k=="killaura" then STATE.bossAuraStatus=nil end
    if k=="autoWorldBoss" then bossAttempts=0;bossRetryAt=0;bossPendingUntil=0 end
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
    if name=="stageRun" and not ok and not STATE.pickupBlocked and not plr:GetAttribute("Dungeoning") then pcall(function() exitBE:Fire(true) end) end
    STATE.busy=false; currentFeature=nil; automatic=false; STATE.phase="idle"
    if name=="towerRun" then nextAllowed[name]=os.clock()+5 end
    if not ok then
        note(tostring(err))
        if tostring(err)~="Stopped" then nextAllowed[name]=os.clock()+5 end
        if name=="stageRun" and tostring(err):find("Back chưa",1,true) then CONFIG.auto=false end
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
    while GEN==_G.__LOOTTOFORGE do
        local started=os.clock()
        local entryOK,entryError=pcall(worldBossEntryPass)
        if not entryOK then CONFIG.autoWorldBoss=false;note("Tự vào boss đã dừng: "..tostring(entryError)) end
        local ok,err=pcall(bossAuraPass)
        if not ok then
            CONFIG.killaura=false
            note("Killaura boss đã dừng: "..tostring(err))
        end
        task.wait(math.max(0.1,0.65-(os.clock()-started)))
    end
end)
local auraElapsed=0
connections[#connections+1]=RunService.Heartbeat:Connect(function(dt)
    auraElapsed=auraElapsed+dt
    if auraElapsed<0.25 then return end
    auraElapsed=0
    killauraPass()
end)
task.spawn(function()
    local support={{"forge","forgePass"},{"index","indexPass"},{"equip","equipPass"},
        {"enchant","enchantPass"},{"sell","sellPass"},{"upgrade","upgradePass"},
        {"rebirth","rebirthPass"},{"race","racePass"},{"dailyTicket","dailyTicketPass"}}
    local supportDue=0
    while GEN==_G.__LOOTTOFORGE do
        if #queue>0 then
            local job=table.remove(queue,1); run(job.name,job.args,nil,false)
        elseif CONFIG.auto and not bossEntryHold() then
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
local player=Players.LocalPlayer
if _G.__LTF_HUB_V6 then pcall(function() _G.__LTF_HUB_V6.destroy() end) end
local alive=true
local connections={}
local api,Luna,Window,lunaGui
local engineMessage="Đang khởi tạo bộ xử lý…"
local jump,noclip=false,false
local speed=nil
local collision={}
local function connect(signal,callback)
    local c=signal:Connect(callback); connections[#connections+1]=c; return c
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
local destroyed=false
local destroyLuna
local function destroy()
    if destroyed then return end
    destroyed=true; alive=false
    if api then api.shutdown() end
    resetPlayer()
    for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    if destroyLuna then pcall(destroyLuna,Luna) end
end
_G.__LTF_HUB_V6={destroy=destroy}
bootText.Text="Đăng Răng To HUB · V7 LUNA\nĐang tải giao diện Luna…"
local LUNA_URL="https://raw.githubusercontent.com/Nebula-Softworks/Luna-Interface-Suite/f714cba7b040b5100ad17cec1a4e5dc27c1f02a3/source.lua"
local previousConfirm
local env=type(getgenv)=="function" and getgenv() or _G
previousConfirm=env.ConfirmLuna; env.ConfirmLuna=true
local loaded,result=pcall(function()
    local source=game:HttpGet(LUNA_URL)
    -- This Hub uses session settings only. Luna calls SetFolder for every tab,
    -- even without a config tab; skip that filesystem initialization entirely.
    local configCount
    source,configCount=source:gsub("\n([ \t]*)SetFolder%(%)","\n%1-- DRT: disk config initialization disabled",1)
    if configCount~=1 then error("Luna config adapter không khớp phiên bản",0) end
    -- Track service connections in this pinned Luna revision so reloading the
    -- Hub also disconnects the library's keyboard and drag listeners.
    source=source:gsub("([%a_][%w_%.]*)%:Connect%(","OwnedLunaConnect(%1,")
    local count
    source,count=source:gsub("function Luna:Destroy%(%)", [[function Luna:Destroy()
        for _,connection in ipairs(OwnedLunaConnections) do pcall(function() connection:Disconnect() end) end
        table.clear(OwnedLunaConnections)]],1)
    if count~=1 then error("Luna lifecycle adapter không khớp phiên bản",0) end
    source=[[local OwnedLunaConnections={}
local function OwnedLunaConnect(signal,callback)
    local connection=signal:Connect(callback)
    OwnedLunaConnections[#OwnedLunaConnections+1]=connection
    return connection
end
]]..source
    local fn,err=loadstring(source,"LunaInterfacePinned")
    if not fn then error("Luna compile: "..tostring(err),0) end
    return fn()
end)
env.ConfirmLuna=previousConfirm
if not loaded then error("Không tải được Luna: "..tostring(result),0) end
if not alive then if result and result.Destroy then pcall(result.Destroy,result) end; return end
if type(result)~="table" or type(result.CreateWindow)~="function" then error("Luna không trả về thư viện hợp lệ",0) end
Luna=result
destroyLuna=Luna.Destroy
Luna.Destroy=function() destroy() end
local palettes={
    ["Tím ngọc"]={Color3.fromRGB(158,125,247),Color3.fromRGB(104,181,242),Color3.fromRGB(99,213,172)},
    ["Hoàng hôn"]={Color3.fromRGB(244,152,101),Color3.fromRGB(224,130,180),Color3.fromRGB(161,131,242)},
    ["Băng xanh"]={Color3.fromRGB(85,154,241),Color3.fromRGB(108,210,233),Color3.fromRGB(174,229,235)}
}
local function setPalette(name)
    local colors=palettes[name] or palettes["Tím ngọc"]
    Luna.ThemeGradient=ColorSequence.new({ColorSequenceKeypoint.new(0,colors[1]),ColorSequenceKeypoint.new(.5,colors[2]),ColorSequenceKeypoint.new(1,colors[3])})
    if lunaGui then local remote=lunaGui:FindFirstChild("ThemeRemote"); if remote then remote.Value=not remote.Value end end
end
setPalette("Tím ngọc")
Window=Luna:CreateWindow({
    Name="Đăng Răng To HUB",
    Subtitle="+1 Loot To Forge · V7.6",
    LogoID="6031097225",
    LoadingEnabled=false,
    LoadingTitle="Đăng Răng To HUB",
    LoadingSubtitle="Farm nhanh · Luna Interface",
    KeySystem=false,
    ConfigSettings={ConfigFolder="DangRangToHub"}
})
Window.Bind=Enum.KeyCode.RightControl
local function findLunaGui()
    local hosts={UIHost}
    pcall(function() local c=game:GetService("CoreGui"); hosts[#hosts+1]=c; local r=c:FindFirstChild("RobloxGui"); if r then hosts[#hosts+1]=r end end)
    for _,host in ipairs(hosts) do
        for _,child in ipairs(host:GetChildren()) do
            if child:IsA("ScreenGui") and child:FindFirstChild("SmartWindow") then
                local main=child.SmartWindow
                if main:FindFirstChild("Title") and main.Title.Title.Text=="Đăng Răng To HUB" then return child end
            end
        end
    end
end
lunaGui=findLunaGui()
if lunaGui then
    lunaGui.Name="DangRangToLunaV7"
    connect(lunaGui.Destroying,function() if not destroyed then destroy() end end)
end
local function notify(text)
    if not alive then return end
    engineMessage=tostring(text)
    pcall(function() Luna:Notification({Title="Đăng Răng To HUB",Content=engineMessage,Icon="info",ImageSource="Material"}) end)
end
local toggles={}
local synced=false
local function toggle(tab,title,key,description)
    local control
    control=tab:CreateToggle({Name=title,Description=description,CurrentValue=false,Callback=function(value)
        if synced then return end
        if not api then
            notify("Chờ bộ xử lý sẵn sàng")
            if control then control:UpdateState(false) end
            return
        end
        api.set(key,value)
    end})
    toggles[#toggles+1]={control=control,key=key}
    return control
end
local function action(name,...)
    if not api then notify("Bộ xử lý chưa sẵn sàng"); return end
    local ok,err=api.call(name,...)
    if not ok then notify(err or "Đang có tác vụ chạy") end
end
local function button(tab,title,callback,description)
    return tab:CreateButton({Name=title,Description=description,Callback=callback})
end
local function slider(tab,title,key,min,max,default,description)
    local control
    control=tab:CreateSlider({Name=title,Description=description,Range={min,max},Increment=1,CurrentValue=default,Callback=function(value)
        if not api then notify("Chờ bộ xử lý sẵn sàng"); return end
        api.set(key,math.clamp(math.floor(tonumber(value) or default),min,max))
    end})
    return control
end
local function dropdown(tab,title,key,options,default,description)
    return tab:CreateDropdown({Name=title,Description=description,Options=options,CurrentOption={default},MultipleOptions=false,Callback=function(values)
        if not api then notify("Chờ bộ xử lý sẵn sàng"); return end
        local value=type(values)=="table" and values[1] or values
        if value then api.set(key,value) end
    end})
end
local function tab(name,icon)
    return Window:CreateTab({Name=name,Icon=icon,ImageSource="Material",ShowTitle=true})
end
local overview=tab("Tổng quan","dashboard")
overview:CreateParagraph({Title="Đăng Răng To HUB",Text="Farm màn → nhặt nhanh → back → vào lại đúng màn. Bật Farm / Tháp / Luyện để tự bật Auto tổng."})
local live=overview:CreateParagraph({Title="TRẠNG THÁI",Text=engineMessage})
local stats=overview:CreateParagraph({Title="PHIÊN CHẠY",Text="Đang chờ dữ liệu…"})
overview:CreateSection("Điều khiển")
toggle(overview,"Auto tổng","auto","Tắt để ngừng tác vụ và giữ các lựa chọn đã đặt.")
button(overview,"Dừng & tắt mọi chức năng",function() if api then api.disableAll() end; resetPlayer(); notify("Đã yêu cầu dừng toàn bộ") end)
button(overview,"Mặc đồ tốt + nhận Index",function() action("prepare") end,"Chạy khi bộ xử lý rảnh.")
button(overview,"Làm mới dữ liệu",function() action("refresh") end)
local farm=tab("Farm màn","sports_esports")
farm:CreateSection("Killaura thủ công")
toggle(farm,"Bật Killaura","killaura","Dùng EnemyHitBE với damage 1e30 giống farm màn cho quái và World Boss trong phạm vi. Boss: đang thử nghiệm, chưa xác nhận một hit.")
slider(farm,"Phạm vi Killaura","killauraRange",10,150,100)
farm:CreateSection("Vòng farm")
toggle(farm,"Farm màn liên tục","farm","Giữ đúng màn đã chọn; không luyện xen giữa lượt farm.")
slider(farm,"Màn farm · 0 = sâu nhất đã vượt","stage",0,27,0)
dropdown(farm,"Cách nhặt drop","pickupMode",{"Nhanh","Gần"},"Nhanh","Nhanh: kích hoạt hàng loạt tại chỗ. Gần: đến từng drop khi game yêu cầu khoảng cách.")
toggle(farm,"Tự đến drop nếu nhặt nhanh thất bại","pickupFallback","Mặc định bật: chỉ đến drop khi nhặt tại chỗ chưa được xác nhận. Không Back nếu chưa nhặt được gì.")
slider(farm,"Giới hạn nhặt · giây","pickupTimeout",4,30,12)
slider(farm,"Giới hạn chờ Back · giây","backTimeout",2,12,5)
button(farm,"Farm một lượt",function() action("stageRun") end)
button(farm,"Nhặt lại drop tại màn hiện tại",function() action("pickupCurrent") end,"Không vào màn mới; thử nhặt và chỉ Back khi có drop biến mất.")
farm:CreateSection("Nhịp farm")
farm:CreateInput({Name="Nghỉ giữa lượt · giây",CurrentValue="0.15",PlaceholderText="0.15",Numeric=true,Enter=false,Callback=function(value)
    local n=tonumber(value); if api and n then api.set("runGap",math.clamp(n,0,5)) end
end})
local training=tab("Power & Luck","bolt")
training:CreateParagraph({Title="Tăng bằng cơ chế game",Text="Train tốt nhất + trang bị tốt + nâng cấp + chủng tộc. Các mục này không ép chỉ số server hay bảo đảm đồ hiếm."})
training:CreateSection("Luyện sức mạnh")
toggle(training,"Tự luyện khi không farm màn","train")
slider(training,"Thời gian mỗi lượt luyện","trainSecs",5,120,20)
button(training,"Luyện một lượt",function() action("trainPass",api and api.CONFIG.trainSecs or 20) end)
training:CreateSection("Nâng cấp")
for _,v in ipairs({{"Tự mua nâng cấp","upgrade"},{"Ưu tiên túi quặng","orePackFirst"},{"Nâng túi quặng","upgOrePack"},{"Nâng Train","upgTrain"},{"Nâng Luck rèn","upgLuck"}}) do toggle(training,v[1],v[2]) end
training:CreateInput({Name="Coins muốn giữ",CurrentValue="0",Numeric=true,Enter=false,Callback=function(value)
    local n=tonumber(value); if api and n then api.set("coinKeep",math.max(0,math.floor(n))) end
end})
button(training,"Nâng cấp ngay",function() action("upgradePass") end)
local gear=tab("Rèn & trang bị","construction")
gear:CreateSection("Tự động")
for _,v in ipairs({{"Tự rèn","forge"},{"Rèn xen kẽ giáp","forgeArmor"},{"Mặc đồ tốt nhất","equip"},{"Bán đồ yếu","sell"},{"Cường hóa đồ đang mặc","enchant"}}) do toggle(gear,v[1],v[2]) end
slider(gear,"Quặng mỗi lần rèn · 0 = toàn bộ","orePerForge",0,100,0,"1–3 được xử lý thành tối thiểu 4. Tối đa 4 loại quặng mỗi lượt.")
dropdown(gear,"Nguyên tố ưu tiên","element",{"Fire","Ice","Thunder","Poison"},"Fire","Ưu tiên cấp đá trước, nguyên tố sau.")
gear:CreateSection("Thao tác nhanh")
for _,v in ipairs({{"Rèn ngay","forgePass"},{"Mặc ngay","equipPass"},{"Bán ngay","sellPass"},{"Cường hóa ngay","enchantPass"}}) do local name=v[2]; button(gear,v[1],function() action(name) end) end
local tower=tab("Tháp băng","ac_unit")
tower:CreateSection("World Boss")
toggle(tower,"Tự vào khi World Boss xuất hiện","autoWorldBoss","Bật riêng với Auto tổng. Theo dõi boss xuất hiện hoặc boss đã tải; chờ lượt farm/tháp hiện tại xong rồi gửi yêu cầu vào. Tối đa 3 lần mỗi đợt boss.")
tower:CreateSection("Tháp băng")
tower:CreateParagraph({Title="Lặp theo số vé",Text="Cần rebirth 2. Hết lượt sẽ kiểm tra vé để chạy tiếp. Nếu bật cả farm và tháp, các lượt sẽ chạy lần lượt."})
toggle(tower,"Chạy tháp liên tục","tower")
toggle(tower,"Nhận vé hằng ngày","dailyTicket")
slider(tower,"Vé muốn giữ","towerKeep",0,100,0)
button(tower,"Chạy / tiếp tục một lượt",function() action("towerRun") end)
button(tower,"Nhận vé hằng ngày ngay",function() action("dailyTicketPass") end)
local progress=tab("Chủng tộc & Index","auto_awesome")
toggle(progress,"Quay / chọn chủng tộc","race")
dropdown(progress,"Ưu tiên chủng tộc","raceProfile",{"Train","Luck","Combat"},"Train","Chỉ đánh giá bonus thật từ dữ liệu game; không tăng tỉ lệ quay.")
button(progress,"Quay / chọn ngay",function() action("racePass") end)
progress:CreateSection("Phần thưởng")
toggle(progress,"Nhận Index","index")
toggle(progress,"Tự tái sinh","rebirth")
button(progress,"Nhận Index ngay",function() action("indexPass") end)
button(progress,"Tái sinh ngay",function() action("rebirthPass") end)
local movement=tab("Người chơi","person")
toggle(movement,"Chống AFK","antiAfk")
local jumpToggle=movement:CreateToggle({Name="Nhảy vô hạn",CurrentValue=false,Callback=function(value) if not synced then jump=value end end})
local clipToggle=movement:CreateToggle({Name="Xuyên tường",CurrentValue=false,Callback=function(value) if synced then return end; noclip=value; if not value then restoreCollision() end end})
movement:CreateSlider({Name="Tốc độ chạy",Range={1,250},Increment=1,CurrentValue=16,Callback=function(value)
    local h=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if h then speed=speed or {original=h.WalkSpeed}; speed.value=math.clamp(value,1,250); h.WalkSpeed=speed.value end
end})
button(movement,"Khôi phục người chơi",resetPlayer)
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
local settings=tab("Giao diện & nhật ký","settings")
Window.Settings=settings
settings:CreateDropdown({Name="Màu giao diện",Options={"Tím ngọc","Hoàng hôn","Băng xanh"},CurrentOption={"Tím ngọc"},MultipleOptions=false,Callback=function(values)
    local value=type(values)=="table" and values[1] or values; setPalette(value)
end})
settings:CreateParagraph({Title="Ẩn / mở",Text="Nút × của Luna ẩn cửa sổ, tác vụ vẫn chạy. Right Ctrl hoặc nút mở trên mobile hiện lại. Đóng hoàn toàn bằng nút bên dưới."})
local logView=settings:CreateParagraph({Title="NHẬT KÝ",Text="Chưa có tác vụ"})
button(settings,"Sao chép nhật ký",function()
    if type(setclipboard)~="function" then notify("Executor không hỗ trợ sao chép"); return end
    local text="Đăng Răng To HUB V7\n"..(api and table.concat(api.STATE.log,"\n") or engineMessage)
    setclipboard(text); notify("Đã sao chép nhật ký")
end)
button(settings,"Đóng Hub & dừng bộ xử lý",destroy)
settings:CreateParagraph({Title="Nguồn giao diện",Text="Luna Interface Suite · Nebula Softworks. Phiên bản được cố định để tránh đổi API ngoài ý muốn."})
overview:Activate()
task.spawn(function()
    local ok,result=pcall(CreateBundledEngine)
    if not alive then if ok and result and result.shutdown then result.shutdown() end; return end
    if ok and type(result)=="table" and result.version==7 and result.ready then
        api=result; notify("Bộ xử lý V7 sẵn sàng. Bật Farm hoặc Tháp để chạy.")
    else
        engineMessage="Lỗi bộ xử lý: "..tostring(result); notify(engineMessage); warn(engineMessage)
    end
end)
local function short(n)
    n=tonumber(n) or 0
    for _,v in ipairs({{1e12,"T"},{1e9,"B"},{1e6,"M"},{1e3,"K"}}) do if math.abs(n)>=v[1] then return string.format("%.1f%s",n/v[1],v[2]) end end
    return tostring(math.floor(n))
end
task.spawn(function()
    local lastLive,lastStats,lastLog
    while alive do
        local ok,err=pcall(function()
            synced=true
            if api then
                for _,entry in ipairs(toggles) do
                    local value=api.CONFIG[entry.key]
                    if entry.control.CurrentValue~=value then entry.control:UpdateState(value) end
                end
            end
            if jumpToggle.CurrentValue~=jump then jumpToggle:UpdateState(jump) end
            if clipToggle.CurrentValue~=noclip then clipToggle:UpdateState(noclip) end
            synced=false
            local liveText=engineMessage
            local statsText="Đang chờ dữ liệu…"
            local logText=engineMessage
            if api then
                local s=api.STATE
                liveText=(s.busy and "ĐANG CHẠY · " or "SẴN SÀNG · ")..s.phase.."\n"..s.note
                local minutes=math.max((os.clock()-s.startedAt)/60,1/60)
                statsText=string.format("Level %s  ·  Rebirth %s  ·  Coins %s\nQuặng %s  ·  Vé %s  ·  Đá %s\nFarm %d lượt  ·  +%d quặng  ·  %.1f quặng/phút\nNhặt %.2fs  ·  Back %.2fs  ·  Tháp thoát %d lượt\n%s",short(s.level),s.rebirth,short(s.coin),s.ore,s.tickets,s.stones,s.runs,s.oreGot,s.oreGot/minutes,s.pickupSecs,s.backSecs,s.towerRuns,s.lastRun)
                local recent={}
                for i=math.max(1,#s.log-5),#s.log do recent[#recent+1]=s.log[i] end
                logText=#recent>0 and table.concat(recent,"\n") or "Chưa có tác vụ"
            end
            if liveText~=lastLive then live:Set({Text=liveText}); lastLive=liveText end
            if statsText~=lastStats then stats:Set({Text=statsText}); lastStats=statsText end
            if logText~=lastLog then logView:Set({Text=logText}); lastLog=logText end
        end)
        synced=false
        if not ok then warn("Hub display: "..tostring(err)) end
        task.wait(.5)
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




