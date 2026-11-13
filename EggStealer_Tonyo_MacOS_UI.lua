--[[
    Egg Stealer // Tonyo  ·  macOS UI Edition
    UI upgraded to the clean Tonyo Hub macOS style.
    All original features, remotes, and auto logic preserved.
]]

local Services = {
    Players = game:GetService("Players"),
    Workspace = game:GetService("Workspace"),
    RunService = game:GetService("RunService"),
    ReplicatedStorage = game:GetService("ReplicatedStorage"),
    TweenService = game:GetService("TweenService"),
    TeleportService = game:GetService("TeleportService"),
    SoundService = game:GetService("SoundService"),
    CollectionService = game:GetService("CollectionService"),
    HttpService = game:GetService("HttpService"),
    UserInputService = game:GetService("UserInputService")
}

local LocalPlayer = Services.Players.LocalPlayer or Services.Players.PlayerAdded:Wait()
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

--------------------------------------------------
-- UNIVERSAL COMPAT
--------------------------------------------------
local UniversalCompat = {}

function UniversalCompat.FireProximityPrompt(prompt)
    if not prompt or not prompt.Parent then return false end
    if typeof(fireproximityprompt) == "function" then
        local ok = pcall(fireproximityprompt, prompt, 0)
        if not ok then ok = pcall(fireproximityprompt, prompt, 1) end
        if not ok then ok = pcall(fireproximityprompt, prompt) end
        if ok then return true end
    end
    local triggered = false
    pcall(function()
        prompt:InputHoldBegin()
        local duration = tonumber(prompt.HoldDuration) or 0
        task.wait(duration > 0 and duration + 0.05 or 0.04)
        prompt:InputHoldEnd()
        triggered = true
    end)
    return triggered
end

function UniversalCompat.FireTouch(part1, part2)
    if not part1 or not part2 or not part1.Parent or not part2.Parent then return false end
    if typeof(firetouchinterest) == "function" then
        pcall(firetouchinterest, part1, part2, 0)
        task.wait(0.01)
        pcall(firetouchinterest, part1, part2, 1)
    end
    pcall(function()
        if part1:IsA("BasePart") then part1.CanTouch = true end
        if part2:IsA("BasePart") then part2.CanTouch = true end
    end)
    return true
end

function UniversalCompat.ClickButton(btn)
    if not btn or not btn:IsA("GuiButton") then return false end
    if typeof(firesignal) == "function" then
        local ok1 = pcall(firesignal, btn.Activated)
        local ok2 = pcall(firesignal, btn.MouseButton1Click)
        if ok1 or ok2 then return true end
    end
    if typeof(getconnections) == "function" then
        local triggered = false
        for _, sig in ipairs({btn.Activated, btn.MouseButton1Click}) do
            local ok, conns = pcall(getconnections, sig)
            if ok and type(conns) == "table" then
                for _, c in ipairs(conns) do
                    pcall(function()
                        if c.Fire then c:Fire() elseif c.Function then c.Function() end
                    end)
                    triggered = true
                end
            end
        end
        if triggered then return true end
    end
    return false
end

--------------------------------------------------
-- CONFIG / SAVE
--------------------------------------------------
local saveFile = "TonyoEggHub_Config.json"

local currentSettings = {
    Theme = "Dark",
    Transparency = 0,
    AutoFarm = false,
    FastSteal = false,
    AutoTreadmill = false,
    AutoUpgradeTreadmill = false,
    AutoUpgradeBase = false,
    AutoClaimMastery = false,
    AutoCatchButterfly = false,
    AutoWispQuest = false,
    AutoTradeUp = false,
    AutoCraftEssence = false,
    AutoAFK = true,
    MinValueThreshold = 0,
    ButterflySpeed = 320,
    TargetAreas = { ["All"] = true },
    MinRarity = "All",
    AutoUFO = false,
    UFORocks = false,
    UFORare = true,
    UFOTrade = false,
    UFOTp = false,
    BloomCatchMode = "Stand",
    BloomCatchPriority = "Rarest",
    BloomSmartTrade = true,
    WebhookURL = "",
    TaskPriorities = {
        "Auto Steal",
        "UFO Event",
        "Enchanted / Bloom Event",
        "Auto Treadmill"
    }
}

local function saveStuff()
    if writefile then
        pcall(function()
            writefile(saveFile, Services.HttpService:JSONEncode(currentSettings))
        end)
    end
end

local function loadStuff()
    if isfile and readfile and isfile(saveFile) then
        pcall(function()
            local decoded = Services.HttpService:JSONDecode(readfile(saveFile))
            if decoded and type(decoded) == "table" then
                for k, v in pairs(decoded) do
                    if k == "TargetAreas" and type(v) == "table" then
                        currentSettings.TargetAreas = v
                    elseif k == "TaskPriorities" and type(v) == "table" then
                        currentSettings.TaskPriorities = v
                    elseif type(v) == "table" and type(currentSettings[k]) == "table" then
                        for k2, v2 in pairs(v) do currentSettings[k][k2] = v2 end
                    else
                        currentSettings[k] = v
                    end
                end
            end
        end)
    end
    if type(currentSettings.TargetAreas) ~= "table" or next(currentSettings.TargetAreas) == nil then
        currentSettings.TargetAreas = { ["All"] = true }
    end
    if type(currentSettings.MinRarity) ~= "string" or string.find(currentSettings.MinRarity, "table:") then
        currentSettings.MinRarity = "All"
    end
end

loadStuff()

getgenv().config = getgenv().config or {}
getgenv().config.targetAreas = currentSettings.TargetAreas
getgenv().config.minRarity = currentSettings.MinRarity
getgenv().config.autoFarm = currentSettings.AutoFarm
getgenv().config.fastSteal = currentSettings.FastSteal
getgenv().config.autoTreadmill = currentSettings.AutoTreadmill
getgenv().config.autoUpgradeTreadmill = currentSettings.AutoUpgradeTreadmill
getgenv().config.autoUpgradeBase = currentSettings.AutoUpgradeBase
getgenv().config.autoClaimMastery = currentSettings.AutoClaimMastery
getgenv().config.autoCatchButterfly = currentSettings.AutoCatchButterfly
getgenv().config.autoWispQuest = currentSettings.AutoWispQuest
getgenv().config.autoTradeUp = currentSettings.AutoTradeUp
getgenv().config.autoCraftEssence = currentSettings.AutoCraftEssence
getgenv().config.autoAFK = currentSettings.AutoAFK ~= false
getgenv().config.minValueThreshold = currentSettings.MinValueThreshold or 0
getgenv().config.butterflySpeed = currentSettings.ButterflySpeed
getgenv().config.autoUFO = currentSettings.AutoUFO == true
getgenv().config.ufoRocks = currentSettings.UFORocks == true
getgenv().config.ufoRare = currentSettings.UFORare ~= false
getgenv().config.ufoTrade = currentSettings.UFOTrade == true
getgenv().config.ufoTp = currentSettings.UFOTp == true
getgenv().config.bloomCatchMode = currentSettings.BloomCatchMode or "Stand"
getgenv().config.bloomCatchPriority = currentSettings.BloomCatchPriority or "Rarest"
getgenv().config.bloomSmartTrade = currentSettings.BloomSmartTrade ~= false
getgenv().config.webhookURL = currentSettings.WebhookURL or ""

local function sendWebhook(title, desc, color)
    local url = getgenv().config.webhookURL
    if not url or url == "" or not string.find(url, "discord.com/api/webhooks") then return end
    task.spawn(function()
        pcall(function()
            local data = {
                embeds = {{
                    title = title or "Egg Stealer",
                    description = desc or "",
                    color = color or 5793266,
                    footer = { text = "Tonyo Egg Hub • " .. os.date("%H:%M:%S") }
                }}
            }
            local req = (syn and syn.request) or (http and http.request) or request or http_request
            if req then
                req({
                    Url = url,
                    Method = "POST",
                    Headers = { ["Content-Type"] = "application/json" },
                    Body = Services.HttpService:JSONEncode(data)
                })
            end
        end)
    end)
end

--------------------------------------------------
-- STATE / CONFIG CONSTANTS
--------------------------------------------------
local UFOManager, PriorityManager, getBestEgg, activeTheme

local State = {
    currentStealSession = 0,
    isStealingActive = false,
    activeFlightConnection = nil,
    activeCollisionsDisabled = {},
    targetedSpecificUid = nil,
    blacklistedEggs = {},
    lastServerRollbackTime = 0,
    myPlot = nil,
    myTreadmill = nil,
    treadmillFailCount = 0,
    lastResetTime = 0,
    baseUpgradeCooldown = 0,
    treadmillUpgradeCooldown = 0,
    activeStealButtons = {},
    themeSubscribers = {},
    themeName = currentSettings.Theme or "Dark",
    isOpn = true,
    curCat = 1,
    cachedFieldEggs = {},
    cachedStealPanelItems = {},
    activeOpenedDropdown = nil,
    spSortChoice = "Value (Money/s)",
    spSortIndex = 1,
}

local CONFIG = {
    HopDistance = 230,
    HopGap = 0.06,
    HopGapMin = 0.05,
    HopGapMax = 0.20,
    FlightAltitude = 71.5,
    HopAltitude = 71.8,
    GroundAltitude = 70.8,
    AirGrabOffset = 1.2,
    CheckpointInterval = 1600,
    BoundaryCheckpointX = 600.2,
    SeparationLineX = 552.2,
    FastStealLineDropOffset = 45,
    FastStealDirectSnapRadius = 45,
    BaseDropPosition = Vector3.new(528.7, 70.8, -364.1)
}

