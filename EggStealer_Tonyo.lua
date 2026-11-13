--[[
    Egg Stealer // Tonyo
    cleaned up version - fixed the undefined root crash on ufo tp checks
    ui refreshed a bit, config renamed so it doesnt clash with other hubs
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
if duration > 0 then
task.wait(duration + 0.05)
else
task.wait(0.04)
end
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
local ok1, conns1 = pcall(getconnections, btn.Activated)
if ok1 and type(conns1) == "table" then
for _, c in ipairs(conns1) do
pcall(function()
if c.Fire then c:Fire() elseif c.Function then c.Function() end
end)
triggered = true
end
end
local ok2, conns2 = pcall(getconnections, btn.MouseButton1Click)
if ok2 and type(conns2) == "table" then
for _, c in ipairs(conns2) do
pcall(function()
if c.Fire then c:Fire() elseif c.Function then c.Function() end
end)
triggered = true
end
end
if triggered then return true end
end

return false
end

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

local UFOManager, PriorityManager, getBestEgg, activeTheme, Window

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
themeName = currentSettings.Theme or "Sapphire",
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
local packages = Services.ReplicatedStorage:FindFirstChild("Packages") or (Services.ReplicatedStorage.WaitForChild and Services.ReplicatedStorage:WaitForChild("Packages", 3))
local networking = packages and (packages:FindFirstChild("Networking") or (packages.WaitForChild and packages:WaitForChild("Networking", 3)))
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
if ragdollEndTime > workspace:GetServerTimeNow() then
return
end

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
if hum then
pcall(function()
hum.PlatformStand = false
hum.Sit = false
hum:ChangeState(Enum.HumanoidStateType.Running)
end)
end
if root then
pcall(function()
root.AssemblyLinearVelocity = Vector3.zero
root.AssemblyAngularVelocity = Vector3.zero
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
if gui.Name ~= "SyntaxHubGUI" and gui.Name ~= "RunBackEffects" and gui.Name ~= "DropHeldEgg" then
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
if State.activeStealButtons[State.targetedSpecificUid] then
State.activeStealButtons[State.targetedSpecificUid].BackgroundColor3 = activeTheme and activeTheme.Accent or Color3.fromRGB(92, 170, 255)
State.activeStealButtons[State.targetedSpecificUid].Text = "Steal"
end
State.targetedSpecificUid = nil
end

if PriorityManager then
PriorityManager:Release("Steal")
PriorityManager:Release("Auto Steal")
end

ShieldManager:UnmuteUGI()
ShieldManager:UndoSwap()
StealUIManager:Unlock()
cleanupFlightState()
setCollisions(true)

local _, root, hum = getAliveRig()
if root then
root.AssemblyLinearVelocity = Vector3.zero
root.AssemblyAngularVelocity = Vector3.zero
end
if hum then
hum.PlatformStand = false
hum.Sit = false
end
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

local BloomManager = {
IsBusy = false,
LastTradeCraft = 0,
LastWispAction = 0,
LastWispFailure = 0,
TrackedButterflies = {},
NetReach = 14,
CenterPosition = Vector3.new(6700, 74, -364),
TradeTiers = { "Green", "Blue", "Purple" },
CostMap = { Green = 10, Blue = 10, Purple = 50 },
EssenceCost = { Green = 240, Blue = 115, Purple = 40, Golden = 1 }
}

pcall(function()
local flagsMod = Services.ReplicatedStorage:FindFirstChild("Shared") and Services.ReplicatedStorage.Shared:FindFirstChild("Flags") and Services.ReplicatedStorage.Shared.Flags:FindFirstChild("ButterflyFlags")
if flagsMod then
local ok, flags = pcall(require, flagsMod)
if ok and flags and flags.NetReach and flags.NetReach.Get then
BloomManager.NetReach = tonumber(flags.NetReach:Get()) or 14
end
if ok and flags then
if flags.GreenToBlueCost and flags.GreenToBlueCost.Get then BloomManager.CostMap.Green = tonumber(flags.GreenToBlueCost:Get()) or 10 end
if flags.BlueToPurpleCost and flags.BlueToPurpleCost.Get then BloomManager.CostMap.Blue = tonumber(flags.BlueToPurpleCost:Get()) or 10 end
if flags.PurpleToGoldenCost and flags.PurpleToGoldenCost.Get then BloomManager.CostMap.Purple = tonumber(flags.PurpleToGoldenCost:Get()) or 50 end
if flags.EssenceGreen and flags.EssenceGreen.Get then BloomManager.EssenceCost.Green = tonumber(flags.EssenceGreen:Get()) or 240 end
if flags.EssenceBlue and flags.EssenceBlue.Get then BloomManager.EssenceCost.Blue = tonumber(flags.EssenceBlue:Get()) or 115 end
if flags.EssencePurple and flags.EssencePurple.Get then BloomManager.EssenceCost.Purple = tonumber(flags.EssencePurple:Get()) or 40 end
if flags.EssenceGolden and flags.EssenceGolden.Get then BloomManager.EssenceCost.Golden = tonumber(flags.EssenceGolden:Get()) or 1 end
end
end
end)

pcall(function()
local reSpawned = getRemote("RE/Butterflies/Spawned")
if reSpawned and reSpawned:IsA("RemoteEvent") then
reSpawned.OnClientEvent:Connect(function(arg1, arg2)
local bf = (type(arg1) == "table" and arg1) or (type(arg2) == "table" and arg2)
if bf and bf.Id then
BloomManager.TrackedButterflies[bf.Id] = bf
end
end)
end
local reRemoved = getRemote("RE/Butterflies/Removed")
if reRemoved and reRemoved:IsA("RemoteEvent") then
reRemoved.OnClientEvent:Connect(function(id)
if id then BloomManager.TrackedButterflies[id] = nil end
end)
end
local reEscaped = getRemote("RE/Butterflies/Escaped")
if reEscaped and reEscaped:IsA("RemoteEvent") then
reEscaped.OnClientEvent:Connect(function(id)
if id then BloomManager.TrackedButterflies[id] = nil end
end)
end
end)

function BloomManager:IsEventActive()
local endsAt = tonumber(workspace:GetAttribute("ButterflyBloomEndsAt"))
local isEvent = (workspace:GetAttribute("Event_ButterflyBloom") == true)
if isEvent then
if endsAt then return workspace:GetServerTimeNow() < endsAt end
return true
end
return false
end

function BloomManager:GetButterflyNet()
local char = LocalPlayer.Character
if not char then return nil end
local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
for _, item in ipairs(char:GetChildren()) do
if item:IsA("Tool") and (item:GetAttribute("ButterflyNet") == true or tostring(item:GetAttribute("ItemType")) == "ButterflyNet" or item.Name == "Butterfly Net") then
return item
end
end
if backpack then
for _, item in ipairs(backpack:GetChildren()) do
if item:IsA("Tool") and (item:GetAttribute("ButterflyNet") == true or tostring(item:GetAttribute("ItemType")) == "ButterflyNet" or item.Name == "Butterfly Net") then
return item
end
end
end
return nil
end

function BloomManager:EnsureNetEquipped()
local tool = self:GetButterflyNet()
local char = LocalPlayer.Character
local hum = char and char:FindFirstChildOfClass("Humanoid")
if tool and char and hum then
if tool.Parent ~= char then
pcall(function() hum:EquipTool(tool) end)
end
return tool
end
if Remotes.ClaimNet then
pcall(function() Remotes.ClaimNet:InvokeServer() end)
task.wait(0.2)
local claimed = self:GetButterflyNet()
if claimed and char and hum and claimed.Parent ~= char then
pcall(function() hum:EquipTool(claimed) end)
end
return claimed
end
return nil
end

function BloomManager:GetGroundPosition(targetPos)
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local filter = {}
local char = LocalPlayer.Character
if char then table.insert(filter, char) end
local swarm = Services.Workspace:FindFirstChild("ButterflyBloomSwarm")
if swarm then table.insert(filter, swarm) end
rayParams.FilterDescendantsInstances = filter

local hit = Services.Workspace:Raycast(targetPos + Vector3.new(0, 25, 0), Vector3.new(0, -120, 0), rayParams)
local _, _, hum = getAliveRig()
local hipHeight = (hum and hum.HipHeight) or 2
if hit then
return Vector3.new(targetPos.X, hit.Position.Y + hipHeight + 1, targetPos.Z)
end
return targetPos
end

function BloomManager:GetLiveButterflies()
local list = {}
local swarm = Services.Workspace:FindFirstChild("ButterflyBloomSwarm")
if swarm then
for _, b in ipairs(swarm:GetChildren()) do
if b:IsA("Model") or b:IsA("BasePart") then
table.insert(list, b)
end
end
end
if #list == 0 then
for id, data in pairs(self.TrackedButterflies) do
if data and data.Position then
table.insert(list, data)
end
end
end
return list
end

function BloomManager:HasWork()
if isMapClosed() then return false end
if getgenv().config.autoCatchButterfly and self:IsEventActive() then
return true
end
if getgenv().config.autoWispQuest and self:HasWispWork() then
return true
end
if (getgenv().config.autoTradeUp or getgenv().config.autoCraftEssence) and self:HasMachineWork() then
return true
end
return false
end

local function getWispTargetPosition(kind)
local world = Services.Workspace:FindFirstChild("World") or Services.Workspace:FindFirstChild("__OBJECTS") or Services.Workspace
local build = world:FindFirstChild("Build") or Services.Workspace:FindFirstChild("Build")

if kind == "WispSpawn" then
local p = build and build:FindFirstChild("EnchantedForestZone") and build.EnchantedForestZone:FindFirstChild("WispSpawn")
if not p then p = Services.Workspace:FindFirstChild("WispSpawn", true) end
if p then
return (p:IsA("BasePart") and p.Position) or (p:IsA("Model") and p:GetPivot().Position) or (p:IsA("Attachment") and p.WorldPosition)
end
elseif kind == "WispAnchor" then
local p = build and build:FindFirstChild("EnchantedForestZone")
local anchor = p and p:FindFirstChild("Zone13Props") and p.Zone13Props:FindFirstChild("EnchantedTree") and p.Zone13Props.EnchantedTree:FindFirstChild("WispAnchor")
if not anchor and p then anchor = p:FindFirstChild("WispAnchor") end
if not anchor then anchor = Services.Workspace:FindFirstChild("WispAnchor", true) end
if anchor then
return (anchor:IsA("BasePart") and anchor.Position) or (anchor:IsA("Model") and anchor:GetPivot().Position) or (anchor:IsA("Attachment") and anchor.WorldPosition)
end
end
return nil
end

function BloomManager:StepTowards(targetPos, maxDuration)
local _, root, hum = getAliveRig()
if not root or not hum then return false end

pcall(function() LocalPlayer:RequestStreamAroundAsync(targetPos) end)
local deadline = os.clock() + (maxDuration or 10.0)

while os.clock() < deadline do
local _, curRoot, curHum = getAliveRig()
if not curRoot or not curHum then return false end

local horizDiff = Vector3.new(targetPos.X - curRoot.Position.X, 0, targetPos.Z - curRoot.Position.Z)
local dist = horizDiff.Magnitude
if dist <= 6 then
return true
end

if dist > 35 then
local speed = tonumber(getgenv().config.butterflySpeed) or 320
local stepSize = math.clamp(speed * 0.1, 15, 45)
local stepTarget = curRoot.Position + horizDiff.Unit * math.min(dist, stepSize)

local ground = self:GetGroundPosition(stepTarget)
curRoot.CFrame = CFrame.new(Vector3.new(stepTarget.X, ground.Y, stepTarget.Z))
curRoot.AssemblyLinearVelocity = Vector3.new(0, math.clamp(curRoot.AssemblyLinearVelocity.Y, -50, 50), 0)
task.wait(0.08)
else
curHum:MoveTo(targetPos)
task.wait(0.15)
end
end

local _, endRoot = getAliveRig()
return endRoot and (targetPos - endRoot.Position).Magnitude <= 10
end

function BloomManager:HandleFusery(quest)
local save = getSaveData()
if not save then return end

local finishRevealRemote = getRemote("RF/Fusery/FinishReveal")
if save.FusionLocked then
if type(save.FusionEggReward) == "table" and finishRevealRemote then
pcall(function() finishRevealRemote:InvokeServer() end)
end
return
end

local areaId = type(quest.Match) == "table" and quest.Match.AreaId
local areaConfigs = Services.ReplicatedStorage:FindFirstChild("Data") and Services.ReplicatedStorage.Data:FindFirstChild("Areas") and Services.ReplicatedStorage.Data.Areas:FindFirstChild("Configs")
local dropCategories = {}
if areaConfigs and areaId then
local cfgMod = areaConfigs:FindFirstChild(tostring(areaId))
if cfgMod and cfgMod:IsA("ModuleScript") then
local ok, cfg = pcall(require, cfgMod)
if ok and cfg and type(cfg.DropTable) == "table" then
for _, row in ipairs(cfg.DropTable) do
local cat = row[1] or row.Category
if cat then dropCategories[tostring(cat)] = true end
end
end
end
end

local readyPets = {}
if type(save.Inventory) == "table" then
for petUid, petData in pairs(save.Inventory) do
if type(petData) == "table" and not petData.IsFavorite and not petData.InFuse then
local cat = tostring(petData.AssetCategory)
if dropCategories[cat] or not areaId then
table.insert(readyPets, petUid)
if #readyPets >= 3 then break end
end
end
end
end

if #readyPets >= 3 then
local ejectRemote = getRemote("RF/Fusery/EjectPet")
local briefingRemote = getRemote("RF/Fusery/ConfirmBriefing")
local loadRemote = getRemote("RF/Fusery/LoadPet")
local fuseRemote = getRemote("RF/Fusery/BeginFuse")

local fusionSlots = (type(save.FusionSlots) == "table" and save.FusionSlots) or {}
local readyMap = { [readyPets[1]] = true, [readyPets[2]] = true, [readyPets[3]] = true }
local loadedMap = {}

for _, slotPet in ipairs(fusionSlots) do
if readyMap[slotPet] then
loadedMap[slotPet] = true
elseif ejectRemote then
pcall(function() ejectRemote:InvokeServer(slotPet) end)
task.wait(0.2)
end
end

if save.FusionInfoAcknowledged == false and briefingRemote then
pcall(function() briefingRemote:InvokeServer() end)
task.wait(0.2)
end

for _, pUid in ipairs(readyPets) do
if not loadedMap[pUid] and loadRemote then
pcall(function() loadRemote:InvokeServer(pUid) end)
task.wait(0.2)
end
end

if fuseRemote then
pcall(function() fuseRemote:InvokeServer() end)
task.wait(0.3)
end
end
end

function BloomManager:HasWispWork()
if isMapClosed() then return false end
if os.clock() - self.LastWispAction < 2.0 then return false end
if os.clock() - self.LastWispFailure < 15.0 then return false end

local save = getSaveData()
local wispComp = save and save.WispCompanion
if type(wispComp) ~= "table" then return false end
if wispComp.Unlocked == true then return false end

local wispData = GameModules:Get("Wisp")
local reqSpeed = (wispData and tonumber(wispData.RequiredSpeedPower)) or 50000000000
local stageCount = (wispData and tonumber(wispData.StageCount)) or 4

if not wispComp.Accepted then
if (tonumber(save.SpeedPower) or 0) < reqSpeed then return false end
local build = Services.Workspace:FindFirstChild("Build")
if not (build and build:GetAttribute("EnchantedForestZoneRevealed") == true) then return false end
return true
end

local stage = tonumber(wispComp.Stage) or 1
if stage >= stageCount then
return true
end

local quest = wispData and wispData.List and wispData.List[stage]
if quest then
local isClaimed = type(wispComp.Claimed) == "table" and wispComp.Claimed[quest.Id]
local progress = type(wispComp.Progress) == "table" and tonumber(wispComp.Progress[quest.Id]) or 0
local target = tonumber(quest.Target) or 1
if not isClaimed and progress >= target then
return true
end

if quest.Event == "PetFused" then
if save.FusionLocked then return true end
local count = 0
if type(save.Inventory) == "table" then
for _, pet in pairs(save.Inventory) do
if type(pet) == "table" and not pet.IsFavorite and not pet.InFuse then
count = count + 1
end
end
end
if count >= 3 then return true end
end
end

return false
end

function BloomManager:ProcessWisp()
local save = getSaveData()
local wispComp = save and save.WispCompanion
if type(wispComp) ~= "table" or wispComp.Unlocked == true then return end

local remote = getRemote("RF/WispCompanion/Request")
if not remote then return end

local wispData = GameModules:Get("Wisp")
local reqSpeed = (wispData and tonumber(wispData.RequiredSpeedPower)) or 50000000000
local stageCount = (wispData and tonumber(wispData.StageCount)) or 4

if not wispComp.Accepted then
if (tonumber(save.SpeedPower) or 0) < reqSpeed then
self.LastWispFailure = os.clock()
return
end
local build = Services.Workspace:FindFirstChild("Build")
if not (build and build:GetAttribute("EnchantedForestZoneRevealed") == true) then
self.LastWispFailure = os.clock()
return
end

local spawnPos = getWispTargetPosition("WispSpawn")
if not spawnPos then
self.LastWispFailure = os.clock()
return
end

if self:StepTowards(spawnPos, 12.0) then
task.wait(0.5)
local ok = pcall(function() remote:InvokeServer("Accept") end)
if ok then
self.LastWispAction = os.clock()
else
self.LastWispFailure = os.clock()
end
else
self.LastWispFailure = os.clock()
end
return
end

local stage = tonumber(wispComp.Stage) or 1
local quest = wispData and wispData.List and wispData.List[stage]

if quest then
local isClaimed = type(wispComp.Claimed) == "table" and wispComp.Claimed[quest.Id]
local progress = type(wispComp.Progress) == "table" and tonumber(wispComp.Progress[quest.Id]) or 0
local target = tonumber(quest.Target) or 1

if not isClaimed and progress >= target then
local ok = pcall(function() remote:InvokeServer("Claim", quest.Id) end)
if ok then
self.LastWispAction = os.clock()
else
self.LastWispFailure = os.clock()
end
return
end
end

if stage >= stageCount then
if not wispComp.Returning then
pcall(function() remote:InvokeServer("BeginReturn") end)
task.wait(0.3)
end

local anchorPos = getWispTargetPosition("WispAnchor")
if not anchorPos then
self.LastWispFailure = os.clock()
return
end

if self:StepTowards(anchorPos, 12.0) then
task.wait(0.5)
local ok = pcall(function() remote:InvokeServer("Return") end)
if ok then
self.LastWispAction = os.clock()
else
self.LastWispFailure = os.clock()
end
else
self.LastWispFailure = os.clock()
end
return
end

if quest and quest.Event == "PetFused" then
self:HandleFusery(quest)
self.LastWispAction = os.clock()
end
end

function BloomManager:HasMachineWork()
local save = getSaveData()
local counts = (save and type(save.Butterflies) == "table" and save.Butterflies.Counts) or {}
if getgenv().config.autoCraftEssence then
local canCraft = true
for k, req in pairs(self.EssenceCost) do
if (counts[k] or 0) < req then canCraft = false break end
end
if canCraft then return true end
end
if getgenv().config.autoTradeUp then
for _, tier in ipairs(self.TradeTiers) do
if (counts[tier] or 0) >= (self.CostMap[tier] or 10) then
return true
end
end
end
return false
end

function BloomManager:EnterEnchantedTree()
if LocalPlayer:GetAttribute("InEnchantedTree") == true then return true end
local world = Services.Workspace:FindFirstChild("World") or Services.Workspace
local enterTrigger = world:FindFirstChild("EnchantedTreeEntrance", true) or world:FindFirstChild("EnterTrigger", true)
local prompt = enterTrigger and enterTrigger:FindFirstChildWhichIsA("ProximityPrompt", true)
if prompt and prompt.Parent then
local tPos = prompt.Parent:IsA("BasePart") and prompt.Parent.Position or prompt.Parent:GetPivot().Position
local _, root, hum = getAliveRig()
if root then
root.CFrame = CFrame.new(tPos + Vector3.new(0, 2, -4))
root.AssemblyLinearVelocity = Vector3.zero
task.wait(0.2)
UniversalCompat.FireProximityPrompt(prompt)
local timeout = os.clock() + 4.0
while os.clock() < timeout do
if LocalPlayer:GetAttribute("InEnchantedTree") == true then return true end
task.wait(0.1)
end
end
end
return LocalPlayer:GetAttribute("InEnchantedTree") == true
end

function BloomManager:LeaveEnchantedTree()
if LocalPlayer:GetAttribute("InEnchantedTree") ~= true then return true end
local interior = Services.Workspace:FindFirstChild("EnchantedTreeInterior", true)
local exitPart = interior and interior:FindFirstChild("ExitTrigger", true)
if exitPart and exitPart:IsA("BasePart") then
local _, root = getAliveRig()
if root then
root.CFrame = exitPart.CFrame
root.AssemblyLinearVelocity = Vector3.zero
UniversalCompat.FireTouch(root, exitPart)
local prompt = exitPart:FindFirstChildWhichIsA("ProximityPrompt")
if prompt then UniversalCompat.FireProximityPrompt(prompt) end
local timeout = os.clock() + 3.0
while os.clock() < timeout do
if LocalPlayer:GetAttribute("InEnchantedTree") ~= true then return true end
task.wait(0.1)
end
end
end
return true
end

function BloomManager:Process()
if State.isStealingActive or isHoldingEgg() then return end
self.IsBusy = true

if getgenv().config.autoCatchButterfly and self:IsEventActive() then
self:EnsureNetEquipped()
local _, root, hum = getAliveRig()
if root and hum then
local mode = getgenv().config.bloomCatchMode or "Stand"
local butterflies = self:GetLiveButterflies()

if mode == "Stand" then
local distToCenter = (root.Position - self.CenterPosition).Magnitude
if distToCenter > 12 then
local groundCenter = self:GetGroundPosition(self.CenterPosition)
root.CFrame = CFrame.new(groundCenter)
root.AssemblyLinearVelocity = Vector3.zero
task.wait(0.2)
end

for _, b in ipairs(butterflies) do
local bPos = (typeof(b.Position) == "Vector3" and b.Position) or (b:IsA("BasePart") and b.Position) or (b:IsA("Model") and b:GetPivot().Position)
if bPos and (bPos - root.Position).Magnitude <= (self.NetReach + 4) then
local tool = self:EnsureNetEquipped()
if tool then pcall(function() tool:Activate() end) end
task.wait(0.1)
end
end
else
local bestB = nil
local bestDist = math.huge
for _, b in ipairs(butterflies) do
local bPos = (typeof(b.Position) == "Vector3" and b.Position) or (b:IsA("BasePart") and b.Position) or (b:IsA("Model") and b:GetPivot().Position)
if bPos then
local d = (bPos - root.Position).Magnitude
if d < bestDist and d <= 250 then
bestDist = d
bestB = b
end
end
end

if bestB then
local bPos = (typeof(bestB.Position) == "Vector3" and bestB.Position) or (bestB:IsA("BasePart") and bestB.Position) or (bestB:GetPivot().Position)
local groundPos = self:GetGroundPosition(bPos)
local speed = tonumber(getgenv().config.butterflySpeed) or 320
local dir = (groundPos - root.Position)
if dir.Magnitude > 6 then
root.CFrame = CFrame.new(root.Position + dir.Unit * math.min(dir.Magnitude, speed * 0.05))
end
local tool = self:EnsureNetEquipped()
if tool and (bPos - root.Position).Magnitude <= self.NetReach then
pcall(function() tool:Activate() end)
end
end
end
end
end

if getgenv().config.autoWispQuest and self:HasWispWork() then
self:ProcessWisp()
end

if (getgenv().config.autoTradeUp or getgenv().config.autoCraftEssence) and self:HasMachineWork() then
if os.clock() - self.LastTradeCraft >= 2.0 then
self.LastTradeCraft = os.clock()
if self:EnterEnchantedTree() then
local tradeRemote = getRemote("RF/Butterflies/AskTradeUp")
local craftRemote = getRemote("RF/Butterflies/AskCraftEssence")

if getgenv().config.autoTradeUp and tradeRemote then
local save = getSaveData()
local counts = (save and type(save.Butterflies) == "table" and save.Butterflies.Counts) or {}
for _, tier in ipairs(self.TradeTiers) do
local req = self.CostMap[tier] or 10
if (counts[tier] or 0) >= req then
pcall(function() tradeRemote:InvokeServer("ButterflyMachine", tier) end)
task.wait(0.2)
end
end
end

if getgenv().config.autoCraftEssence and craftRemote then
pcall(function() craftRemote:InvokeServer("MutationShrine") end)
task.wait(0.2)
end

self:LeaveEnchantedTree()
end
end
end

self.IsBusy = false
end

UFOManager = {
IsBusy = false,
State = {
st = {},
sus = {},
eggs = 0,
no = 0,
left = nil
},
Codes = { "4827", "0327" },
PipeValueMap = { Straight = 5, Elbow = 3, Cross = 15 },
PipeDirs = {
{ 1, -1, 0, 4 },
{ 2, 0, 1, 8 },
{ 4, 1, 0, 1 },
{ 8, 0, -1, 2 }
}
}

pcall(function()
local reState = getRemote("RE/UFOSightings/State")
if reState and reState:IsA("RemoteEvent") then
reState.OnClientEvent:Connect(function(st)
if type(st) == "table" then
UFOManager.State.st = st
UFOManager.State.sus = {}
for _, uid in ipairs(st.Suspicious or {}) do
UFOManager.State.sus[uid] = true
end
end
end)
end
end)

function UFOManager:FetchState()
local fetchRemote = getRemote("RF/UFOSightings/Fetch")
if fetchRemote and fetchRemote:IsA("RemoteFunction") then
local ok, st = pcall(function() return fetchRemote:InvokeServer() end)
if ok and type(st) == "table" then
self.State.st = st
self.State.sus = {}
for _, uid in ipairs(st.Suspicious or {}) do
self.State.sus[uid] = true
end
return st
end
end
return nil
end

function UFOManager:GetUfoPosition()
local ufo = self.State.st and self.State.st.Ufo
if not ufo then return nil end
if typeof(ufo) == "Instance" then
if ufo:IsA("Model") then
return ufo:GetPivot().Position
elseif ufo:IsA("BasePart") then
return ufo.Position
end
elseif typeof(ufo) == "Vector3" then
return ufo
end
return nil
end

task.spawn(function()
task.wait(1.0)
pcall(function() UFOManager:FetchState() end)
end)

function UFOManager:RotateMask(mask, steps)
for i = 1, steps do
mask = bit32.band(bit32.bor(bit32.lshift(mask, 1), bit32.rshift(mask, 3)), 15)
end
return mask
end

function UFOManager:SolvePipePuzzle(seed)
local puzzleMod = Services.ReplicatedStorage:FindFirstChild("Shared") and Services.ReplicatedStorage.Shared:FindFirstChild("Modules") and Services.ReplicatedStorage.Shared.Modules:FindFirstChild("UFOSightingsPipePuzzle")
if not puzzleMod then return nil end
local ok, puzzleLib = pcall(require, puzzleMod)
if not ok or not puzzleLib or typeof(puzzleLib.Generate) ~= "function" then return nil end

local grid = puzzleLib.Generate(seed)
local visited = {}
local rotations = {}

for r = 1, 5 do
for c = 1, 5 do
rotations[((r - 1) * 5) + c] = grid[r][c].Rotation
end
end

local function dfs(r, c, enterBit)
local idx = ((r - 1) * 5) + c
visited[idx] = true

for rot = 0, 3 do
local basePiece = grid[r][c].Piece
local pieceMask = self.PipeValueMap[basePiece] or 5
local rotated = self:RotateMask(pieceMask, rot)

if bit32.band(rotated, enterBit) ~= 0 then
rotations[idx] = rot
if r == 4 and c == 5 and bit32.band(rotated, 2) ~= 0 then
return true
end

for _, dirData in ipairs(self.PipeDirs) do
local outBit, dr, dc, oppBit = dirData[1], dirData[2], dirData[3], dirData[4]
if outBit ~= enterBit and bit32.band(rotated, outBit) ~= 0 then
local nr, nc = r + dr, c + dc
if nr >= 1 and nr <= 5 and nc >= 1 and nc <= 5 then
local nIdx = ((nr - 1) * 5) + nc
if not visited[nIdx] then
if dfs(nr, nc, oppBit) then return true end
end
end
end
end
end
end

visited[idx] = nil
return false
end

if dfs(2, 1, 8) then
return rotations
end
return nil
end

function UFOManager:IsInRareUFO()
local interior = self.State.st and self.State.st.Interior
if interior and (tonumber(interior.EndsAt) or 0) > 0 then return true end
local rareModel = Services.Workspace:FindFirstChild("RareUFOInterior")
return rareModel ~= nil
end

function UFOManager:HasWork()
local anyUfo = getgenv().config.autoUFO or getgenv().config.ufoRocks or getgenv().config.ufoTrade or getgenv().config.ufoRare
if not anyUfo then return nil end
local st = self.State.st or {}

if not st.Available then return nil end
if st.SpeedLocked or st.Tutorial then return nil end
if State.isStealingActive or isHoldingEgg() then return nil end

if self:IsInRareUFO() then return "inside" end
if os.clock() < (self.State.no or 0) then return nil end
if isMapClosed() then return nil end

if getgenv().config.autoUFO then
if not st.Unlocked then return "repair" end
if st.Reward then return "reward" end
end
if getgenv().config.ufoRocks and st.Rocks and st.Rocks.List and #st.Rocks.List > 0 then return "rocks" end
if getgenv().config.ufoTrade and (st.SpaceRocks or 0) >= (st.RockCost or math.huge) then return "trade" end
if getgenv().config.ufoRare and st.Event and st.Event.Variant == "Rare" and st.Decoded and st.Event.Id ~= self.State.left then
return "board"
end
if getgenv().config.autoUFO then
if st.Event and st.Required and not st.Decoded and not st.Complete then return "decode" end
if st.Event and st.Decoded and not st.Complete and st.Event.Variant ~= "Rare" then return "hold" end
end
return nil
end

function UFOManager:IsUfoEgg(eggRecord, uid)
if not getgenv().config.autoUFO then return false end
local st = self.State.st
if not (st and st.Available and st.Event and st.Decoded and not st.Complete and st.Event.Variant ~= "Rare") then
return false
end
if uid and self.State.sus[uid] then return true end
if next(self.State.sus) == nil and eggRecord then
local area = eggRecord.AreaId or (eggRecord.Record and eggRecord.Record.AreaId)
if tostring(area) == tostring(st.Biome) then return true end
end
return false
end

function UFOManager:Process()
local work = self:HasWork()
if not work then return end
local _, root, hum = getAliveRig()
if not root or not hum then return end
self.IsBusy = true

if work == "repair" then
local camp = Services.Workspace:FindFirstChild("UFOSightingsCamp")
local repairSuccess = false
if camp then
if not self.State.st.MetChaser then
local chaser = camp:FindFirstChild("AlienChaser")
local cRoot = chaser and chaser:FindFirstChild("HumanoidRootPart")
if cRoot then
root.CFrame = CFrame.new(cRoot.Position + Vector3.new(0, 2, -4))
root.AssemblyLinearVelocity = Vector3.zero
task.wait(0.3)
invokeRemote("RF/UFOSightings/Talk")
self:FetchState()
end
end

local repairPoint = camp:FindFirstChild("Root") and camp.Root:FindFirstChild("RepairPoint")
local rPos = repairPoint and (repairPoint:IsA("Attachment") and repairPoint.WorldPosition or repairPoint.Position)
if rPos then
root.CFrame = CFrame.new(rPos + Vector3.new(0, 2, 0))
root.AssemblyLinearVelocity = Vector3.zero
task.wait(0.2)
local ok, success, puzzleData = invokeRemote("RF/UFOSightings/Repair", "Begin")

if ok and success and type(puzzleData) == "table" and puzzleData.Seed then
local solvedRotations = self:SolvePipePuzzle(puzzleData.Seed)
if solvedRotations then
task.wait(3.4)
invokeRemote("RF/UFOSightings/Repair", "Finish", { Id = puzzleData.Id, Rotations = solvedRotations })
self:FetchState()
repairSuccess = true
end
end
end
end
if not repairSuccess then
self.State.no = os.clock() + 60
end

elseif work == "decode" then
local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
local function getDecoder()
for _, t in ipairs(root.Parent:GetChildren()) do
if t:IsA("Tool") and t:GetAttribute("UFOSignalDecoder") == true then return t end
end
if backpack then
for _, t in ipairs(backpack:GetChildren()) do
if t:IsA("Tool") and t:GetAttribute("UFOSignalDecoder") == true then return t end
end
end
return nil
end

local decoder = getDecoder()
if decoder and hum then
pcall(function() hum:EquipTool(decoder) end)
local timeout = os.clock() + 60.0
local bestSignal = 0
local bestX = root.Position.X
local dir = 1
local nextEquipCheck = os.clock() + 0.5

while os.clock() < timeout do
if not self.State.st.Event or self.State.st.Decoded then break end

if os.clock() >= nextEquipCheck then
nextEquipCheck = os.clock() + 0.5
local curDecoder = getDecoder()
if curDecoder and curDecoder.Parent ~= root.Parent then
pcall(function() hum:EquipTool(curDecoder) end)
end
end

local signal = tonumber(self.State.st.Signal) or 0
local curX = root.Position.X
if signal > bestSignal then
bestSignal = signal
bestX = curX
end

if curX > 6950 and dir > 0 then
dir = -1
elseif curX < 650 and dir < 0 then
dir = 1
end

local speed = (signal < 2 and 180) or 80
local targetVelX = dir * speed

if bestSignal >= 4 then
targetVelX = math.clamp((bestX - curX) * 5, -60, 60)
else
if signal < bestSignal then
if math.abs(bestX - curX) < 20 then
bestSignal = signal
dir = -dir
else
targetVelX = math.sign(bestX - curX) * math.min(speed, 120)
end
end
end

root.AssemblyLinearVelocity = Vector3.new(
targetVelX,
root.AssemblyLinearVelocity.Y,
math.clamp((-365 - root.Position.Z) * 5, -50, 50)
)
task.wait(0.05)
end
root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
pcall(function() hum:UnequipTools() end)
self:FetchState()
end

elseif work == "board" then
local uPos = self:GetUfoPosition()
if uPos then
local targetPos = uPos - Vector3.new(0, 85, 0)
local approachTimeout = os.clock() + 2.0
while os.clock() < approachTimeout and not self:IsInRareUFO() do
local diff = targetPos - root.Position
if diff.Magnitude <= 8 then break end
root.CFrame = CFrame.new(root.Position + diff.Unit * math.min(diff.Magnitude, 30))
root.AssemblyLinearVelocity = Vector3.zero
task.wait(0.08)
end
root.CFrame = CFrame.new(targetPos)
root.AssemblyLinearVelocity = Vector3.zero

local timeout = os.clock() + 8.0
while os.clock() < timeout and not self:IsInRareUFO() do
task.wait(0.1)
end
end

elseif work == "inside" then
local rareInterior = Services.Workspace:FindFirstChild("RareUFOInterior")
local capsules = rareInterior and rareInterior:FindFirstChild("Interactables") and rareInterior.Interactables:FindFirstChild("Capsules")

local function getWeapon()
for _, t in ipairs(root.Parent:GetChildren()) do
if t:IsA("Tool") and t.Name ~= "UFOSignalDecoder" and t.Name ~= "Butterfly Net" then return t end
end
local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
if bp then
for _, t in ipairs(bp:GetChildren()) do
if t:IsA("Tool") and t.Name ~= "UFOSignalDecoder" and t.Name ~= "Butterfly Net" then return t end
end
end
return nil
end

local weapon = getWeapon()
if weapon and hum and weapon.Parent ~= root.Parent then
pcall(function() hum:EquipTool(weapon) end)
end

if capsules then
for _, cap in ipairs(capsules:GetChildren()) do
if cap:IsA("Model") and not (self.State.st.Interior and self.State.st.Interior.Broken and table.find(self.State.st.Interior.Broken, cap.Name)) then
local intRocks = self.State.st.Rocks
if intRocks and intRocks.List then
for _, r in ipairs(intRocks.List) do
pcall(function() fireRemote("RE/UFOSightings/CollectRock", intRocks.Id, r.Index) end)
end
end

local capPos = cap:GetPivot().Position
root.CFrame = CFrame.new(capPos + Vector3.new(0, 1, 3))
root.AssemblyLinearVelocity = Vector3.zero
if weapon then
if weapon.Parent ~= root.Parent then pcall(function() hum:EquipTool(weapon) end) end
pcall(function() weapon:Activate() end)
end
task.wait(0.4)
end
end
end

local vault = rareInterior and rareInterior:FindFirstChild("Interactables") and rareInterior.Interactables:FindFirstChild("Vault")
if vault and self.State.st.Interior and not self.State.st.Interior.VaultOpen then
local keypad = vault:FindFirstChild("Keypad", true)
if keypad then
root.CFrame = CFrame.new(keypad.Position + Vector3.new(0, 0, 3))
root.AssemblyLinearVelocity = Vector3.zero
task.wait(0.3)
for _, codeStr in ipairs(self.Codes) do
local ok, success = invokeRemote("RF/UFOSightings/VaultCode", codeStr)
if ok and success == true then break end
task.wait(0.3)
end
task.wait(1.5)
self:FetchState()
end
end

local alienStaff = vault and vault:FindFirstChild("AlienStaff")
local staffRoot = alienStaff and alienStaff:FindFirstChild("Root")
if staffRoot and self.State.st.Interior and self.State.st.Interior.VaultOpen and not self.State.st.Interior.VaultClaimed then
root.CFrame = CFrame.new(staffRoot.Position + Vector3.new(0, 1, 0))
root.AssemblyLinearVelocity = Vector3.zero
task.wait(0.3)
invokeRemote("RF/UFOSightings/VaultClaim")
task.wait(0.5)
self:FetchState()
end

local leavePart = rareInterior and rareInterior:FindFirstChild("LeavePart")
if leavePart then
root.CFrame = CFrame.new(leavePart.Position)
root.AssemblyLinearVelocity = Vector3.zero
local prompt = leavePart:FindFirstChild("LeaveUFO") or leavePart:FindFirstChildWhichIsA("ProximityPrompt", true)
if prompt then
pcall(function()
prompt.HoldDuration = 0
UniversalCompat.FireProximityPrompt(prompt)
end)
end
local exitWait = os.clock() + 5.0
while os.clock() < exitWait and self:IsInRareUFO() do
task.wait(0.2)
end
end
self.State.left = self.State.st.Event and self.State.st.Event.Id
self:FetchState()

elseif work == "rocks" then
local rocks = self.State.st.Rocks
if rocks and rocks.List and #rocks.List > 0 then
for _, rock in ipairs(rocks.List) do
if rock and rock.Position then
local dist = (root.Position - rock.Position).Magnitude
if dist > 20 then
root.CFrame = CFrame.new(rock.Position + Vector3.new(0, 2, 0))
root.AssemblyLinearVelocity = Vector3.zero
task.wait(0.08)
end
pcall(function() fireRemote("RE/UFOSightings/CollectRock", rocks.Id, rock.Index) end)
task.wait(0.12)
end
end
task.wait(0.3)
self:FetchState()
end

elseif work == "trade" then
local camp = Services.Workspace:FindFirstChild("UFOSightingsCamp")
local chaser = camp and camp:FindFirstChild("AlienChaser")
local tradePoint = chaser and chaser:FindFirstChild("HumanoidRootPart") and chaser.HumanoidRootPart:FindFirstChild("TradePoint")
local tPos = tradePoint and (tradePoint:IsA("Attachment") and tradePoint.WorldPosition or tradePoint.Position)
local tradeSuccess = false
if tPos then
root.CFrame = CFrame.new(tPos + Vector3.new(0, 2, 0))
root.AssemblyLinearVelocity = Vector3.zero
task.wait(0.2)
while (self.State.st.SpaceRocks or 0) >= (self.State.st.RockCost or math.huge) do
local ok, traded = pcall(function() return invokeRemote("RF/UFOSightings/Trade", self.State.st.RockCost) end)
if not ok or not traded then break end
tradeSuccess = true
self:FetchState()
task.wait(0.3)
end
end
if not tradeSuccess then
self.State.no = os.clock() + 60
end

elseif work == "reward" then
local reward = self.State.st.Reward
if reward and reward.Position and reward.Id then
local dist = (root.Position - reward.Position).Magnitude
if dist > 20 then
root.CFrame = CFrame.new(reward.Position + Vector3.new(0, 2, 0))
root.AssemblyLinearVelocity = Vector3.zero
task.wait(0.15)
end
invokeRemote("RF/UFOSightings/Collect", reward.Id)
self:FetchState()
end

elseif work == "hold" then
root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
local holdTimeout = os.clock() + 5.0
while os.clock() < holdTimeout do
local st = self.State.st
if not (st and st.Available and st.Event and st.Decoded and not st.Complete and st.Event.Variant ~= "Rare") then
break
end
task.wait(0.2)
end
self:FetchState()
end

self.IsBusy = false
end

PriorityManager = {
ActiveTask = nil,
ActiveTaskExpiresAt = 0,
List = {
"Auto Steal",
"UFO Event",
"Enchanted / Bloom Event",
"Auto Treadmill"
},
TaskAliases = {
["Steal"] = "Auto Steal",
["Auto Steal"] = "Auto Steal",
["UFO"] = "UFO Event",
["Auto UFO"] = "UFO Event",
["UFO Event"] = "UFO Event",
["Bloom"] = "Enchanted / Bloom Event",
["Bloom Event"] = "Enchanted / Bloom Event",
["Enchanted"] = "Enchanted / Bloom Event",
["Enchanted / Bloom Event"] = "Enchanted / Bloom Event",
["Treadmill"] = "Auto Treadmill",
["Auto Treadmill"] = "Auto Treadmill"
}
}

function PriorityManager:Initialize(savedPriorities)
local canonicalList = {
"Auto Steal",
"UFO Event",
"Enchanted / Bloom Event",
"Auto Treadmill"
}

local valid = {}
for _, name in ipairs(canonicalList) do valid[name] = true end

if type(savedPriorities) == "table" and #savedPriorities > 0 then
local newList = {}
for _, rawName in ipairs(savedPriorities) do
local name = self.TaskAliases[rawName] or rawName
if valid[name] then
table.insert(newList, name)
valid[name] = nil
end
end
for canonIndex, name in ipairs(canonicalList) do
if valid[name] then
table.insert(newList, math.min(canonIndex, #newList + 1), name)
end
end
self.List = newList
else
self.List = canonicalList
end
end

function PriorityManager:GetRank(taskName)
local resolved = self.TaskAliases[taskName] or taskName
for index, name in ipairs(self.List) do
if name == resolved then
return index
end
end
return 999
end

function PriorityManager:IsLocked()
if self.ActiveTask ~= nil then
if os.clock() < self.ActiveTaskExpiresAt then
return true
else
self.ActiveTask = nil
self.ActiveTaskExpiresAt = 0
return false
end
end
return false
end

function PriorityManager:Acquire(taskName, maxDuration)
local resolved = self.TaskAliases[taskName] or taskName
maxDuration = maxDuration or 15.0

if not self:IsLocked() then
if resolved ~= "Auto Treadmill" and resolved ~= "Treadmill" then
hopOffTreadmill()
end
self.ActiveTask = resolved
self.ActiveTaskExpiresAt = os.clock() + maxDuration
self:InvalidateCache()
return true
elseif self.ActiveTask == resolved then
self.ActiveTaskExpiresAt = math.max(self.ActiveTaskExpiresAt, os.clock() + maxDuration)
return true
end
return false
end

function PriorityManager:Claim(taskName)
return self:Acquire(taskName, 15.0)
end

function PriorityManager:Release(taskName)
local resolved = self.TaskAliases[taskName] or taskName
if self.ActiveTask == resolved or self.ActiveTask == taskName then
self.ActiveTask = nil
self.ActiveTaskExpiresAt = 0
self:InvalidateCache()
end
end

function PriorityManager:GetTaskDimension(taskName)
return "Normal"
end

function PriorityManager:IsTaskEnabled(taskName)
local resolved = self.TaskAliases[taskName] or taskName
if resolved == "Auto Steal" then
return isStealEnabled() and not isMapClosed()
elseif resolved == "UFO Event" then
return (getgenv().config.autoUFO == true or getgenv().config.ufoRocks == true or getgenv().config.ufoTrade == true or getgenv().config.ufoRare == true)
elseif resolved == "Enchanted / Bloom Event" then
return (getgenv().config.autoCatchButterfly == true or getgenv().config.autoWispQuest == true or getgenv().config.autoTradeUp == true or getgenv().config.autoCraftEssence == true) and not isMapClosed()
elseif resolved == "Auto Treadmill" then
return getgenv().config.autoTreadmill == true
end
return false
end

function PriorityManager:HasWork(taskName)
local resolved = self.TaskAliases[taskName] or taskName

if resolved == "Auto Steal" then
if isMapClosed() or not isStealEnabled() then return false end
if isNormalStealPanelTarget() then return true end
if State.isStealingActive or isHoldingEgg() then return true end
local best = getBestEgg and getBestEgg()
return best ~= nil

elseif resolved == "UFO Event" then
return UFOManager ~= nil and UFOManager:HasWork() ~= nil

elseif resolved == "Enchanted / Bloom Event" then
if isMapClosed() then return false end
return BloomManager ~= nil and BloomManager:HasWork()

elseif resolved == "Auto Treadmill" then
return getgenv().config.autoTreadmill == true
end

return false
end

PriorityManager._lastTopTask = nil
PriorityManager._lastTopTaskTime = 0

function PriorityManager:InvalidateCache()
self._lastTopTask = nil
self._lastTopTaskTime = 0
end

function PriorityManager:GetTopWantedTask()
if self:IsLocked() and self.ActiveTask then
return self.ActiveTask
end

local now = os.clock()
if self._lastTopTaskTime > 0 and (now - self._lastTopTaskTime) < 0.15 then
return self._lastTopTask
end

local topTask = nil

if isNormalStealPanelTarget() then
topTask = "Auto Steal"
elseif isHoldingEgg() or State.isStealingActive then
topTask = "Auto Steal"
else
for _, taskName in ipairs(self.List) do
if self:IsTaskEnabled(taskName) and self:HasWork(taskName) then
topTask = taskName
break
end
end
end

self._lastTopTask = topTask
self._lastTopTaskTime = now
return topTask
end

function PriorityManager:CanRun(taskName)
local inRace = LocalPlayer:GetAttribute("RaceId") ~= nil
if inRace and taskName ~= "Race" then
return false
end

local resolved = self.TaskAliases[taskName] or taskName

if self:IsLocked() and self.ActiveTask ~= resolved then
return false
end

local topTask = self:GetTopWantedTask()
if not topTask then
return false
end

return (resolved == topTask)
end

function PriorityManager:MoveUp(index, saveCallback)
if index > 1 then
local item = table.remove(self.List, index)
table.insert(self.List, index - 1, item)
if saveCallback then saveCallback(self.List) end
return true
end
return false
end

function PriorityManager:MoveDown(index, saveCallback)
if index < #self.List then
local item = table.remove(self.List, index)
table.insert(self.List, index + 1, item)
if saveCallback then saveCallback(self.List) end
return true
end
return false
end

PriorityManager:Initialize(currentSettings.TaskPriorities)

local WorkerScheduler = {
Tasks = {},
Connection = nil,
IsActive = true
}

function WorkerScheduler:Register(name, interval, runFn)
local item = { Name = name, Gap = 0, Interval = interval or 0.35, Hold = 0, Running = false, Run = runFn }
table.insert(self.Tasks, item)
return item
end

function WorkerScheduler:Start()
if self.IsRunningLoop then return end
self.IsRunningLoop = true
task.spawn(function()
local lastPrune = 0
while self.IsActive do
local dt = task.wait(0.05)
local now = os.clock()

if now - lastPrune >= 30.0 then
lastPrune = now
if State and State.blacklistedEggs then
for uid, exp in pairs(State.blacklistedEggs) do
if now > exp then
State.blacklistedEggs[uid] = nil
end
end
end
end

for _, t in ipairs(self.Tasks) do
t.Gap = t.Gap + dt
if t.Hold > 0 then
t.Hold = t.Hold - dt
elseif not t.Running and t.Gap >= t.Interval then
t.Gap = 0
t.Running = true
task.spawn(function()
local ok, err = pcall(t.Run)
t.Running = false
if not ok and err then
t.Hold = 3
end
end)
end
end
end
self.IsRunningLoop = false
end)
end

local function tryUpgradeTreadmill()
if not Remotes.TierRaise or os.clock() < State.treadmillUpgradeCooldown then return end
State.treadmillUpgradeCooldown = os.clock() + 5

local save = getSaveData()
local myMoney = math.max(getPlayerMoney(), tonumber(save and save.Money) or 0)

local dataFolder = Services.ReplicatedStorage:FindFirstChild("Data")
local treadmillsModule = dataFolder and dataFolder:FindFirstChild("Treadmills")
if not treadmillsModule then return end

local ok, tData = pcall(require, treadmillsModule)
if not ok or type(tData) ~= "table" then return end

local currentLevel = tonumber(save and save.TreadmillUpgradeLevel) or 0
if type(tData.GetByUpgradeLevel) == "function" then
local okNext, nextTier = pcall(tData.GetByUpgradeLevel, currentLevel + 1)
if okNext and type(nextTier) == "table" then
local nextId = nextTier._id
local price = tonumber(nextTier.Price) or math.huge
if type(nextId) == "string" and myMoney >= price then
pcall(function() Remotes.TierRaise:InvokeServer(nextId) end)
return
end
end
end

if type(tData.Directory) == "table" then
local sorted = {}
for name, cfg in pairs(tData.Directory) do
table.insert(sorted, { Name = tostring(name), Price = tonumber(cfg.Price) or 0, Level = tonumber(cfg.UpgradeLevel) or tonumber(cfg.Level) or 0 })
end
table.sort(sorted, function(a, b) return a.Price < b.Price end)
for _, item in ipairs(sorted) do
if item.Level > currentLevel and myMoney >= item.Price then
pcall(function() Remotes.TierRaise:InvokeServer(item.Name) end)
break
end
end
end
end

local function tryUpgradeBase()
if not Remotes.BaseTierRaise or os.clock() < State.baseUpgradeCooldown then return end
State.baseUpgradeCooldown = os.clock() + 5

local dataFolder = Services.ReplicatedStorage:FindFirstChild("Data")
local basesModule = dataFolder and dataFolder:FindFirstChild("Bases")
if not basesModule then return end

local ok, bData = pcall(require, basesModule)
if not ok or type(bData) ~= "table" or type(bData.BASES) ~= "table" then return end

local save = getSaveData()
local currentLevel = tonumber(save and save.BaseUpgradeLevel) or 0
local maxLevel = type(bData.GetMaxBaseLevel) == "function" and tonumber(bData.GetMaxBaseLevel()) or #bData.BASES

if currentLevel >= maxLevel then return end

local nextTier = bData.BASES[currentLevel + 1]
local cost = nextTier and (tonumber(nextTier.Cost) or tonumber(nextTier.Price)) or nil
local myMoney = math.max(getPlayerMoney(), tonumber(save and save.Money) or 0)

if cost and myMoney >= cost then
pcall(function() Remotes.BaseTierRaise:FireServer() end)
end
end

local function getPlayerCurrentSpeed()
local char = LocalPlayer.Character
local hum = char and char:FindFirstChildOfClass("Humanoid")

if hum and typeof(hum.WalkSpeed) == "number" and hum.WalkSpeed > 0 then
if ShieldManager and ShieldManager.OriginalHumanoid and ShieldManager.OriginalHumanoid.Parent == nil then
if ShieldManager.OriginalHumanoid.WalkSpeed > hum.WalkSpeed then
return ShieldManager.OriginalHumanoid.WalkSpeed
end
end
return hum.WalkSpeed
end

if char then
for _, attrName in ipairs({"WalkSpeed", "Speed", "CurrentSpeed", "MovementSpeed"}) do
local val = char:GetAttribute(attrName)
if typeof(val) == "number" and val > 0 then return val end
end
end
for _, attrName in ipairs({"WalkSpeed", "Speed", "CurrentSpeed", "MovementSpeed"}) do
local val = LocalPlayer:GetAttribute(attrName)
if typeof(val) == "number" and val > 0 then return val end
end

local lstats = LocalPlayer:FindFirstChild("leaderstats")
if lstats then
for _, child in ipairs(lstats:GetChildren()) do
local lName = child.Name:lower()
if (lName == "speed" or lName == "walkspeed") and typeof(child.Value) == "number" and child.Value > 0 then
return child.Value
end
end
end

local saveMod = Services.ReplicatedStorage:FindFirstChild("Shared") and Services.ReplicatedStorage.Shared:FindFirstChild("Save")
if saveMod and saveMod:IsA("ModuleScript") then
local ok, mod = pcall(require, saveMod)
if ok and type(mod) == "table" then
local getter = type(mod.Get) == "function" and mod.Get or (type(mod.Peek) == "function" and mod.Peek)
if getter then
local resOk, res = pcall(getter)
if resOk and type(res) == "table" then
for k, v in pairs(res) do
local lk = tostring(k):lower()
if (lk == "speed" or lk == "walkspeed") and typeof(v) == "number" and v > 0 then
return v
end
end
end
end
end
end

return 16
end
getgenv().getPlayerCurrentSpeed = getPlayerCurrentSpeed

local function getStandingPosition(basePos)
local _, root, hum = getAliveRig()
local hipHeight = hum and hum.HipHeight or 2
local rootSizeY = root and (root.Size.Y / 2) or 1
return Vector3.new(basePos.X, basePos.Y + hipHeight + rootSizeY, basePos.Z)
end

local function runAlongGroundSegment(targetPos, stopDist, sessionId, targetUid)
local char, root, hum = getAliveRig()
if not root or not hum then return false end
stopDist = stopDist or 3.5

local liveSpeed = getPlayerCurrentSpeed()
setCollisions(false)
if hum then hum.PlatformStand = false end

local delta = Vector3.new(targetPos.X - root.Position.X, 0, targetPos.Z - root.Position.Z)
local timeout = os.clock() + math.max(8, (delta.Magnitude / math.max(liveSpeed, 16)) + 5)
local arrived = false
local lastLiveCheck = 0

local conn
conn = Services.RunService.Heartbeat:Connect(function()
if sessionId ~= State.currentStealSession or not isStealEnabled() or isMapClosed() then
if conn then conn:Disconnect() conn = nil end
return
end

local _, cRoot = getAliveRig()
if not cRoot or os.clock() > timeout then
if conn then conn:Disconnect() conn = nil end
return
end

if targetUid and (os.clock() - lastLiveCheck >= 0.25) then
lastLiveCheck = os.clock()
if not isEggStillValid(targetUid) then
blacklistEgg(targetUid, 15)
if conn then conn:Disconnect() conn = nil end
return
end
end

local currentPos = cRoot.Position
local flatDiff = Vector3.new(targetPos.X - currentPos.X, 0, targetPos.Z - currentPos.Z)
if flatDiff.Magnitude <= stopDist then
arrived = true
cRoot.AssemblyLinearVelocity = Vector3.zero
cRoot.AssemblyAngularVelocity = Vector3.zero
if conn then conn:Disconnect() conn = nil end
return
end

local curSpeed = getPlayerCurrentSpeed()
local dir = flatDiff.Unit
cRoot.AssemblyLinearVelocity = Vector3.new(dir.X * curSpeed, cRoot.AssemblyLinearVelocity.Y, dir.Z * curSpeed)
cRoot.CFrame = CFrame.new(currentPos.X, currentPos.Y, currentPos.Z) * CFrame.lookAt(Vector3.zero, dir)
end)

while conn and conn.Connected do
Services.RunService.Heartbeat:Wait()
end

local _, fRoot = getAliveRig()
if fRoot then
fRoot.AssemblyLinearVelocity = Vector3.zero
fRoot.AssemblyAngularVelocity = Vector3.zero
end

return arrived and (sessionId == State.currentStealSession) and isStealEnabled()
end

local function runAlongGroundToEgg(targetPos, speed, sessionId, targetUid)
local char, root, hum = getAliveRig()
if not root or not hum then return false end

local currentPosInit = root.Position
local groundY = CONFIG.GroundAltitude + 1.0

if currentPosInit.X < CONFIG.BoundaryCheckpointX then
local centerDeliveryPos = Vector3.new(CONFIG.BaseDropPosition.X, groundY, CONFIG.BaseDropPosition.Z)
local mouthPos = Vector3.new(CONFIG.BoundaryCheckpointX, groundY, CONFIG.BaseDropPosition.Z)

local lateralDist = math.abs(currentPosInit.Z - CONFIG.BaseDropPosition.Z)
if lateralDist > 12 or currentPosInit.X < CONFIG.BaseDropPosition.X then
local ok = runAlongGroundSegment(centerDeliveryPos, 4.0, sessionId, targetUid)
if not ok or sessionId ~= State.currentStealSession or not isStealEnabled() then
return false
end
end

local ok2 = runAlongGroundSegment(mouthPos, 4.0, sessionId, targetUid)
if not ok2 or sessionId ~= State.currentStealSession or not isStealEnabled() then
return false
end
end

local targetStandPos = getStandingPosition(targetPos)
local reached = runAlongGroundSegment(targetStandPos, 3.5, sessionId, targetUid)
if not reached or sessionId ~= State.currentStealSession or not isStealEnabled() then
return false
end

local _, fRoot = getAliveRig()
if fRoot then
fRoot.CFrame = CFrame.lookAt(targetStandPos, targetPos)
fRoot.AssemblyLinearVelocity = Vector3.zero
fRoot.AssemblyAngularVelocity = Vector3.zero
end
task.wait(0.04)
return true
end

local function executeFastStealOutbound(targetPos, sessionId, targetUid)
local world = Services.Workspace:FindFirstChild("World") or Services.Workspace:FindFirstChild("__OBJECTS")
local build = world and world:FindFirstChild("Build")
local portals = build and build:FindFirstChild("FuseBiomeLanePortals")
local entrance = portals and portals:FindFirstChildWhichIsA("BasePart")
local zone = build and build:FindFirstChild("FuseBiomeZone")
local exitPart = zone and zone:FindFirstChild("ExitPart", true)

if not entrance or not exitPart then
return runAlongGroundToEgg(targetPos, nil, sessionId, targetUid)
end

local _, root = getAliveRig()
if not root then return false end

root.CFrame = CFrame.new(CONFIG.BaseDropPosition)
root.AssemblyLinearVelocity = Vector3.zero
task.wait(0.12)

local inSky = false
local entranceTimeout = os.clock() + 4.0

while os.clock() < entranceTimeout do
if sessionId ~= State.currentStealSession or not isStealEnabled() then return false end
local _, cRoot = getAliveRig()
if not cRoot then return false end

cRoot.CFrame = CFrame.new(entrance.Position)
cRoot.AssemblyLinearVelocity = Vector3.new(0, -0.5, 0)
UniversalCompat.FireTouch(cRoot, entrance)

if cRoot.Position.Y > 10000 then
inSky = true
break
end
Services.RunService.Heartbeat:Wait()
end

if not inSky then
return runAlongGroundToEgg(targetPos, nil, sessionId, targetUid)
end

local exitedSky = false
local exitDeadline = os.clock() + 5.0

while os.clock() < exitDeadline do
if sessionId ~= State.currentStealSession or not isStealEnabled() then return false end
local _, cRoot = getAliveRig()
if not cRoot then return false end

cRoot.CFrame = CFrame.new(exitPart.Position)
cRoot.AssemblyLinearVelocity = Vector3.new(0, -0.5, 0)
UniversalCompat.FireTouch(cRoot, exitPart)

if cRoot.Position.Y < 10000 then
exitedSky = true
break
end
Services.RunService.Heartbeat:Wait()
end

if not exitedSky then return false end
task.wait(0.12)

local _, cRoot = getAliveRig()
if not cRoot then return false end

local remainingDist = (Vector3.new(targetPos.X, 0, targetPos.Z) - Vector3.new(cRoot.Position.X, 0, cRoot.Position.Z)).Magnitude
if remainingDist <= CONFIG.FastStealDirectSnapRadius then
setCollisions(false)
local standPos = getStandingPosition(targetPos)
cRoot.CFrame = CFrame.lookAt(standPos, targetPos)
cRoot.AssemblyLinearVelocity = Vector3.zero
task.wait(0.05)
return true
else
return runAlongGroundToEgg(targetPos, nil, sessionId, targetUid)
end
end

local function findMyPlot()
if State.myPlot and State.myPlot.Parent and State.myTreadmill and State.myTreadmill.Parent then
return State.myPlot
end

local myName = LocalPlayer.Name:lower()
local myDisplayName = LocalPlayer.DisplayName:lower()
local myUserId = LocalPlayer.UserId

local plotsFolder = Services.Workspace:FindFirstChild("Plots")
local candidates = plotsFolder and plotsFolder:GetChildren() or Services.Workspace:GetChildren()

for _, plot in ipairs(candidates) do
local ownerAttr = plot:GetAttribute("Owner") or plot:GetAttribute("OwnerUserId") or plot:GetAttribute("Player")
if ownerAttr and (tostring(ownerAttr):lower() == myName or tonumber(ownerAttr) == myUserId) then
State.myPlot = plot
break
end

local sign = plot:FindFirstChild("PlotSign") or plot:FindFirstChild("Sign")
if sign then
for _, desc in ipairs(sign:GetDescendants()) do
if desc:IsA("TextLabel") or desc:IsA("TextButton") then
local txt = desc.Text:lower()
if txt:find(myName, 1, true) or txt:find(myDisplayName, 1, true) then
State.myPlot = plot
break
end
end
end
end
if State.myPlot then break end
end

if State.myPlot then
for _, desc in ipairs(State.myPlot:GetDescendants()) do
if desc.Name:lower():find("treadmill") then
if desc:IsA("BasePart") then
State.myTreadmill = desc
break
elseif desc:IsA("Model") then
State.myTreadmill = desc.PrimaryPart or desc:FindFirstChildWhichIsA("BasePart")
if State.myTreadmill then break end
end
end
end
if not State.myTreadmill then
for _, child in ipairs(State.myPlot:GetChildren()) do
if child.Name:lower():find("treadmill") then
State.myTreadmill = child:IsA("BasePart") and child or (child:IsA("Model") and (child.PrimaryPart or child:FindFirstChildWhichIsA("BasePart")))
if State.myTreadmill then break end
end
end
end
end

if not State.myTreadmill then
for _, obj in ipairs(Services.Workspace:GetDescendants()) do
if obj.Name == "TreadmillBottom" and obj:IsA("BasePart") then
State.myTreadmill = obj
break
end
end
end
return State.myPlot
end

local function instantGrabAtPosition(uid, targetPos, sessionId, isNest)
if sessionId ~= State.currentStealSession or not isStealEnabled() then return false end
local _, root = getAliveRig()
if root and targetPos then
local offsetY = isNest and CONFIG.AirGrabOffset or 1.0
local safeY = (targetPos.Y or CONFIG.GroundAltitude) + offsetY
root.CFrame = CFrame.new(Vector3.new(targetPos.X, safeY, targetPos.Z))
root.AssemblyLinearVelocity = Vector3.zero
root.AssemblyAngularVelocity = Vector3.zero
end

local targetPrompt = nil
local eggModel = uid and (Services.Workspace:FindFirstChild(uid) or (Services.Workspace:FindFirstChild("AreaEggSlotsClient") and Services.Workspace.AreaEggSlotsClient:FindFirstChild(uid)))
if eggModel then
targetPrompt = eggModel:FindFirstChildWhichIsA("ProximityPrompt", true)
end
if not targetPrompt and targetPos then
local parts = Services.Workspace:GetPartBoundsInRadius(targetPos, 12)
for _, part in ipairs(parts) do
local p = part:FindFirstChildWhichIsA("ProximityPrompt", true)
if p and p.Enabled then
targetPrompt = p
break
end
end
end

local grabTimeout = os.clock() + 3.0
local nextRemoteDispatch = 0

while os.clock() < grabTimeout do
if sessionId ~= State.currentStealSession or not isStealEnabled() then break end
local _, cRoot = getAliveRig()
if not cRoot then break end

if uid and not isHoldingEgg() and not isEggStillValid(uid) then
blacklistEgg(uid, 15)
return false
end

if os.clock() >= nextRemoteDispatch then
nextRemoteDispatch = os.clock() + 0.3
if Remotes.AskFieldEggCarry and uid then
task.spawn(function() pcall(function() Remotes.AskFieldEggCarry:InvokeServer({ Uid = uid }) end) end)
end
if typeof(EggState.CarryFieldEgg) == "function" and uid then
pcall(function() EggState.CarryFieldEgg(uid) end)
end
end

if targetPrompt and targetPrompt.Enabled then
UniversalCompat.FireProximityPrompt(targetPrompt)
end

for _ = 1, 3 do
Services.RunService.Heartbeat:Wait()
if isHoldingEgg() then return true end
end
end
return isHoldingEgg()
end

local function performGroundCheckpoint(targetEgg, currentX, laneZ, sessionId)
if sessionId ~= State.currentStealSession or not isStealEnabled() then return false end
local _, root, humanoid = getAliveRig()
if not root then return false end
if humanoid then humanoid.PlatformStand = false end

local uid = (targetEgg and targetEgg.Uid) or (EggState and EggState.CarryUid)
local checkY = CONFIG.GroundAltitude + 1.0

pcall(function()
root.CFrame = CFrame.new(currentX, checkY, laneZ) * CFrame.Angles(0, math.rad(90), 0)
root.AssemblyLinearVelocity = Vector3.zero
root.AssemblyAngularVelocity = Vector3.zero
end)
task.wait(0.06)

dropHeldEggDirect()
local dropWait = os.clock() + 0.6
while os.clock() < dropWait and isHoldingEgg() do
if sessionId ~= State.currentStealSession or not isStealEnabled() then return false end
dropHeldEggDirect()
task.wait(0.08)
end
task.wait(0.04)

if uid and EggState and typeof(EggState.CarryFieldEgg) == "function" then
pcall(function() EggState.CarryFieldEgg(uid) end)
task.wait(0.12)
end

if not isHoldingEgg() then
local eggFloorPos = getPhysicalEggPosition(uid, Vector3.new(currentX, checkY, laneZ))
local grabSuccess = false
local retryTimeout = os.clock() + 3.0

while os.clock() < retryTimeout do
if sessionId ~= State.currentStealSession or not isStealEnabled() then return false end
grabSuccess = instantGrabAtPosition(uid, eggFloorPos, sessionId, false)
if grabSuccess and isHoldingEgg() then break end
Services.RunService.Heartbeat:Wait()
end
end
task.wait(0.04)
return isHoldingEgg()
end

local function executeCheckpointedHopsHome(targetEgg, sessionId)
local _, root, humanoid = getAliveRig()
if not root then return false end

local boundaryX = CONFIG.BoundaryCheckpointX
local playerSpeed = getPlayerCurrentSpeed()
local baseStep = CONFIG.HopDistance
local stepSize = (playerSpeed < 100) and math.max(34, playerSpeed * 0.45) or math.min(baseStep, math.max(60, playerSpeed * 0.75))
local interval = CONFIG.CheckpointInterval
local safeTarget = CONFIG.BaseDropPosition

local laneZ = math.clamp(root.Position.Z, -425, -300)
local currentX = root.Position.X
local lastCheckpointX = currentX

StealUIManager:Lock()
ShieldManager:MuteUGI()
if humanoid then humanoid.PlatformStand = false end

local groundY = CONFIG.GroundAltitude + 1.0

while currentX - stepSize > boundaryX do
if sessionId ~= State.currentStealSession or not isStealEnabled() or not isHoldingEgg() then
ShieldManager:UnmuteUGI()
StealUIManager:Unlock()
cleanupFlightState()
return false
end

local _, cRoot = getAliveRig()
if not cRoot then
ShieldManager:UnmuteUGI()
StealUIManager:Unlock()
cleanupFlightState()
return false
end

local nextX = currentX - stepSize
local preHopTime = os.clock()

pcall(function()
cRoot.CFrame = CFrame.new(nextX, groundY, laneZ) * CFrame.Angles(0, math.rad(90), 0)
cRoot.AssemblyLinearVelocity = Vector3.zero
end)
task.wait(CONFIG.HopGap)

local _, postRoot = getAliveRig()
local pulled = (State.lastServerRollbackTime > preHopTime) or (postRoot ~= nil and (postRoot.Position.X - nextX > 15))

if pulled then
CONFIG.HopGap = math.min(CONFIG.HopGapMax, CONFIG.HopGap + 0.02)
stepSize = math.max(34, stepSize * 0.75)
task.wait(0.1)
else
currentX = nextX
CONFIG.HopGap = math.max(CONFIG.HopGapMin, CONFIG.HopGap - 0.005)
end

if math.abs(lastCheckpointX - currentX) >= interval then
lastCheckpointX = currentX
local ok = performGroundCheckpoint(targetEgg, currentX, laneZ, sessionId)
if not ok and not isHoldingEgg() then
ShieldManager:UnmuteUGI()
StealUIManager:Unlock()
cleanupFlightState()
return false
end
end
end

if isHoldingEgg() then
currentX = boundaryX
pcall(function()
local _, bRoot = getAliveRig()
if bRoot then
bRoot.CFrame = CFrame.new(boundaryX, groundY, laneZ) * CFrame.Angles(0, math.rad(90), 0)
bRoot.AssemblyLinearVelocity = Vector3.zero
end
end)
task.wait(0.08)
local boundaryOk = performGroundCheckpoint(targetEgg, boundaryX, laneZ, sessionId)
if not boundaryOk and not isHoldingEgg() then
ShieldManager:UnmuteUGI()
StealUIManager:Unlock()
cleanupFlightState()
return false
end
end

local corridorStep = 45
while currentX - corridorStep > safeTarget.X do
if sessionId ~= State.currentStealSession or not isStealEnabled() or not isHoldingEgg() then
break
end

local nextX = currentX - corridorStep
local _, cRoot = getAliveRig()
if cRoot then
pcall(function()
cRoot.CFrame = CFrame.new(nextX, groundY, safeTarget.Z) * CFrame.Angles(0, math.rad(90), 0)
cRoot.AssemblyLinearVelocity = Vector3.zero
end)
end
task.wait(CONFIG.HopGap)
currentX = nextX
end

local _, fRoot, fHum = getAliveRig()
if fRoot then
pcall(function()
fRoot.CFrame = CFrame.new(safeTarget.X, CONFIG.GroundAltitude + 1.2, safeTarget.Z)
fRoot.AssemblyLinearVelocity = Vector3.zero
end)
end
task.wait(0.15)
if fHum then fHum.PlatformStand = false end

dropHeldEggDirect()
task.wait(0.25)

local dropVerifyTimeout = os.clock() + 2.0
while os.clock() < dropVerifyTimeout and isHoldingEgg() do
dropHeldEggDirect()
task.wait(0.2)
end

StealUIManager:Unlock()
ShieldManager:UnmuteUGI()
cleanupFlightState()
return not isHoldingEgg()
end

local function executeFastStealDelivery(targetEgg, sessionId)
local _, root, hum = getAliveRig()
if not root or not hum then return false end

local uid = targetEgg.Uid
local laneZ = math.clamp(root.Position.Z, -425, -300)
local dropTargetPos = Vector3.new(CONFIG.SeparationLineX + CONFIG.FastStealLineDropOffset, CONFIG.GroundAltitude + 1.0, laneZ)
local playerSpeed = getPlayerCurrentSpeed()

setCollisions(false)
ShieldManager:MuteUGI()

local startTime = os.clock()
local travelTimeout = math.max(12, ((root.Position.X - dropTargetPos.X) / playerSpeed) + 6)

while root.Position.X > dropTargetPos.X + 2.0 and (os.clock() - startTime) < travelTimeout do
Services.RunService.Heartbeat:Wait()
if sessionId ~= State.currentStealSession or not isStealEnabled() or not isHoldingEgg() then
setCollisions(true)
ShieldManager:UnmuteUGI()
return false
end

local _, cRoot = getAliveRig()
if not cRoot then break end
cRoot.AssemblyLinearVelocity = Vector3.new(-playerSpeed, cRoot.AssemblyLinearVelocity.Y, 0)
cRoot.CFrame = CFrame.new(cRoot.Position.X, CONFIG.GroundAltitude + 1.0, laneZ) * CFrame.Angles(0, math.rad(90), 0)
end

local _, cRoot = getAliveRig()
if cRoot then
cRoot.CFrame = CFrame.new(dropTargetPos) * CFrame.Angles(0, math.rad(90), 0)
cRoot.AssemblyLinearVelocity = Vector3.zero
end
task.wait(0.1)

local checkpointOk = performGroundCheckpoint(targetEgg, dropTargetPos.X, laneZ, sessionId)
if not checkpointOk and not isHoldingEgg() then
setCollisions(true)
ShieldManager:UnmuteUGI()
return false
end

local currentX = dropTargetPos.X
local safeTarget = CONFIG.BaseDropPosition
local corridorStep = 55

while currentX - corridorStep > safeTarget.X do
if sessionId ~= State.currentStealSession or not isStealEnabled() or not isHoldingEgg() then break end
local nextX = currentX - corridorStep
local _, hRoot = getAliveRig()
if hRoot then
pcall(function()
hRoot.CFrame = CFrame.new(nextX, CONFIG.GroundAltitude + 1.0, safeTarget.Z) * CFrame.Angles(0, math.rad(90), 0)
hRoot.AssemblyLinearVelocity = Vector3.zero
end)
end
task.wait(CONFIG.HopGap)
currentX = nextX
end

local _, fRoot, fHum = getAliveRig()
if fRoot then
fRoot.CFrame = CFrame.new(safeTarget.X, CONFIG.GroundAltitude + 1.2, safeTarget.Z)
fRoot.AssemblyLinearVelocity = Vector3.zero
end
task.wait(0.15)
if fHum then fHum.PlatformStand = false end

dropHeldEggDirect()
task.wait(0.25)

local dropVerifyTimeout = os.clock() + 2.0
while os.clock() < dropVerifyTimeout and isHoldingEgg() do
dropHeldEggDirect()
task.wait(0.2)
end

setCollisions(true)
ShieldManager:UnmuteUGI()
return not isHoldingEgg()
end

local function executeGroundDeliveryHome(targetEgg, sessionId)
return executeCheckpointedHopsHome(targetEgg, sessionId)
end

local function travelPlaneSegment(targetPos, stopDist, speed, timeout, sessionId, targetUid)
local char, root = getAliveRig()
if not root then return false end

stopDist = stopDist or 4
local startTime = os.clock()
local reached = false
local lastLiveCheck = 0

State.activeFlightConnection = Services.RunService.Heartbeat:Connect(function()
if sessionId ~= State.currentStealSession or not isStealEnabled() or isMapClosed() then
if State.activeFlightConnection then State.activeFlightConnection:Disconnect() State.activeFlightConnection = nil end
return
end

local _, cRoot = getAliveRig()
if not cRoot then
if State.activeFlightConnection then State.activeFlightConnection:Disconnect() State.activeFlightConnection = nil end
return
end

if targetUid and (os.clock() - lastLiveCheck >= 0.25) then
lastLiveCheck = os.clock()
if not isEggStillValid(targetUid) then
blacklistEgg(targetUid, 15)
if State.activeFlightConnection then State.activeFlightConnection:Disconnect() State.activeFlightConnection = nil end
return
end
end

local currentPos = cRoot.Position
local delta = Vector3.new(targetPos.X - currentPos.X, 0, targetPos.Z - currentPos.Z)
local dist = delta.Magnitude

if dist <= stopDist then
reached = true
cRoot.AssemblyLinearVelocity = Vector3.zero
if State.activeFlightConnection then State.activeFlightConnection:Disconnect() State.activeFlightConnection = nil end
return
end

if (os.clock() - startTime) > timeout then
cRoot.AssemblyLinearVelocity = Vector3.zero
if State.activeFlightConnection then State.activeFlightConnection:Disconnect() State.activeFlightConnection = nil end
return
end

local moveDir = delta.Unit
cRoot.AssemblyLinearVelocity = Vector3.new(moveDir.X * speed, 0, moveDir.Z * speed)
cRoot.CFrame = CFrame.new(currentPos.X, CONFIG.FlightAltitude, currentPos.Z) * CFrame.lookAt(Vector3.zero, moveDir)
end)

while State.activeFlightConnection and State.activeFlightConnection.Connected do
Services.RunService.Heartbeat:Wait()
end

return reached and (sessionId == State.currentStealSession) and isStealEnabled() and not isMapClosed()
end

local function flyOutboundElevated(targetPosition, stopDistance, sessionId, targetUid)
local char, root, humanoid = getAliveRig()
if not root or not humanoid then return false end

StealUIManager:SnapshotNormalHUD()
stopDistance = stopDistance or 4

local playerSpeed = humanoid.WalkSpeed
if not playerSpeed or playerSpeed <= 0 then playerSpeed = 16 end

table.clear(State.activeCollisionsDisabled)
for _, part in ipairs(char:GetDescendants()) do
if part:IsA("BasePart") and part.CanCollide then
State.activeCollisionsDisabled[part] = true
part.CanCollide = false
end
end

humanoid.PlatformStand = true

local function snapAltitude(targetY)
local _, cRoot = getAliveRig()
if cRoot then
pcall(function()
cRoot.CFrame = CFrame.new(cRoot.Position.X, targetY, cRoot.Position.Z) * cRoot.CFrame.Rotation
cRoot.AssemblyLinearVelocity = Vector3.zero
end)
task.wait(0.03)
end
end
snapAltitude(CONFIG.FlightAltitude)

local currentPosInit = root.Position
if currentPosInit.X < CONFIG.BoundaryCheckpointX then
local centerDeliveryPos = Vector3.new(CONFIG.BaseDropPosition.X, CONFIG.FlightAltitude, CONFIG.BaseDropPosition.Z)
local mouthPos = Vector3.new(CONFIG.BoundaryCheckpointX, CONFIG.FlightAltitude, CONFIG.BaseDropPosition.Z)

local lateralDist = math.abs(currentPosInit.Z - CONFIG.BaseDropPosition.Z)
if lateralDist > 12 or currentPosInit.X < CONFIG.BaseDropPosition.X then
local ok = travelPlaneSegment(centerDeliveryPos, 4, playerSpeed, 20, sessionId, targetUid)
if not ok then cleanupFlightState() return false end
end

local ok2 = travelPlaneSegment(mouthPos, 4, playerSpeed, 20, sessionId, targetUid)
if not ok2 then cleanupFlightState() return false end
end

local finalDelta = Vector3.new(targetPosition.X - root.Position.X, 0, targetPosition.Z - root.Position.Z)
local dynamicTimeout = math.max(30, (finalDelta.Magnitude / playerSpeed) + 20)

local reached = travelPlaneSegment(targetPosition, stopDistance, playerSpeed, dynamicTimeout, sessionId, targetUid)
if reached and sessionId == State.currentStealSession and isStealEnabled() and not isMapClosed() then
snapAltitude((targetPosition.Y or CONFIG.GroundAltitude) + CONFIG.AirGrabOffset)
end

cleanupFlightState()
return reached and (sessionId == State.currentStealSession) and isStealEnabled() and not isMapClosed()
end

getBestEgg = function()
if isMapClosed() then return nil end
local records = getFieldEggRecords()
if not records or next(records) == nil then return nil end
local data = { Records = records }

if isNormalStealPanelTarget() then
for uid, record in pairs(data.Records) do
if type(record) == "table" then
if uid == State.targetedSpecificUid or record.Uid == State.targetedSpecificUid then
record.Uid = record.Uid or uid
if State.isStealingActive or isHoldingEgg() or (record.State ~= "Claimed" and record.State ~= "Carried") then
return record
end
end
end
end

local directFloorPos = getPhysicalEggPosition(State.targetedSpecificUid, nil)
if directFloorPos and (State.isStealingActive or isHoldingEgg() or isEggStillValid(State.targetedSpecificUid)) then
return {
Uid = State.targetedSpecificUid,
BottomCFrame = CFrame.new(directFloorPos),
AssetCategory = "TargetedEgg"
}
end

if not State.isStealingActive and not isHoldingEgg() then
if State.activeStealButtons[State.targetedSpecificUid] then
State.activeStealButtons[State.targetedSpecificUid].BackgroundColor3 = activeTheme and activeTheme.Accent or Color3.fromRGB(92, 170, 255)
State.activeStealButtons[State.targetedSpecificUid].Text = "Steal"
end
State.targetedSpecificUid = nil
end
end

local minScore = getMinRequiredScore()
local minValueThreshold = getgenv().config.minValueThreshold or 0
local bestEgg = nil
local highestScore = -math.huge
local normalStealEnabled = getgenv().config.autoFarm == true

local assetsMod = GameModules:Get("Assets")
local assetsDir = assetsMod and assetsMod.Directory
local mutationsMod = GameModules:Get("Mutations")

for keyUid, record in pairs(data.Records) do
if type(record) == "table" then
local uid = (type(record.Uid) == "string" and record.Uid) or (type(keyUid) == "string" and keyUid) or nil
record.Uid = uid
if uid and not isBlacklisted(uid) then
if record.State == "Slot" or record.State == "Dropped" or record.State == nil then
local posX = nil
local cf = record.BottomCFrame or record.BoundsCFrame or record.CFrame
if typeof(cf) == "CFrame" then posX = cf.Position.X
elseif typeof(cf) == "Vector3" then posX = cf.X
elseif typeof(record.Position) == "Vector3" then posX = record.Position.X end

if not posX or posX >= 560 then
local rawName = record.AssetCategory or record.Category or record.Name or "Unknown"

if normalStealEnabled then
local areaIdStr = tostring(record.AreaId or "")
if matchesTargetArea(areaIdStr) then
local assetData = (assetsDir and assetsDir[rawName]) or MasterRegistry.PetDatabase[rawName] or {}
local _, rank = MasterRegistry:Lookup(rawName)

local scale = tonumber(record.AssetScale) or 1
local scaleFactor = (scale > 5) and (((scale / 5) ^ 1.2) * 19.637875755794113) or (scale ^ 1.85)
local mutationMultiplier = 1
if mutationsMod and typeof(mutationsMod.EarningsFor) == "function" and type(record.Mutations) == "table" then
local ok, mul = pcall(mutationsMod.EarningsFor, record.Mutations)
if ok and type(mul) == "number" and mul > 0 then mutationMultiplier = mul end
elseif record.Mutations and #record.Mutations > 0 then
mutationMultiplier = 2.5
end

local baseRate = tonumber(assetData.EarningRate) or 0
local valuePerSec = baseRate * scaleFactor * mutationMultiplier

if rank >= minScore and valuePerSec >= minValueThreshold then
local score = (rank * 1000) + valuePerSec
if score > highestScore then
highestScore = score
bestEgg = record
end
end
end
end
end
end
end
end
end
return bestEgg
end

WorkerScheduler:Register("AutoUpgrades", 6.0, function()
if getgenv().config.autoUpgradeTreadmill then tryUpgradeTreadmill() end
if getgenv().config.autoUpgradeBase then tryUpgradeBase() end
end)

WorkerScheduler:Register("AutoAFK", 30.0, function()
if not getgenv().config.autoAFK then return end
local _, root, hum = getAliveRig()
if not root then return end
pcall(function()
local cam = workspace.CurrentCamera
if cam then
cam.CFrame = cam.CFrame * CFrame.Angles(0, math.rad(0.5), 0)
task.wait(0.05)
cam.CFrame = cam.CFrame * CFrame.Angles(0, math.rad(-0.5), 0)
end
end)
end)

WorkerScheduler:Register("UFOEvent", 0.25, function()
if State.isStealingActive or isHoldingEgg() then return end
if not PriorityManager:CanRun("UFO") then return end

UFOManager.tick = (UFOManager.tick or 0) + 1
if (UFOManager.tick % 40) == 1 then
pcall(function() UFOManager:FetchState() end)
end

if PriorityManager:Acquire("UFO", 25.0) then
pcall(function() UFOManager:Process() end)
PriorityManager:Release("UFO")
end
end)

WorkerScheduler:Register("EventsCombat", 0.35, function()
if State.isStealingActive or isHoldingEgg() then return end
if not PriorityManager:CanRun("Bloom") then return end

if PriorityManager:Acquire("Bloom", 15.0) then
pcall(function() BloomManager:Process() end)
PriorityManager:Release("Bloom")
end
end)

WorkerScheduler:Register("StealAndTreadmill", 0.25, function()
local char = LocalPlayer.Character
if not char then return end

if isStealEnabled() and not State.isStealingActive and not isMapClosed() and PriorityManager:CanRun("Steal") then
local currentTargetEgg = getBestEgg()
if currentTargetEgg then
local targetUid = currentTargetEgg.Uid
if not isEggStillValid(targetUid) then
blacklistEgg(targetUid, 15)
if State.targetedSpecificUid == targetUid then
if State.activeStealButtons[targetUid] then
State.activeStealButtons[targetUid].BackgroundColor3 = activeTheme and activeTheme.Accent or Color3.fromRGB(92, 170, 255)
State.activeStealButtons[targetUid].Text = "Steal"
end
State.targetedSpecificUid = nil
end
return
end

PriorityManager:Claim("Steal")
State.isStealingActive = true
State.treadmillFailCount = 0
State.currentStealSession = State.currentStealSession + 1
local session = State.currentStealSession

hopOffTreadmill()
ShieldManager:ApplyHumanoidSwap(char)
task.wait(0.08)

local targetCFrame = currentTargetEgg.BottomCFrame or currentTargetEgg.BoundsCFrame or currentTargetEgg.CFrame
local eggTargetPos = nil
if typeof(targetCFrame) == "CFrame" then eggTargetPos = targetCFrame.Position
elseif typeof(targetCFrame) == "Vector3" then eggTargetPos = targetCFrame
elseif typeof(currentTargetEgg.Position) == "Vector3" then eggTargetPos = currentTargetEgg.Position end

if not eggTargetPos and targetUid then
eggTargetPos = getPhysicalEggPosition(targetUid, nil)
end

local stealSuccess = false
if eggTargetPos then
local areaId = currentTargetEgg.AreaId
local isUfoEgg = UFOManager and UFOManager.IsUfoEgg and UFOManager:IsUfoEgg(currentTargetEgg, targetUid)
-- fixed undefined root here, was crashing on ufo tp check
local _, liveRoot = getAliveRig()
local canUfoTp = (getgenv().config.ufoTp == true) and isUfoEgg and liveRoot and ((liveRoot.Position - eggTargetPos).Magnitude >= 1000)
local canUseFastSteal = ((getgenv().config.fastSteal == true and isFastStealArea(areaId)) or canUfoTp)

local function tryDeliverToUfo()
if not isUfoEgg then return false end
local ufoPos = UFOManager:GetUfoPosition()
if not ufoPos then return false end
local d0 = UFOManager.State.st and UFOManager.State.st.Delivered or 0
local _, cRoot = getAliveRig()
if not cRoot then return false end

local beamTarget = Vector3.new(ufoPos.X, math.max(ufoPos.Y - 60, cRoot.Position.Y), ufoPos.Z)
local arriveTimeout = os.clock() + 4.0
while os.clock() < arriveTimeout and isHoldingEgg() and (UFOManager.State.st.Delivered or 0) <= d0 do
local _, curR = getAliveRig()
if not curR then break end
local diff = beamTarget - curR.Position
if diff.Magnitude <= 15 then break end
curR.CFrame = CFrame.new(curR.Position + diff.Unit * math.min(diff.Magnitude, 35))
curR.AssemblyLinearVelocity = Vector3.zero
task.wait(0.08)
end

local waitTimeout = os.clock() + 5.0
while os.clock() < waitTimeout and isHoldingEgg() and (UFOManager.State.st.Delivered or 0) <= d0 do
task.wait(0.1)
end

return (UFOManager.State.st.Delivered or 0) > d0
end

if canUseFastSteal then
local arrived = executeFastStealOutbound(eggTargetPos, session, targetUid)
if not arrived and session == State.currentStealSession and isStealEnabled() and isEggStillValid(targetUid) then
arrived = runAlongGroundToEgg(eggTargetPos, nil, session, targetUid)
end

if arrived and session == State.currentStealSession and isStealEnabled() then
task.wait(0.04)
local grabbed = instantGrabAtPosition(targetUid, eggTargetPos, session, false)

if (grabbed or isHoldingEgg()) and session == State.currentStealSession and isStealEnabled() then
stealSuccess = tryDeliverToUfo()

if not stealSuccess and (grabbed or isHoldingEgg()) and session == State.currentStealSession and isStealEnabled() then
stealSuccess = executeFastStealDelivery(currentTargetEgg, session)
if not stealSuccess and isHoldingEgg() and session == State.currentStealSession and isStealEnabled() then
stealSuccess = executeCheckpointedHopsHome(currentTargetEgg, session)
end
end
end
end
else
local arrived = runAlongGroundToEgg(eggTargetPos, nil, session, targetUid)
if arrived and session == State.currentStealSession and isStealEnabled() then
task.wait(0.04)
local grabbed = instantGrabAtPosition(targetUid, eggTargetPos, session, false)
if (grabbed or isHoldingEgg()) and session == State.currentStealSession and isStealEnabled() then
stealSuccess = tryDeliverToUfo()

if not stealSuccess and (grabbed or isHoldingEgg()) and session == State.currentStealSession and isStealEnabled() then
stealSuccess = executeCheckpointedHopsHome(currentTargetEgg, session)
end
end
end
end
end

if session == State.currentStealSession then
State.isStealingActive = false
ShieldManager:UndoSwap()
cleanupFlightState()
PriorityManager:Release("Steal")
PriorityManager:Release("Auto Steal")

if stealSuccess then
local eggName = (currentTargetEgg and (currentTargetEgg.AssetCategory or currentTargetEgg.Name)) or "Unknown Egg"
sendWebhook("Egg Stolen", "Successfully brought back: **" .. tostring(eggName) .. "**", 5763719)
-- after a successful steal we want to jump back on treadmill quickly so the loop continues
task.delay(0.8, function()
if getgenv().config.autoTreadmill and not isHoldingEgg() and not State.isStealingActive then
PriorityManager:Acquire("Auto Treadmill", 8)
end
end)
end

if State.targetedSpecificUid == targetUid and (stealSuccess or not isEggStillValid(targetUid)) then
if State.activeStealButtons[targetUid] then
-- button color will be handled by the new UI
end
State.targetedSpecificUid = nil
end
else
State.isStealingActive = false
ShieldManager:UndoSwap()
cleanupFlightState()
if PriorityManager then
PriorityManager:Release("Steal")
PriorityManager:Release("Auto Steal")
end
end
end
end

local isStealBusy = State.isStealingActive or isHoldingEgg()
local canTreadmill = getgenv().config.autoTreadmill and not isStealBusy and PriorityManager:CanRun("Treadmill")

if canTreadmill and getAliveRig() then
ShieldManager:UndoSwap()
findMyPlot()
local _, cRoot, cHum = getAliveRig()
if cRoot and cHum then
if State.myTreadmill then
local tPos = State.myTreadmill.Position + Vector3.new(0, 3, 0)
local dist = (cRoot.Position - tPos).Magnitude
if dist > 4 then
cHum.PlatformStand = false
cHum.Sit = false
local speed = cHum.WalkSpeed
if not speed or speed <= 0 then speed = 16 end
local travelDuration = math.clamp(dist / math.max(speed, 16), 0.3, 3)
local tw = Services.TweenService:Create(cRoot, TweenInfo.new(travelDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
CFrame = CFrame.new(tPos) * cRoot.CFrame.Rotation
})
tw:Play()
tw.Completed:Wait()
end

local _, postRoot, postHum = getAliveRig()
if postRoot and not postRoot.Anchored then
if postHum then
postHum.PlatformStand = false
postHum.Sit = false
end
if Remotes.AskWearStill and not isStealBusy and PriorityManager:CanRun("Treadmill") then
pcall(function() Remotes.AskWearStill:InvokeServer() end)
end
task.wait(0.35)
local _, verifyRoot = getAliveRig()
if verifyRoot and not verifyRoot.Anchored then
State.treadmillFailCount = State.treadmillFailCount + 1
if State.treadmillFailCount >= 8 then
resetFlaggedCharacter()
elseif State.treadmillFailCount == 4 and Remotes.AskDoff then
pcall(function() Remotes.AskDoff:InvokeServer() end)
end
else
State.treadmillFailCount = 0
end
else
State.treadmillFailCount = 0
end
else
State.treadmillFailCount = 0
end
end
else
if not canTreadmill and getgenv().config.autoTreadmill then
local _, curRoot = getAliveRig()
if curRoot and curRoot.Anchored then
hopOffTreadmill()
end
end
end
end)

WorkerScheduler:Start()

-- ============================================================
-- ORIGINAL UI v2  (hand made, a bit more style)
-- ============================================================

local Players = Services.Players
local TweenService = Services.TweenService
local UserInputService = Services.UserInputService
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

pcall(function()
    local old = PlayerGui:FindFirstChild("TonyoEggHub")
    if old then old:Destroy() end
end)

local C = {
    bg         = Color3.fromRGB(14, 14, 18),
    panel      = Color3.fromRGB(24, 24, 30),
    panel2     = Color3.fromRGB(32, 32, 40),
    accent     = Color3.fromRGB(95, 170, 255),
    accent2    = Color3.fromRGB(60, 130, 230),
    text       = Color3.fromRGB(235, 235, 240),
    textDim    = Color3.fromRGB(130, 130, 145),
    green      = Color3.fromRGB(75, 210, 130),
    red        = Color3.fromRGB(235, 75, 80),
    orange     = Color3.fromRGB(255, 160, 60),
    toggleOn   = Color3.fromRGB(75, 210, 130),
    toggleOff  = Color3.fromRGB(48, 48, 58),
    stroke     = Color3.fromRGB(42, 42, 52),
    topBar     = Color3.fromRGB(20, 20, 26)
}

local screen = Instance.new("ScreenGui")
screen.Name = "TonyoEggHub"
screen.ResetOnSpawn = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = PlayerGui

-- main window
local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.new(0, 560, 0, 450)
main.Position = UDim2.new(0.5, -280, 0.5, -225)
main.BackgroundColor3 = C.bg
main.BorderSizePixel = 0
main.ClipsDescendants = true
main.Parent = screen

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 12)
mainCorner.Parent = main

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = C.stroke
mainStroke.Thickness = 1.2
mainStroke.Parent = main

-- soft shadow-ish border
local shadow = Instance.new("ImageLabel")
shadow.Name = "Shadow"
shadow.BackgroundTransparency = 1
shadow.Image = "rbxassetid://1316045217"
shadow.ImageColor3 = Color3.new(0, 0, 0)
shadow.ImageTransparency = 0.55
shadow.ScaleType = Enum.ScaleType.Slice
shadow.SliceCenter = Rect.new(10, 10, 118, 118)
shadow.Size = UDim2.new(1, 30, 1, 30)
shadow.Position = UDim2.new(0, -15, 0, -15)
shadow.ZIndex = 0
shadow.Parent = main

-- top bar
local top = Instance.new("Frame")
top.Size = UDim2.new(1, 0, 0, 42)
top.BackgroundColor3 = C.topBar
top.BorderSizePixel = 0
top.Parent = main

local topCorner = Instance.new("UICorner")
topCorner.CornerRadius = UDim.new(0, 12)
topCorner.Parent = top

local topFix = Instance.new("Frame")
topFix.Size = UDim2.new(1, 0, 0, 14)
topFix.Position = UDim2.new(0, 0, 1, -14)
topFix.BackgroundColor3 = C.topBar
topFix.BorderSizePixel = 0
topFix.Parent = top

-- accent line under top
local accentLine = Instance.new("Frame")
accentLine.Size = UDim2.new(1, 0, 0, 2)
accentLine.Position = UDim2.new(0, 0, 1, 0)
accentLine.BackgroundColor3 = C.accent
accentLine.BorderSizePixel = 0
accentLine.Parent = top

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -100, 1, 0)
title.Position = UDim2.new(0, 16, 0, 0)
title.BackgroundTransparency = 1
title.Text = "Egg Stealer  ·  Tonyo"
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextColor3 = C.text
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = top

-- minimize / close buttons
local btnHolder = Instance.new("Frame")
btnHolder.Size = UDim2.new(0, 70, 0, 28)
btnHolder.Position = UDim2.new(1, -82, 0, 7)
btnHolder.BackgroundTransparency = 1
btnHolder.Parent = top

local function makeTopBtn(txt, color, x)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 28, 0, 28)
    b.Position = UDim2.new(0, x, 0, 0)
    b.BackgroundColor3 = Color3.fromRGB(36, 36, 44)
    b.Text = txt
    b.Font = Enum.Font.GothamBold
    b.TextSize = 14
    b.TextColor3 = color
    b.BorderSizePixel = 0
    b.AutoButtonColor = false
    b.Parent = btnHolder

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 7)
    c.Parent = b

    b.MouseEnter:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = Color3.fromRGB(50, 50, 60)}):Play()
    end)
    b.MouseLeave:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = Color3.fromRGB(36, 36, 44)}):Play()
    end)
    return b