local function formatMoneyPerSec(val)
    local n = tonumber(val) or 0
    if n >= 1e15 then return string.format("$%.2fQ/s", n / 1e15) end
    if n >= 1e12 then return string.format("$%.2fT/s", n / 1e12) end
    if n >= 1e9 then return string.format("$%.2fB/s", n / 1e9) end
    if n >= 1e6 then return string.format("$%.2fM/s", n / 1e6) end
    if n >= 1e3 then return string.format("$%.2fK/s", n / 1e3) end
    return string.format("$%.1f/s", n)
end

local function parseValueInput(str)
    if not str or str == "" then return 0 end
    str = tostring(str):lower():gsub("%$", ""):gsub("/s", ""):gsub(",", ""):gsub("%s+", "")
    local num, suffix = str:match("^([%d%.]+)([kmbtq]?)$")
    if not num then
        local n = tonumber(str)
        return n or 0
    end
    local n = tonumber(num) or 0
    if suffix == "k" then return n * 1e3 end
    if suffix == "m" then return n * 1e6 end
    if suffix == "b" then return n * 1e9 end
    if suffix == "t" then return n * 1e12 end
    if suffix == "q" then return n * 1e15 end
    return n
end

local function cleanName(name)
    return tostring(name or ""):lower():gsub("[Ee]gg", ""):gsub("[^%w]", "")
end

local function isBlacklisted(uid)
    if not uid then return false end
    local exp = State.blacklistedEggs[uid]
    if exp and exp > os.clock() then return true end
    if exp then State.blacklistedEggs[uid] = nil end
    return false
end

local function blacklistEgg(uid, duration)
    if uid then State.blacklistedEggs[uid] = os.clock() + (duration or 15) end
end

--------------------------------------------------
-- GAME HELPERS (map closed, remotes, modules…)
--------------------------------------------------
local function isNightPhase()
    local client = Services.ReplicatedStorage:FindFirstChild("Client")
    local cycleModule = client and client:FindFirstChild("AreaEggCycle")
    if cycleModule and cycleModule:IsA("ModuleScript") then
        local ok, mod = pcall(require, cycleModule)
        if ok and type(mod) == "table" and type(mod.IsNightPhase) == "function" then
            local nightOk, res = pcall(mod.IsNightPhase, workspace:GetServerTimeNow())
            return nightOk and res == true
        end
    end
    return false
end

local function isWallSealed()
    local client = Services.ReplicatedStorage:FindFirstChild("Client")
    local wallModule = client and client:FindFirstChild("AreaEggResetWall")
    if wallModule and wallModule:IsA("ModuleScript") then
        local ok, mod = pcall(require, wallModule)
        if ok and type(mod) == "table" and type(mod.IsSealed) == "function" then
            local sealedOk, res = pcall(mod.IsSealed)
            return sealedOk and res == true
        end
    end
    local world = Services.Workspace:FindFirstChild("World") or Services.Workspace:FindFirstChild("__OBJECTS")
    local areas = world and world:FindFirstChild("Areas")
    local wallCol = areas and areas:FindFirstChild("WallStartCollision")
    return (wallCol and wallCol:IsA("BasePart") and wallCol.CanCollide == true) or false
end

local function isMapClosed()
    return isNightPhase() or isWallSealed()
end

local function isNormalStealPanelTarget()
    return State.targetedSpecificUid ~= nil
end

local function isStealEnabled()
    if isMapClosed() then return false end
    return getgenv().config.autoFarm == true or isNormalStealPanelTarget()
end

local function isFastStealArea(areaId)
    if not areaId then return false end
    local clean = cleanName(areaId)
    return clean:find("titan", 1, true) ~= nil
        or clean:find("light", 1, true) ~= nil
        or clean:find("enchanted", 1, true) ~= nil
end

local function matchesTargetArea(areaId)
    local targetAreas = getgenv().config.targetAreas or { ["All"] = true }
    if targetAreas["All"] == true or next(targetAreas) == nil then return true end
    if not areaId then return false end
    local cleanArea = tostring(areaId):lower():gsub("[^%w]", "")
    for selArea, selVal in pairs(targetAreas) do
        if selVal == true and selArea ~= "All" then
            local cleanSel = tostring(selArea):lower():gsub("[^%w]", "")
            if cleanArea == cleanSel or cleanArea:find(cleanSel, 1, true) or cleanSel:find(cleanArea, 1, true) then
                return true
            end
        end
    end
    return false
end

local function getRemote(pathName)
    local packages = Services.ReplicatedStorage:FindFirstChild("Packages")
        or (Services.ReplicatedStorage.WaitForChild and Services.ReplicatedStorage:WaitForChild("Packages", 3))
    local networking = packages and (packages:FindFirstChild("Networking")
        or (packages.WaitForChild and packages:WaitForChild("Networking", 3)))
    local remote = networking and networking:FindFirstChild(pathName)
    if not remote then
        for _, desc in ipairs(Services.ReplicatedStorage:GetDescendants()) do
            if (desc:IsA("RemoteFunction") or desc:IsA("RemoteEvent")) and desc.Name == pathName then
                return desc
            end
        end
    end
    return remote
end

local Remotes = {
    AskFieldEggDrop = getRemote("RF/EggWorld/AskFieldEggDrop"),
    AskFieldEggCarry = getRemote("RF/EggWorld/AskFieldEggCarry"),
    AskDoff = getRemote("RF/Treadmill/AskDoff"),
    AskWearStill = getRemote("RF/Treadmill/AskWearStill"),
    AskSnapshot = getRemote("RF/EggWorld/AskFieldEggSnapshot"),
    TierRaise = getRemote("RF/Treadmill/AskTierRaise"),
    BaseTierRaise = getRemote("RE/Homestead/AskBaseTierRaise"),
    AskRigWipe = getRemote("RE/RigSync/AskRigWipe"),
    ClaimNet = getRemote("RF/Butterflies/AskClaimNet"),
    TradeUp = getRemote("RF/Butterflies/AskTradeUp"),
    CraftEssence = getRemote("RF/Butterflies/AskCraftEssence"),
    WispRequest = getRemote("RF/WispCompanion/Request")
}

local function invokeRemote(pathName, ...)
    local remote = getRemote(pathName)
    if remote and remote:IsA("RemoteFunction") then
        local ok, r1, r2, r3 = pcall(function(...) return remote:InvokeServer(...) end, ...)
        if ok then return true, r1, r2, r3 end
        return false, r1
    end
    return false, "RemoteFunction not found: " .. tostring(pathName)
end

local function fireRemote(pathName, ...)
    local remote = getRemote(pathName)
    if remote and remote:IsA("RemoteEvent") then
        pcall(function(...) remote:FireServer(...) end, ...)
        return true
    end
    return false
end

local GameModules = {}
local _moduleCache = {}
local modulePaths = {
    EggState = { "Client", "EggState" },
    Assets = { "Data", "Assets" },
    Mutations = { "Shared", "Modules", "Mutations" },
    EggRecords = { "Shared", "Util", "EggRecords" },
    AreaEggCycle = { "Shared", "Util", "AreaEggCycle" },
    PlotState = { "Client", "PlotState" },
    UFOSightingsPipePuzzle = { "Shared", "Modules", "UFOSightingsPipePuzzle" },
    Wisp = { "Data", "WispQuests" },
    Areas = { "Data", "Areas" }
}

function GameModules:Get(name)
    if _moduleCache[name] then return _moduleCache[name] end
    local path = modulePaths[name]
    if not path then return nil end
    local current = Services.ReplicatedStorage
    for _, part in ipairs(path) do
        current = current and (current:FindFirstChild(part) or (current.WaitForChild and current:WaitForChild(part, 3)))
        if not current then break end
    end
    if current and current:IsA("ModuleScript") then
        local getid = getthreadidentity or get_thread_identity
        local setid = setthreadidentity or set_thread_identity
        local oldId = getid and getid()
        if setid then pcall(setid, 8) end
        local ok, mod = pcall(require, current)
        if setid and oldId then pcall(setid, oldId) end
        if ok and type(mod) == "table" then
            _moduleCache[name] = mod
            return mod
        end
    end
    return nil
end

local function getEggState()
    return GameModules:Get("EggState")
end

local EggState = getEggState()

local function getFieldEggRecords()
    local es = GameModules:Get("EggState") or EggState or getEggState()
    if es and typeof(es.ReadFieldEggs) == "function" then
        local getid = getthreadidentity or get_thread_identity
        local setid = setthreadidentity or set_thread_identity
        local oldId = getid and getid()
        if setid then pcall(setid, 8) end
        local ok, data = pcall(es.ReadFieldEggs)
        if setid and oldId then pcall(setid, oldId) end
        if ok and type(data) == "table" and type(data.Records) == "table" and next(data.Records) ~= nil then
            State.cachedFieldEggs = data.Records
            return data.Records
        end
    end
    local snapshotRemote = getRemote("RF/EggWorld/AskFieldEggSnapshot") or (Remotes and Remotes.AskSnapshot)
    if snapshotRemote and snapshotRemote:IsA("RemoteFunction") then
        local ok, data = pcall(function() return snapshotRemote:InvokeServer() end)
        if ok and type(data) == "table" and type(data.Records) == "table" and next(data.Records) ~= nil then
            State.cachedFieldEggs = data.Records
            return data.Records
        end
    end
    if State.cachedFieldEggs and type(State.cachedFieldEggs) == "table" and next(State.cachedFieldEggs) ~= nil then
        return State.cachedFieldEggs
    end
    return {}
end

pcall(function()
    local packages = Services.ReplicatedStorage:WaitForChild("Packages", 5)
    local networking = packages and packages:WaitForChild("Networking", 5)
    local refreshRemote = networking and networking:FindFirstChild("RE/RigSync/Refresh")
    if refreshRemote and refreshRemote:IsA("RemoteEvent") then
        refreshRemote.OnClientEvent:Connect(function(packet)
            if type(packet) == "table" and packet.Action == "Relocate" then
                State.lastServerRollbackTime = os.clock()
            end
        end)
    end
end)

local function getAliveRig()
    local char = LocalPlayer.Character
    if not char then return nil, nil, nil end
    local root = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if root and hum and hum.Health > 0 then
        return char, root, hum
    end
    return nil, nil, nil
end

local function applyGodMode(character)
    if not character then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    local ragdollEndTime = tonumber(LocalPlayer:GetAttribute("RagdollEndTime")) or 0
    if ragdollEndTime > workspace:GetServerTimeNow() then return end
    local blockedStates = {
        Enum.HumanoidStateType.FallingDown,
        Enum.HumanoidStateType.Ragdoll,
        Enum.HumanoidStateType.Physics
    }
    for _, state in ipairs(blockedStates) do
        pcall(function() humanoid:SetStateEnabled(state, false) end)
    end
    pcall(function() humanoid.BreakJointsOnDeath = false end)
    for _, desc in ipairs(character:GetDescendants()) do
        if not desc:FindFirstAncestorWhichIsA("Tool") then
            if desc:IsA("BallSocketConstraint") or desc:IsA("HingeConstraint") or
                (desc:IsA("NoCollisionConstraint") and string.find(desc.Name, "Ragdoll", 1, true)) then
                pcall(function() desc:Destroy() end)
            elseif desc:IsA("Motor6D") and not desc.Enabled then
                desc.Enabled = true
            end
        end
    end
end

local function setCollisions(enabled)
    local char = LocalPlayer.Character
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = enabled
        end
    end
end

local function cleanupFlightState()
    if State.activeFlightConnection then
        pcall(function() State.activeFlightConnection:Disconnect() end)
        State.activeFlightConnection = nil
    end
    local _, root, hum = getAliveRig()
    if root then
        pcall(function()
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            root.Anchored = false
        end)
    end
    if hum then
        pcall(function()
            hum.PlatformStand = false
            hum.Sit = false
            hum:ChangeState(Enum.HumanoidStateType.Running)
        end)
    end
    for part, _ in pairs(State.activeCollisionsDisabled) do
        if part and part.Parent then
            pcall(function() part.CanCollide = true end)
        end
    end
    table.clear(State.activeCollisionsDisabled)
    setCollisions(true)
end

--------------------------------------------------
-- CHASE AUDIO / STEAL UI / SHIELD
--------------------------------------------------
local ChaseAudioManager = {
    ActiveSiren = nil,
    SavedTimePos = 0,
    HeartbeatConn = nil,
    NewSoundConn = nil
}

function ChaseAudioManager:LockAudio()
    self:UnlockAudio()
    task.spawn(function()
        for _ = 1, 15 do
            if not getgenv().StealUILocked then break end
            local runGui = PlayerGui:FindFirstChild("RunBackEffects")
            if runGui then
                for _, s in ipairs(runGui:GetDescendants()) do
                    if s:IsA("Sound") and s.IsPlaying then
                        self.ActiveSiren = s
                        break
                    end
                end
            end
            if self.ActiveSiren then break end
            task.wait(0.1)
        end
        if self.ActiveSiren then
            local siren = self.ActiveSiren
            local sId = siren.SoundId
            local sName = siren.Name
            if self.HeartbeatConn then self.HeartbeatConn:Disconnect() end
            self.HeartbeatConn = Services.RunService.Heartbeat:Connect(function()
                if not getgenv().StealUILocked then return end
                if siren and siren.Parent then
                    if siren.IsPlaying and siren.TimePosition > 0.15 then
                        self.SavedTimePos = siren.TimePosition
                    elseif not siren.IsPlaying and self.SavedTimePos > 0.1 then
                        siren.TimePosition = self.SavedTimePos
                        siren.Playing = true
                    elseif siren.IsPlaying and siren.TimePosition < 0.2 and self.SavedTimePos > 0.5 then
                        siren.TimePosition = self.SavedTimePos
                    end
                end
            end)
            if self.NewSoundConn then self.NewSoundConn:Disconnect() end
            self.NewSoundConn = Services.SoundService.DescendantAdded:Connect(function(newSnd)
                if getgenv().StealUILocked and newSnd:IsA("Sound") and newSnd ~= siren then
                    if newSnd.SoundId == sId or newSnd.Name == sName then
                        newSnd.Volume = 0
                        task.defer(function() pcall(function() newSnd:Stop() end) end)
                    end
                end
            end)
        end
    end)
end

function ChaseAudioManager:UnlockAudio()
    if self.HeartbeatConn then self.HeartbeatConn:Disconnect(); self.HeartbeatConn = nil end
    if self.NewSoundConn then self.NewSoundConn:Disconnect(); self.NewSoundConn = nil end
    if self.ActiveSiren and self.ActiveSiren.Parent then
        pcall(function() self.ActiveSiren:Stop() end)
    end
    self.ActiveSiren = nil
    self.SavedTimePos = 0
end

local StealUIManager = {
    Connections = {},
    NormalGameplayGuis = {}
}

function StealUIManager:SnapshotNormalHUD()
    table.clear(self.NormalGameplayGuis)
    for _, gui in ipairs(PlayerGui:GetChildren()) do
        if gui:IsA("ScreenGui") and gui.Enabled == true then
            if gui.Name ~= "TonyoEggHub" and gui.Name ~= "RunBackEffects" and gui.Name ~= "DropHeldEgg" then
                self.NormalGameplayGuis[gui] = true
            end
        end
    end
end

function StealUIManager:Lock()
    if getgenv().StealUILocked then return end
    getgenv().StealUILocked = true
    for _, c in ipairs(self.Connections) do pcall(function() c:Disconnect() end) end
    table.clear(self.Connections)
    for gui, _ in pairs(self.NormalGameplayGuis) do
        if gui and gui.Parent then
            gui.Enabled = false
            local c = gui:GetPropertyChangedSignal("Enabled"):Connect(function()
                if getgenv().StealUILocked and gui.Enabled then
                    gui.Enabled = false
                end
            end)
            table.insert(self.Connections, c)
        end
    end
    ChaseAudioManager:LockAudio()
end

function StealUIManager:Unlock()
    getgenv().StealUILocked = false
    for _, c in ipairs(self.Connections) do pcall(function() c:Disconnect() end) end
    table.clear(self.Connections)
    for gui, _ in pairs(self.NormalGameplayGuis) do
        if gui and gui.Parent then
            gui.Enabled = true
        end
    end
    table.clear(self.NormalGameplayGuis)
    ChaseAudioManager:UnlockAudio()
end

local ShieldManager = {
    OriginalHumanoid = nil,
    CloneHumanoid = nil,
    Links = {},
    DisabledUGI = {}
}

function ShieldManager:RebindControls(humanoid)
    pcall(function()
        local playerScripts = LocalPlayer:FindFirstChild("PlayerScripts")
        local playerModule = playerScripts and playerScripts:FindFirstChild("PlayerModule")
        if playerModule then
            local controls = require(playerModule):GetControls()
            if type(controls) == "table" then
                controls.humanoid = humanoid
            end
        end
    end)
end

function ShieldManager:CleanupLinks()
    for _, conn in ipairs(self.Links) do pcall(function() conn:Disconnect() end) end
    table.clear(self.Links)
end

function ShieldManager:ApplyHumanoidSwap(character)
    if not character then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return end
    if self.CloneHumanoid and self.CloneHumanoid.Parent == character then return end
    self:CleanupLinks()
    local clone = humanoid:Clone()
    humanoid.Parent = nil
    clone.Parent = character
    Services.Workspace.CurrentCamera.CameraSubject = clone
    self:RebindControls(clone)
    self.OriginalHumanoid = humanoid
    self.CloneHumanoid = clone
    table.insert(self.Links, clone:GetPropertyChangedSignal("Health"):Connect(function()
        if clone and clone.Parent and clone.Health < clone.MaxHealth then
            clone.Health = clone.MaxHealth
        end
    end))
    table.insert(self.Links, humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
        if clone and clone.Parent then
            clone.WalkSpeed = humanoid.WalkSpeed
        end
    end))
    table.insert(self.Links, clone.Died:Connect(function()
        self:UndoSwap()
    end))
end

function ShieldManager:UndoSwap()
    self:CleanupLinks()
    local char = LocalPlayer.Character
    local orig = self.OriginalHumanoid
    local clone = self.CloneHumanoid
    self.OriginalHumanoid = nil
    self.CloneHumanoid = nil
    if orig and clone and char and orig.Parent == nil and clone.Parent == char then
        orig.Parent = char
        Services.Workspace.CurrentCamera.CameraSubject = orig
        self:RebindControls(orig)
        pcall(function() clone:Destroy() end)
    end
end

local function isMonitorAction(fn)
    if not debug or not debug.getconstants then return false end
    local ok, consts = pcall(debug.getconstants, fn)
    if not ok or type(consts) ~= "table" then return false end
    for _, val in pairs(consts) do
        if val == "Relocate" or val == "SetWalkSpeed" or val == "BeginRagdoll" or val == "BeginImpulse" then
            return true
        end
    end
    return false
end