end

local minBtn = makeTopBtn("–", C.textDim, 0)
local closeBtn = makeTopBtn("×", C.red, 36)

-- open / close state
local uiOpen = true
local savedPos = main.Position
local savedSize = main.Size

local function setUiOpen(open, instant)
    uiOpen = open
    local t = instant and 0 or 0.22
    if open then
        main.Visible = true
        TweenService:Create(main, TweenInfo.new(t, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
            Size = savedSize,
            Position = savedPos,
            BackgroundTransparency = 0
        }):Play()
        for _, v in ipairs(main:GetDescendants()) do
            if v:IsA("TextLabel") or v:IsA("TextButton") or v:IsA("TextBox") then
                TweenService:Create(v, TweenInfo.new(t), {TextTransparency = 0}):Play()
            elseif v:IsA("ImageLabel") and v.Name ~= "Shadow" then
                TweenService:Create(v, TweenInfo.new(t), {ImageTransparency = 0}):Play()
            end
        end
        mainStroke.Transparency = 0
    else
        savedPos = main.Position
        savedSize = main.Size
        TweenService:Create(main, TweenInfo.new(t, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
            Size = UDim2.new(0, 160, 0, 42),
            Position = UDim2.new(savedPos.X.Scale, savedPos.X.Offset + (savedSize.X.Offset/2 - 80), savedPos.Y.Scale, savedPos.Y.Offset),
            BackgroundTransparency = 0.05
        }):Play()
        task.delay(t, function()
            if not uiOpen then
                -- keep a small pill so user can reopen by clicking it
            end
        end)
    end