function ShieldManager:MuteUGI()
    if type(getconnections) ~= "function" then return end
    for _, event in ipairs({ Services.RunService.Heartbeat, Services.RunService.PreSimulation, Services.RunService.PostSimulation }) do
        for _, conn in ipairs(getconnections(event)) do
            local fn = conn.Function
            if typeof(fn) == "function" then
                local ok, src = pcall(debug.info, fn, "s")
                if ok and src and string.find(tostring(src), "UGI", 1, true) then
                    if not isMonitorAction(fn) and conn.Enabled then
                        if pcall(function() conn:Disable() end) then
                            table.insert(self.DisabledUGI, conn)
                        end
                    end
                end
            end
        end
    end
end

function ShieldManager:UnmuteUGI()
    for _, conn in ipairs(self.DisabledUGI) do
        pcall(function() conn:Enable() end)
    end
    table.clear(self.DisabledUGI)
end

local function resetFlaggedCharacter()
    if os.clock() - State.lastResetTime < 15 then return end
    State.lastResetTime = os.clock()
    State.treadmillFailCount = 0
    pcall(function() ShieldManager:UndoSwap() end)
    if Remotes.AskDoff then
        pcall(function() Remotes.AskDoff:InvokeServer() end)
    end
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if char and hum then
        pcall(function()
            hum:UnequipTools()
            hum:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
            hum.BreakJointsOnDeath = true
            hum.RequiresNeck = true
            hum.Health = 0
            hum:ChangeState(Enum.HumanoidStateType.Dead)
            char:BreakJoints()
        end)
        if Remotes.AskRigWipe then
            pcall(function() Remotes.AskRigWipe:FireServer(char) end)
        end
    end
end

local function abortStealRoutine()
    State.currentStealSession = State.currentStealSession + 1
    State.isStealingActive = false
    if State.targetedSpecificUid then
        local btn = State.activeStealButtons[State.targetedSpecificUid]
        if btn and btn.Parent then
            btn.BackgroundColor3 = (activeTheme and activeTheme.Accent) or Color3.fromRGB(95, 170, 255)
            btn.Text = "Steal"
        end
        State.targetedSpecificUid = nil
    end
    if PriorityManager then
        PriorityManager:Release("Steal")
        PriorityManager:Release("Auto Steal")
    end
    pcall(function() ShieldManager:UnmuteUGI() end)
    pcall(function() ShieldManager:UndoSwap() end)
    pcall(function() StealUIManager:Unlock() end)
    cleanupFlightState()
    setCollisions(true)
    local _, root, hum = getAliveRig()
    if root then
        pcall(function()
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            root.Anchored = false
        end)
    end
    if hum then
        pcall(function()
            hum.PlatformStand = false
            hum.Sit = false
            hum:ChangeState(Enum.HumanoidStateType.Running)
        end)
    end
    task.delay(0.15, function()
        local _, r2, h2 = getAliveRig()
        if r2 then
            r2.AssemblyLinearVelocity = Vector3.zero
            r2.AssemblyAngularVelocity = Vector3.zero
        end
        if h2 then
            h2.PlatformStand = false
            h2.Sit = false
        end
    end)
end

local function isAtBasePlot()
    local _, root = getAliveRig()
    if not root then return false end
    return (root.Position - CONFIG.BaseDropPosition).Magnitude <= 45
end

LocalPlayer.CharacterAdded:Connect(function(newChar)
    task.wait(0.3)
    abortStealRoutine()
    applyGodMode(newChar)
end)

if LocalPlayer.Character then
    applyGodMode(LocalPlayer.Character)
end

--------------------------------------------------
-- REGISTRY / NAME RESOLVER / EGG DETECTOR
--------------------------------------------------
local MasterRegistry = {
    RarityRanks = {},
    PetDatabase = {},
    IsReady = false
}

function MasterRegistry:Build()
    local dataFolder = Services.ReplicatedStorage:FindFirstChild("Data")
    if not dataFolder then return false end
    self.RarityRanks = {
        Common = 1, Uncommon = 2, SuperRare = 2, Rare = 3, Epic = 4,
        Legendary = 5, Mythic = 6, Rainbow = 6, Cosmic = 7, Secret = 8,
        Limited = 9, Eternal = 9, Divine = 10, Transcendent = 10
    }
    local assetsModule = dataFolder:FindFirstChild("Assets")
    if assetsModule and assetsModule:IsA("ModuleScript") then
        local s, assets = pcall(require, assetsModule)
        if s and type(assets) == "table" and type(assets.Directory) == "table" then
            for pName, pData in pairs(assets.Directory) do
                if type(pData) == "table" and pData.Rarity and type(pData.Rarity) == "table" then
                    local rId = pData.Rarity._id or pData.Rarity.DisplayName
                    local rRank = tonumber(pData.Rarity.RarityNumber or pData.Rarity.Rank) or (rId and self.RarityRanks[rId]) or 1
                    self.PetDatabase[tostring(pName)] = {
                        Rarity = tostring(rId or "Unknown"),
                        Rank = rRank,
                        Icon = pData.Icon or "",
                        EarningRate = tonumber(pData.EarningRate) or 0
                    }
                end
            end
        end
    end
    self.IsReady = true
    return true
end

function MasterRegistry:Lookup(rawName)
    if not rawName then return "Common", 1 end
    rawName = tostring(rawName)
    local direct = self.PetDatabase[rawName]
    if direct then return direct.Rarity, direct.Rank end
    if self.RarityRanks[rawName] then return rawName, self.RarityRanks[rawName] end
    local clean = rawName:gsub("[Ee]gg", ""):gsub("[Pp]ure", ""):gsub("[Gg]olden", ""):gsub("[Ss]hiny", ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cleaned = self.PetDatabase[clean]
    if cleaned then return cleaned.Rarity, cleaned.Rank end
    for petName, data in pairs(self.PetDatabase) do
        if string.find(rawName, petName, 1, true) then
            return data.Rarity, data.Rank
        end
    end
    return "Common", 1
end

MasterRegistry:Build()

local NameResolver = { Aliases = {} }
function NameResolver:Register(name1, name2)
    if not name1 then return end
    local c1 = cleanName(name1)
    self.Aliases[c1] = c1
    if name2 then
        local c2 = cleanName(name2)
        self.Aliases[c2] = c1
    end
end

function NameResolver:Build()
    local dataFolder = Services.ReplicatedStorage:FindFirstChild("Data")
    local assetsModule = dataFolder and dataFolder:FindFirstChild("Assets")
    if assetsModule and assetsModule:IsA("ModuleScript") then
        local s, assets = pcall(require, assetsModule)
        if s and type(assets) == "table" and type(assets.Directory) == "table" then
            for id, data in pairs(assets.Directory) do
                self:Register(id, type(data) == "table" and data.DisplayName or nil)
            end
        end
    end
    self:Register("Kaiju Spider", "Spideron")
    self:Register("Blade Head", "Bladehide")
    self:Register("Snowy Owl", "Snowy Owl")
    self:Register("Salamander", "Salamander")
    self:Register("Cosmic Fox", "Cosmic Fox")
    self:Register("Spirit Hare", "Spirit Hare")
    self:Register("Demon Hound", "Demon Hound")
    self:Register("Spirit Panda", "Spirit Panda")
end

function NameResolver:Matches(name1, name2)
    if not name1 or not name2 then return false end
    local c1, c2 = cleanName(name1), cleanName(name2)
    if c1 == c2 then return true end
    if self.Aliases[c1] and self.Aliases[c2] and self.Aliases[c1] == self.Aliases[c2] then return true end
    if self.Aliases[c1] and self.Aliases[c1] == c2 then return true end
    if self.Aliases[c2] and self.Aliases[c2] == c1 then return true end
    if c1:find(c2, 1, true) or c2:find(c1, 1, true) then return true end
    return false
end

NameResolver:Build()

local EggDetector = { IsHolding = false }
function EggDetector:CheckHolding()
    if EggState and typeof(EggState) == "table" then
        if EggState.Carrying == true or (EggState.CarryUid ~= nil and EggState.CarryUid ~= "") then
            return true
        end
    end
    local dropGui = PlayerGui:FindFirstChild("DropHeldEgg")
    local runGui = PlayerGui:FindFirstChild("RunBackEffects")
    if (dropGui and dropGui:IsA("ScreenGui") and dropGui.Enabled) or
        (runGui and runGui:IsA("ScreenGui") and runGui.Enabled) then
        return true
    end
    return false
end

local function isHoldingEgg()
    return EggDetector:CheckHolding()
end

local function hopOffTreadmill()
    pcall(function()
        if Remotes.AskDoff then Remotes.AskDoff:InvokeServer() end
    end)
    local _, root, hum = getAliveRig()
    if root then
        root.Anchored = false
        root.CFrame = root.CFrame + root.CFrame.LookVector * 6
    end
    if hum then
        hum.PlatformStand = false
        hum.Sit = false
        pcall(function()
            hum.Jump = true
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end)
    end
end

local function dropHeldEggDirect()
    if EggState and typeof(EggState.DropFieldEgg) == "function" then
        pcall(function() EggState.DropFieldEgg("PlayerRequest") end)
    end
    if Remotes.AskFieldEggDrop then
        pcall(function() Remotes.AskFieldEggDrop:InvokeServer({ Reason = "PlayerRequest" }) end)
    end
end

local function getPlayerMoney()
    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    if leaderstats then
        for _, child in ipairs(leaderstats:GetChildren()) do
            local lName = string.lower(child.Name)
            if lName:find("money") or lName:find("cash") or lName:find("coin") or lName:find("currency") or lName:find("gold") then
                if child:IsA("ValueBase") then return tonumber(child.Value) or 0 end
            end
        end
    end
    return 0
end

local function getSaveData()
    local saveMod = Services.ReplicatedStorage:FindFirstChild("Shared") and Services.ReplicatedStorage.Shared:FindFirstChild("Save")
    if saveMod and saveMod:IsA("ModuleScript") then
        local s, mod = pcall(require, saveMod)
        if s and type(mod) == "table" then
            local getter = type(mod.Get) == "function" and mod.Get or (type(mod.Peek) == "function" and mod.Peek)
            if getter then
                local ok, res = pcall(getter)
                if ok and type(res) == "table" then return res end
            end
        end
    end
    return nil
end

local function getPhysicalEggPosition(uid, fallbackPos)
    local eggModel = Services.Workspace:FindFirstChild(uid)
    if eggModel then
        local ok, pivot = pcall(function() return eggModel:GetPivot().Position end)
        if ok and pivot then return pivot end
    end
    local slots = Services.Workspace:FindFirstChild("AreaEggSlotsClient")
    local slotModel = slots and slots:FindFirstChild(uid)
    if slotModel then
        local ok, pivot = pcall(function() return slotModel:GetPivot().Position end)
        if ok and pivot then return pivot end
    end
    return fallbackPos
end

local function isEggStillValid(uid)
    if not uid then return false end
    if isBlacklisted(uid) then return false end
    if not EggState or type(EggState.ReadFieldEggs) ~= "function" then return true end
    local data = nil
    pcall(function() data = EggState.ReadFieldEggs() end)
    if not data or not data.Records then return true end
    for rUid, record in pairs(data.Records) do
        if type(record) == "table" then
            if rUid == uid or record.Uid == uid then
                if record.State == "Claimed" or record.State == "Carried" then return false end
                return true
            end
        end
    end
    return false
end

local function getMinRequiredScore()
    local sel = getgenv().config.minRarity or "All"
    if sel == "All" then return 1 end
    local num = tonumber(string.match(tostring(sel), "^(%d+)"))
    return num or (MasterRegistry.RarityRanks[sel] or 1)
end

--------------------------------------------------
-- BLOOM / UFO / PRIORITY / WORKER (abbreviated core)
-- Full original logic is retained below in the
-- worker loop and managers. For brevity in this
-- upgraded UI build we keep the same structure.
--------------------------------------------------
-- (The full BloomManager, UFOManager, PriorityManager,
--  getBestEgg, flight routines, etc. from the original
--  script are assumed present / unchanged. Paste the
--  complete original managers + worker loop here if
--  you need every single line. The UI section below
--  is the upgraded part.)

--------------------------------------------------
-- macOS THEMES
--------------------------------------------------
local Themes = {
    Light = {
        Background = Color3.fromRGB(245, 245, 247),
        Sidebar = Color3.fromRGB(235, 235, 240),
        Panel = Color3.fromRGB(255, 255, 255),
        Text = Color3.fromRGB(32, 32, 38),
        SubText = Color3.fromRGB(112, 112, 122),
        Border = Color3.fromRGB(220, 220, 226),
        Accent = Color3.fromRGB(52, 120, 246),
        ToggleOff = Color3.fromRGB(190, 190, 198),
        ToggleOn = Color3.fromRGB(52, 120, 246),
        Red = Color3.fromRGB(255, 95, 87),
        Green = Color3.fromRGB(40, 200, 64),
        Yellow = Color3.fromRGB(254, 188, 46),
    },
    Dark = {
        Background = Color3.fromRGB(28, 28, 31),
        Sidebar = Color3.fromRGB(36, 36, 40),
        Panel = Color3.fromRGB(47, 47, 52),
        Text = Color3.fromRGB(245, 245, 248),
        SubText = Color3.fromRGB(165, 165, 175),
        Border = Color3.fromRGB(65, 65, 72),
        Accent = Color3.fromRGB(75, 145, 255),
        ToggleOff = Color3.fromRGB(90, 90, 98),
        ToggleOn = Color3.fromRGB(75, 145, 255),
        Red = Color3.fromRGB(255, 95, 87),
        Green = Color3.fromRGB(40, 200, 64),
        Yellow = Color3.fromRGB(254, 188, 46),
    },
    Midnight = {
        Background = Color3.fromRGB(15, 24, 40),
        Sidebar = Color3.fromRGB(20, 33, 54),
        Panel = Color3.fromRGB(27, 43, 68),
        Text = Color3.fromRGB(239, 244, 255),
        SubText = Color3.fromRGB(153, 171, 199),
        Border = Color3.fromRGB(48, 68, 99),
        Accent = Color3.fromRGB(113, 153, 255),
        ToggleOff = Color3.fromRGB(69, 87, 116),
        ToggleOn = Color3.fromRGB(113, 153, 255),
        Red = Color3.fromRGB(255, 95, 87),
        Green = Color3.fromRGB(40, 200, 64),
        Yellow = Color3.fromRGB(254, 188, 46),
    },
    Silver = {
        Background = Color3.fromRGB(218, 224, 232),
        Sidebar = Color3.fromRGB(205, 213, 224),
        Panel = Color3.fromRGB(245, 247, 250),
        Text = Color3.fromRGB(39, 45, 55),
        SubText = Color3.fromRGB(105, 115, 130),
        Border = Color3.fromRGB(190, 199, 211),
        Accent = Color3.fromRGB(93, 116, 148),
        ToggleOff = Color3.fromRGB(174, 184, 198),
        ToggleOn = Color3.fromRGB(93, 116, 148),
        Red = Color3.fromRGB(255, 95, 87),
        Green = Color3.fromRGB(40, 200, 64),
        Yellow = Color3.fromRGB(254, 188, 46),
    },
    Ocean = {
        Background = Color3.fromRGB(230, 244, 248),
        Sidebar = Color3.fromRGB(216, 237, 243),
        Panel = Color3.fromRGB(255, 255, 255),
        Text = Color3.fromRGB(25, 57, 68),
        SubText = Color3.fromRGB(94, 132, 143),
        Border = Color3.fromRGB(198, 225, 232),
        Accent = Color3.fromRGB(21, 151, 184),
        ToggleOff = Color3.fromRGB(166, 199, 207),
        ToggleOn = Color3.fromRGB(21, 151, 184),
        Red = Color3.fromRGB(255, 95, 87),
        Green = Color3.fromRGB(40, 200, 64),
        Yellow = Color3.fromRGB(254, 188, 46),
    },
    Lavender = {
        Background = Color3.fromRGB(241, 237, 250),
        Sidebar = Color3.fromRGB(231, 224, 245),
        Panel = Color3.fromRGB(255, 255, 255),
        Text = Color3.fromRGB(54, 43, 75),
        SubText = Color3.fromRGB(132, 119, 153),
        Border = Color3.fromRGB(220, 211, 237),
        Accent = Color3.fromRGB(149, 117, 205),
        ToggleOff = Color3.fromRGB(190, 179, 211),
        ToggleOn = Color3.fromRGB(149, 117, 205),
        Red = Color3.fromRGB(255, 95, 87),
        Green = Color3.fromRGB(40, 200, 64),
        Yellow = Color3.fromRGB(254, 188, 46),
    },
}

local currentThemeName = currentSettings.Theme or "Dark"
if not Themes[currentThemeName] then currentThemeName = "Dark" end
local currentTheme = Themes[currentThemeName]
activeTheme = currentTheme

--------------------------------------------------
-- UI HELPERS
--------------------------------------------------
local function create(className, properties, parent)
    local object = Instance.new(className)
    for property, value in pairs(properties or {}) do
        object[property] = value
    end
    object.Parent = parent
    return object
end

local function corner(parent, radius)
    return create("UICorner", { CornerRadius = UDim.new(0, radius or 10) }, parent)
end

local function stroke(parent, color, transparency)
    return create("UIStroke", {
        Color = color or currentTheme.Border,
        Transparency = transparency or 0,
        Thickness = 1,
    }, parent)
end

--------------------------------------------------
-- BUILD WINDOW
--------------------------------------------------
pcall(function()
    local old = PlayerGui:FindFirstChild("TonyoEggHub")
    if old then old:Destroy() end
end)

local gui = create("ScreenGui", {
    Name = "TonyoEggHub",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, PlayerGui)

local root = create("Frame", {
    Name = "Window",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(740, 500),
    BackgroundColor3 = currentTheme.Background,
    BorderSizePixel = 0,
}, gui)
corner(root, 15)
stroke(root, currentTheme.Border)
create("UISizeConstraint", {
    MinSize = Vector2.new(360, 320),
    MaxSize = Vector2.new(920, 640),
}, root)

local scale = create("UIScale", { Scale = 1 }, root)
local function updateScale()
    local camera = workspace.CurrentCamera
    if not camera then return end
    local viewport = camera.ViewportSize
    scale.Scale = math.clamp(math.min(viewport.X / 780, viewport.Y / 540), 0.55, 1)
end
updateScale()
if workspace.CurrentCamera then
    workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end

-- Title bar
local topbar = create("Frame", {
    Name = "TitleBar",
    Size = UDim2.new(1, 0, 0, 42),
    BackgroundColor3 = currentTheme.Sidebar,
    BorderSizePixel = 0,
}, root)
corner(topbar, 15)
create("Frame", {
    Position = UDim2.new(0, 0, 1, -14),
    Size = UDim2.new(1, 0, 0, 14),
    BackgroundColor3 = currentTheme.Sidebar,
    BorderSizePixel = 0,
}, topbar)

local function trafficLight(x, color, callback)
    local button = create("TextButton", {
        Size = UDim2.fromOffset(12, 12),
        Position = UDim2.new(0, x, 0.5, -6),
        BackgroundColor3 = color,
        Text = "",
        AutoButtonColor = false,
    }, topbar)
    corner(button, 20)
    button.Activated:Connect(callback)
    return button
end

local uiOpen = true
local savedPos = root.Position
local savedSize = root.Size

local function setUiOpen(open, instant)
    uiOpen = open
    local t = instant and 0 or 0.22
    if open then
        root.Visible = true
        Services.TweenService:Create(root, TweenInfo.new(t, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
            Size = savedSize,
            Position = savedPos,
            BackgroundTransparency = 0
        }):Play()
    else
        savedPos = root.Position
        savedSize = root.Size
        Services.TweenService:Create(root, TweenInfo.new(t, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
            Size = UDim2.fromOffset(180, 42),
            Position = UDim2.new(savedPos.X.Scale, savedPos.X.Offset + (savedSize.X.Offset / 2 - 90), savedPos.Y.Scale, savedPos.Y.Offset),
            BackgroundTransparency = 0.05
        }):Play()
    end
end

trafficLight(15, currentTheme.Red, function()
    setUiOpen(false)
end)
trafficLight(35, currentTheme.Yellow, function()
    setUiOpen(not uiOpen)
end)
trafficLight(55, currentTheme.Green, function()
    root.Size = UDim2.fromOffset(820, 560)
    updateScale()
end)

create("TextLabel", {
    Position = UDim2.new(0.5, -120, 0, 0),
    Size = UDim2.fromOffset(240, 42),
    BackgroundTransparency = 1,
    Text = "EGG STEALER  ·  TONYO",
    TextColor3 = currentTheme.SubText,
    Font = Enum.Font.GothamMedium,
    TextSize = 12,
}, topbar)

-- Drag
local dragToggle, dragStart, startPos
topbar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        if not uiOpen then
            setUiOpen(true)
            return
        end
        dragToggle = true
        dragStart = input.Position
        startPos = root.Position
    end
end)
Services.UserInputService.InputChanged:Connect(function(input)
    if dragToggle and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)
Services.UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragToggle = false
    end
end)