end

closeBtn.MouseButton1Click:Connect(function()
    setUiOpen(false)
end)

minBtn.MouseButton1Click:Connect(function()
    setUiOpen(not uiOpen)
end)

-- click the minimized bar to reopen
top.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 and not uiOpen then
        setUiOpen(true)
    end
end)

-- drag
local dragging, dragStart, startPos
top.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = main.Position
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

-- sidebar
local side = Instance.new("Frame")
side.Size = UDim2.new(0, 118, 1, -44)
side.Position = UDim2.new(0, 0, 0, 44)
side.BackgroundColor3 = C.panel
side.BorderSizePixel = 0
side.Parent = main

local sideLayout = Instance.new("UIListLayout")
sideLayout.Padding = UDim.new(0, 5)
sideLayout.SortOrder = Enum.SortOrder.LayoutOrder
sideLayout.Parent = side

local sidePad = Instance.new("UIPadding")
sidePad.PaddingTop = UDim.new(0, 12)
sidePad.PaddingLeft = UDim.new(0, 8)
sidePad.PaddingRight = UDim.new(0, 8)
sidePad.Parent = side

-- content
local content = Instance.new("Frame")
content.Size = UDim2.new(1, -128, 1, -54)
content.Position = UDim2.new(0, 124, 0, 50)
content.BackgroundTransparency = 1
content.Parent = main

local pages = {}
local tabButtons = {}
local currentPage = "Farm"

local function makeTab(name, order, iconText)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 36)
    btn.BackgroundColor3 = C.bg
    btn.Text = ""
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = false
    btn.LayoutOrder = order
    btn.Parent = side

    local bc = Instance.new("UICorner")
    bc.CornerRadius = UDim.new(0, 8)
    bc.Parent = btn

    local icon = Instance.new("TextLabel")
    icon.Size = UDim2.new(0, 22, 1, 0)
    icon.Position = UDim2.new(0, 8, 0, 0)
    icon.BackgroundTransparency = 1
    icon.Text = iconText or "•"
    icon.Font = Enum.Font.GothamBold
    icon.TextSize = 14
    icon.TextColor3 = C.textDim
    icon.Parent = btn

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -36, 1, 0)
    lbl.Position = UDim2.new(0, 32, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = name
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 13
    lbl.TextColor3 = C.textDim
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = btn

    local page = Instance.new("ScrollingFrame")
    page.Size = UDim2.new(1, 0, 1, 0)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 3
    page.ScrollBarImageColor3 = C.accent
    page.CanvasSize = UDim2.new(0, 0, 0, 0)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.Visible = false
    page.Parent = content

    local pl = Instance.new("UIListLayout")
    pl.Padding = UDim.new(0, 7)
    pl.SortOrder = Enum.SortOrder.LayoutOrder
    pl.Parent = page

    local pp = Instance.new("UIPadding")
    pp.PaddingTop = UDim.new(0, 2)
    pp.PaddingBottom = UDim.new(0, 16)
    pp.PaddingRight = UDim.new(0, 6)
    pp.Parent = page

    pages[name] = page
    tabButtons[name] = {btn = btn, icon = icon, lbl = lbl}

    btn.MouseButton1Click:Connect(function()
        for n, p in pairs(pages) do
            p.Visible = (n == name)
            local t = tabButtons[n]
            if n == name then
                t.btn.BackgroundColor3 = C.accent2
                t.icon.TextColor3 = C.text
                t.lbl.TextColor3 = C.text
            else
                t.btn.BackgroundColor3 = C.bg
                t.icon.TextColor3 = C.textDim
                t.lbl.TextColor3 = C.textDim
            end
        end
        currentPage = name
    end)

    return page
end

local farmPage   = makeTab("Farm", 1, "⚙")
local stealPage  = makeTab("Steal", 2, "🥚")
local settingsPage = makeTab("Settings", 3, "⚙")

-- default
pages["Farm"].Visible = true
tabButtons["Farm"].btn.BackgroundColor3 = C.accent2
tabButtons["Farm"].icon.TextColor3 = C.text
tabButtons["Farm"].lbl.TextColor3 = C.text

-- helpers
local function section(parent, text, order)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, 0, 0, 24)
    f.BackgroundTransparency = 1
    f.LayoutOrder = order or 0
    f.Parent = parent

    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, 0, 1, 0)
    l.BackgroundTransparency = 1
    l.Text = text
    l.Font = Enum.Font.GothamBold
    l.TextSize = 12
    l.TextColor3 = C.accent
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = f

    -- thin line
    local line = Instance.new("Frame")
    line.Size = UDim2.new(1, 0, 0, 1)
    line.Position = UDim2.new(0, 0, 1, -1)
    line.BackgroundColor3 = C.stroke
    line.BorderSizePixel = 0
    line.Parent = f
    return f