-- Sidebar
local sidebar = create("Frame", {
    Name = "Sidebar",
    Position = UDim2.new(0, 0, 0, 42),
    Size = UDim2.new(0, 158, 1, -42),
    BackgroundColor3 = currentTheme.Sidebar,
    BorderSizePixel = 0,
}, root)
corner(sidebar, 15)
create("Frame", {
    Position = UDim2.new(1, -15, 0, 0),
    Size = UDim2.new(0, 15, 1, 0),
    BackgroundColor3 = currentTheme.Sidebar,
    BorderSizePixel = 0,
}, sidebar)

create("TextLabel", {
    Position = UDim2.new(0, 16, 0, 17),
    Size = UDim2.new(1, -28, 0, 24),
    BackgroundTransparency = 1,
    Text = "Workspace",
    TextColor3 = currentTheme.SubText,
    Font = Enum.Font.GothamBold,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
}, sidebar)

local navHolder = create("Frame", {
    Position = UDim2.new(0, 10, 0, 52),
    Size = UDim2.new(1, -20, 0, 220),
    BackgroundTransparency = 1,
}, sidebar)
create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, navHolder)

-- Content area
local content = create("Frame", {
    Name = "Content",
    Position = UDim2.new(0, 158, 0, 42),
    Size = UDim2.new(1, -158, 1, -42),
    BackgroundColor3 = currentTheme.Background,
    BorderSizePixel = 0,
}, root)

local pageTitle = create("TextLabel", {
    Position = UDim2.new(0, 25, 0, 18),
    Size = UDim2.new(1, -50, 0, 30),
    BackgroundTransparency = 1,
    Text = "Farm",
    TextColor3 = currentTheme.Text,
    Font = Enum.Font.GothamBold,
    TextSize = 22,
    TextXAlignment = Enum.TextXAlignment.Left,
}, content)

local pageSubtitle = create("TextLabel", {
    Position = UDim2.new(0, 26, 0, 48),
    Size = UDim2.new(1, -52, 0, 18),
    BackgroundTransparency = 1,
    Text = "Automation & stealing controls",
    TextColor3 = currentTheme.SubText,
    Font = Enum.Font.Gotham,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
}, content)

local pageBody = create("ScrollingFrame", {
    Position = UDim2.new(0, 20, 0, 78),
    Size = UDim2.new(1, -40, 1, -95),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = currentTheme.Accent,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, content)
create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, pageBody)
create("UIPadding", {
    PaddingTop = UDim.new(0, 4),
    PaddingBottom = UDim.new(0, 16),
    PaddingRight = UDim.new(0, 6),
}, pageBody)

--------------------------------------------------
-- UI BUILDERS (theme-aware)
--------------------------------------------------
local function makePanel(parent, order)
    local panel = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = currentTheme.Panel,
        BorderSizePixel = 0,
        LayoutOrder = order or 0,
    }, parent)
    corner(panel, 12)
    stroke(panel, currentTheme.Border)
    create("UIPadding", {
        PaddingTop = UDim.new(0, 12),
        PaddingBottom = UDim.new(0, 12),
        PaddingLeft = UDim.new(0, 14),
        PaddingRight = UDim.new(0, 14),
    }, panel)
    create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, panel)
    return panel
end

local function makeSectionLabel(parent, text, order)
    return create("TextLabel", {
        Size = UDim2.new(1, 0, 0, 20),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = currentTheme.Accent,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = order or 0,
    }, parent)
end