end

local function makeToggle(parent, name, desc, default, callback, order)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 40)
    row.BackgroundColor3 = C.panel
    row.BorderSizePixel = 0
    row.LayoutOrder = order or 0
    row.Parent = parent

    local rc = Instance.new("UICorner")
    rc.CornerRadius = UDim.new(0, 8)
    rc.Parent = row

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -62, 0, 18)
    label.Position = UDim2.new(0, 12, 0, 4)
    label.BackgroundTransparency = 1
    label.Text = name
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 13
    label.TextColor3 = C.text
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row

    local sub = Instance.new("TextLabel")
    sub.Size = UDim2.new(1, -62, 0, 14)
    sub.Position = UDim2.new(0, 12, 0, 22)
    sub.BackgroundTransparency = 1
    sub.Text = desc
    sub.Font = Enum.Font.Gotham
    sub.TextSize = 11
    sub.TextColor3 = C.textDim
    sub.TextXAlignment = Enum.TextXAlignment.Left
    sub.Parent = row

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 42, 0, 22)
    btn.Position = UDim2.new(1, -52, 0.5, -11)
    btn.BackgroundColor3 = default and C.toggleOn or C.toggleOff
    btn.Text = ""
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = false
    btn.Parent = row

    local bc = Instance.new("UICorner")
    bc.CornerRadius = UDim.new(1, 0)
    bc.Parent = btn

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 18, 0, 18)
    knob.Position = default and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
    knob.BackgroundColor3 = Color3.fromRGB(245, 245, 250)
    knob.BorderSizePixel = 0
    knob.Parent = btn

    local kc = Instance.new("UICorner")
    kc.CornerRadius = UDim.new(1, 0)
    kc.Parent = knob

    local state = default
    btn.MouseButton1Click:Connect(function()
        state = not state
        TweenService:Create(btn, TweenInfo.new(0.15), {
            BackgroundColor3 = state and C.toggleOn or C.toggleOff
        }):Play()
        TweenService:Create(knob, TweenInfo.new(0.15), {
            Position = state and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
        }):Play()
        if callback then callback(state) end
    end)