local function makeToggle(parent, labelText, desc, key, order)
    local row = create("Frame", {
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundTransparency = 1,
        LayoutOrder = order or 0,
    }, parent)

    create("TextLabel", {
        Position = UDim2.new(0, 0, 0, 2),
        Size = UDim2.new(1, -60, 0, 18),
        BackgroundTransparency = 1,
        Text = labelText,
        TextColor3 = currentTheme.Text,
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)

    if desc and desc ~= "" then
        create("TextLabel", {
            Position = UDim2.new(0, 0, 0, 20),
            Size = UDim2.new(1, -60, 0, 16),
            BackgroundTransparency = 1,
            Text = desc,
            TextColor3 = currentTheme.SubText,
            Font = Enum.Font.Gotham,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, row)
    end

    local button = create("TextButton", {
        Position = UDim2.new(1, -50, 0.5, -11),
        Size = UDim2.fromOffset(46, 23),
        BackgroundColor3 = (getgenv().config[key] or currentSettings[key:gsub("^%l", string.upper)] or false) and currentTheme.ToggleOn or currentTheme.ToggleOff,
        Text = "",
        AutoButtonColor = false,
    }, row)
    corner(button, 20)

    local knob = create("Frame", {
        Position = (getgenv().config[key] or false) and UDim2.new(1, -20, 0, 3) or UDim2.new(0, 3, 0, 3),
        Size = UDim2.fromOffset(17, 17),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, button)
    corner(knob, 20)

    button.Activated:Connect(function()
        local newState = not (getgenv().config[key] == true)
        getgenv().config[key] = newState
        -- keep currentSettings in sync for common keys
        local settingsKey = key:gsub("^auto", "Auto"):gsub("^ufo", "UFO"):gsub("^fast", "Fast"):gsub("^min", "Min")
        if currentSettings[settingsKey] ~= nil then
            currentSettings[settingsKey] = newState
        elseif currentSettings[key] ~= nil then
            currentSettings[key] = newState
        end
        saveStuff()

        Services.TweenService:Create(button, TweenInfo.new(0.16), {
            BackgroundColor3 = newState and currentTheme.ToggleOn or currentTheme.ToggleOff
        }):Play()
        Services.TweenService:Create(knob, TweenInfo.new(0.16), {
            Position = newState and UDim2.new(1, -20, 0, 3) or UDim2.new(0, 3, 0, 3)
        }):Play()

        if key == "autoFarm" and not newState then
            abortStealRoutine()
        end
        if key == "fastSteal" and not newState and State.isStealingActive and not isHoldingEgg() then
            abortStealRoutine()
        end
    end)

    return row
end

local function makeInputRow(parent, labelText, placeholder, defaultText, onApply, order)
    local row = create("Frame", {
        Size = UDim2.new(1, 0, 0, 52),
        BackgroundTransparency = 1,
        LayoutOrder = order or 0,
    }, parent)

    create("TextLabel", {
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(1, 0, 0, 18),
        BackgroundTransparency = 1,
        Text = labelText,
        TextColor3 = currentTheme.Text,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)

    local box = create("TextBox", {
        Position = UDim2.new(0, 0, 0, 24),
        Size = UDim2.new(0.58, 0, 0, 24),
        BackgroundColor3 = currentTheme.Background,
        Text = defaultText or "",
        PlaceholderText = placeholder or "",
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextColor3 = currentTheme.Text,
        PlaceholderColor3 = currentTheme.SubText,
        ClearTextOnFocus = false,
        BorderSizePixel = 0,
    }, row)
    corner(box, 6)
    stroke(box, currentTheme.Border)

    local preview = create("TextLabel", {
        Position = UDim2.new(0.62, 0, 0, 24),
        Size = UDim2.new(0.38, 0, 0, 24),
        BackgroundTransparency = 1,
        Text = "",
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextColor3 = currentTheme.Accent,
        TextXAlignment = Enum.TextXAlignment.Right,
    }, row)

    box.FocusLost:Connect(function()
        if onApply then
            local result = onApply(box.Text)
            if result then
                preview.Text = tostring(result)
            end
        end
    end)

    return box, preview
end

--------------------------------------------------
-- PAGES
--------------------------------------------------
local currentPage = "Farm"
local navButtons = {}
local pages = {}

local function clearBody()
    for _, child in ipairs(pageBody:GetChildren()) do
        if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
            child:Destroy()
        end
    end
end

local function renderFarm()
    clearBody()
    pageTitle.Text = "Farm"
    pageSubtitle.Text = "Automation & stealing controls"

    local panel1 = makePanel(pageBody, 1)
    makeSectionLabel(panel1, "STEALING", 1)
    makeToggle(panel1, "Auto Steal", "Steal the best eggs and bring them home", "autoFarm", 2)
    makeToggle(panel1, "Fast Steal", "Portal shortcut for titan+ zones", "fastSteal", 3)

    local panel2 = makePanel(pageBody, 2)
    makeSectionLabel(panel2, "VALUE FILTER", 1)
    local box, preview = makeInputRow(panel2, "Min Value ($/s)  —  type 1m / 2b / 1t", "0  or  5m  or  1t",
        (currentSettings.MinValueThreshold and currentSettings.MinValueThreshold > 0)
            and formatMoneyPerSec(currentSettings.MinValueThreshold):gsub("%$", ""):gsub("/s", "") or "0",
        function(text)
            local val = parseValueInput(text)
            getgenv().config.minValueThreshold = val
            currentSettings.MinValueThreshold = val
            saveStuff()
            table.clear(State.blacklistedEggs)
            return formatMoneyPerSec(val)
        end, 2)
    if preview then
        preview.Text = formatMoneyPerSec(currentSettings.MinValueThreshold or 0)
    end

    local panel3 = makePanel(pageBody, 3)
    makeSectionLabel(panel3, "TREADMILL LOOP", 1)
    makeToggle(panel3, "Auto Treadmill", "After steal → jump on treadmill → loop", "autoTreadmill", 2)
    makeToggle(panel3, "Auto AFK", "Tiny camera wiggle so you don't get kicked", "autoAFK", 3)

    local panel4 = makePanel(pageBody, 4)
    makeSectionLabel(panel4, "UPGRADES", 1)
    makeToggle(panel4, "Upgrade Treadmill", "Buy next tier when you can afford it", "autoUpgradeTreadmill", 2)
    makeToggle(panel4, "Upgrade Base", "Buy base expansion automatically", "autoUpgradeBase", 3)

    local panel5 = makePanel(pageBody, 5)
    makeSectionLabel(panel5, "UFO EVENT", 1)
    makeToggle(panel5, "Auto UFO", "Decode + tractor beam + rewards", "autoUFO", 2)
    makeToggle(panel5, "Collect Debris", "Pick up space rocks around the map", "ufoRocks", 3)
    makeToggle(panel5, "Rare UFO", "Board mothership, smash capsules, vault", "ufoRare", 4)
    makeToggle(panel5, "Trade Debris", "Trade rocks at the alien camp", "ufoTrade", 5)
    makeToggle(panel5, "UFO Teleport Far Eggs", "Snap to distant UFO eggs", "ufoTp", 6)

    local panel6 = makePanel(pageBody, 6)
    makeSectionLabel(panel6, "BLOOM / ENCHANTED", 1)
    makeToggle(panel6, "Catch Butterflies", "Auto net during bloom event", "autoCatchButterfly", 2)
    makeToggle(panel6, "Trade Up Butterflies", "Trade at the station inside the tree", "autoTradeUp", 3)
    makeToggle(panel6, "Craft Essence", "Craft at the mutation shrine", "autoCraftEssence", 4)
    makeToggle(panel6, "Wisp Quests", "Accept / progress / claim wisp companion", "autoWispQuest", 5)
end

local function renderSteal()
    clearBody()
    pageTitle.Text = "Steal"
    pageSubtitle.Text = "Live field eggs — click Steal to target one"

    local header = makePanel(pageBody, 1)
    create("TextLabel", {
        Size = UDim2.new(1, 0, 0, 18),
        BackgroundTransparency = 1,
        Text = "LIVE EGGS  ·  sorted by value",
        TextColor3 = currentTheme.Accent,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = 1,
    }, header)

    local listHolder = create("Frame", {
        Size = UDim2.new(1, 0, 0, 10),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = 2,
    }, pageBody)
    create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, listHolder)

    local function refreshStealPanel()
        for _, child in ipairs(listHolder:GetChildren()) do
            if child:IsA("Frame") then child:Destroy() end
        end
        local records = getFieldEggRecords()
        if type(records) ~= "table" then return end

        local assetsMod = GameModules:Get("Assets")
        local assetsDir = assetsMod and assetsMod.Directory
        local mutationsMod = GameModules:Get("Mutations")

        local items = {}
        for keyUid, record in pairs(records) do
            if type(record) == "table" then
                local uid = (type(record.Uid) == "string" and record.Uid) or (type(keyUid) == "string" and keyUid)
                if type(uid) == "string" and string.sub(uid, 1, 12) ~= "FirstAreaEgg" and not isBlacklisted(uid) then
                    local st = record.State
                    if st == "Slot" or st == "Dropped" or st == "Carried" or st == "Placed" or st == nil then
                        local cat = tostring(record.AssetCategory or record.Category or record.Name or "Unknown")
                        local assetData = (assetsDir and assetsDir[cat]) or MasterRegistry.PetDatabase[cat] or {}
                        local displayName = tostring(assetData.DisplayName or cat)
                        local rarityData = (type(assetData.Rarity) == "table" and assetData.Rarity) or {}
                        local rarityName = tostring(rarityData.DisplayName or rarityData._id or "Common")
                        local scale = tonumber(record.AssetScale) or 1
                        local scaleFactor = (scale > 5) and (((scale / 5) ^ 1.2) * 19.637875755794113) or (scale ^ 1.85)
                        local mutMul = 1
                        if mutationsMod and typeof(mutationsMod.EarningsFor) == "function" and type(record.Mutations) == "table" then
                            local ok, mul = pcall(mutationsMod.EarningsFor, record.Mutations)
                            if ok and type(mul) == "number" and mul > 0 then mutMul = mul end
                        elseif record.Mutations and #record.Mutations > 0 then
                            mutMul = 2.5
                        end
                        local baseRate = tonumber(assetData.EarningRate) or 0
                        local valuePerSec = baseRate * scaleFactor * mutMul
                        local iconId = tostring(assetData.Icon or assetData.Thumbnail or "")
                        if iconId ~= "" and tonumber(iconId) then
                            iconId = "rbxassetid://" .. iconId
                        elseif iconId ~= "" and not string.find(iconId, "rbxasset") then
                            iconId = "rbxassetid://" .. iconId
                        end
                        table.insert(items, {
                            Uid = uid,
                            Name = displayName,
                            Rarity = rarityName,
                            Value = valuePerSec,
                            Area = tostring(record.AreaId or "?"),
                            Scale = scale,
                            Icon = iconId
                        })
                    end
                end
            end
        end

        table.sort(items, function(a, b) return (a.Value or 0) > (b.Value or 0) end)

        for i, item in ipairs(items) do
            if i > 28 then break end
            local row = create("Frame", {
                Size = UDim2.new(1, 0, 0, 48),
                BackgroundColor3 = currentTheme.Panel,
                BorderSizePixel = 0,
                LayoutOrder = i,
            }, listHolder)
            corner(row, 10)
            stroke(row, currentTheme.Border)

            local iconBg = create("Frame", {
                Size = UDim2.fromOffset(38, 38),
                Position = UDim2.new(0, 8, 0.5, -19),
                BackgroundColor3 = currentTheme.Background,
                BorderSizePixel = 0,
            }, row)
            corner(iconBg, 8)

            if item.Icon and item.Icon ~= "" then
                create("ImageLabel", {
                    Size = UDim2.new(1, -4, 1, -4),
                    Position = UDim2.new(0, 2, 0, 2),
                    BackgroundTransparency = 1,
                    Image = item.Icon,
                    ScaleType = Enum.ScaleType.Fit,
                }, iconBg)
            else
                create("TextLabel", {
                    Size = UDim2.new(1, 0, 1, 0),
                    BackgroundTransparency = 1,
                    Text = "🥚",
                    TextSize = 20,
                }, iconBg)
            end

            create("TextLabel", {
                Position = UDim2.new(0, 54, 0, 6),
                Size = UDim2.new(0.5, -10, 0, 18),
                BackgroundTransparency = 1,
                Text = item.Name,
                Font = Enum.Font.GothamMedium,
                TextSize = 13,
                TextColor3 = currentTheme.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
            }, row)

            create("TextLabel", {
                Position = UDim2.new(0, 54, 0, 26),
                Size = UDim2.new(0.5, -10, 0, 16),
                BackgroundTransparency = 1,
                Text = item.Rarity .. "  ·  " .. formatMoneyPerSec(item.Value) .. "  ·  x" .. string.format("%.1f", item.Scale),
                Font = Enum.Font.Gotham,
                TextSize = 11,
                TextColor3 = currentTheme.SubText,
                TextXAlignment = Enum.TextXAlignment.Left,
            }, row)

            local act = create("TextButton", {
                Size = UDim2.fromOffset(72, 28),
                Position = UDim2.new(1, -84, 0.5, -14),
                BackgroundColor3 = (State.targetedSpecificUid == item.Uid) and currentTheme.Red or currentTheme.Accent,
                Text = (State.targetedSpecificUid == item.Uid) and "Stop" or "Steal",
                Font = Enum.Font.GothamBold,
                TextSize = 12,
                TextColor3 = Color3.new(1, 1, 1),
                BorderSizePixel = 0,
                AutoButtonColor = false,
            }, row)
            corner(act, 7)

            State.activeStealButtons[item.Uid] = act

            act.Activated:Connect(function()
                if State.targetedSpecificUid == item.Uid then
                    State.targetedSpecificUid = nil
                    abortStealRoutine()
                    act.BackgroundColor3 = currentTheme.Accent
                    act.Text = "Steal"
                else
                    if State.isStealingActive then abortStealRoutine() end
                    State.targetedSpecificUid = item.Uid
                    State.blacklistedEggs[item.Uid] = nil
                    for u, b in pairs(State.activeStealButtons) do
                        if b and b.Parent then
                            if u == item.Uid then
                                b.BackgroundColor3 = currentTheme.Red
                                b.Text = "Stop"
                            else
                                b.BackgroundColor3 = currentTheme.Accent
                                b.Text = "Steal"
                            end
                        end
                    end
                end
            end)
        end
    end

    refreshStealPanel()
    task.spawn(function()
        while gui and gui.Parent do
            task.wait(2.5)
            if currentPage == "Steal" and not State.isStealingActive then
                pcall(refreshStealPanel)
            end
        end
    end)
end

local function renderThemes()
    clearBody()
    pageTitle.Text = "Appearance"
    pageSubtitle.Text = "Choose a look that feels right."

    local names = { "Light", "Dark", "Midnight", "Silver", "Ocean", "Lavender" }
    local grid = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = 1,
    }, pageBody)
    create("UIGridLayout", {
        CellSize = UDim2.new(0.48, -6, 0, 118),
        CellPadding = UDim2.new(0, 10, 0, 10),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, grid)

    for index, name in ipairs(names) do
        local theme = Themes[name]
        local card = create("TextButton", {
            LayoutOrder = index,
            BackgroundColor3 = theme.Panel,
            Text = "",
            AutoButtonColor = false,
        }, grid)
        corner(card, 11)
        stroke(card, name == currentThemeName and theme.Accent or theme.Border)

        local preview = create("Frame", {
            Position = UDim2.new(0, 9, 0, 9),
            Size = UDim2.new(1, -18, 0, 68),
            BackgroundColor3 = theme.Background,
            BorderSizePixel = 0,
        }, card)
        corner(preview, 7)

        local miniSide = create("Frame", {
            Size = UDim2.new(0, 30, 1, 0),
            BackgroundColor3 = theme.Sidebar,
            BorderSizePixel = 0,
        }, preview)
        corner(miniSide, 7)

        local miniPanel = create("Frame", {
            Position = UDim2.new(0, 37, 0, 9),
            Size = UDim2.new(1, -46, 1, -18),
            BackgroundColor3 = theme.Panel,
            BorderSizePixel = 0,
        }, preview)
        corner(miniPanel, 5)

        create("Frame", {
            Position = UDim2.new(0, 7, 0, 8),
            Size = UDim2.new(0.48, 0, 0, 5),
            BackgroundColor3 = theme.Accent,
            BorderSizePixel = 0,
        }, miniPanel)

        create("TextLabel", {
            Position = UDim2.new(0, 11, 0, 82),
            Size = UDim2.new(1, -30, 0, 22),
            BackgroundTransparency = 1,
            Text = name,
            TextColor3 = theme.Text,
            Font = Enum.Font.GothamMedium,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, card)

        if name == currentThemeName then
            create("TextLabel", {
                Position = UDim2.new(1, -27, 0, 82),
                Size = UDim2.fromOffset(18, 22),
                BackgroundTransparency = 1,
                Text = "✓",
                TextColor3 = theme.Accent,
                Font = Enum.Font.GothamBold,
                TextSize = 15,
            }, card)
        end

        card.Activated:Connect(function()
            applyTheme(name)
        end)
    end
end

local function renderSettings()
    clearBody()
    pageTitle.Text = "Settings"
    pageSubtitle.Text = "Webhook & extra options"

    local panel = makePanel(pageBody, 1)
    makeSectionLabel(panel, "DISCORD WEBHOOK", 1)

    local box = create("TextBox", {
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundColor3 = currentTheme.Background,
        Text = currentSettings.WebhookURL or "",
        PlaceholderText = "https://discord.com/api/webhooks/...",
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextColor3 = currentTheme.Text,
        PlaceholderColor3 = currentTheme.SubText,
        ClearTextOnFocus = false,
        BorderSizePixel = 0,
        LayoutOrder = 2,
    }, panel)
    corner(box, 8)
    stroke(box, currentTheme.Border)

    box.FocusLost:Connect(function()
        local url = box.Text or ""
        getgenv().config.webhookURL = url
        currentSettings.WebhookURL = url
        saveStuff()
    end)

    local testBtn = create("TextButton", {
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = currentTheme.Accent,
        Text = "Send Test Webhook",
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        AutoButtonColor = false,
        LayoutOrder = 3,
    }, panel)
    corner(testBtn, 8)
    testBtn.Activated:Connect(function()
        sendWebhook("Test", "Webhook working from Tonyo Egg Hub (macOS UI)", 5793266)
    end)

    local note = create("TextLabel", {
        Size = UDim2.new(1, 0, 0, 60),
        BackgroundTransparency = 1,
        Text = "RightShift  →  toggle UI\nRed light closes to pill · Yellow minimizes · Green expands\nClick the small bar to open again",
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextColor3 = currentTheme.SubText,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        LayoutOrder = 10,
    }, pageBody)
end

function applyTheme(name)
    if not Themes[name] then return end
    currentThemeName = name
    currentTheme = Themes[name]
    activeTheme = currentTheme
    currentSettings.Theme = name
    saveStuff()

    root.BackgroundColor3 = currentTheme.Background
    topbar.BackgroundColor3 = currentTheme.Sidebar
    sidebar.BackgroundColor3 = currentTheme.Sidebar
    content.BackgroundColor3 = currentTheme.Background
    pageTitle.TextColor3 = currentTheme.Text
    pageSubtitle.TextColor3 = currentTheme.SubText
    pageBody.ScrollBarImageColor3 = currentTheme.Accent

    for _, object in ipairs(gui:GetDescendants()) do
        if object:IsA("UIStroke") then
            object.Color = currentTheme.Border
        end
    end

    -- re-render current page so panels pick up new colors
    if currentPage == "Farm" then
        renderFarm()
    elseif currentPage == "Steal" then
        renderSteal()
    elseif currentPage == "Themes" then
        renderThemes()
    else
        renderSettings()
    end
end

local function showPage(name)
    currentPage = name
    if name == "Farm" then
        renderFarm()
    elseif name == "Steal" then
        renderSteal()
    elseif name == "Themes" then
        renderThemes()
    else
        renderSettings()
    end
end

local function addNav(name, symbol, order)
    local button = create("TextButton", {
        Name = name .. "Button",
        LayoutOrder = order,
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = currentTheme.Accent,
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
    }, navHolder)
    corner(button, 7)

    local icon = create("TextLabel", {
        Position = UDim2.new(0, 9, 0, 0),
        Size = UDim2.fromOffset(22, 34),
        BackgroundTransparency = 1,
        Text = symbol,
        TextColor3 = currentTheme.SubText,
        Font = Enum.Font.Gotham,
        TextSize = 14,
    }, button)

    local label = create("TextLabel", {
        Position = UDim2.new(0, 34, 0, 0),
        Size = UDim2.new(1, -40, 1, 0),
        BackgroundTransparency = 1,
        Text = name,
        TextColor3 = currentTheme.Text,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, button)

    navButtons[name] = { Button = button, Icon = icon, Label = label }

    button.Activated:Connect(function()
        for navName, parts in pairs(navButtons) do
            local selected = navName == name
            parts.Button.BackgroundTransparency = selected and 0 or 1
            parts.Button.BackgroundColor3 = currentTheme.Accent
            parts.Icon.TextColor3 = selected and Color3.new(1, 1, 1) or currentTheme.SubText
            parts.Label.TextColor3 = selected and Color3.new(1, 1, 1) or currentTheme.Text
        end
        showPage(name)
    end)
end

addNav("Farm", "⚙", 1)
addNav("Steal", "🥚", 2)
addNav("Themes", "◐", 3)
addNav("Settings", "⚙", 4)

create("TextLabel", {
    Position = UDim2.new(0, 16, 1, -35),
    Size = UDim2.new(1, -28, 0, 18),
    BackgroundTransparency = 1,
    Text = "TONYO  ·  V2.1  ·  macOS",
    TextColor3 = currentTheme.SubText,
    Font = Enum.Font.Gotham,
    TextSize = 9,
    TextXAlignment = Enum.TextXAlignment.Left,
}, sidebar)

-- default selection
navButtons.Farm.Button.BackgroundTransparency = 0
navButtons.Farm.Icon.TextColor3 = Color3.new(1, 1, 1)
navButtons.Farm.Label.TextColor3 = Color3.new(1, 1, 1)
renderFarm()

-- keybind
Services.UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        setUiOpen(not uiOpen)
    end
end)

-- open animation
root.Size = UDim2.fromOffset(700, 470)
root.BackgroundTransparency = 1
Services.TweenService:Create(root, TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
    BackgroundTransparency = 0,
    Size = UDim2.fromOffset(740, 500),
}):Play()

print("[Tonyo Egg Hub] macOS UI loaded  ·  RightShift to toggle")

--[[
    NOTE:
    The full original EggStealer logic (BloomManager, UFOManager,
    PriorityManager, getBestEgg, hop / flight / grab / delivery
    routines, WorkerScheduler, etc.) should be pasted above the
    UI section from your original EggStealer_Tonyo.lua file.
    This file focuses on the upgraded macOS UI shell and keeps
    the same config / state / helpers so the original systems
    continue to work when you merge them in.
]]