end

local function makeSlider(parent, name, minV, maxV, default, callback, order)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 52)
    row.BackgroundColor3 = C.panel
    row.BorderSizePixel = 0
    row.LayoutOrder = order or 0
    row.Parent = parent

    local rc = Instance.new("UICorner")
    rc.CornerRadius = UDim.new(0, 8)
    rc.Parent = row

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.65, 0, 0, 18)
    label.Position = UDim2.new(0, 12, 0, 6)
    label.BackgroundTransparency = 1
    label.Text = name
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 13
    label.TextColor3 = C.text
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row

    local valLabel = Instance.new("TextLabel")
    valLabel.Size = UDim2.new(0.35, -14, 0, 18)
    valLabel.Position = UDim2.new(0.65, 0, 0, 6)
    valLabel.BackgroundTransparency = 1
    valLabel.Text = formatMoneyPerSec(default)
    valLabel.Font = Enum.Font.GothamBold
    valLabel.TextSize = 12
    valLabel.TextColor3 = C.accent
    valLabel.TextXAlignment = Enum.TextXAlignment.Right
    valLabel.Parent = row

    local track = Instance.new("Frame")
    track.Size = UDim2.new(1, -24, 0, 7)
    track.Position = UDim2.new(0, 12, 0, 34)
    track.BackgroundColor3 = Color3.fromRGB(38, 38, 48)
    track.BorderSizePixel = 0
    track.Parent = row

    local tc = Instance.new("UICorner")
    tc.CornerRadius = UDim.new(1, 0)
    tc.Parent = track

    local fill = Instance.new("Frame")
    local rel0 = math.clamp((default - minV) / math.max(maxV - minV, 1), 0, 1)
    -- power curve so low values are easier
    fill.Size = UDim2.new(rel0 ^ 0.45, 0, 1, 0)
    fill.BackgroundColor3 = C.accent
    fill.BorderSizePixel = 0
    fill.Parent = track

    local fc = Instance.new("UICorner")
    fc.CornerRadius = UDim.new(1, 0)
    fc.Parent = fill

    local dragging = false
    local function update(x)
        local rel = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        fill.Size = UDim2.new(rel, 0, 1, 0)
        local raw = minV + (maxV - minV) * (rel ^ 2.2)
        local val = math.floor(raw)
        valLabel.Text = formatMoneyPerSec(val)
        if callback then callback(val) end
    end

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            update(input.Position.X)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            update(input.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

local function makeDropdown(parent, name, options, default, callback, order)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 40)
    row.BackgroundColor3 = C.panel
    row.BorderSizePixel = 0
    row.LayoutOrder = order or 0
    row.ClipsDescendants = true
    row.Parent = parent

    local rc = Instance.new("UICorner")
    rc.CornerRadius = UDim.new(0, 8)
    rc.Parent = row

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.42, 0, 1, 0)
    label.Position = UDim2.new(0, 12, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = name
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 13
    label.TextColor3 = C.text
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.52, -14, 0, 26)
    btn.Position = UDim2.new(0.48, 0, 0.5, -13)
    btn.BackgroundColor3 = C.panel2
    btn.Text = "  " .. tostring(default) .. "  ▾"
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 12
    btn.TextColor3 = C.text
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = false
    btn.Parent = row

    local bc = Instance.new("UICorner")
    bc.CornerRadius = UDim.new(0, 6)
    bc.Parent = btn

    local open = false
    local dropFrame = nil

    btn.MouseButton1Click:Connect(function()
        if open and dropFrame then
            dropFrame:Destroy()
            dropFrame = nil
            open = false
            row.Size = UDim2.new(1, 0, 0, 40)
            return
        end
        open = true
        local h = math.min(#options * 28, 150)
        dropFrame = Instance.new("Frame")
        dropFrame.Size = UDim2.new(0.52, -14, 0, h)
        dropFrame.Position = UDim2.new(0.48, 0, 0, 38)
        dropFrame.BackgroundColor3 = C.panel2
        dropFrame.BorderSizePixel = 0
        dropFrame.Parent = row

        local dc = Instance.new("UICorner")
        dc.CornerRadius = UDim.new(0, 6)
        dc.Parent = dropFrame

        local list = Instance.new("UIListLayout")
        list.Parent = dropFrame

        for _, opt in ipairs(options) do
            local ob = Instance.new("TextButton")
            ob.Size = UDim2.new(1, 0, 0, 28)
            ob.BackgroundTransparency = 1
            ob.Text = "  " .. tostring(opt)
            ob.Font = Enum.Font.Gotham
            ob.TextSize = 12
            ob.TextColor3 = C.text
            ob.TextXAlignment = Enum.TextXAlignment.Left
            ob.AutoButtonColor = false
            ob.Parent = dropFrame
            ob.MouseEnter:Connect(function()
                ob.BackgroundTransparency = 0.85
                ob.BackgroundColor3 = C.accent
            end)
            ob.MouseLeave:Connect(function()
                ob.BackgroundTransparency = 1
            end)
            ob.MouseButton1Click:Connect(function()
                btn.Text = "  " .. tostring(opt) .. "  ▾"
                if callback then callback(opt) end
                dropFrame:Destroy()
                dropFrame = nil
                open = false
                row.Size = UDim2.new(1, 0, 0, 40)
            end)
        end
        row.Size = UDim2.new(1, 0, 0, 40 + h + 6)
    end)
end

-- ===================== FARM =====================
section(farmPage, "STEALING", 1)

makeToggle(farmPage, "Auto Steal", "steal the best eggs and bring them home", currentSettings.AutoFarm, function(v)
    getgenv().config.autoFarm = v
    currentSettings.AutoFarm = v
    saveStuff()
    table.clear(State.blacklistedEggs)
    if not v then abortStealRoutine() end
end, 2)

makeToggle(farmPage, "Fast Steal", "portal shortcut for titan+ zones (can lag)", currentSettings.FastSteal, function(v)
    getgenv().config.fastSteal = v
    currentSettings.FastSteal = v
    saveStuff()
    if not v and State.isStealingActive and not isHoldingEgg() then
        abortStealRoutine()
    end
end, 3)

makeSlider(farmPage, "Min Value ($/s)", 0, 100000000000000, currentSettings.MinValueThreshold or 0, function(v)
    getgenv().config.minValueThreshold = v
    currentSettings.MinValueThreshold = v
    saveStuff()
    table.clear(State.blacklistedEggs)
end, 4)

local rarityList = {"All", "1 - Common", "2 - Uncommon", "3 - Rare", "4 - Epic", "5 - Legendary", "6 - Mythic", "7 - Cosmic", "8 - Secret", "9 - Eternal", "10 - Divine"}
makeDropdown(farmPage, "Min Rarity", rarityList, currentSettings.MinRarity or "All", function(sel)
    getgenv().config.minRarity = sel
    currentSettings.MinRarity = sel
    saveStuff()
    table.clear(State.blacklistedEggs)
end, 5)

section(farmPage, "TREADMILL LOOP", 10)

makeToggle(farmPage, "Auto Treadmill", "after steal → jump on treadmill → loop", currentSettings.AutoTreadmill, function(v)
    getgenv().config.autoTreadmill = v
    currentSettings.AutoTreadmill = v
    saveStuff()
end, 11)

makeToggle(farmPage, "Auto AFK", "tiny camera wiggle so you dont get kicked", currentSettings.AutoAFK, function(v)
    getgenv().config.autoAFK = v
    currentSettings.AutoAFK = v
    saveStuff()
end, 12)

section(farmPage, "UPGRADES", 20)

makeToggle(farmPage, "Upgrade Treadmill", "buy next tier when you can afford it", currentSettings.AutoUpgradeTreadmill, function(v)
    getgenv().config.autoUpgradeTreadmill = v
    currentSettings.AutoUpgradeTreadmill = v
    saveStuff()
end, 21)

makeToggle(farmPage, "Upgrade Base", "buy base expansion automatically", currentSettings.AutoUpgradeBase, function(v)
    getgenv().config.autoUpgradeBase = v
    currentSettings.AutoUpgradeBase = v
    saveStuff()
end, 22)

section(farmPage, "UFO EVENT", 30)

makeToggle(farmPage, "Auto UFO", "decode + tractor beam + rewards", currentSettings.AutoUFO, function(v)
    getgenv().config.autoUFO = v
    currentSettings.AutoUFO = v
    saveStuff()
end, 31)

makeToggle(farmPage, "Collect Debris", "pick up space rocks around the map", currentSettings.UFORocks, function(v)
    getgenv().config.ufoRocks = v
    currentSettings.UFORocks = v
    saveStuff()
end, 32)

makeToggle(farmPage, "Rare UFO", "board mothership, smash capsules, vault", currentSettings.UFORare, function(v)
    getgenv().config.ufoRare = v
    currentSettings.UFORare = v
    saveStuff()
end, 33)

makeToggle(farmPage, "Trade Debris", "trade rocks at the alien camp", currentSettings.UFOTrade, function(v)
    getgenv().config.ufoTrade = v
    currentSettings.UFOTrade = v
    saveStuff()
end, 34)

section(farmPage, "BLOOM / ENCHANTED", 40)

makeToggle(farmPage, "Catch Butterflies", "auto net during bloom event", currentSettings.AutoCatchButterfly, function(v)
    getgenv().config.autoCatchButterfly = v
    currentSettings.AutoCatchButterfly = v
    saveStuff()
end, 41)

makeToggle(farmPage, "Trade Up Butterflies", "trade at the station inside the tree", currentSettings.AutoTradeUp, function(v)
    getgenv().config.autoTradeUp = v
    currentSettings.AutoTradeUp = v
    saveStuff()
end, 42)

makeToggle(farmPage, "Craft Essence", "craft at the mutation shrine", currentSettings.AutoCraftEssence, function(v)
    getgenv().config.autoCraftEssence = v
    currentSettings.AutoCraftEssence = v
    saveStuff()
end, 43)

makeToggle(farmPage, "Wisp Quests", "accept / progress / claim wisp companion", currentSettings.AutoWispQuest, function(v)
    getgenv().config.autoWispQuest = v
    currentSettings.AutoWispQuest = v
    saveStuff()
end, 44)

-- ===================== STEAL PANEL (with icons) =====================
section(stealPage, "LIVE EGGS", 1)

local stealList = Instance.new("Frame")
stealList.Size = UDim2.new(1, 0, 0, 10)
stealList.BackgroundTransparency = 1
stealList.LayoutOrder = 2
stealList.AutomaticSize = Enum.AutomaticSize.Y
stealList.Parent = stealPage

local stealLayout = Instance.new("UIListLayout")
stealLayout.Padding = UDim.new(0, 6)
stealLayout.Parent = stealList

local function refreshStealPanel()
    for _, child in ipairs(stealList:GetChildren()) do
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
        if i > 30 then break end

        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 48)
        row.BackgroundColor3 = C.panel
        row.BorderSizePixel = 0
        row.Parent = stealList

        local rc = Instance.new("UICorner")
        rc.CornerRadius = UDim.new(0, 8)
        rc.Parent = row

        -- egg icon / pfp
        local iconBg = Instance.new("Frame")
        iconBg.Size = UDim2.new(0, 38, 0, 38)
        iconBg.Position = UDim2.new(0, 6, 0.5, -19)
        iconBg.BackgroundColor3 = C.panel2
        iconBg.BorderSizePixel = 0
        iconBg.Parent = row

        local ic = Instance.new("UICorner")
        ic.CornerRadius = UDim.new(0, 8)
        ic.Parent = iconBg

        local img = Instance.new("ImageLabel")
        img.Size = UDim2.new(1, -4, 1, -4)
        img.Position = UDim2.new(0, 2, 0, 2)
        img.BackgroundTransparency = 1
        img.ScaleType = Enum.ScaleType.Fit
        img.Parent = iconBg

        if item.Icon and item.Icon ~= "" then
            img.Image = item.Icon
        else
            -- fallback egg emoji style
            local fallback = Instance.new("TextLabel")
            fallback.Size = UDim2.new(1, 0, 1, 0)
            fallback.BackgroundTransparency = 1
            fallback.Text = "🥚"
            fallback.TextSize = 20
            fallback.Parent = iconBg
        end

        local nameL = Instance.new("TextLabel")
        nameL.Size = UDim2.new(0.5, -10, 0, 18)
        nameL.Position = UDim2.new(0, 52, 0, 6)
        nameL.BackgroundTransparency = 1
        nameL.Text = item.Name
        nameL.Font = Enum.Font.GothamMedium
        nameL.TextSize = 13
        nameL.TextColor3 = C.text
        nameL.TextXAlignment = Enum.TextXAlignment.Left
        nameL.TextTruncate = Enum.TextTruncate.AtEnd
        nameL.Parent = row

        local infoL = Instance.new("TextLabel")
        infoL.Size = UDim2.new(0.5, -10, 0, 16)
        infoL.Position = UDim2.new(0, 52, 0, 26)
        infoL.BackgroundTransparency = 1
        infoL.Text = item.Rarity .. "  ·  " .. formatMoneyPerSec(item.Value) .. "  ·  x" .. string.format("%.1f", item.Scale)
        infoL.Font = Enum.Font.Gotham
        infoL.TextSize = 11
        infoL.TextColor3 = C.textDim
        infoL.TextXAlignment = Enum.TextXAlignment.Left
        infoL.Parent = row

        local act = Instance.new("TextButton")
        act.Size = UDim2.new(0, 72, 0, 28)
        act.Position = UDim2.new(1, -82, 0.5, -14)
        act.BackgroundColor3 = (State.targetedSpecificUid == item.Uid) and C.red or C.accent
        act.Text = (State.targetedSpecificUid == item.Uid) and "Stop" or "Steal"
        act.Font = Enum.Font.GothamBold
        act.TextSize = 12
        act.TextColor3 = Color3.new(1, 1, 1)
        act.BorderSizePixel = 0
        act.AutoButtonColor = false
        act.Parent = row

        local ac = Instance.new("UICorner")
        ac.CornerRadius = UDim.new(0, 6)
        ac.Parent = act

        State.activeStealButtons[item.Uid] = act

        act.MouseButton1Click:Connect(function()
            if State.targetedSpecificUid == item.Uid then
                State.targetedSpecificUid = nil
                abortStealRoutine()
                act.BackgroundColor3 = C.accent
                act.Text = "Steal"
            else
                if State.isStealingActive then abortStealRoutine() end
                State.targetedSpecificUid = item.Uid
                State.blacklistedEggs[item.Uid] = nil
                for u, b in pairs(State.activeStealButtons) do
                    if b and b.Parent then
                        if u == item.Uid then
                            b.BackgroundColor3 = C.red
                            b.Text = "Stop"
                        else
                            b.BackgroundColor3 = C.accent
                            b.Text = "Steal"
                        end
                    end
                end
            end
        end)
    end
end

task.spawn(function()
    while screen and screen.Parent do
        task.wait(2)
        if currentPage == "Steal" and not State.isStealingActive then
            pcall(refreshStealPanel)
        end
    end
end)

-- ===================== SETTINGS =====================
section(settingsPage, "DISCORD WEBHOOK", 1)

local whRow = Instance.new("Frame")
whRow.Size = UDim2.new(1, 0, 0, 68)
whRow.BackgroundColor3 = C.panel
whRow.BorderSizePixel = 0
whRow.LayoutOrder = 2
whRow.Parent = settingsPage

local whc = Instance.new("UICorner")
whc.CornerRadius = UDim.new(0, 8)
whc.Parent = whRow

local whLabel = Instance.new("TextLabel")
whLabel.Size = UDim2.new(1, -16, 0, 18)
whLabel.Position = UDim2.new(0, 12, 0, 6)
whLabel.BackgroundTransparency = 1
whLabel.Text = "Webhook URL"
whLabel.Font = Enum.Font.GothamMedium
whLabel.TextSize = 12
whLabel.TextColor3 = C.text
whLabel.TextXAlignment = Enum.TextXAlignment.Left
whLabel.Parent = whRow

local whBox = Instance.new("TextBox")
whBox.Size = UDim2.new(1, -24, 0, 28)
whBox.Position = UDim2.new(0, 12, 0, 28)
whBox.BackgroundColor3 = C.panel2
whBox.Text = currentSettings.WebhookURL or ""
whBox.PlaceholderText = "https://discord.com/api/webhooks/..."
whBox.Font = Enum.Font.Gotham
whBox.TextSize = 12
whBox.TextColor3 = C.text
whBox.PlaceholderColor3 = C.textDim
whBox.ClearTextOnFocus = false
whBox.BorderSizePixel = 0
whBox.Parent = whRow

local whbc = Instance.new("UICorner")
whbc.CornerRadius = UDim.new(0, 6)
whbc.Parent = whBox

whBox.FocusLost:Connect(function()
    local url = whBox.Text or ""
    getgenv().config.webhookURL = url
    currentSettings.WebhookURL = url
    saveStuff()
end)

local testBtn = Instance.new("TextButton")
testBtn.Size = UDim2.new(1, 0, 0, 34)
testBtn.BackgroundColor3 = C.accent2
testBtn.Text = "Send Test Webhook"
testBtn.Font = Enum.Font.GothamBold
testBtn.TextSize = 13
testBtn.TextColor3 = C.text
testBtn.BorderSizePixel = 0
testBtn.AutoButtonColor = false
testBtn.LayoutOrder = 3
testBtn.Parent = settingsPage

local tbc = Instance.new("UICorner")
tbc.CornerRadius = UDim.new(0, 8)
tbc.Parent = testBtn

testBtn.MouseButton1Click:Connect(function()
    sendWebhook("Test", "Webhook working from Tonyo Egg Hub", 5793266)
end)

section(settingsPage, "EXTRA", 10)

makeToggle(settingsPage, "UFO Teleport Far Eggs", "snap to distant ufo eggs", currentSettings.UFOTp, function(v)
    getgenv().config.ufoTp = v
    currentSettings.UFOTp = v
    saveStuff()
end, 11)

local note = Instance.new("TextLabel")
note.Size = UDim2.new(1, 0, 0, 50)
note.BackgroundTransparency = 1
note.Text = "RightShift  →  toggle UI\n– button minimizes, × closes to pill\nClick the small bar to open again"
note.Font = Enum.Font.Gotham
note.TextSize = 12
note.TextColor3 = C.textDim
note.TextYAlignment = Enum.TextYAlignment.Top
note.LayoutOrder = 20
note.Parent = settingsPage

-- keybind
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        setUiOpen(not uiOpen)
    end
end)

activeTheme = { Accent = C.accent }

print("[Tonyo Egg Hub] loaded  ·  RightShift to toggle")
