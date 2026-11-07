local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local LogService = game:GetService("LogService")

local player = Players.LocalPlayer

local ADMIN_NAMES = {dador_1234567 = true, ipoge6 = true}
local function isAdmin()
	return ADMIN_NAMES[player.Name:lower()] == true
end

local function getGuiParent()
	local ok, parent = pcall(function()
		return (gethui and gethui()) or game:GetService("CoreGui")
	end)
	if ok and parent then
		return parent
	end
	return player:WaitForChild("PlayerGui")
end
local guiParent = getGuiParent()

local function clip(s, n)
	s = tostring(s)
	n = n or 500
	return #s > n and (s:sub(1, n) .. "...") or s
end

local function oneLine(s, n)
	s = tostring(s or ""):gsub("%s+", " ")
	return clip(s, n or 160)
end

local function copyList(t)
	local out = {}
	for i, v in ipairs(t) do
		out[i] = v
	end
	return out
end

local function safeRequest(requestData)
	if syn and syn.request then
		return syn.request(requestData)
	elseif http_request then
		return http_request(requestData)
	elseif request then
		return request(requestData)
	end
	local res = HttpService:RequestAsync({
		Url = requestData.Url,
		Method = requestData.Method or "GET",
		Headers = requestData.Headers,
		Body = requestData.Body,
	})
	return {StatusCode = res.StatusCode, Body = res.Body, Success = res.Success, Headers = res.Headers}
end

local function decode(raw)
	if type(raw) ~= "string" or raw == "" then
		return nil
	end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	return ok and data or nil
end

local SAVE_FILE = "TONYO_MODEL_settings.json"

local settings = {engine = "auto", keys = {}, models = {}, found = {}, customUrl = "", ping = true,
	autoAnchor = true, autoCollide = true, autoPlace = true, autoRun = false, autoAnimate = true,
	globalChat = false, playersOnlyTonyo = true}
local TX = {}
local firstRun = true

pcall(function()
	if isfile and readfile and isfile(SAVE_FILE) then
		local d = HttpService:JSONDecode(readfile(SAVE_FILE))
		if type(d) == "table" then
			firstRun = false
			settings.engine = type(d.engine) == "string" and d.engine or settings.engine
			settings.keys = type(d.keys) == "table" and d.keys or {}
			settings.models = type(d.models) == "table" and d.models or {}
			settings.found = type(d.found) == "table" and d.found or {}
			settings.customUrl = type(d.customUrl) == "string" and d.customUrl or ""
			settings.spawnAt = type(d.spawnAt) == "table" and d.spawnAt or nil
			settings.uid = type(d.uid) == "string" and d.uid or nil
			if type(d.ping) == "boolean" then
				settings.ping = d.ping
			end
			for _, k in ipairs({"autoAnchor", "autoCollide", "autoPlace", "autoRun", "autoAnimate", "globalChat", "playersOnlyTonyo"}) do
				if type(d[k]) == "boolean" then
					settings[k] = d[k]
				end
			end
		end
	end
end)

local function saveSettings()
	pcall(function()
		if writefile then
			writefile(SAVE_FILE, HttpService:JSONEncode(settings))
		end
	end)
end

-- TONYO v5 build tools: animation engine, auto anchor / auto collide, extra AI rules.
;(function()
	local RunService = game:GetService("RunService")

	local anim = {active = {}}

	local function num(v, d, lo, hi)
		v = tonumber(v)
		if not v or v ~= v then
			return d
		end
		return math.clamp(v, lo, hi)
	end

	local function axisOf(v, default)
		if type(v) == "table" and #v >= 3 then
			local x, y, z = tonumber(v[1]), tonumber(v[2]), tonumber(v[3])
			if x and y and z and (x ~= 0 or y ~= 0 or z ~= 0) then
				return Vector3.new(x, y, z).Unit
			end
		elseif type(v) == "string" then
			local a = v:upper()
			if a == "X" then
				return Vector3.new(1, 0, 0)
			elseif a == "Y" then
				return Vector3.new(0, 1, 0)
			elseif a == "Z" then
				return Vector3.new(0, 0, 1)
			end
		end
		return default
	end

	local function vec3(v, default)
		if type(v) == "table" and #v >= 3 then
			local x, y, z = tonumber(v[1]), tonumber(v[2]), tonumber(v[3])
			if x and y and z then
				return Vector3.new(math.clamp(x, -500, 500), math.clamp(y, -500, 500), math.clamp(z, -500, 500))
			end
		end
		return default
	end

	-- Each effect returns a function(t) -> worldOffset, localRotation, scaleMultiplier (any may be nil)
	local EFFECTS = {}

	function EFFECTS.spin(p)
		local axis = axisOf(p.axis, Vector3.new(0, 1, 0))
		local dps = num(p.speed, 90, -2000, 2000)
		return function(t)
			return nil, CFrame.fromAxisAngle(axis, math.rad(dps) * t)
		end, string.format("spin %g deg/s", dps)
	end

	function EFFECTS.bob(p)
		local height = num(p.height, 1.5, -200, 200)
		local cps = num(p.speed, 0.5, 0, 20)
		return function(t)
			return Vector3.new(0, math.sin(t * math.pi * 2 * cps) * height, 0)
		end, string.format("bob %g studs", height)
	end

	function EFFECTS.swing(p)
		local axis = axisOf(p.axis, Vector3.new(0, 1, 0))
		local angle = math.rad(num(p.angle, 30, -360, 360))
		local cps = num(p.speed, 0.5, 0, 20)
		return function(t)
			return nil, CFrame.fromAxisAngle(axis, angle * math.sin(t * math.pi * 2 * cps))
		end, string.format("swing %g deg", math.deg(angle))
	end

	function EFFECTS.pulse(p)
		local amount = num(p.amount, 0.15, -0.9, 3)
		local cps = num(p.speed, 1, 0, 20)
		return function(t)
			return nil, nil, 1 + amount * math.sin(t * math.pi * 2 * cps)
		end, string.format("pulse %g%%", amount * 100)
	end

	function EFFECTS.slide(p)
		local offset = vec3(p.offset, Vector3.new(0, 4, 0))
		local secs = num(p.time, 2, 0.1, 120)
		return function(t)
			return offset * ((1 - math.cos(t * math.pi / secs)) / 2)
		end, string.format("slide %g studs", offset.Magnitude)
	end

	local function apply(st)
		local inst = st.inst
		local pos, rot, scale = Vector3.zero, CFrame.identity, 1
		for _, e in ipairs(st.effects) do
			local o, r, sc = e.fn(st.t)
			if o then
				pos = pos + o
			end
			if r then
				rot = rot * r
			end
			if sc then
				scale = scale * sc
			end
		end
		if math.abs(scale - st.lastScale) > 0.0005 then
			st.lastScale = scale
			if inst:IsA("BasePart") then
				inst.Size = st.baseSize * scale
			elseif st.baseScale then
				inst:ScaleTo(st.baseScale * scale)
			end
		end
		inst:PivotTo(CFrame.new(pos) * st.base * rot)
	end

	function anim.stop(inst, noRestore)
		local st = anim.active[inst]
		if not st then
			return false
		end
		anim.active[inst] = nil
		if st.conn then
			st.conn:Disconnect()
		end
		if st.anc then
			st.anc:Disconnect()
		end
		if not noRestore then
			pcall(function()
				inst:PivotTo(st.base)
				if inst:IsA("BasePart") then
					inst.Size = st.baseSize
				elseif st.baseScale then
					inst:ScaleTo(st.baseScale)
				end
			end)
		end
		return true
	end

	function anim.stopAll()
		for inst in pairs(anim.active) do
			anim.stop(inst)
		end
	end

	function anim.start(inst, kind, params)
		if typeof(inst) ~= "Instance" or not (inst:IsA("Model") or inst:IsA("BasePart")) then
			error("only a Model or a Part can be animated")
		end
		kind = tostring(kind or "spin"):lower()
		if kind == "stop" then
			anim.stop(inst)
			return "stopped"
		end
		local build = EFFECTS[kind]
		if not build then
			error("unknown animation " .. kind .. " (use spin, bob, swing, pulse, slide or stop)")
		end
		local fn, desc = build(type(params) == "table" and params or {})
		local st = anim.active[inst]
		if not st then
			st = {inst = inst, base = inst:GetPivot(), t = 0, effects = {}, lastScale = 1}
			if inst:IsA("BasePart") then
				st.baseSize = inst.Size
			else
				local ok, sc = pcall(function()
					return inst:GetScale()
				end)
				st.baseScale = ok and sc or nil
			end
			anim.active[inst] = st
			st.conn = RunService.Heartbeat:Connect(function(dt)
				if not inst.Parent then
					return
				end
				st.t = st.t + dt
				if not pcall(apply, st) then
					anim.stop(inst, true)
				end
			end)
			st.anc = inst.AncestryChanged:Connect(function()
				if not inst:IsDescendantOf(game) then
					anim.stop(inst, true)
				end
			end)
		end
		for i, e in ipairs(st.effects) do
			if e.kind == kind then
				table.remove(st.effects, i)
				break
			end
		end
		st.effects[#st.effects + 1] = {kind = kind, fn = fn}
		return desc
	end

	TX.anim = anim
	pcall(function()
		shared.TONYO_ANIM = anim
	end)
	pcall(function()
		getgenv().TONYO_ANIM = anim
	end)

	-- ============ auto anchor / auto collide ============
	local PHYSICS_WORDS = {
		"Motor6D", "Humanoid", "BodyVelocity", "BodyPosition", "BodyGyro", "BodyForce", "LinearVelocity",
		"AngularVelocity", "VectorForce", "AlignPosition", "HingeConstraint", "SpringConstraint",
		"RopeConstraint", "VehicleSeat",
	}

	local function surroundings(part)
		local rigged, character = false, false
		local cur = part.Parent
		while cur and cur ~= workspace and cur ~= game do
			if cur:IsA("Model") then
				if cur:FindFirstChildOfClass("Humanoid") then
					character = true
				end
				if not rigged and cur:FindFirstChildWhichIsA("Motor6D", true) then
					rigged = true
				end
			end
			cur = cur.Parent
		end
		return rigged, character
	end

	function TX.options(code)
		local o = {anchor = settings.autoAnchor ~= false, collide = settings.autoCollide ~= false}
		if type(code) == "string" then
			if code:find("Anchored%s*=%s*false") then
				o.anchor = false
			end
			if code:find("CanCollide%s*=%s*false") then
				o.collide = false
			end
			for _, w in ipairs(PHYSICS_WORDS) do
				if code:find(w, 1, true) then
					o.anchor = false
					break
				end
			end
		end
		return o
	end

	function TX.fixPart(part, o)
		if not part:IsA("BasePart") or part:IsA("Terrain") then
			return 0, 0
		end
		local rigged, character = surroundings(part)
		if character then
			return 0, 0
		end
		local a, c = 0, 0
		-- A rigged creature keeps its limbs loose so joints can move them, but its root part is always anchored.
		local isRoot = rigged and part:FindFirstChildWhichIsA("Motor6D") ~= nil
		if o.anchor and (not rigged or isRoot) and not part.Anchored and not part:GetAttribute("TonyoKeepAnchor") then
			part.Anchored = true
			a = 1
		end
		if o.collide and not part.CanCollide and not part:GetAttribute("TonyoKeepGhost") then
			part.CanCollide = true
			c = 1
		end
		return a, c
	end

	function TX.fixBatch(list)
		local o = TX.options()
		if not o.anchor and not o.collide then
			return 0, 0
		end
		local a, c = 0, 0
		for _, inst in ipairs(list) do
			local items = {inst}
			for _, d in ipairs(inst:GetDescendants()) do
				items[#items + 1] = d
			end
			for _, x in ipairs(items) do
				local ok, da, dc = pcall(TX.fixPart, x, o)
				if ok then
					a = a + da
					c = c + dc
				end
			end
		end
		return a, c
	end

	-- Fixes anything that lands in the spawn folder later (clones, inserts, parts added by AI code).
	local watched = {}
	function TX.watch(folder, connList)
		if not folder or watched[folder] then
			return
		end
		watched[folder] = true
		local c = folder.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") then
				task.defer(function()
					local o = TX.options()
					if o.anchor or o.collide then
						pcall(TX.fixPart, d, o)
					end
				end)
			end
		end)
		if connList then
			connList[#connList + 1] = c
		end
	end

	-- Watches Instance.new inside one piece of AI code, then fixes only the parts that code made.
	function TX.track(code)
		local o = TX.options(code)
		if not o.anchor and not o.collide then
			return nil
		end
		local tracker = {fixed = 0}
		local proxy = setmetatable({
			new = function(class, parent)
				local obj = Instance.new(class, parent)
				if typeof(obj) == "Instance" and obj:IsA("BasePart") then
					task.defer(function()
						local ok, a, c = pcall(TX.fixPart, obj, o)
						if ok then
							tracker.fixed = tracker.fixed + a + c
						end
					end)
				end
				return obj
			end,
		}, {__index = Instance})
		-- Prefixed on the same line so error line numbers stay correct.
		function tracker.wrap(src)
			local ok = pcall(function()
				shared.TONYO_PROXY = proxy
			end)
			if not ok then
				return src
			end
			return "local Instance = shared.TONYO_PROXY or Instance; " .. src
		end
		return tracker
	end

	-- Extra rules appended to the system prompt, depending on the toggles in the BUILD tab.
	function TX.rules()
		local t = {}
		if settings.autoAnchor ~= false or settings.autoCollide ~= false then
			t[#t + 1] = " The app auto-fixes parts you create: "
				.. (settings.autoAnchor ~= false and "it anchors them (do not set Anchored=false unless something must fall or be pushed by physics) " or "")
				.. (settings.autoCollide ~= false and "and turns CanCollide on (do not set CanCollide=false unless a part must be walk-through)." or "")
		end
		if settings.autoAnimate ~= false then
			t[#t + 1] = ' ANIMATION: for anything that should move (fans, windmills, doors, coins, platforms, lights) add animate ops to the same ops list so it moves right away, without waiting to be asked: '
				.. '{"op":"animate","path":"Spawns.Windmill","type":"spin","axis":"Y","speed":60}. '
				.. 'Types: spin (speed in degrees per second, axis X, Y or Z), bob (height in studs, speed in cycles per second), swing (angle in degrees, speed, axis), '
				.. 'pulse (amount 0.1 means 10 percent, speed), slide (offset [x,y,z] in studs, time in seconds one way), stop. '
				.. 'Several animate ops on one path stack, for example spin plus bob for a coin. Animate a whole Model or a Part, never one part of a rigged creature (use rig plus a localscript for living things). '
				.. 'In local code you can also call getgenv().TONYO_ANIM.start(instance, "spin", {speed = 90}) and getgenv().TONYO_ANIM.stop(instance).'
		end
		if settings.autoPlace ~= false then
			t[#t + 1] = " SCRIPTS: when a feature needs both server and client code, always give BOTH blocks, a ```lua server:Name block for the server half and a ```lua local:NameClient block for the client half, "
				.. "and let them talk through a RemoteEvent that both find by the same name. The app auto-saves the server half and auto-places both in Workspace.TONYO_Scripts. "
				.. "Never claim the server half ran, because a client executor cannot run server scripts."
		end
		return table.concat(t)
	end
end)()

local function itemsOf(data)
	if type(data) ~= "table" then
		return {}
	end
	if data[1] ~= nil then
		return data
	end
	return data.data or data.models or data.items or {}
end

local function hasValue(list, value)
	if type(list) ~= "table" then
		return false
	end
	for _, v in ipairs(list) do
		if v == value then
			return true
		end
	end
	return false
end

local PARSE = {}

function PARSE.openai(data)
	local out = {}
	for _, m in ipairs(itemsOf(data)) do
		if type(m) == "string" then
			out[#out + 1] = {id = m}
		elseif type(m) == "table" and type(m.id) == "string" then
			out[#out + 1] = {id = m.id, created = tonumber(m.created)}
		end
	end
	return out
end

function PARSE.gemini(data)
	local out = {}
	for _, m in ipairs(itemsOf(data)) do
		if type(m) == "table" and type(m.name) == "string" and hasValue(m.supportedGenerationMethods, "generateContent") then
			out[#out + 1] = {id = (m.name:gsub("^models/", ""))}
		end
	end
	return out
end

function PARSE.date(s)
	local y, mo, d = tostring(s or ""):match("(%d+)%-(%d+)%-(%d+)")
	if y then
		return tonumber(y) * 10000 + tonumber(mo) * 100 + tonumber(d)
	end
	return nil
end

function PARSE.claude(data)
	local out = {}
	for _, m in ipairs(itemsOf(data)) do
		if type(m) == "table" and type(m.id) == "string" then
			out[#out + 1] = {id = m.id, created = PARSE.date(m.created_at)}
		end
	end
	return out
end

function PARSE.mistral(data)
	local out, seen = {}, {}
	for _, m in ipairs(itemsOf(data)) do
		if type(m) == "table" and type(m.id) == "string" then
			local caps = type(m.capabilities) == "table" and m.capabilities or {}
			if caps.completion_chat ~= false then
				local ids = {m.id}
				if type(m.aliases) == "table" then
					for _, a in ipairs(m.aliases) do
						if type(a) == "string" and a:find("%-latest$") then
							ids[#ids + 1] = a
						end
					end
				end
				for _, id in ipairs(ids) do
					if not seen[id] then
						seen[id] = true
						out[#out + 1] = {id = id, created = tonumber(m.created)}
					end
				end
			end
		end
	end
	return out
end

function PARSE.together(data)
	local out = {}
	for _, m in ipairs(itemsOf(data)) do
		if type(m) == "table" and type(m.id) == "string" and (m.type == nil or m.type == "chat") then
			out[#out + 1] = {id = m.id, created = tonumber(m.created)}
		end
	end
	return out
end

function PARSE.openrouter(data)
	local out = {}
	for _, m in ipairs(itemsOf(data)) do
		if type(m) == "table" and type(m.id) == "string" then
			local outputs = type(m.architecture) == "table" and m.architecture.output_modalities or nil
			local textOnly = outputs == nil or (hasValue(outputs, "text") and not hasValue(outputs, "image"))
			if textOnly then
				out[#out + 1] = {id = m.id, created = tonumber(m.created)}
			end
		end
	end
	return out
end

function PARSE.github(data)
	local out = {}
	for _, m in ipairs(itemsOf(data)) do
		if type(m) == "table" and type(m.id) == "string" then
			local outputs = m.supported_output_modalities
			if outputs == nil or hasValue(outputs, "text") then
				out[#out + 1] = {id = m.id}
			end
		end
	end
	return out
end

local rankModels
do
	local GENERIC_SKIP = {
		"embed", "whisper", "tts", "speech", "audio", "transcri", "moderat", "guard", "rerank",
		"dall%-e", "image", "veo%-", "sora", "diffusion", "flux", "realtime", "[%-/]ocr",
		"orpheus", "safety", "reward", "classif", "^ft:", "lyria", "robotics",
	}

	local function matchesAny(low, patterns)
		for _, pat in ipairs(patterns or {}) do
			if low:find(pat) then
				return true
			end
		end
		return false
	end

	local function isDated(low)
		return low:find("%d%d%d%d%-%d%d%-%d%d") ~= nil
			or low:find("%-%d%d%d%d$") ~= nil
			or low:find("%-%d%d%d$") ~= nil
			or low:find("%-%d%d%-%d%d%d%d$") ~= nil
	end

	local function versionKey(low)
		local out = {}
		for n in low:gmatch("%d+%.?%d*") do
			out[#out + 1] = tonumber(n)
		end
		return out
	end

	local function compareVersions(a, b)
		for i = 1, math.max(#a, #b) do
			local x, y = a[i] or -1, b[i] or -1
			if x ~= y then
				return x < y and -1 or 1
			end
		end
		return 0
	end

	function rankModels(p, models)
		local rows, seen = {}, {}
		for _, m in ipairs(models) do
			local id = m.id
			if type(id) == "string" and id ~= "" and not seen[id] then
				seen[id] = true
				local low = id:lower()
				if not matchesAny(low, GENERIC_SKIP) and not matchesAny(low, p.skip) then
					local tier = #p.prefer + 1
					for i, pat in ipairs(p.prefer) do
						if low:find(pat) then
							tier = i
							break
						end
					end
					rows[#rows + 1] = {
						id = id,
						tier = tier,
						dated = isDated(low),
						ver = versionKey(low),
						created = m.created or 0,
					}
				end
			end
		end
		table.sort(rows, function(a, b)
			if a.tier ~= b.tier then
				return a.tier < b.tier
			end
			if a.dated ~= b.dated then
				return not a.dated
			end
			local c = compareVersions(a.ver, b.ver)
			if c ~= 0 then
				return c > 0
			end
			if a.created ~= b.created then
				return a.created > b.created
			end
			return a.id < b.id
		end)
		local ids = {}
		for i, r in ipairs(rows) do
			ids[i] = r.id
		end
		return ids
	end
end

local function jsonHeaders(extra)
	local h = {["Content-Type"] = "application/json"}
	for k, v in pairs(extra or {}) do
		h[k] = v
	end
	return h
end

local function textOf(content)
	if type(content) == "string" then
		return content
	end
	if type(content) == "table" then
		local out = {}
		for _, part in ipairs(content) do
			if type(part) == "string" then
				out[#out + 1] = part
			elseif type(part) == "table" and type(part.text) == "string" then
				out[#out + 1] = part.text
			end
		end
		return table.concat(out)
	end
	return ""
end

local function openAI(def)
	local function base()
		local b = def.getBase and def.getBase() or def.base or ""
		return (tostring(b):gsub("/+$", ""):gsub("/chat/completions$", ""))
	end
	local p = {
		id = def.id, name = def.name, tag = def.tag, keyUrl = def.keyUrl, keyHint = def.keyHint,
		model = def.model or "", ctx = def.ctx,
		prefer = def.prefer or {}, skip = def.skip or {},
		rotate = def.rotate, keyOptional = def.keyOptional, needsUrl = def.needsUrl,
	}
	p.build = function(key, model, system, msgs)
		local m = {{role = "system", content = system}}
		for _, x in ipairs(msgs) do
			m[#m + 1] = {role = x.role, content = x.text}
		end
		local headers = jsonHeaders(def.headers)
		if key and key ~= "" then
			headers.Authorization = "Bearer " .. key
		end
		return {
			Url = base() .. "/chat/completions",
			Headers = headers,
			Body = HttpService:JSONEncode({model = model, messages = m}),
		}
	end
	p.listReq = function(key)
		local headers = {Accept = "application/json"}
		for k, v in pairs(def.headers or {}) do
			headers[k] = v
		end
		if key and key ~= "" then
			headers.Authorization = "Bearer " .. key
		end
		return {Url = def.listUrl or (base() .. "/models"), Headers = headers}
	end
	p.parseModels = def.parseModels or PARSE.openai
	p.parse = function(data)
		local c = data.choices and data.choices[1]
		return textOf(c and c.message and c.message.content)
	end
	p.ready = def.ready
	return p
end

local PROVIDERS = {
	{
		id = "gemini", name = "Gemini", tag = "free tier", keyUrl = "aistudio.google.com/apikey",
		model = "gemini-flash-latest",
		prefer = {
			"^gemini%-[%d%.]+%-flash$", "^gemini%-flash%-latest$", "^gemini%-[%d%.]+%-flash%-lite$",
			"^gemini%-[%d%.]+%-flash", "^gemini%-[%d%.]+%-pro$", "^gemini%-[%d%.]+%-pro", "^gemini",
		},
		skip = {"gemma", "live", "native", "computer", "learnlm", "aqa", "banana", "deep%-research"},
		build = function(key, model, system, msgs)
			local contents = {}
			for _, x in ipairs(msgs) do
				contents[#contents + 1] = {
					role = x.role == "assistant" and "model" or "user",
					parts = {{text = x.text}},
				}
			end
			return {
				Url = "https://generativelanguage.googleapis.com/v1beta/models/" .. model .. ":generateContent",
				Headers = jsonHeaders({["x-goog-api-key"] = key}),
				Body = HttpService:JSONEncode({
					systemInstruction = {parts = {{text = system}}},
					contents = contents,
				}),
			}
		end,
		parse = function(data)
			local text = ""
			local c = data.candidates and data.candidates[1] and data.candidates[1].content
			if c and c.parts then
				for _, part in ipairs(c.parts) do
					if part.text and not part.thought then
						text = text .. part.text
					end
				end
			end
			return text
		end,
		listReq = function(key)
			return {
				Url = "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000",
				Headers = {["x-goog-api-key"] = key},
			}
		end,
		parseModels = PARSE.gemini,
	},
	openAI({
		id = "groq", name = "Groq", tag = "free tier", keyUrl = "console.groq.com/keys",
		base = "https://api.groq.com/openai/v1", model = "llama-3.3-70b-versatile",
		ctx = 4000,
		prefer = {"llama%-3%.3%-70b", "gpt%-oss%-120b", "gpt%-oss%-20b", "llama%-4", "qwen", "llama"},
		skip = {"compound", "prompt"},
	}),
	openAI({
		id = "cerebras", name = "Cerebras", tag = "free tier", keyUrl = "cloud.cerebras.ai",
		base = "https://api.cerebras.ai/v1", model = "gpt-oss-120b",
		ctx = 5000,
		prefer = {"gpt%-oss%-120b", "qwen%-3%-235b", "glm", "qwen", "llama"},
	}),
	openAI({
		id = "sambanova", name = "SambaNova", tag = "free tier", keyUrl = "cloud.sambanova.ai/apis",
		base = "https://api.sambanova.ai/v1", model = "Meta-Llama-3.3-70B-Instruct",
		prefer = {"deepseek%-v3", "llama%-3%.3%-70b", "gpt%-oss", "minimax", "qwen", "llama"},
	}),
	openAI({
		id = "nvidia", name = "NVIDIA", tag = "free credits", keyUrl = "build.nvidia.com",
		base = "https://integrate.api.nvidia.com/v1", model = "meta/llama-3.3-70b-instruct",
		prefer = {"gpt%-oss%-120b", "deepseek%-v3", "llama%-3%.3%-70b", "coder", "nemotron", "llama%-3%.1%-70b", "llama"},
		skip = {"retriev", "parse", "riva", "vila", "neva", "fuyu", "paligemma", "kosmos", "cosmos", "deplot", "clip", "genmol", "diffdock", "bge", "snowflake", "baai"},
	}),
	openAI({
		id = "openrouter", name = "OpenRouter", tag = "free models", keyUrl = "openrouter.ai/keys",
		base = "https://openrouter.ai/api/v1", model = "openrouter/free",
		rotate = true,
		parseModels = PARSE.openrouter,
		prefer = {
			"coder.*:free$", "gpt%-oss%-120b.*:free$", "nemotron.*:free$", "deepseek.*:free$",
			"llama%-3%.3%-70b.*:free$", "glm.*:free$", "kimi.*:free$", "qwen.*:free$", ":free$",
		},
		skip = {"^openrouter/auto", "^openrouter/bodybuilder"},
	}),
	openAI({
		id = "mistral", name = "Mistral", tag = "free tier", keyUrl = "console.mistral.ai",
		base = "https://api.mistral.ai/v1", model = "mistral-small-latest",
		parseModels = PARSE.mistral,
		prefer = {
			"^mistral%-large%-latest$", "^mistral%-medium%-latest$", "^mistral%-small%-latest$",
			"^codestral%-latest$", "%-latest$", "^mistral%-",
		},
		skip = {"moderation", "voxtral"},
	}),
	openAI({
		id = "github", name = "GitHub Models", tag = "free, low limits",
		keyUrl = "github.com/settings/personal-access-tokens",
		keyHint = "Create a token with the Models: read permission.",
		base = "https://models.github.ai/inference", listUrl = "https://models.github.ai/catalog/models",
		model = "openai/gpt-4.1-mini", ctx = 5000,
		headers = {Accept = "application/vnd.github+json"},
		parseModels = PARSE.github,
		prefer = {"openai/gpt%-[%d%.]+%-mini$", "openai/gpt%-[%d%.]+$", "deepseek", "llama%-3%.3", "grok", "mistral", "phi"},
	}),
	openAI({
		id = "huggingface", name = "Hugging Face", tag = "free credits", keyUrl = "huggingface.co/settings/tokens",
		keyHint = "Use a token that allows calls to Inference Providers.",
		base = "https://router.huggingface.co/v1", model = "openai/gpt-oss-120b",
		prefer = {"gpt%-oss%-120b", "deepseek%-v3", "coder", "llama%-3%.3%-70b", "qwen", "llama"},
	}),
	openAI({
		id = "together", name = "Together", tag = "paid", keyUrl = "api.together.ai/settings/api-keys",
		base = "https://api.together.xyz/v1", model = "meta-llama/Llama-3.3-70B-Instruct-Turbo",
		parseModels = PARSE.together,
		prefer = {"gpt%-oss%-120b", "llama%-3%.3%-70b", "coder", "deepseek%-v3", "qwen", "llama"},
	}),
	openAI({
		id = "fireworks", name = "Fireworks", tag = "paid", keyUrl = "fireworks.ai/account/api-keys",
		base = "https://api.fireworks.ai/inference/v1", model = "accounts/fireworks/models/gpt-oss-120b",
		prefer = {"gpt%-oss%-120b", "llama%-v3p3%-70b", "deepseek%-v3", "coder", "qwen", "llama"},
	}),
	openAI({
		id = "xai", name = "xAI", tag = "paid", keyUrl = "console.x.ai",
		base = "https://api.x.ai/v1", model = "grok-4.5",
		prefer = {"^grok%-[%d%.]+$", "fast", "mini", "^grok"},
	}),
	openAI({
		id = "deepseek", name = "DeepSeek", tag = "very cheap", keyUrl = "platform.deepseek.com",
		base = "https://api.deepseek.com", model = "deepseek-chat",
		prefer = {"chat", "flash", "v%d", "reasoner"},
	}),
	openAI({
		id = "openai", name = "OpenAI", tag = "paid", keyUrl = "platform.openai.com/api-keys",
		base = "https://api.openai.com/v1", model = "gpt-5.6-terra",
		prefer = {
			"^gpt%-[%d%.]+%-terra$", "^gpt%-[%d%.]+%-luna$", "^gpt%-[%d%.]+%-mini$",
			"^gpt%-[%d%.]+%-sol$", "^gpt%-[%d%.]+$", "^gpt%-4",
		},
		skip = {"instruct", "search", "codex", "deep%-research", "chatgpt", "computer", "davinci", "babbage", "^gpt%-3", "^o%d"},
	}),
	{
		id = "claude", name = "Claude", tag = "paid", keyUrl = "console.anthropic.com",
		model = "claude-sonnet-5-5",
		prefer = {"sonnet", "haiku", "opus"},
		build = function(key, model, system, msgs, maxTokens)
			local m = {}
			for _, x in ipairs(msgs) do
				m[#m + 1] = {role = x.role, content = x.text}
			end
			return {
				Url = "https://api.anthropic.com/v1/messages",
				Headers = jsonHeaders({["x-api-key"] = key, ["anthropic-version"] = "2023-06-01"}),
				Body = HttpService:JSONEncode({
					model = model,
					max_tokens = maxTokens or 4096,
					system = system,
					messages = m,
				}),
			}
		end,
		parse = function(data)
			local text = ""
			if data.content then
				for _, b in ipairs(data.content) do
					if b.type == "text" then
						text = text .. b.text
					end
				end
			end
			return text
		end,
		listReq = function(key)
			return {
				Url = "https://api.anthropic.com/v1/models?limit=1000",
				Headers = {["x-api-key"] = key, ["anthropic-version"] = "2023-06-01"},
			}
		end,
		parseModels = PARSE.claude,
	},
	openAI({
		id = "cohere", name = "Cohere", tag = "free trial key", keyUrl = "dashboard.cohere.com/api-keys",
		base = "https://api.cohere.ai/compatibility/v1", model = "command-a-03-2025",
		prefer = {"^command%-a", "^command%-r%-plus", "^command%-r", "^command"},
	}),
	openAI({
		id = "deepinfra", name = "DeepInfra", tag = "free credits", keyUrl = "deepinfra.com/dash/api_keys",
		base = "https://api.deepinfra.com/v1/openai", model = "meta-llama/Llama-3.3-70B-Instruct",
		prefer = {"deepseek%-v3", "llama%-3%.3%-70b", "qwen", "coder", "llama"},
	}),
	openAI({
		id = "chutes", name = "Chutes", tag = "some free models", keyUrl = "chutes.ai/auth/start",
		keyHint = "Free, no-card models exist alongside paid ones on the same catalog; check llm.chutes.ai/v1/models.",
		base = "https://llm.chutes.ai/v1", model = "deepseek-ai/DeepSeek-V3",
		prefer = {"deepseek%-v3", "llama%-3%.1%-70b", "qwen", "llama"},
	}),
	openAI({
		id = "zai", name = "Z.AI", tag = "free tier", keyUrl = "z.ai/manage-apikey/apikey-list",
		keyHint = "GLM-4.5-Flash is free; larger GLM models are paid.",
		base = "https://api.z.ai/api/paas/v4", model = "glm-4.6",
		prefer = {"^glm%-4%.6$", "^glm%-4%.5%-flash$", "^glm%-4%.5", "^glm"},
	}),
	openAI({
		id = "moonshot", name = "Moonshot (Kimi)", tag = "paid", keyUrl = "platform.moonshot.ai/console/api-keys",
		base = "https://api.moonshot.ai/v1", model = "kimi-k2-0905-preview",
		prefer = {"kimi%-k2", "moonshot%-v1%-128k", "moonshot"},
	}),
	openAI({
		id = "minimax", name = "MiniMax", tag = "paid", keyUrl = "platform.minimax.io/user-center/basic-information/interface-key",
		base = "https://api.minimax.io/v1", model = "MiniMax-M2",
		prefer = {"minimax%-m2", "minimax%-text", "minimax"},
	}),
	openAI({
		id = "qwen", name = "Qwen", tag = "paid", keyUrl = "bailian.console.alibabacloud.com",
		keyHint = "A DashScope key from Alibaba Cloud Model Studio (international site).",
		base = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1", model = "qwen-plus",
		prefer = {"^qwen3%-max$", "^qwen%-max$", "^qwen%-plus$", "^qwen"},
	}),
	openAI({
		id = "perplexity", name = "Perplexity", tag = "paid", keyUrl = "perplexity.ai/account/api/keys",
		keyHint = "Sonar models can search the live web as part of the reply.",
		base = "https://api.perplexity.ai", model = "sonar-pro",
		prefer = {"^sonar%-pro$", "^sonar%-reasoning", "^sonar"},
	}),
	openAI({
		id = "ai21", name = "AI21", tag = "paid", keyUrl = "studio.ai21.com/account/api-keys",
		base = "https://api.ai21.com/studio/v1", model = "jamba-large-1.7",
		prefer = {"jamba%-large", "jamba%-mini", "jamba"},
	}),
	openAI({
		id = "hyperbolic", name = "Hyperbolic", tag = "paid", keyUrl = "app.hyperbolic.xyz/settings",
		base = "https://api.hyperbolic.xyz/v1", model = "meta-llama/Llama-3.3-70B-Instruct",
		prefer = {"deepseek%-v3", "llama%-3%.3%-70b", "qwen", "llama"},
	}),
	openAI({
		id = "novita", name = "Novita", tag = "paid", keyUrl = "novita.ai/settings/key-management",
		base = "https://api.novita.ai/v3/openai", model = "meta-llama/llama-3.3-70b-instruct",
		prefer = {"deepseek%-v3", "llama%-3%.3%-70b", "qwen", "llama"},
	}),
	openAI({
		id = "nebius", name = "Nebius", tag = "paid", keyUrl = "studio.nebius.com/settings/api-keys",
		base = "https://api.tokenfactory.nebius.com/v1", model = "meta-llama/Llama-3.3-70B-Instruct",
		prefer = {"deepseek%-v3", "llama%-3%.3%-70b", "qwen", "llama"},
	}),
	openAI({
		id = "venice", name = "Venice", tag = "paid", keyUrl = "venice.ai/settings/api",
		keyHint = "A privacy-focused host; no prompts logged by the provider.",
		base = "https://api.venice.ai/api/v1", model = "llama-3.3-70b",
		prefer = {"llama%-3%.3%-70b", "qwen", "llama"},
	}),
	openAI({
		id = "custom", name = "Custom", tag = "any OpenAI-style API",
		keyUrl = nil, keyHint = "Paste the base URL, for example https://host/v1. The key is optional.",
		needsUrl = true, keyOptional = true,
		getBase = function()
			return settings.customUrl
		end,
		ready = function()
			return settings.customUrl ~= ""
		end,
		prefer = {},
	}),
}

local PROVIDER_BY_ID = {}
for _, p in ipairs(PROVIDERS) do
	PROVIDER_BY_ID[p.id] = p
end

do
	local STEPS = {
		gemini = "1. Open aistudio.google.com/apikey and sign in with Google.\n2. Tap Create API key.\n3. Copy the key (starts with AIza). The free tier needs no card.",
		groq = "1. Open console.groq.com/keys and sign up.\n2. Tap Create API Key and give it a name.\n3. Copy it now, it is shown once (starts with gsk_). Free tier, no card.",
		cerebras = "1. Open cloud.cerebras.ai and sign up.\n2. Go to API Keys and create one.\n3. Copy it (starts with csk-). The free tier has small limits.",
		sambanova = "1. Open cloud.sambanova.ai/apis and sign up.\n2. Create an API key.\n3. Copy it. The free tier needs no card.",
		nvidia = "1. Open build.nvidia.com and sign in (a phone check may be needed).\n2. Open any model and tap Get API Key.\n3. Copy it (starts with nvapi-). Free credits cover light use.",
		openrouter = "1. Open openrouter.ai/keys and sign in.\n2. Tap Create Key.\n3. Copy it (starts with sk-or-). Models ending in :free cost nothing, with daily limits.",
		mistral = "1. Open console.mistral.ai and create an account.\n2. Pick the free Experiment plan when asked.\n3. Go to API Keys, create one and copy it.",
		github = "1. Open github.com/settings/personal-access-tokens and tap Generate new token.\n2. Under Account permissions set Models to Read-only.\n3. Generate and copy it (starts with github_pat_). Free, with low rate limits.",
		huggingface = "1. Open huggingface.co/settings/tokens and tap Create new token.\n2. Choose Fine-grained and tick Make calls to Inference Providers.\n3. Create and copy it (starts with hf_). A small monthly credit is free.",
		together = "1. Open api.together.ai/settings/api-keys and sign in.\n2. Create a key.\n3. Copy it. You may need to add credit before it works.",
		fireworks = "1. Open fireworks.ai/account/api-keys and sign in.\n2. Create an API key.\n3. Copy it (starts with fw_). New accounts may need credit.",
		xai = "1. Open console.x.ai and sign in.\n2. Add credit under Billing.\n3. Go to API Keys, create one and copy it (starts with xai-).",
		deepseek = "1. Open platform.deepseek.com and sign up.\n2. Top up a small balance.\n3. Go to API keys, create one and copy it (starts with sk-).",
		openai = "1. Open platform.openai.com/api-keys and sign in.\n2. Make sure the account has billing credit.\n3. Tap Create new secret key and copy it (starts with sk-).",
		claude = "1. Open console.anthropic.com and sign in.\n2. Add credit under Billing.\n3. Go to API Keys, tap Create Key and copy it (starts with sk-ant-).",
		custom = "Paste the base URL of any OpenAI-compatible API, for example https://host/v1. Add a key only if that server wants one. Tonyo reads /models from that URL to pick a model.",
	}
	for id, text in pairs(STEPS) do
		PROVIDER_BY_ID[id].steps = text
	end
end

local function detectProvider(key)
	local function by(id)
		return PROVIDER_BY_ID[id]
	end
	local strong = {
		{"^sk%-ant%-", "claude"}, {"^sk%-or%-", "openrouter"}, {"^sk%-proj%-", "openai"}, {"^AIza", "gemini"},
		{"^gsk_", "groq"}, {"^xai%-", "xai"}, {"^nvapi%-", "nvidia"}, {"^hf_", "huggingface"},
		{"^csk%-", "cerebras"}, {"^github_pat_", "github"}, {"^ghp_", "github"}, {"^fw_", "fireworks"},
		{"^tgp_v1_", "together"},
	}
	for _, r in ipairs(strong) do
		if key:find(r[1]) then
			return by(r[2]), true
		end
	end
	if #key == 35 and key:find("^sk%-%x+$") then
		return by("deepseek"), false
	end
	if key:find("^sk%-") then
		return by("openai"), false
	end
	if key:find("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") then
		return by("sambanova"), false
	end
	if #key == 64 and key:find("^%x+$") then
		return by("together"), false
	end
	if #key == 32 and key:find("^%w+$") then
		return by("mistral"), false
	end
	return nil, false
end

local function isAuto()
	return settings.engine == "auto" or PROVIDER_BY_ID[settings.engine] == nil
end

local function getProvider()
	return PROVIDER_BY_ID[settings.engine]
end

local function hasKey(p)
	local k = settings.keys[p.id]
	if type(k) == "string" and k ~= "" then
		return not p.ready or p.ready()
	end
	return p.keyOptional == true and p.ready ~= nil and p.ready()
end

local function pinnedModel(p)
	local m = settings.models[p.id]
	return (type(m) == "string" and m ~= "") and m or nil
end

local MAX_RETRIES = 3
local MAX_WAIT = 45
local FOUND_TTL = 6 * 3600

local function extractError(data, raw)
	if type(data) == "table" then
		local e = data.error
		if type(e) == "table" and e.message then
			return tostring(e.message)
		end
		if type(e) == "string" then
			return e
		end
		if data.message then
			return tostring(data.message)
		end
		if type(data[1]) == "table" and type(data[1].error) == "table" and data[1].error.message then
			return tostring(data[1].error.message)
		end
	end
	return type(raw) == "string" and raw:sub(1, 160) or "no details"
end

local function getHeader(headers, name)
	if type(headers) ~= "table" then
		return nil
	end
	for k, v in pairs(headers) do
		if string.lower(tostring(k)) == name then
			return v
		end
	end
	return nil
end

local function getRetryDelay(res, raw)
	local h = tonumber(getHeader(res.Headers, "retry-after"))
	if h then
		return h
	end
	if type(raw) == "string" then
		local g = raw:match('"retryDelay"%s*:%s*"(%d+%.?%d*)s"')
		if g then
			return tonumber(g)
		end
	end
	return nil
end

local function isNoCredits(raw)
	local s = string.lower(type(raw) == "string" and raw or "")
	return s:find("insufficient_quota", 1, true) ~= nil
		or s:find("credit balance", 1, true) ~= nil
		or s:find("insufficient balance", 1, true) ~= nil
		or s:find("insufficient credit", 1, true) ~= nil
		or s:find("out of credits", 1, true) ~= nil
end

local function callProvider(p, key, model, system, msgs, maxTokens, maxRetries, onRetry)
	local req = p.build(key, model, system, msgs, maxTokens)
	local attempt = 0
	while true do
		attempt = attempt + 1
		local ok, res = pcall(safeRequest, {
			Url = req.Url,
			Method = "POST",
			Headers = req.Headers,
			Body = req.Body,
		})
		if not ok or not res then
			return false, {network = true, message = tostring(res)}
		end

		local status = res.StatusCode or (res.Success and 200 or 0)
		local raw = res.Body
		local data = decode(raw)

		if status >= 200 and status < 300 then
			local pok, text = pcall(p.parse, data or {})
			return true, (pok and text) or ""
		end

		local message = extractError(data, raw)
		local noCredits = isNoCredits(raw) or status == 402
		local delay = getRetryDelay(res, raw)
		local retryable = (status == 429 or status == 503 or status == 529) and not noCredits
		if retryable and delay and delay > MAX_WAIT then
			retryable = false
		end

		if retryable and attempt <= (maxRetries or MAX_RETRIES) then
			local wait = math.clamp(delay or (2 ^ attempt) * 2, 1, MAX_WAIT)
			if onRetry then
				onRetry(attempt, wait)
			end
			task.wait(wait)
		else
			return false, {status = status, message = message, noCredits = noCredits, retryIn = delay}
		end
	end
end

local function isModelProblem(err)
	if not err or err.network then
		return false
	end
	local s = err.status
	if s == 404 then
		return true
	end
	if s == 400 or s == 403 or s == 422 then
		return string.lower(err.message or ""):find("model", 1, true) ~= nil
	end
	return false
end

local function isTooBig(err)
	if not err or err.network then
		return false
	end
	if err.status == 413 then
		return true
	end
	if err.status == 400 or err.status == 422 then
		local m = string.lower(err.message or "")
		if m:find("context", 1, true) and (m:find("length", 1, true) or m:find("window", 1, true)
			or m:find("exceed", 1, true) or m:find("limit", 1, true)) then
			return true
		end
		return m:find("too large", 1, true) ~= nil or m:find("too long", 1, true) ~= nil
			or m:find("reduce the length", 1, true) ~= nil
	end
	return false
end

local function isBadKey(err)
	if not err or err.network then
		return false
	end
	local m = string.lower(err.message or "")
	for _, phrase in ipairs({"api key not valid", "invalid api key", "incorrect api key", "api_key_invalid", "invalid x-api-key", "invalid_api_key"}) do
		if m:find(phrase, 1, true) then
			return true
		end
	end
	if err.status == 401 then
		return true
	end
	if err.status == 403 then
		return not isModelProblem(err)
	end
	return false
end

local liveRanked = {}
local listFailedUntil = {}

local function discoverModels(p, key, force)
	local mem = liveRanked[p.id]
	if mem and not force and os.time() - mem.at < FOUND_TTL then
		return mem.ids
	end
	if not p.listReq then
		return nil, {message = "This provider has no model list."}
	end
	if not force and (listFailedUntil[p.id] or 0) > os.clock() then
		return nil, {message = "Model list unavailable right now."}
	end

	local req = p.listReq(key)
	local ok, res = pcall(safeRequest, {Url = req.Url, Method = "GET", Headers = req.Headers})
	if not ok or not res then
		listFailedUntil[p.id] = os.clock() + 120
		return nil, {network = true, message = tostring(res)}
	end
	local status = res.StatusCode or (res.Success and 200 or 0)
	local data = decode(res.Body)
	if status < 200 or status >= 300 then
		listFailedUntil[p.id] = os.clock() + 120
		return nil, {status = status, message = extractError(data, res.Body)}
	end

	local pok, models = pcall(p.parseModels, data)
	local ids = pok and rankModels(p, models) or {}
	if #ids == 0 then
		listFailedUntil[p.id] = os.clock() + 120
		return nil, {status = status, message = "The model list was empty."}
	end

	liveRanked[p.id] = {ids = ids, at = os.time()}
	local top = {}
	for i = 1, math.min(#ids, 8) do
		top[i] = ids[i]
	end
	if p.id == "openrouter" and not hasValue(top, "openrouter/free") then
		table.insert(top, math.min(2, #top + 1), "openrouter/free")
	end
	settings.found[p.id] = {ids = top, at = os.time()}
	saveSettings()
	return ids
end

local function candidatesFor(p, key, force)
	local pinned = pinnedModel(p)
	if pinned then
		return {pinned}, "pinned"
	end
	if not force then
		local f = settings.found[p.id]
		if type(f) == "table" and type(f.ids) == "table" and #f.ids > 0 and os.time() - (tonumber(f.at) or 0) < FOUND_TTL then
			return f.ids, "cache"
		end
	end
	if discoverModels(p, key, force) then
		return settings.found[p.id].ids, "live"
	end
	if p.model ~= "" then
		return {p.model}, "default"
	end
	return {}, "none"
end

local function demoteModel(p, id)
	local f = settings.found[p.id]
	if type(f) == "table" and type(f.ids) == "table" then
		for i, v in ipairs(f.ids) do
			if v == id then
				table.remove(f.ids, i)
				break
			end
		end
		saveSettings()
	end
end

local function askProvider(p, key, system, msgs, maxTokens, retries, onRetry)
	local refreshed = false
	while true do
		local found, src = candidatesFor(p, key, refreshed)
		local cands = copyList(found)
		if #cands == 0 then
			return false, {status = 404, noModel = true, message = "No model found for " .. p.name .. "."}
		end
		local limit = src == "pinned" and 1 or (p.rotate and 4 or 3)
		local lastErr
		for i = 1, math.min(#cands, limit) do
			local id = cands[i]
			local ok, res = callProvider(p, key, id, system, msgs, maxTokens, p.rotate and 0 or retries, onRetry)
			if ok then
				return true, res, id
			end
			lastErr = res
			if isTooBig(res) then
				return false, res
			end
			local modelBad = isModelProblem(res)
			local busy = p.rotate and (res.status == 429 or res.status == 503)
			if src == "pinned" or not (modelBad or busy) then
				return false, res
			end
			if modelBad and src ~= "default" then
				demoteModel(p, id)
			end
		end

		if src == "cache" and not refreshed and isModelProblem(lastErr) then
			refreshed = true
		else
			return false, lastErr
		end
	end
end

local contextText = ""

local ROOTS = {
	"Workspace", "ReplicatedStorage", "ReplicatedFirst", "StarterGui", "StarterPack", "StarterPlayer",
	"Lighting", "SoundService", "Teams", "Chat", "TextChatService", "MaterialService",
}
local SCAN_PER_ROOT, SCAN_DEPTH, SCAN_KIDS, SCAN_CHARS = 160, 6, 30, 16000
local MAX_HISTORY = 12

local SYSTEM_PROMPT = "You are TONYO Model, an AI assistant inside a Roblox executor UI, running on the player's client. "
	.. "Help with Luau scripting, Roblox development and general questions. Be concise. "
	.. "Your replies appear in a small chat window: use short paragraphs, **bold**, `inline code` and fenced code blocks only. No tables, no HTML. "
	.. "Game info may appear under [Game context] (a scan of the game tree) or [Game data] (details of objects the user @mentioned, "
	.. "including script source when available). Use it, and never invent objects that are not listed; "
	.. "if you need more, ask the user to press Scan or @mention an object by its path (e.g. @Workspace.Map.Door). "
	.. "You can create anything with Luau (Instance.new parts, models, GUIs, effects, sounds, tools, and script logic). "
	.. "Reply with Luau inside code blocks. Label each block's script type on the opening fence line: "
	.. "```lua local:Name for client code (the user taps Run and it executes on the client only, other players will not see it), "
	.. "or ```lua server:Name for server Script code (it cannot run from the client, so the user saves it and pastes it into a Script "
	.. "in ServerScriptService in Studio). Remember server code uses ServerScriptService/ServerStorage and RemoteEvents for client communication. "
	.. 'To spawn, build, place, change or remove things in the game, do NOT write a script. Reply with one short sentence and one fenced block labelled ops that holds a JSON array. The app applies it on the client right away, so only this player sees it. '
	.. 'Ops: {"op":"create","class":"Part","name":"Box","parent":"Spawns","props":{"Size":[4,4,4],"Position":[0,2,0],"Color":[255,0,0],"Material":"Neon","Anchored":true}} ; '
	.. '{"op":"set","path":"Spawns.Box","props":{"Color":[0,0,255]}} ; {"op":"delete","path":"Spawns.Box"} ; '
	.. '{"op":"clone","path":"ReplicatedStorage.Car","name":"Car1","props":{"Position":[0,0,0]}} . '
	.. '"parent" is optional and defaults to the Spawns folder (Workspace.TONYO_Spawns); a later op may use an earlier object as parent, for example "Spawns.House". '
	.. 'Vectors and colors are arrays ([x,y,z] and [r,g,b] from 0 to 255) and enums are strings such as "Neon" or "Ball". '
	.. 'Positions of things inside Spawns are relative to a spawn point on the ground in front of the player, so [0,2,0] puts a 4 stud tall part standing right there. Only add "abs":true when the user gives exact world coordinates, and never invent world coordinates. '
	.. 'Build bigger things (houses, cars, towers, trees) from several create ops, give every object a unique name, and keep it under 60 ops. A Model or Folder is invisible unless it has Part children, so always add parts inside it. To make a creature, vehicle or building: first {"op":"create","class":"Model","name":"Dog"}, then many create ops for its parts with "parent":"Spawns.Dog" and unique part names (a dog needs about 14 parts: Body, Chest, Head, Snout, Nose, two Eyes, two Ears, four Legs, Tail), with sensible Size, Position, Color and Material. If it must move or animate, end the list with {"op":"rig","path":"Spawns.Dog","root":"Body"}, which joins every part to the root with a Motor6D named after the part (stored in the root). Then give the animation as a localscript:DogAnimation block that finds the model with workspace:WaitForChild("TONYO_Spawns"):WaitForChild("Dog"), saves each Motor6D C0, and every RunService.Heartbeat sets motor.C0 = base * CFrame.Angles(...) for walking legs, a wagging tail and a bobbing head. Never use script.Parent in that code. To load a real model from the catalog the user names an asset id for, use {"op":"insert","assetId":123456,"name":"Car"}; never invent asset ids. If the context contains an inspected model, use its exact part names, offsets and joints when you animate or edit it. Scripts cannot be made with ops. '
	.. 'When the user wants a script to install in the game, put the full code in a fenced block labelled script:Name, localscript:Name or modulescript:Name (for example ```script:DoorHandler). The app places it in Workspace as a real Script object and the user moves it. Say in one sentence where it belongs, such as ServerScriptService, StarterPlayerScripts, StarterGui or ReplicatedStorage. '
	.. "Use print() for output. Keep each script focused and safe."

local function isScript(inst)
	return inst:IsA("LuaSourceContainer")
end

local function scanGame()
	local lines, count = {}, 0
	local function walk(inst, depth, limit)
		if #lines >= limit then
			return
		end
		local tag = inst.ClassName .. (isScript(inst) and " *script*" or "")
		table.insert(lines, string.rep("  ", depth) .. inst.Name .. " [" .. tag .. "]")
		count = count + 1
		local kids = inst:GetChildren()
		if depth >= SCAN_DEPTH then
			if #kids > 0 then
				lines[#lines] = lines[#lines] .. " (+" .. #kids .. " children)"
			end
			return
		end
		for i, k in ipairs(kids) do
			if i > SCAN_KIDS then
				table.insert(lines, string.rep("  ", depth + 1) .. "... +" .. (#kids - SCAN_KIDS) .. " more")
				break
			end
			walk(k, depth + 1, limit)
		end
	end
	for _, name in ipairs(ROOTS) do
		local ok, svc = pcall(game.GetService, game, name)
		if ok and svc then
			walk(svc, 0, #lines + SCAN_PER_ROOT)
		end
	end
	for _, name in ipairs({"PlayerGui", "Backpack", "PlayerScripts"}) do
		local inst = player:FindFirstChild(name)
		if inst then
			walk(inst, 0, #lines + SCAN_PER_ROOT)
		end
	end
	local text = table.concat(lines, "\n")
	if #text > SCAN_CHARS then
		text = text:sub(1, SCAN_CHARS) .. "\n..."
	end

	local scripts = {}
	pcall(function()
		for _, d in ipairs(game:GetDescendants()) do
			if #scripts >= 150 then
				break
			end
			if isScript(d) then
				local full = d:GetFullName()
				if not full:find("^CoreGui") and not full:find("^CorePackages") then
					table.insert(scripts, full .. " [" .. d.ClassName .. "]")
				end
			end
		end
	end)
	if #scripts > 0 then
		text = text .. "\n\nSCRIPTS (client-visible; server-only scripts in ServerScriptService/ServerStorage can't be seen):\n"
			.. table.concat(scripts, "\n")
	end
	return text, count
end

local function resolvePath(path)
	local cur = game
	for _, part in ipairs(string.split(path, ".")) do
		if part == "" then
			return nil
		end
		local nxt
		if cur == game then
			local ok, svc = pcall(game.GetService, game, part)
			if ok then
				nxt = svc
			end
		end
		if not nxt and cur == Players and part == "LocalPlayer" then
			nxt = player
		end
		if not nxt then
			nxt = cur:FindFirstChild(part)
		end
		if not nxt and cur == game then
			nxt = game:FindFirstChild(part, true)
		end
		if not nxt then
			return nil
		end
		cur = nxt
	end
	return cur
end

local function describe(inst)
	local out = {inst:GetFullName() .. " [" .. inst.ClassName .. "]"}
	local function try(label, fn)
		local ok, v = pcall(fn)
		if ok and v ~= nil then
			table.insert(out, label .. ": " .. tostring(v))
		end
	end
	if inst:IsA("BasePart") then
		try("Position", function() return inst.Position end)
		try("Size", function() return inst.Size end)
		try("Anchored", function() return inst.Anchored end)
		try("CanCollide", function() return inst.CanCollide end)
		try("Transparency", function() return inst.Transparency end)
	end
	if inst:IsA("ValueBase") then
		try("Value", function() return inst.Value end)
	end
	if inst:IsA("GuiObject") then
		try("Visible", function() return inst.Visible end)
		try("Size", function() return inst.Size end)
	end
	local kids = inst:GetChildren()
	if #kids > 0 then
		local names = {}
		for i, k in ipairs(kids) do
			if i > 25 then
				table.insert(names, "... +" .. (#kids - 25) .. " more")
				break
			end
			table.insert(names, k.Name .. " [" .. k.ClassName .. "]")
		end
		table.insert(out, "Children: " .. table.concat(names, ", "))
	end
	if isScript(inst) then
		local src
		if decompile then
			local ok, r = pcall(decompile, inst)
			if ok and type(r) == "string" and r ~= "" then
				src = r
			end
		end
		if not src then
			local ok, r = pcall(function() return inst.Source end)
			if ok and type(r) == "string" and r ~= "" then
				src = r
			end
		end
		table.insert(out, src and ("Source:\n" .. clip(src, 4000)) or "Source: unavailable in this executor")
	end
	return table.concat(out, "\n")
end

local function expandMentions(text)
	local seen, blocks = {}, {}
	for raw in text:gmatch("@([%w_%.]+)") do
		local path = raw:gsub("%.+$", "")
		if path ~= "" and not seen[path] and #blocks < 4 then
			seen[path] = true
			local ok, inst = pcall(resolvePath, path)
			if ok and inst then
				local dok, d = pcall(describe, inst)
				table.insert(blocks, dok and d or ("@" .. path .. ": could not read"))
			else
				table.insert(blocks, "@" .. path .. ": not found")
			end
		end
	end
	if #blocks == 0 then
		return text
	end
	return text .. "\n\n[Game data]\n" .. table.concat(blocks, "\n\n")
end

local function buildSystem(p, scale)
	if contextText == "" then
		return SYSTEM_PROMPT .. (TX.rules and TX.rules() or "")
	end
	local limit = math.floor((p.ctx or 12000) * (scale or 1))
	local ctx = contextText
	if #ctx > limit then
		ctx = ctx:sub(1, limit) .. "\n...[context trimmed to fit this provider's limit]"
	end
	return SYSTEM_PROMPT .. (TX.rules and TX.rules() or "") .. "\n\n[Game context]\n" .. ctx
end

local function runCode(code)
	if not loadstring then
		return false, "This executor has no loadstring."
	end
	local logs = {}
	local conn = LogService.MessageOut:Connect(function(msg)
		table.insert(logs, msg)
	end)
	local tracker = TX.track and TX.track(code) or nil
	local fn, err = loadstring(tracker and tracker.wrap(code) or code)
	local ok, res
	if not fn then
		ok, res = false, err
	else
		ok, res = pcall(fn)
	end
	task.wait(0.3)
	conn:Disconnect()
	if tracker and tracker.fixed > 0 then
		table.insert(logs, 1, "[TONYO] auto-fixed " .. tracker.fixed .. " part setting(s): anchored or made solid")
	end
	if ok then
		return true, table.concat(logs, "\n")
	end
	return false, tostring(res)
end

local function cleanReply(text)
	local t = text:gsub("^%s+", ""):gsub("%s+$", "")
	if t:sub(1, 1) == "{" then
		local d = decode(t)
		if type(d) == "table" and type(d.say) == "string" then
			if type(d.ops) == "table" and #d.ops > 0 then
				local okj, enc = pcall(function()
					return HttpService:JSONEncode(d.ops)
				end)
				if okj then
					return d.say .. "\n```ops\n" .. enc .. "\n```"
				end
			end
			return d.say
		end
	end
	return t
end

local lastGood = nil
local cooldown = {}

local function routeOrder()
	local list = {}
	for _, p in ipairs(PROVIDERS) do
		if hasKey(p) then
			list[#list + 1] = p
		end
	end
	if lastGood then
		for i, p in ipairs(list) do
			if p.id == lastGood then
				if i > 1 then
					table.remove(list, i)
					table.insert(list, 1, p)
				end
				break
			end
		end
	end
	local ready, cooling = {}, {}
	for _, p in ipairs(list) do
		if (cooldown[p.id] or 0) > os.clock() then
			cooling[#cooling + 1] = p
		else
			ready[#ready + 1] = p
		end
	end
	for _, p in ipairs(cooling) do
		ready[#ready + 1] = p
	end
	return ready
end

local function markCooldown(p, err)
	if err.network or isTooBig(err) then
		return
	end
	local s = err.status
	local now = os.clock()
	if isModelProblem(err) and not isBadKey(err) then
		return
	end
	if err.noCredits or s == 402 then
		cooldown[p.id] = now + 1800
	elseif isBadKey(err) then
		cooldown[p.id] = now + 600
	elseif s == 429 or s == 503 or s == 529 then
		cooldown[p.id] = now + math.min(err.retryIn or 60, 300)
	end
end

local function isBusy(err)
	local s = err.status
	return not err.network and not err.noCredits and (s == 429 or s == 503 or s == 529)
end

local function reasonOf(err)
	if err.network then
		return "connection failed"
	end
	local s = err.status
	if err.noCredits or s == 402 then
		return "no credit left"
	elseif err.noModel then
		return "no model found"
	elseif isBadKey(err) then
		return "key rejected"
	elseif isModelProblem(err) then
		return "model not available"
	elseif isBusy(err) then
		return "rate limited"
	elseif isTooBig(err) then
		return "request too big"
	end
	return "error " .. tostring(s)
end

local function route(msgs, onNote)
	local plist
	if isAuto() then
		plist = routeOrder()
	else
		plist = {getProvider()}
	end
	if #plist == 0 then
		return false, {noKeys = true}, nil, nil, {}
	end

	local multi = #plist > 1
	local fails = {}

	for idx, p in ipairs(plist) do
		local key = settings.keys[p.id] or ""
		if onNote then
			onNote(idx == 1 and ("Asking " .. p.name) or ("Trying " .. p.name))
		end
		local scale, m = 1, copyList(msgs)
		local ok, res, model
		for _ = 1, 3 do
			ok, res, model = askProvider(p, key, buildSystem(p, scale), m, nil, multi and 0 or MAX_RETRIES, function(attempt, wait)
				if onNote then
					onNote(string.format("%s is busy, retrying in %ds (%d/%d)", p.name, math.ceil(wait), attempt, MAX_RETRIES))
				end
			end)
			if ok or not isTooBig(res) then
				break
			end
			scale = scale / 2
			if #m > 2 then
				table.remove(m, 1)
				table.remove(m, 1)
			end
			if onNote then
				onNote("Too much context for " .. p.name .. ", trimming")
			end
		end
		if ok then
			if isAuto() then
				lastGood = p.id
			end
			return true, res, p, model, fails
		end
		fails[#fails + 1] = {p = p, err = res}
		markCooldown(p, res)
	end

	if multi then
		local best, bestWait
		for _, f in ipairs(fails) do
			if isBusy(f.err) then
				local w = f.err.retryIn or 15
				if w <= MAX_WAIT and (not bestWait or w < bestWait) then
					best, bestWait = f.p, w
				end
			end
		end
		if best then
			for left = math.ceil(bestWait), 1, -1 do
				if onNote then
					onNote(string.format("Everything is busy, retrying %s in %ds", best.name, left))
				end
				task.wait(1)
			end
			local ok, res, model = askProvider(best, settings.keys[best.id] or "", buildSystem(best, 1), copyList(msgs), nil, 1, nil)
			if ok then
				lastGood = best.id
				return true, res, best, model, fails
			end
			fails[#fails + 1] = {p = best, err = res}
		end
	end

	local last = fails[#fails]
	return false, last.err, last.p, nil, fails
end

local function explainError(err, p)
	local raw = oneLine(err.message, 220)
	if err.network then
		return {title = "Can't reach " .. p.name, hint = "Check your connection, or whether your executor allows HTTP requests.", raw = raw}
	end
	local s = err.status
	if err.noCredits or s == 402 then
		return {
			title = p.name .. " has no credit left on this key",
			hint = "Add billing to that account, or switch to a provider with a free tier.",
			raw = raw, fix = "setup",
		}
	elseif err.noModel then
		return {title = "No model found for " .. p.name, hint = "Open Setup, tap Model and choose one.", raw = raw, fix = "setup"}
	elseif isBadKey(err) then
		return {title = p.name .. " rejected the key", hint = "Check the key in Setup, or use How to get a key there.", raw = raw, fix = "setup"}
	elseif isTooBig(err) then
		return {
			title = "The request is too big for " .. p.name,
			hint = "Clear the chat, or scan again. Auto uses a bigger provider if you add one.",
			raw = raw,
		}
	elseif isModelProblem(err) then
		if pinnedModel(p) then
			return {
				title = p.name .. " doesn't have the model you picked",
				hint = "Open Setup and set Model back to Auto.",
				raw = raw, fix = "setup",
			}
		end
		return {title = p.name .. " didn't accept the model", hint = "Try again in a moment. Auto will pick another one.", raw = raw}
	elseif s == 429 then
		local hint = err.retryIn and ("Try again in about " .. math.ceil(err.retryIn) .. " seconds.")
			or "Wait a minute, or add another provider and use Auto."
		return {title = p.name .. " is rate limited", hint = hint, raw = raw}
	end
	return {title = p.name .. " returned an error (HTTP " .. tostring(s) .. ")", hint = "", raw = raw}
end

local function explainFailures(fails)
	if #fails == 1 then
		return explainError(fails[1].err, fails[1].p)
	end
	local lines = {}
	local fix
	for _, f in ipairs(fails) do
		lines[#lines + 1] = f.p.name .. ": " .. reasonOf(f.err)
		local e = explainError(f.err, f.p)
		fix = fix or e.fix
	end
	return {
		title = "No provider could answer",
		hint = table.concat(lines, "\n"),
		raw = "",
		fix = fix or "setup",
	}
end

local function testProvider(p)
	if not hasKey(p) then
		return "idle", "Add a key first."
	end
	local key = settings.keys[p.id] or ""
	local ids, lerr = discoverModels(p, key, true)
	if ids then
		local pinned = pinnedModel(p)
		return "ok", string.format("Key works, %d models found. %s", #ids, pinned and ("Using " .. pinned .. ".") or ("Auto picks " .. ids[1] .. "."))
	end
	if lerr and isBadKey(lerr) then
		return "fail", "The key was rejected. Check that you copied all of it."
	end
	local model = pinnedModel(p) or p.model
	if model == "" then
		return "fail", "Couldn't read a model list from this URL. Check the base URL, or choose a model by name."
	end
	local ok, res = callProvider(p, key, model, "Reply with OK.", {{role = "user", text = "ping"}}, 8, 0)
	if ok then
		return "ok", "Key works. Using " .. model .. "."
	elseif res.noCredits or res.status == 402 then
		return "fail", "No credit left on this key."
	elseif isBusy(res) then
		return "warn", "Key works, but it is rate limited right now."
	elseif isBadKey(res) then
		return "fail", "The key was rejected. Check that you copied all of it."
	elseif isModelProblem(res) then
		return "warn", "Key works, but " .. model .. " was refused. Pick another model."
	end
	return "fail", "Failed (HTTP " .. tostring(res.status or "?") .. "): " .. oneLine(res.message, 120)
end

local app = {}
local view = {}
local conns = {}

local C = {
	ink = Color3.fromRGB(10, 10, 12),
	window = Color3.fromRGB(41, 41, 47),
	well = Color3.fromRGB(25, 25, 30),
	raised = Color3.fromRGB(62, 62, 71),
	raisedHi = Color3.fromRGB(80, 80, 92),
	raisedLip = Color3.fromRGB(36, 36, 43),
	line = Color3.fromRGB(72, 72, 82),
	text = Color3.fromRGB(242, 239, 230),
	sub = Color3.fromRGB(186, 183, 174),
	faint = Color3.fromRGB(130, 128, 121),
	white = Color3.fromRGB(255, 255, 255),
	head = Color3.fromRGB(35, 96, 206),
	headHi = Color3.fromRGB(66, 134, 242),
	headLo = Color3.fromRGB(22, 62, 146),
	yellow = Color3.fromRGB(255, 200, 36),
	yellowLip = Color3.fromRGB(176, 122, 10),
	yellowInk = Color3.fromRGB(38, 28, 4),
	green = Color3.fromRGB(76, 204, 104),
	greenLip = Color3.fromRGB(30, 118, 56),
	blue = Color3.fromRGB(56, 124, 236),
	blueLip = Color3.fromRGB(26, 68, 158),
	red = Color3.fromRGB(226, 66, 58),
	redLip = Color3.fromRGB(136, 28, 26),
	redText = Color3.fromRGB(255, 148, 138),
	redTint = Color3.fromRGB(60, 32, 34),
	orange = Color3.fromRGB(246, 142, 42),
	amber = Color3.fromRGB(240, 176, 52),
	code = Color3.fromRGB(17, 17, 21),
	codeHead = Color3.fromRGB(30, 30, 37),
	codeText = Color3.fromRGB(226, 224, 216),
	scroll = Color3.fromRGB(150, 118, 30),
}

local K = {
	yellow = {bg = C.yellow, lip = C.yellowLip, fg = C.yellowInk},
	green = {bg = C.green, lip = C.greenLip, fg = C.ink},
	blue = {bg = C.blue, lip = C.blueLip, fg = C.white},
	red = {bg = C.red, lip = C.redLip, fg = C.white},
	gray = {bg = C.raised, lip = C.raisedLip, fg = C.text},
}

local function pickFont(names, fallback)
	for _, n in ipairs(names) do
		local ok, f = pcall(function()
			return Enum.Font[n]
		end)
		if ok and f then
			return f
		end
	end
	return fallback
end

local F = {
	reg = pickFont({"Gotham", "BuilderSans", "SourceSans"}, Enum.Font.SourceSans),
	med = pickFont({"GothamMedium", "BuilderSansMedium", "SourceSansSemibold"}, Enum.Font.SourceSansSemibold),
	bold = pickFont({"GothamBold", "BuilderSansBold", "SourceSansBold"}, Enum.Font.SourceSansBold),
	head = pickFont({"FredokaOne", "GothamBlack", "SourceSansBold"}, Enum.Font.SourceSansBold),
	code = pickFont({"RobotoMono", "Code"}, Enum.Font.Code),
}

local AX = Enum.TextXAlignment
local AUTO_Y = Enum.AutomaticSize.Y

local PANEL_W, PANEL_H
do
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(800, 450)
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	if touchOnly then
		PANEL_W = math.clamp(math.floor(viewport.X * 0.46), 310, 390)
		PANEL_H = math.clamp(math.floor(viewport.Y * 0.7), 250, 350)
	else
		PANEL_W = math.clamp(math.floor(viewport.X * 0.3), 370, 470)
		PANEL_H = math.clamp(math.floor(viewport.Y * 0.64), 380, 560)
	end
end
local HEAD_H, TAB_H, FOOT_H = 42, 36, 80
local BUBBLE_MAX = math.floor((PANEL_W - 36) * 0.84)
local CODE_LINE_H, CODE_MAX_LINES = 15, 12

local function make(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	if parent then
		o.Parent = parent
	end
	return o
end

local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
	return c
end

local function stroke(inst, color, thick, alpha)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color or C.ink
	s.Thickness = thick or 2
	s.Transparency = alpha or 0
	s.Parent = inst
	return s
end

local function pad(inst, l, t, r, b)
	local p = Instance.new("UIPadding")
	p.PaddingLeft, p.PaddingTop, p.PaddingRight, p.PaddingBottom = UDim.new(0, l), UDim.new(0, t), UDim.new(0, r), UDim.new(0, b)
	p.Parent = inst
	return p
end

local function stack(inst, gap, horizontal)
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, gap or 0)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	if horizontal then
		l.FillDirection = Enum.FillDirection.Horizontal
		l.VerticalAlignment = Enum.VerticalAlignment.Center
	end
	l.Parent = inst
	return l
end

local function gradient(inst, top, bottom)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = 90
	g.Parent = inst
	return g
end

local function label(parent, o)
	local wrap = o.wrap == true
	return make("TextLabel", {
		Name = o.name or "Label",
		BackgroundTransparency = 1,
		Text = o.text or "",
		Font = o.font or F.reg,
		TextSize = o.ts or 13,
		TextColor3 = o.color or C.text,
		TextXAlignment = o.align or AX.Left,
		TextYAlignment = o.yalign or Enum.TextYAlignment.Center,
		TextWrapped = wrap,
		RichText = o.rich == true,
		TextTruncate = wrap and Enum.TextTruncate.None or Enum.TextTruncate.AtEnd,
		Size = o.size or UDim2.new(1, 0, 0, 18),
		Position = o.pos or UDim2.new(0, 0, 0, 0),
		AnchorPoint = o.anchor or Vector2.new(0, 0),
		AutomaticSize = o.auto or Enum.AutomaticSize.None,
		LayoutOrder = o.order or 0,
	}, parent)
end

local function tween(inst, props, t, style)
	TweenService:Create(inst, TweenInfo.new(t or 0.1, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function paint(b, bg, lipColor, fg)
	b:SetAttribute("base", bg)
	b.BackgroundColor3 = bg
	local lip = b:FindFirstChild("Lip")
	if lip and lipColor then
		lip.BackgroundColor3 = lipColor
	end
	if fg then
		b.TextColor3 = fg
	end
end

local function brick(parent, o)
	local ghost = o.ghost == true
	local k = K[o.kind or "gray"]
	local base = o.bg or k.bg
	local b = make("TextButton", {
		Name = o.name or "Brick",
		Text = o.text or "",
		AutoButtonColor = false,
		BackgroundColor3 = ghost and C.white or base,
		BackgroundTransparency = ghost and 1 or 0,
		BorderSizePixel = 0,
		Font = o.font or F.head,
		TextSize = o.ts or 13,
		TextColor3 = o.fg or k.fg,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = o.size or UDim2.new(0, 60, 0, 28),
		Position = o.pos or UDim2.new(0, 0, 0, 0),
		AnchorPoint = o.anchor or Vector2.new(0, 0),
		LayoutOrder = o.order or 0,
	}, parent)
	b:SetAttribute("base", base)
	corner(b, o.radius or 5)
	local lip
	if not ghost then
		stroke(b, C.ink, o.sw or 2)
		lip = make("Frame", {
			Name = "Lip", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, o.lipH or 3), BackgroundColor3 = o.lip or k.lip, BorderSizePixel = 0,
		}, b)
		corner(lip, 3)
	end
	local function rest()
		if ghost then
			b.BackgroundTransparency = 1
		else
			tween(b, {BackgroundColor3 = b:GetAttribute("base")}, 0.08)
			lip.Size = UDim2.new(1, 0, 0, o.lipH or 3)
		end
	end
	b.MouseEnter:Connect(function()
		if ghost then
			b.BackgroundTransparency = 0.9
		else
			tween(b, {BackgroundColor3 = b:GetAttribute("base"):Lerp(C.white, 0.12)}, 0.08)
		end
	end)
	b.MouseLeave:Connect(rest)
	b.InputBegan:Connect(function(input)
		if isPress(input) then
			if ghost then
				b.BackgroundTransparency = 0.8
			else
				b.BackgroundColor3 = b:GetAttribute("base"):Lerp(C.ink, 0.22)
				lip.Size = UDim2.new(1, 0, 0, 1)
			end
		end
	end)
	b.InputEnded:Connect(function(input)
		if isPress(input) then
			rest()
		end
	end)
	if o.onClick then
		b.Activated:Connect(o.onClick)
	end
	return b
end

local function textBox(parent, o)
	local t = make("TextBox", {
		Name = o.name or "TextBox",
		BackgroundColor3 = C.well,
		BorderSizePixel = 0,
		Font = F.reg,
		TextSize = 12,
		TextColor3 = C.text,
		PlaceholderText = o.placeholder or "",
		PlaceholderColor3 = C.faint,
		Text = "",
		ClearTextOnFocus = false,
		TextXAlignment = AX.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = o.size or UDim2.new(1, 0, 0, 32),
		Position = o.pos or UDim2.new(0, 0, 0, 0),
		LayoutOrder = o.order or 0,
	}, parent)
	corner(t, 5)
	local s = stroke(t, C.ink, 2)
	pad(t, 10, 0, 10, 0)
	t.Focused:Connect(function()
		s.Color = C.yellow
	end)
	t.FocusLost:Connect(function()
		s.Color = C.ink
	end)
	return t
end
local old = guiParent:FindFirstChild("TONYOModel_UI")
if old then
	old:Destroy()
end

local gui = make("ScreenGui", {
	Name = "TONYOModel_UI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 999999,
}, guiParent)

local panel = make("Frame", {
	Name = "Panel",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 14),
	Size = UDim2.new(0, PANEL_W, 0, PANEL_H),
	BackgroundTransparency = 1,
}, gui)

local shadow = make("Frame", {
	Name = "Shadow", Position = UDim2.new(0, 0, 0, 6), Size = UDim2.new(1, 0, 1, 0),
	BackgroundColor3 = C.ink, BackgroundTransparency = 0.45, BorderSizePixel = 0,
}, panel)
corner(shadow, 8)

local card = make("Frame", {
	Name = "Card", Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = C.window,
	BorderSizePixel = 0, ClipsDescendants = true,
}, panel)
corner(card, 8)
stroke(card, C.ink, 3)

for i = 0, math.floor((PANEL_W - 44) / 24) - 1 do
	local s = make("Frame", {
		Name = "Stud", Size = UDim2.new(0, 14, 0, 7), Position = UDim2.new(0, 18 + i * 24, 0, -9),
		BackgroundColor3 = C.headHi, BorderSizePixel = 0,
	}, panel)
	corner(s, 3)
	stroke(s, C.ink, 2)
end

local head = make("Frame", {
	Name = "Header", Size = UDim2.new(1, 0, 0, HEAD_H), BackgroundColor3 = C.white, BorderSizePixel = 0,
}, card)
gradient(head, C.headHi, C.headLo)
make("Frame", {
	Name = "HeaderEdge", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0),
	Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = C.ink, BorderSizePixel = 0,
}, head)

local title = label(head, {
	name = "Title", text = "TONYO", font = F.head, ts = 24, color = C.white,
	size = UDim2.new(0, 92, 1, -3), pos = UDim2.new(0, 14, 0, 0),
})
title.TextStrokeColor3 = C.ink
title.TextStrokeTransparency = 0

local sticker = make("Frame", {
	Name = "Sticker", Size = UDim2.new(0, 34, 0, 18), Position = UDim2.new(0, 110, 0, 11),
	Rotation = -6, BackgroundColor3 = C.yellow, BorderSizePixel = 0,
}, head)
corner(sticker, 3)
stroke(sticker, C.ink, 2)
local counter = make("TextButton", {
	Name = "PlayerCounter", Text = "", AutoButtonColor = false, Size = UDim2.new(0, 80, 0, 22), Position = UDim2.new(0, 152, 0, 10),
	BackgroundColor3 = C.headLo, BorderSizePixel = 0,
}, head)
corner(counter, 4)
stroke(counter, C.ink, 2)
local counterDot = make("Frame", {Name = "CounterDot", Size = UDim2.new(0, 8, 0, 8), Position = UDim2.new(0, 7, 0.5, -4), BackgroundColor3 = C.green, BorderSizePixel = 0}, counter)
corner(counterDot, 2)
stroke(counterDot, C.ink, 1)
local counterText = label(counter, {name = "CounterText", text = "1/1", font = F.head, ts = 12, color = C.white, size = UDim2.new(1, -22, 1, 0), pos = UDim2.new(0, 20, 0, 0)})
counter.Activated:Connect(function()
	view.selectTab("players")
end)
label(sticker, {name = "StickerText", text = "v6", font = F.head, ts = 12, color = C.yellowInk, align = AX.Center, size = UDim2.new(1, 0, 1, 0)})

local ONLINE_DB = "https://last1-d8426-default-rtdb.firebaseio.com"
local SCRIPT_URL = ""
local online = {count = nil, at = 0, status = "not set up", users = {}, control = {}, lastError = ""}

local function refreshCounter()
	if online.count then
		counterText.Text = online.count .. " online"
	else
		counterText.Text = #Players:GetPlayers() .. "/" .. Players.MaxPlayers
	end
end

brick(head, {
	name = "CloseButton", text = "X", kind = "red", ts = 14, size = UDim2.new(0, 26, 0, 26), pos = UDim2.new(1, -38, 0, 6),
	onClick = function()
		app.close()
	end,
})
brick(head, {
	name = "MinButton", text = "-", kind = "yellow", ts = 20, size = UDim2.new(0, 26, 0, 26), pos = UDim2.new(1, -70, 0, 6),
	onClick = function()
		app.toggleMin()
	end,
})

local tabStrip = make("ScrollingFrame", {
	Name = "TabStrip", Position = UDim2.new(0, 0, 0, HEAD_H), Size = UDim2.new(1, 0, 0, TAB_H), BackgroundTransparency = 1,
	BorderSizePixel = 0, ScrollBarThickness = 0, CanvasSize = UDim2.new(0, 474, 0, 0), ScrollingDirection = Enum.ScrollingDirection.X,
}, card)
local tabs = {}
local function addTab(id, text, x, w)
	tabs[id] = brick(tabStrip, {
		name = "Tab_" .. id, text = text, ts = 13, kind = "gray", fg = C.sub,
		size = UDim2.new(0, w, 0, 26), pos = UDim2.new(0, x, 0, 7),
		onClick = function()
			view.selectTab(id)
		end,
	})
end
addTab("chat", "CHAT", 10, 70)
addTab("setup", "SETUP", 84, 72)
addTab("export", "EXPORT", 160, 78)
addTab("players", "PLAYERS", 242, 86)
addTab("audit", "AUDIT", 332, 70)
addTab("news", "NEW", 406, 56)
addTab("build", "BUILD", 466, 66)
addTab("global", "GLOBAL", 536, 84)
addTab("assets", "ASSETS", 624, 74)
tabStrip.CanvasSize = UDim2.new(0, 710, 0, 0)
if isAdmin() then
	addTab("admin", "ADMIN", 702, 66)
	tabStrip.CanvasSize = UDim2.new(0, 780, 0, 0)
end

local banner = make("TextButton", {
	Name = "Banner", Text = "", AutoButtonColor = false, Position = UDim2.new(0, 0, 0, HEAD_H + TAB_H),
	Size = UDim2.new(1, 0, 0, 0), BackgroundColor3 = C.red, BorderSizePixel = 0, Visible = false, ZIndex = 25,
	ClipsDescendants = true,
}, card)
local bannerLabel = label(banner, {
	name = "BannerText", font = F.bold, ts = 11, color = C.white, align = AX.Center, wrap = true,
	size = UDim2.new(1, -16, 0, 0), pos = UDim2.new(0, 8, 0, 4), auto = AUTO_Y,
})
do
	local av = make("ImageLabel", {
		Name = "Avatar", Size = UDim2.new(0, 26, 0, 26), Position = UDim2.new(0, 6, 0, 4), BackgroundColor3 = C.ink,
		BorderSizePixel = 0, Visible = false, ZIndex = 26,
	}, banner)
	corner(av, 5)
end
local function setBanner(show, text, color, uid)
	banner.Visible = show
	if show then
		banner.BackgroundColor3 = color
		bannerLabel.Text = text
		local withPic = tonumber(uid) ~= nil and tonumber(uid) > 0
		local av = banner:FindFirstChild("Avatar")
		if av then
			av.Visible = withPic
			if withPic then
				av.Image = "rbxthumb://type=AvatarHeadShot&id=" .. math.floor(tonumber(uid)) .. "&w=100&h=100"
			end
		end
		bannerLabel.Position = UDim2.new(0, withPic and 40 or 8, 0, 4)
		bannerLabel.Size = UDim2.new(1, withPic and -48 or -16, 0, 0)
		banner.Size = UDim2.new(1, 0, 0, withPic and 34 or 24)
	end
end

do
	local dragging, dragStart, startPos
	conns[#conns + 1] = head.InputBegan:Connect(function(input)
		if isPress(input) then
			dragging, dragStart, startPos = true, input.Position, panel.Position
			local c
			c = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					c:Disconnect()
				end
			end)
		end
	end)
	conns[#conns + 1] = UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - dragStart
			local vp = gui.AbsoluteSize
			local x = math.clamp(startPos.X.Offset + d.X, -(vp.X - PANEL_W) / 2, (vp.X - PANEL_W) / 2)
			local y = math.clamp(startPos.Y.Offset + d.Y, 12, math.max(12, vp.Y - HEAD_H - 40))
			panel.Position = UDim2.new(startPos.X.Scale, x, startPos.Y.Scale, y)
		end
	end)
end

local body = make("Frame", {
	Name = "Body", Position = UDim2.new(0, 0, 0, HEAD_H + TAB_H), Size = UDim2.new(1, 0, 1, -(HEAD_H + TAB_H)),
	BackgroundTransparency = 1,
}, card)

local chat = make("Frame", {Name = "ChatPage", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1}, body)

local well = make("Frame", {
	Name = "MessageWell", Position = UDim2.new(0, 8, 0, 2), Size = UDim2.new(1, -16, 1, -(FOOT_H + 6)),
	BackgroundColor3 = C.well, BorderSizePixel = 0,
}, chat)
corner(well, 6)
stroke(well, C.ink, 2)

local list = make("ScrollingFrame", {
	Name = "MessageList", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 4, ScrollBarImageColor3 = C.scroll, CanvasSize = UDim2.new(0, 0, 0, 0),
	ScrollingDirection = Enum.ScrollingDirection.Y,
}, well)
pad(list, 10, 10, 10, 10)
local listLayout = stack(list, 12)

local stick = true
listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	local h = listLayout.AbsoluteContentSize.Y + 20
	list.CanvasSize = UDim2.new(0, 0, 0, h)
	if stick then
		list.CanvasPosition = Vector2.new(0, math.max(0, h - list.AbsoluteSize.Y))
	end
end)
list:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
	local maxY = list.CanvasSize.Y.Offset - list.AbsoluteSize.Y
	stick = list.CanvasPosition.Y >= maxY - 40
end)

local empty = make("Frame", {
	Name = "EmptyState", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.new(1, -40, 0, 0), AutomaticSize = AUTO_Y, BackgroundTransparency = 1,
}, well)
do
	local l = stack(empty, 8)
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
end

local function miniBrick(parent, color, x, y, w, rot)
	local f = make("Frame", {
		Size = UDim2.new(0, w, 0, 18), Position = UDim2.new(0, x, 0, y), Rotation = rot,
		BackgroundColor3 = color, BorderSizePixel = 0,
	}, parent)
	corner(f, 3)
	stroke(f, C.ink, 2)
	for i = 0, 1 do
		local s = make("Frame", {
			Size = UDim2.new(0, 10, 0, 5), Position = UDim2.new(0, 7 + i * (w - 28), 0, -7),
			BackgroundColor3 = color, BorderSizePixel = 0,
		}, f)
		corner(s, 2)
		stroke(s, C.ink, 2)
	end
	return f
end

local emptyArt = make("Frame", {Name = "EmptyArt", Size = UDim2.new(0, 76, 0, 68), BackgroundTransparency = 1, LayoutOrder = 0}, empty)
miniBrick(emptyArt, C.red, 10, 46, 56, 0)
miniBrick(emptyArt, C.yellow, 16, 26, 44, 4)
miniBrick(emptyArt, C.blue, 24, 8, 32, -8)

local emptyTitle = label(empty, {name = "EmptyTitle", font = F.head, ts = 18, align = AX.Center, wrap = true, size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = 1})
local emptyBody = label(empty, {name = "EmptyBody", ts = 12, color = C.sub, align = AX.Center, wrap = true, size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = 2})
local emptyChips = {}
for i, text in ipairs({"Spawn a red neon cube", "Build a small house", "Make a dog with walking animation"}) do
	emptyChips[i] = brick(empty, {
		name = "StartChip" .. i, text = text, kind = "gray", ts = 11, font = F.med, size = UDim2.new(0, 214, 0, 26), order = 3 + i,
		onClick = function()
			app.prefill(text)
		end,
	})
end
local emptyButton = brick(empty, {
	name = "EmptySetup", text = "OPEN SETUP", kind = "yellow", ts = 13, size = UDim2.new(0, 124, 0, 30), order = 3,
	onClick = function()
		view.selectTab("setup")
	end,
})

local foot = make("Frame", {
	Name = "Footer", Position = UDim2.new(0, 0, 1, -FOOT_H), Size = UDim2.new(1, 0, 0, FOOT_H), BackgroundTransparency = 1,
}, chat)

local statusDot = make("Frame", {
	Name = "StatusDot", Size = UDim2.new(0, 9, 0, 9), Position = UDim2.new(0, 14, 0, 10),
	BackgroundColor3 = C.faint, BorderSizePixel = 0,
}, foot)
corner(statusDot, 2)
stroke(statusDot, C.ink, 1)
local statusLabel = label(foot, {name = "StatusText", font = F.med, ts = 11, color = C.sub, size = UDim2.new(1, -250, 0, 18), pos = UDim2.new(0, 30, 0, 5)})

local scanButton = brick(foot, {
	name = "ScanButton", text = "SCAN", ts = 11, kind = "gray", radius = 4, lipH = 2,
	size = UDim2.new(0, 62, 0, 20), pos = UDim2.new(1, -134, 0, 4),
	onClick = function()
		app.scan()
	end,
})
brick(foot, {
	name = "ExportButton", text = "EXPORT", ts = 11, kind = "gray", radius = 4, lipH = 2,
	size = UDim2.new(0, 66, 0, 20), pos = UDim2.new(1, -206, 0, 4),
	onClick = function()
		view.selectTab("export")
	end,
})
brick(foot, {
	name = "ClearButton", text = "CLEAR", ts = 11, kind = "gray", fg = C.sub, radius = 4, lipH = 2,
	size = UDim2.new(0, 56, 0, 20), pos = UDim2.new(1, -64, 0, 4),
	onClick = function()
		app.clear()
	end,
})

local inputWrap = make("Frame", {
	Name = "InputWrap", Position = UDim2.new(0, 8, 0, 30), Size = UDim2.new(1, -16, 0, 42),
	BackgroundColor3 = C.well, BorderSizePixel = 0,
}, foot)
corner(inputWrap, 6)
local inputStroke = stroke(inputWrap, C.ink, 2)

local input = make("TextBox", {
	Name = "InputBox", Size = UDim2.new(1, -86, 1, 0), BackgroundTransparency = 1, Font = F.reg, TextSize = 13,
	TextColor3 = C.text, PlaceholderColor3 = C.faint, PlaceholderText = "Ask anything, or @path to read an object",
	Text = "", ClearTextOnFocus = false, TextXAlignment = AX.Left, TextTruncate = Enum.TextTruncate.AtEnd,
}, inputWrap)
pad(input, 12, 0, 0, 0)

local sendButton = brick(inputWrap, {
	name = "SendButton", text = "SEND", kind = "yellow", ts = 13,
	size = UDim2.new(0, 68, 0, 30), pos = UDim2.new(1, -74, 0.5, -15),
	onClick = function()
		app.submit()
	end,
})

function app.prefill(text)
	input.Text = text
	input:CaptureFocus()
end

input.Focused:Connect(function()
	inputStroke.Color = C.yellow
end)
input.FocusLost:Connect(function(enter)
	inputStroke.Color = C.ink
	if enter then
		app.submit()
	end
end)

local STATUS_COLORS = {idle = C.faint, busy = C.amber, ok = C.green, warn = C.amber, fail = C.red}
local lastState, lastText = "idle", ""

function view.setStatus(state, text)
	lastState, lastText = state, text
	statusDot.BackgroundColor3 = STATUS_COLORS[state] or C.faint
	statusLabel.Text = text
end

function view.flash(text)
	local s, t = lastState, lastText
	statusLabel.Text = text
	task.delay(1.4, function()
		if statusLabel.Parent and statusLabel.Text == text then
			view.setStatus(s, t)
		end
	end)
end

function view.setBusy(isBusy)
	sendButton.Text = isBusy and "..." or "SEND"
	if isBusy then
		paint(sendButton, C.raised, C.raisedLip, C.sub)
	else
		paint(sendButton, C.yellow, C.yellowLip, C.yellowInk)
	end
end

function view.setScanned(done)
	scanButton.Text = done and "RESCAN" or "SCAN"
	if done then
		paint(scanButton, C.green, C.greenLip, C.ink)
	else
		paint(scanButton, C.raised, C.raisedLip, C.text)
	end
end

function view.setEmpty(show, hasKeys)
	empty.Visible = show
	if show then
		if hasKeys then
			emptyTitle.Text = "Ask about this game"
			emptyBody.Text = "Tell me what to spawn, like a red neon cube or a small house. Press Scan so I can see the game, or type @Workspace.Door to read one object."
		else
			emptyTitle.Text = "Add a key to start"
			emptyBody.Text = "Pick Auto in Setup and paste a key from any provider. Gemini, Groq, Cerebras and others have free tiers."
		end
		emptyButton.Visible = not hasKeys
		for _, c in ipairs(emptyChips) do
			c.Visible = hasKeys
		end
	end
end

function view.copy(text)
	if setclipboard then
		setclipboard(text)
		view.flash("Copied")
	else
		view.flash("Copy isn't supported here")
	end
end

local rowCount = 0
local function newRow()
	rowCount = rowCount + 1
	empty.Visible = false
	return make("Frame", {
		Name = "Row" .. rowCount, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = AUTO_Y, LayoutOrder = rowCount,
	}, list)
end

function view.clearMessages()
	for _, ch in ipairs(list:GetChildren()) do
		if ch:IsA("Frame") then
			ch:Destroy()
		end
	end
	rowCount = 0
	stick = true
end

function view.user(text)
	stick = true
	local row = newRow()
	local b = make("TextLabel", {
		Name = "UserBubble", AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.new(0, 0, 0, 0),
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
		BackgroundColor3 = C.yellow, BorderSizePixel = 0, Font = F.med, TextSize = 13, TextColor3 = C.yellowInk,
		TextWrapped = true, TextXAlignment = AX.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = text,
	}, row)
	corner(b, 5)
	stroke(b, C.ink, 2)
	pad(b, 11, 8, 11, 11)
	local lip = make("Frame", {
		Name = "Lip", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, -11, 1, 11),
		Size = UDim2.new(1, 22, 0, 3), BackgroundColor3 = C.yellowLip, BorderSizePixel = 0,
	}, b)
	corner(lip, 3)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(BUBBLE_MAX, math.huge)
	limit.Parent = b
end

function view.note(text, color)
	local row = newRow()
	local dot = make("Frame", {
		Name = "NoteDot", Size = UDim2.new(0, 6, 0, 6), Position = UDim2.new(0, 2, 0, 5),
		BackgroundColor3 = color or C.orange, BorderSizePixel = 0, Rotation = 45,
	}, row)
	label(row, {
		name = "Note", text = text, ts = 11, color = color or C.faint, wrap = true,
		size = UDim2.new(1, -16, 0, 0), pos = UDim2.new(0, 16, 0, 0), auto = AUTO_Y,
	})
end

function view.thinking(text)
	local row = newRow()
	local blocks = {}
	for i = 1, 3 do
		blocks[i] = make("Frame", {
			Name = "Block" .. i, Size = UDim2.new(0, 9, 0, 9), Position = UDim2.new(0, 2 + (i - 1) * 13, 0, 4),
			BackgroundColor3 = C.faint, BorderSizePixel = 0,
		}, row)
		corner(blocks[i], 2)
		stroke(blocks[i], C.ink, 1)
	end
	local lbl = label(row, {
		name = "Thinking", text = text, ts = 12, color = C.sub, wrap = true,
		size = UDim2.new(1, -48, 0, 0), pos = UDim2.new(0, 46, 0, 0), auto = AUTO_Y,
	})
	local alive = true
	task.spawn(function()
		local n = 0
		while alive do
			n = n % 3 + 1
			for i, b in ipairs(blocks) do
				b.BackgroundColor3 = i == n and C.yellow or C.faint
				b.Position = UDim2.new(0, 2 + (i - 1) * 13, 0, i == n and 2 or 4)
			end
			task.wait(0.22)
		end
	end)
	return {
		set = function(t)
			lbl.Text = t
		end,
		stop = function()
			alive = false
			row:Destroy()
		end,
	}
end

function view.error(info)
	local row = newRow()
	local box = make("Frame", {
		Name = "ErrorBox", BackgroundColor3 = C.redTint, BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y,
	}, row)
	corner(box, 5)
	stroke(box, C.redLip, 2)
	local badge = make("Frame", {
		Name = "ErrorBadge", Size = UDim2.new(0, 22, 0, 22), Position = UDim2.new(0, 10, 0, 10),
		BackgroundColor3 = C.red, BorderSizePixel = 0,
	}, box)
	corner(badge, 4)
	stroke(badge, C.ink, 2)
	label(badge, {name = "BadgeMark", text = "!", font = F.head, ts = 15, color = C.white, align = AX.Center, size = UDim2.new(1, 0, 1, 0)})
	local content = make("Frame", {
		Name = "ErrorContent", BackgroundTransparency = 1, Position = UDim2.new(0, 40, 0, 0),
		Size = UDim2.new(1, -48, 0, 0), AutomaticSize = AUTO_Y,
	}, box)
	pad(content, 0, 10, 0, 10)
	stack(content, 4)
	label(content, {name = "ErrorTitle", text = info.title, font = F.bold, ts = 13, color = C.redText, wrap = true, size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = 1})
	if info.hint and info.hint ~= "" then
		label(content, {name = "ErrorHint", text = info.hint, ts = 12, wrap = true, size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = 2})
	end
	if info.raw and info.raw ~= "" then
		label(content, {name = "ErrorRaw", text = info.raw, ts = 11, color = C.faint, wrap = true, size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = 3})
	end
	if info.fix == "setup" then
		brick(content, {
			name = "ErrorSetup", text = "OPEN SETUP", kind = "yellow", ts = 12, size = UDim2.new(0, 104, 0, 26), order = 4,
			onClick = function()
				view.selectTab("setup")
			end,
		})
	end
end

local function escapeRich(s)
	return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function md(text)
	text = escapeRich((text:gsub("\r", "")))
	local out = {}
	for line in (text .. "\n"):gmatch("(.-)\n") do
		local heading = line:match("^%s*#+%s+(.+)$")
		local bullet = line:match("^%s*[%-%*]%s+(.+)$")
		if heading then
			line = '<font color="#FFC824"><b>' .. heading .. "</b></font>"
		elseif bullet then
			line = "\u{2022}  " .. bullet
		elseif line:match("^%s*%-%-%-+%s*$") then
			line = ""
		end
		out[#out + 1] = line
	end
	text = table.concat(out, "\n")
	text = text:gsub("%*%*(.-)%*%*", "<b>%1</b>")
	text = text:gsub("`([^`\n]+)`", '<font color="#FFD24A">%1</font>')
	return text
end

local function parseReply(reply)
	local segs, pos = {}, 1
	while true do
		local s, e, info, code = reply:find("```([^\r\n]*)\r?\n(.-)```", pos)
		if not s then
			break
		end
		if s > pos then
			segs[#segs + 1] = {t = "text", v = reply:sub(pos, s - 1)}
		end
		segs[#segs + 1] = {t = "code", info = info, v = code}
		pos = e + 1
	end
	if pos <= #reply then
		segs[#segs + 1] = {t = "text", v = reply:sub(pos)}
	end
	return segs
end

local forge = {origin = nil, folder = nil, manual = nil, source = ""}
local batch = {}
do
	local BLOCKED = {Script = true, LocalScript = true, ModuleScript = true}
	local MAX_OPS = 80
	local createdSet = {}

	local function vec(v, n)
		if type(v) == "table" and #v >= n then
			local out = {}
			for i = 1, n do
				out[i] = tonumber(v[i]) or 0
			end
			return out
		end
		return nil
	end

	function forge.getFolder()
		if not forge.folder or not forge.folder.Parent then
			local f = workspace:FindFirstChild("TONYO_Spawns")
			if not f then
				f = Instance.new("Folder")
				f.Name = "TONYO_Spawns"
				f.Parent = workspace
			end
			forge.folder = f
		end
		return forge.folder
	end

	function forge.getOrigin()
		if forge.manual then
			forge.source = "typed"
			return forge.manual
		end
		local char = player.Character
		local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
		if forge.origin and root and (root.Position - forge.origin).Magnitude > 120 then
			forge.origin = nil
		end
		if not forge.origin then
			if root then
				local cf = root.CFrame
				local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
				if look.Magnitude < 0.01 then
					look = Vector3.new(0, 0, -1)
				end
				forge.origin = cf.Position + look.Unit * 14 - Vector3.new(0, 3, 0)
				forge.source = "your character"
			else
				local cam = workspace.CurrentCamera
				local cf = cam and cam.CFrame or CFrame.new(0, 10, 0)
				local pos = cf.Position + cf.LookVector * 30
				local hit = workspace:Raycast(cf.Position, cf.LookVector * 400)
				if hit and math.abs(hit.Position.Y - cf.Position.Y) < 300 then
					pos = hit.Position
				end
				forge.origin = pos
				forge.source = "camera"
			end
		end
		return forge.origin
	end

	function forge.playerNote()
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not root then
			forge.origin = nil
		end
		local o = forge.getOrigin()
		return string.format("\n\n[Spawn point is at %.0f, %.0f, %.0f, right in front of the player. Position new things with small offsets from [0,0,0]. Never invent world coordinates.]", o.X, o.Y, o.Z)
	end

	local function findPath(path)
		if type(path) ~= "string" or path == "" then
			return nil
		end
		local parts = string.split(path, ".")
		local first = parts[1]:lower()
		local cur
		if first == "spawns" then
			cur = forge.getFolder()
		elseif first == "me" or first == "character" then
			cur = player.Character
			if not cur then
				return nil
			end
		end
		if cur then
			for i = 2, #parts do
				cur = cur:FindFirstChild(parts[i])
				if not cur then
					return nil
				end
			end
			return cur
		end
		local ok, inst = pcall(resolvePath, path)
		if ok then
			return inst
		end
		return nil
	end

	forge.find = findPath

	local function convert(cur, value)
		local t = typeof(cur)
		if t == "Vector3" then
			local v = vec(value, 3)
			if v then
				return Vector3.new(v[1], v[2], v[3])
			end
		elseif t == "Vector2" then
			local v = vec(value, 2)
			if v then
				return Vector2.new(v[1], v[2])
			end
		elseif t == "Color3" then
			if type(value) == "string" then
				local ok, c = pcall(Color3.fromHex, value)
				if ok and c then
					return c
				end
				local okb, bc = pcall(function()
					return BrickColor.new(value).Color
				end)
				if okb and bc then
					return bc
				end
			end
			local v = vec(value, 3)
			if v then
				if v[1] <= 1 and v[2] <= 1 and v[3] <= 1 then
					return Color3.new(v[1], v[2], v[3])
				end
				return Color3.fromRGB(v[1], v[2], v[3])
			end
		elseif t == "BrickColor" then
			return BrickColor.new(value)
		elseif t == "CFrame" then
			local v = vec(value, 6)
			if v then
				return CFrame.new(v[1], v[2], v[3]) * CFrame.Angles(math.rad(v[4]), math.rad(v[5]), math.rad(v[6]))
			end
			v = vec(value, 3)
			if v then
				return CFrame.new(v[1], v[2], v[3])
			end
		elseif t == "UDim2" then
			local v = vec(value, 4)
			if v then
				return UDim2.new(v[1], v[2], v[3], v[4])
			end
		elseif t == "UDim" then
			local v = vec(value, 2)
			if v then
				return UDim.new(v[1], v[2])
			end
		elseif t == "EnumItem" then
			for _, item in ipairs(cur.EnumType:GetEnumItems()) do
				if item.Name == value or item.Value == value then
					return item
				end
			end
			error("bad value " .. tostring(value))
		elseif t == "number" then
			return tonumber(value)
		elseif t == "boolean" then
			return value == true or value == "true"
		elseif t == "string" then
			return tostring(value)
		end
		return value
	end

	local function setProps(inst, props, rel)
		local errs = {}
		for name, value in pairs(props) do
			if name ~= "Parent" then
				local ok, err = pcall(function()
					if name == "Position" and inst:IsA("Model") then
						local v = vec(value, 3)
						local p = Vector3.new(v[1], v[2], v[3])
						if rel then
							p = p + forge.getOrigin()
						end
						inst:PivotTo(CFrame.new(p))
						return
					end
					local newVal = convert(inst[name], value)
					if rel and (name == "Position" or name == "CFrame") then
						local o = forge.getOrigin()
						if typeof(newVal) == "Vector3" then
							newVal = newVal + o
						elseif typeof(newVal) == "CFrame" then
							newVal = newVal + o
						end
					end
					inst[name] = newVal
				end)
				if not ok then
					errs[#errs + 1] = name .. ": " .. oneLine(err, 60)
				end
			end
		end
		return errs
	end

	local function isSpawned(inst)
		return createdSet[inst] == true or (forge.folder ~= nil and inst:IsDescendantOf(forge.folder))
	end

	local function protected(inst)
		return inst == game or inst == workspace or inst.Parent == game or inst == player or inst == player.Character
			or inst == workspace.CurrentCamera or inst == workspace.Terrain or inst:IsDescendantOf(Players)
			or inst == gui or inst:IsDescendantOf(gui)
	end

	local function placeDefault(inst)
		local o = forge.getOrigin()
		if inst:IsA("BasePart") then
			inst.Position = o + Vector3.new(0, inst.Size.Y / 2, 0)
		elseif inst:IsA("Model") then
			local _, size = inst:GetBoundingBox()
			inst:PivotTo(CFrame.new(o + Vector3.new(0, size.Y / 2, 0)))
		end
	end

	local function attach(inst, parentPath)
		local parent
		if parentPath ~= nil then
			parent = findPath(parentPath)
			if not parent then
				error("parent not found: " .. tostring(parentPath))
			end
		else
			parent = forge.getFolder()
		end
		inst.Parent = parent
		createdSet[inst] = true
		batch[#batch + 1] = inst
	end

	local function popIn(inst)
		if inst:IsA("BasePart") and inst.Anchored and not (inst.Parent and inst.Parent:IsA("Model")) then
			local target = inst.Size
			inst.Size = target * 0.05
			TweenService:Create(inst, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = target}):Play()
			task.delay(0.6, function()
				if inst.Parent then
					inst.Size = target
				end
			end)
		end
	end

	function forge.flash(list)
		local n = 0
		for _, inst in ipairs(list) do
			if n >= 10 then
				break
			end
			if inst.Parent and (inst:IsA("BasePart") or inst:IsA("Model")) then
				n = n + 1
				pcall(function()
					local h = Instance.new("Highlight")
					h.Name = "TONYO_Flash"
					h.Adornee = inst
					h.FillColor = C.yellow
					h.OutlineColor = C.white
					h.FillTransparency = 0.45
					h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
					h.Parent = inst
					task.delay(3, function()
						h:Destroy()
					end)
				end)
			end
		end
	end

	function forge.goTo()
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local o = forge.origin or forge.manual
		if root and o then
			root.CFrame = CFrame.new(o + Vector3.new(0, 5, 18), o)
			return true
		end
		local cam = workspace.CurrentCamera
		if cam and o then
			cam.CFrame = CFrame.lookAt(o + Vector3.new(0, 10, 24), o + Vector3.new(0, 2, 0))
			return true
		end
		return false
	end

	local function applyOne(op)
		if type(op) ~= "table" then
			error("not an operation")
		end
		local kind = tostring(op.op or ""):lower()
		local props = type(op.props) == "table" and op.props or {}
		local rel = op.abs ~= true
		if kind == "create" then
			local class = tostring(op.class or op.className or "Part")
			if BLOCKED[class] then
				error(class .. " can't be made with ops, use a code block")
			end
			local inst = Instance.new(class)
			if type(op.name) == "string" and op.name ~= "" then
				inst.Name = op.name
			end
			if inst:IsA("BasePart") and props.Anchored == nil and settings.autoAnchor ~= false then
				inst.Anchored = true
			end
			local errs = setProps(inst, props, rel)
			if props.Anchored == false then
				inst:SetAttribute("TonyoKeepAnchor", true)
			end
			if props.CanCollide == false then
				inst:SetAttribute("TonyoKeepGhost", true)
			end
			if props.Position == nil and props.CFrame == nil then
				pcall(placeDefault, inst)
			end
			attach(inst, op.parent)
			pcall(popIn, inst)
			return "+ " .. class .. " " .. inst.Name, errs
		elseif kind == "clone" or kind == "spawn" then
			local src = findPath(op.path or op.from)
			if not src then
				error("not found: " .. tostring(op.path or op.from))
			end
			local flipped = {}
			pcall(function()
				for _, d in ipairs(src:GetDescendants()) do
					if not d.Archivable then
						d.Archivable = true
						flipped[#flipped + 1] = d
					end
				end
				if not src.Archivable then
					src.Archivable = true
					flipped[#flipped + 1] = src
				end
			end)
			local okc, copy = pcall(function()
				return src:Clone()
			end)
			for _, d in ipairs(flipped) do
				pcall(function()
					d.Archivable = false
				end)
			end
			if not okc or not copy then
				error("can't clone " .. src.Name)
			end
			if type(op.name) == "string" and op.name ~= "" then
				copy.Name = op.name
			end
			local errs = setProps(copy, props, rel)
			if props.Position == nil and props.CFrame == nil then
				pcall(placeDefault, copy)
			end
			attach(copy, op.parent)
			return "+ " .. copy.ClassName .. " " .. copy.Name, errs
		elseif kind == "insert" then
			local id = tonumber(op.assetId or op.id)
			if not id then
				error("insert needs an assetId")
			end
			local objs
			pcall(function()
				objs = game:GetObjects("rbxassetid://" .. id)
			end)
			if not objs or #objs == 0 then
				pcall(function()
					local m = game:GetService("InsertService"):LoadAsset(id)
					objs = m:GetChildren()
					for _, c in ipairs(objs) do
						c.Parent = nil
					end
					m:Destroy()
				end)
			end
			if not objs or #objs == 0 then
				error("couldn't load asset " .. id .. ", your executor may not support loading assets")
			end
			local inst = objs[1]
			if #objs > 1 then
				inst = Instance.new("Model")
				inst.Name = "Asset" .. id
				for _, o in ipairs(objs) do
					o.Parent = inst
				end
			end
			local stripped = 0
			for _, d in ipairs(inst:GetDescendants()) do
				if d:IsA("LuaSourceContainer") then
					d:Destroy()
					stripped = stripped + 1
				end
			end
			if type(op.name) == "string" and op.name ~= "" then
				inst.Name = op.name
			end
			local errs = setProps(inst, props, rel)
			if props.Anchored == false then
				inst:SetAttribute("TonyoKeepAnchor", true)
			end
			if props.CanCollide == false then
				inst:SetAttribute("TonyoKeepGhost", true)
			end
			if props.Position == nil and props.CFrame == nil then
				pcall(placeDefault, inst)
			end
			attach(inst, op.parent)
			if stripped > 0 then
				errs[#errs + 1] = stripped .. " scripts inside were removed"
			end
			return "+ " .. inst.ClassName .. " " .. inst.Name .. " (asset " .. id .. ")", errs
		elseif kind == "rig" then
			local model = findPath(op.path)
			if not model or not model:IsA("Model") then
				error("rig needs the path of a Model")
			end
			local root = model:FindFirstChild(tostring(op.root or ""), true)
			if not root or not root:IsA("BasePart") then
				root = nil
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") then
						root = d
						break
					end
				end
			end
			if not root then
				error("the model has no parts to rig")
			end
			model.PrimaryPart = root
			local n = 0
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and d ~= root then
					local m = Instance.new("Motor6D")
					m.Name = d.Name
					m.Part0 = root
					m.Part1 = d
					m.C0 = root.CFrame:ToObjectSpace(d.CFrame)
					m.C1 = CFrame.new()
					d.Anchored = false
					d.Massless = true
					d.CanCollide = false
					m.Parent = root
					n = n + 1
				end
			end
			root.Anchored = true
			return "~ rigged " .. model.Name .. ", " .. n .. " joints on " .. root.Name
		elseif kind == "animate" then
			local inst = findPath(op.path)
			if not inst then
				error("not found: " .. tostring(op.path))
			end
			local kindName = tostring(op.type or op.anim or "spin"):lower()
			TX.pending = TX.pending or {}
			table.insert(TX.pending, {inst = inst, kind = kindName, op = op})
			return "~ animate " .. inst.Name .. " (" .. kindName .. ")"
		elseif kind == "set" or kind == "edit" then
			local inst = findPath(op.path)
			if not inst then
				error("not found: " .. tostring(op.path))
			end
			local errs = setProps(inst, props, rel and isSpawned(inst))
			return "~ " .. inst.Name, errs
		elseif kind == "delete" or kind == "destroy" then
			local inst = findPath(op.path)
			if not inst then
				error("not found: " .. tostring(op.path))
			end
			if protected(inst) then
				error("protected: " .. inst.Name)
			end
			local nm = inst.Name
			inst:Destroy()
			return "- " .. nm
		end
		error("unknown op: " .. kind)
	end

	function forge.apply(ops)
		batch = {}
		TX.pending = nil
		local lines, made, failed = {}, 0, 0
		for i, op in ipairs(ops) do
			if i > MAX_OPS then
				lines[#lines + 1] = {text = "Stopped at " .. MAX_OPS .. " ops.", bad = true}
				break
			end
			local ok, res, errs = pcall(applyOne, op)
			if ok then
				made = made + 1
				lines[#lines + 1] = {text = res}
				for _, e in ipairs(errs or {}) do
					lines[#lines + 1] = {text = "   " .. e, bad = true}
				end
			else
				failed = failed + 1
				lines[#lines + 1] = {text = "x " .. oneLine(res, 90), bad = true}
			end
		end
		if forge.origin or forge.manual then
			local o = forge.getOrigin()
			local top = {}
			for _, inst in ipairs(batch) do
				if not createdSet[inst.Parent] and (inst:IsA("Model") or inst:IsA("BasePart")) then
					top[#top + 1] = inst
				end
			end
			if #top > 0 then
				local okc, c0, size = pcall(function()
					if top[1]:IsA("Model") then
						return top[1]:GetBoundingBox()
					end
					return top[1].CFrame, top[1].Size
				end)
				if okc and c0 and (c0.Position - o).Magnitude > 250 then
					local delta = (o + Vector3.new(0, size.Y / 2, 0)) - c0.Position
					for _, inst in ipairs(top) do
						pcall(function()
							inst:PivotTo(inst:GetPivot() + delta)
						end)
					end
					lines[#lines + 1] = {text = "The AI picked coordinates far away, so everything was moved next to you.", info = true}
				end
			end
		end
		if TX.fixBatch then
			local okf, fa, fc = pcall(TX.fixBatch, batch)
			if okf and ((fa or 0) > 0 or (fc or 0) > 0) then
				lines[#lines + 1] = {text = string.format("auto: anchored %d, made solid %d", fa, fc), info = true}
			end
		end
		pcall(TX.watch, forge.getFolder(), conns)
		local snapshot = batch
		for _, wait in ipairs({0.4, 1.5, 4}) do
			task.delay(wait, function()
				pcall(TX.fixBatch, snapshot)
			end)
		end
		if TX.pending then
			local pend = TX.pending
			TX.pending = nil
			task.delay(0.7, function()
				for _, a in ipairs(pend) do
					local oka, res = pcall(TX.anim.start, a.inst, a.kind, a.op)
					if not oka then
						pcall(view.log, "animate " .. a.inst.Name .. ": " .. oneLine(tostring(res), 70), "bad")
					end
				end
			end)
		end
		task.defer(forge.flash, batch)
		local shown = 0
		for _, inst in ipairs(batch) do
			if shown < 4 and not createdSet[inst.Parent] then
				local ok, cf, size = pcall(function()
					if inst:IsA("Model") then
						return inst:GetBoundingBox()
					end
					if inst:IsA("BasePart") then
						return inst.CFrame, inst.Size
					end
				end)
				if ok and cf and size then
					shown = shown + 1
					lines[#lines + 1] = {
						text = string.format("@ %s at %.0f, %.0f, %.0f  size %.0f x %.0f x %.0f", inst.Name, cf.X, cf.Y, cf.Z, size.X, size.Y, size.Z),
						info = true,
					}
				end
			end
		end
		local ch = player.Character
		if #batch > 0 and not (ch and ch:FindFirstChild("HumanoidRootPart")) then
			pcall(forge.goTo)
		end
		local parts = 0
		for _, inst in ipairs(batch) do
			if inst:IsA("BasePart") then
				parts = parts + 1
			end
			for _, d in ipairs(inst:GetDescendants()) do
				if d:IsA("BasePart") then
					parts = parts + 1
				end
			end
		end
		return lines, made, failed, batch, parts
	end

	function forge.placeScript(class, name, code, sub)
		local folder = workspace:FindFirstChild("TONYO_Scripts")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "TONYO_Scripts"
			folder.Parent = workspace
		end
		if sub then
			local inner = folder:FindFirstChild(sub)
			if not inner then
				inner = Instance.new("Folder")
				inner.Name = sub
				inner.Parent = folder
			end
			folder = inner
		end
		local old = folder:FindFirstChild(name)
		if old then
			old:Destroy()
		end
		local sc = Instance.new(class)
		sc.Name = name
		if class ~= "ModuleScript" then
			pcall(function()
				sc.Disabled = true
			end)
		end
		local wrote = pcall(function()
			sc.Source = code
		end)
		if not wrote and sethiddenproperty then
			wrote = pcall(sethiddenproperty, sc, "Source", code)
		end
		if wrote then
			local okr, got = pcall(function()
				return sc.Source
			end)
			wrote = okr and got == code
		end
		if not wrote then
			local sv = Instance.new("StringValue")
			sv.Name = "SourceText"
			sv.Value = code
			sv.Parent = sc
		end
		sc.Parent = folder
		return wrote, sc
	end

	function forge.undo(list)
		for _, inst in ipairs(list) do
			createdSet[inst] = nil
			pcall(function()
				inst:Destroy()
			end)
		end
	end
end

local function opsCard(parent, code, order)
	local data = decode(code)
	local ops = data
	if type(data) == "table" and type(data.ops) == "table" then
		ops = data.ops
	end
	if type(ops) == "table" and ops.op ~= nil then
		ops = {ops}
	end

	local card = make("Frame", {
		Name = "OpsCard", BackgroundColor3 = C.code, BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, LayoutOrder = order,
	}, parent)
	corner(card, 5)
	stroke(card, C.ink, 2)
	stack(card, 0)

	local top = make("Frame", {Name = "OpsHead", BackgroundColor3 = C.codeHead, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 1}, card)
	corner(top, 5)
	make("Frame", {
		Name = "OpsHeadSquare", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = C.codeHead, BorderSizePixel = 0,
	}, top)
	local badge = make("Frame", {
		Name = "OpsBadge", Size = UDim2.new(0, 56, 0, 16), Position = UDim2.new(0, 10, 0, 8),
		BackgroundColor3 = C.yellow, BorderSizePixel = 0, Rotation = -3,
	}, top)
	corner(badge, 3)
	stroke(badge, C.ink, 1)
	label(badge, {name = "OpsBadgeText", text = "SPAWN", font = F.head, ts = 10, color = C.yellowInk, align = AX.Center, size = UDim2.new(1, 0, 1, 0)})
	local countLabel = label(top, {name = "OpsCount", font = F.med, ts = 11, color = C.sub, size = UDim2.new(1, -270, 1, 0), pos = UDim2.new(0, 76, 0, 0)})

	make("Frame", {Name = "OpsDivider", Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = C.ink, BorderSizePixel = 0, LayoutOrder = 2}, card)
	local resultLabel = label(card, {
		name = "OpsResult", rich = true, wrap = true, ts = 11, font = F.code, size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = 3,
	})
	pad(resultLabel, 10, 8, 10, 8)

	local current = {}
	local function render(lines, made, failed, parts, created)
		local out = {}
		for _, l in ipairs(lines) do
			local color = l.bad and "#FF9488" or (l.info and "#B9B6AC" or "#7FE29A")
			out[#out + 1] = '<font color="' .. color .. '">' .. escapeRich(l.text) .. "</font>"
		end
		if forge.origin or forge.manual then
			table.insert(out, 1, string.format('<font color="#B9B6AC">Spawn point %.1f, %.1f, %.1f (%s)</font>', forge.getOrigin().X, forge.getOrigin().Y, forge.getOrigin().Z, forge.source))
		end
		if created and created > 0 and parts == 0 then
			out[#out + 1] = '<font color="#F0B034">Nothing visible was made. A Model or Folder with no parts inside is invisible, so ask for parts or an asset id.</font>'
		elseif parts then
			out[#out + 1] = '<font color="#B9B6AC">' .. parts .. " visible parts spawned</font>"
		end
		resultLabel.Text = table.concat(out, "\n")
		countLabel.Text = made .. " done" .. (failed > 0 and (", " .. failed .. " failed") or "")
	end

	local function run()
		if type(ops) ~= "table" or #ops == 0 then
			countLabel.Text = "nothing to apply"
			resultLabel.Text = '<font color="#FF9488">Could not read the spawn list. Ask again.</font>'
			return
		end
		local ok, lines, made, failed, list, parts = pcall(forge.apply, ops)
		if not ok then
			countLabel.Text = "failed"
			resultLabel.Text = '<font color="#FF9488">' .. escapeRich(oneLine(lines, 140)) .. "</font>"
			return
		end
		current = list
		render(lines, made, failed, parts, #list)
		view.log(string.format("Spawn: %d done, %d failed, %d parts", made, failed, parts or 0), failed > 0 and "warn" or "ok")
	end

	brick(top, {
		name = "OpsUndo", text = "UNDO", kind = "red", ts = 11, size = UDim2.new(0, 56, 0, 22), pos = UDim2.new(1, -62, 0, 5),
		radius = 4, lipH = 2,
		onClick = function()
			forge.undo(current)
			current = {}
			countLabel.Text = "removed"
			resultLabel.Text = '<font color="#B9B6AC">Everything this block spawned was removed.</font>'
		end,
	})
	brick(top, {
		name = "OpsGo", text = "GO", kind = "blue", ts = 11, size = UDim2.new(0, 44, 0, 22), pos = UDim2.new(1, -176, 0, 5),
		radius = 4, lipH = 2,
		onClick = function()
			countLabel.Text = forge.goTo() and "moved you next to it" or "can't find your character"
		end,
	})
	brick(top, {
		name = "OpsAgain", text = "AGAIN", kind = "green", ts = 11, size = UDim2.new(0, 60, 0, 22), pos = UDim2.new(1, -128, 0, 5),
		radius = 4, lipH = 2,
		onClick = run,
	})
	task.defer(run)
	return card
end

local viewer = make("Frame", {
	Name = "CodeViewer", Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = C.window, BorderSizePixel = 0,
	Visible = false, ZIndex = 40, Active = true,
}, body)
local viewerTitle, viewerBox
do
	brick(viewer, {
		name = "ViewerBack", text = "BACK", kind = "gray", ts = 12, size = UDim2.new(0, 60, 0, 26), pos = UDim2.new(0, 8, 0, 5),
		onClick = function()
			viewer.Visible = false
		end,
	})
	viewerTitle = label(viewer, {name = "ViewerTitle", font = F.head, ts = 14, align = AX.Center, color = C.yellow, size = UDim2.new(1, -150, 0, 36), pos = UDim2.new(0, 75, 0, 0)})
	brick(viewer, {
		name = "ViewerCopy", text = "COPY", kind = "yellow", ts = 12, size = UDim2.new(0, 56, 0, 26), pos = UDim2.new(1, -64, 0, 5),
		onClick = function()
			view.copy(viewerBox.Text)
		end,
	})
	make("Frame", {Name = "ViewerEdge", Position = UDim2.new(0, 0, 0, 38), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = C.ink, BorderSizePixel = 0}, viewer)
	local sc = make("ScrollingFrame", {
		Name = "ViewerScroll", Position = UDim2.new(0, 8, 0, 46), Size = UDim2.new(1, -16, 1, -54), BackgroundColor3 = C.code,
		BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = C.scroll, CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = AUTO_Y,
	}, viewer)
	corner(sc, 5)
	stroke(sc, C.ink, 2)
	viewerBox = make("TextBox", {
		Name = "ViewerText", BackgroundTransparency = 1, MultiLine = true, TextEditable = true, ClearTextOnFocus = false,
		TextWrapped = true, Font = F.code, TextSize = 12, TextColor3 = C.codeText, TextXAlignment = AX.Left,
		TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, Text = "",
	}, sc)
	pad(viewerBox, 8, 8, 8, 8)
end

function view.showCode(name, code)
	viewerTitle.Text = name
	viewerBox.Text = code
	viewer.Visible = true
end

local function codeCard(parent, info, code, idx, order)
	local lang = (info:match("^%s*([%w_]+)") or ""):lower()
	local isServer = info:lower():find("server", 1, true) ~= nil
	local name = info:match(":%s*([%w_%-]+)%s*$") or ("Script" .. idx)
	local DELIVER = {script = "Script", localscript = "LocalScript", modulescript = "ModuleScript"}
	local deliver = DELIVER[lang]
	local runnable = lang == "" or lang == "lua" or lang == "luau" or lang == "local" or lang == "server"
	code = code:gsub("\n+$", "")
	local lines = select(2, code:gsub("\n", "")) + 1

	local card = make("Frame", {
		Name = "CodeCard", BackgroundColor3 = C.code, BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, LayoutOrder = order,
	}, parent)
	corner(card, 5)
	stroke(card, C.ink, 2)
	stack(card, 0)

	local top = make("Frame", {Name = "CodeHead", BackgroundColor3 = C.codeHead, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 1}, card)
	corner(top, 5)
	make("Frame", {
		Name = "CodeHeadSquare", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = C.codeHead, BorderSizePixel = 0,
	}, top)

	local titleRow = make("Frame", {
		Name = "CodeTitle", BackgroundTransparency = 1, Size = UDim2.new(0, 0, 1, 0),
		Position = UDim2.new(0, 10, 0, 0), AutomaticSize = Enum.AutomaticSize.X,
	}, top)
	stack(titleRow, 7, true)
	local kindText = runnable and (isServer and "SERVER" or "CLIENT") or lang:upper()
	local badge = make("Frame", {
		Name = "CodeKind", Size = UDim2.new(0, 0, 0, 16), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = isServer and C.blue or (runnable and C.green or C.raised), BorderSizePixel = 0, LayoutOrder = 1,
	}, titleRow)
	corner(badge, 3)
	stroke(badge, C.ink, 1)
	pad(badge, 6, 0, 6, 0)
	label(badge, {
		name = "CodeKindText", text = kindText, font = F.head, ts = 10,
		color = isServer and C.white or C.ink, size = UDim2.new(0, 0, 1, 0), auto = Enum.AutomaticSize.X,
	})
	local nameLabel = label(titleRow, {
		name = "CodeName", text = name, font = F.med, ts = 12, size = UDim2.new(0, 0, 1, 0),
		auto = Enum.AutomaticSize.X, order = 2,
	})
	local nameLimit = Instance.new("UISizeConstraint")
	nameLimit.MaxSize = Vector2.new(math.max(50, PANEL_W - 250), math.huge)
	nameLimit.Parent = nameLabel

	local result
	local runButton
	local runAction
	local autoKind = nil
	do
		local low = info:lower()
		if low:find("server", 1, true) then
			autoKind = "server"
		elseif low:find("local", 1, true) and not deliver then
			autoKind = "local"
		elseif not deliver and (lang == "" or lang == "lua" or lang == "luau") and lines >= 4 then
			local serverHints = {"ServerScriptService", "ServerStorage", "OnServerEvent", "OnServerInvoke", "DataStoreService", "PlayerAdded", "FireClient", "FireAllClients"}
			autoKind = "local"
			for _, h in ipairs(serverHints) do
				if code:find(h, 1, true) then
					autoKind = "server"
					break
				end
			end
		end
	end
	if deliver then
		local function place()
			local wrote, sc = forge.placeScript(deliver, name, code)
			if setclipboard then
				setclipboard(code)
			end
			view.log("Placed " .. deliver .. " " .. name .. (wrote and "" or ", source blocked"), wrote and "ok" or "warn")
			local saved = false
			pcall(function()
				if writefile then
					if makefolder and isfolder and not isfolder("TONYO_Scripts") then
						makefolder("TONYO_Scripts")
					end
					writefile("TONYO_Scripts/" .. name .. ".lua", code)
					saved = true
				end
			end)
			result.Visible = true
			if wrote then
				result.Text = "Placed " .. deliver .. " " .. name .. " in Workspace.TONYO_Scripts. Move it to where it belongs, then enable it. The code is also copied." .. (saved and (" Saved as workspace/TONYO_Scripts/" .. name .. ".lua.") or "")
				result.TextColor3 = C.green
			else
				result.Text = "Placed " .. deliver .. " " .. name .. " in Workspace.TONYO_Scripts, but Roblox blocked writing code into it. The code is in its SourceText child and copied to your clipboard. Roblox makes scripts created while the game runs read only, so tap OPEN CODE TO COPY OR SELECT and paste it into your own script." .. (saved and (" Also saved as workspace/TONYO_Scripts/" .. name .. ".lua.") or "")
				result.TextColor3 = C.amber
			end
		end
		runButton = brick(top, {
			name = "CodePlace", text = "PLACE", kind = "yellow", ts = 11,
			size = UDim2.new(0, 56, 0, 22), pos = UDim2.new(1, -62, 0, 5), radius = 4, lipH = 2,
			onClick = place,
		})
		if deliver ~= "ModuleScript" then
			local playButton
			playButton = brick(top, {
				name = "CodePlay", text = "PLAY", kind = "green", ts = 11,
				size = UDim2.new(0, 52, 0, 22), pos = UDim2.new(1, -176, 0, 5), radius = 4, lipH = 2,
				onClick = function()
					playButton.Text = "..."
					task.spawn(function()
						local ok, out = runCode(code)
						playButton.Text = "PLAY"
						result.Visible = true
						if ok then
							result.Text = "Playing on your client." .. (out ~= "" and ("\n" .. clip(out, 400)) or "")
							result.TextColor3 = C.green
						else
							result.Text = "Error: " .. clip(out, 500)
							result.TextColor3 = C.redText
						end
					end)
				end,
			})
		end
		task.defer(place)
	end
	if runnable then
		runButton = brick(top, {
			name = "CodeRun", text = isServer and "SAVE" or "RUN", kind = isServer and "blue" or "green", ts = 11,
			size = UDim2.new(0, 56, 0, 22), pos = UDim2.new(1, -62, 0, 5), radius = 4, lipH = 2,
			onClick = function()
				runAction()
			end,
		})
		runAction = function(auto)
				if isServer then
					local saved = false
					pcall(function()
						if writefile then
							if makefolder and isfolder and not isfolder("TONYO_Scripts") then
								makefolder("TONYO_Scripts")
							end
							writefile("TONYO_Scripts/" .. name .. ".server.lua", code)
							saved = true
						end
					end)
					if setclipboard and not auto then
						setclipboard(code)
					end
					result.Text = (saved and ("Saved to workspace/TONYO_Scripts/" .. name .. ".server.lua. ") or "Couldn't save a file. ")
						.. (setclipboard and not auto and "Code copied. " or "")
						.. "A client executor can't run server scripts. Paste this into a Script in ServerScriptService in Studio."
					result.TextColor3 = C.sub
					result.Visible = true
					return
				end
				runButton.Text = "RUNNING"
				task.spawn(function()
					local ok, out = runCode(code)
					runButton.Text = "AGAIN"
					if ok then
						result.Text = "Ran without errors." .. (out ~= "" and ("\n" .. clip(out, 500)) or "")
						result.TextColor3 = C.green
					else
						result.Text = "Error: " .. clip(out, 500)
						result.TextColor3 = C.redText
					end
					result.Visible = true
				end)
		end
		task.defer(function()
			if settings.autoPlace == false or not autoKind then
				return
			end
			local cls = autoKind == "server" and "Script" or "LocalScript"
			local subName = autoKind == "server" and "ServerScriptService" or "StarterPlayerScripts"
			local okp, wrote = pcall(forge.placeScript, cls, name, code, subName)
			local where = "Workspace.TONYO_Scripts." .. subName
			if not okp then
				view.log("Auto place failed for " .. name, "bad")
				return
			end
			view.log("Auto-placed " .. cls .. " " .. name .. " in " .. where, "ok")
			if autoKind == "server" then
				runAction(true)
				result.Text = "Auto-placed Script " .. name .. " in " .. where .. ". " .. result.Text
				result.Visible = true
			else
				result.Visible = true
				result.TextColor3 = C.green
				result.Text = "Auto-placed LocalScript " .. name .. " in " .. where .. (settings.autoRun == true and ". Running it now." or ". Tap RUN to start it, or turn on AUTO RUN in the BUILD tab.")
				if settings.autoRun == true then
					runAction(true)
				end
			end
		end)
	end
	brick(top, {
		name = "CodeCopy", text = "COPY", kind = "gray", fg = C.sub, ts = 11,
		size = UDim2.new(0, 50, 0, 22), pos = UDim2.new(1, (runnable or deliver) and -118 or -58, 0, 5), radius = 4, lipH = 2,
		onClick = function()
			view.copy(code)
		end,
	})

	make("Frame", {Name = "CodeDivider", Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = C.ink, BorderSizePixel = 0, LayoutOrder = 2}, card)

	local collapsed = lines > CODE_MAX_LINES
	local bodyFrame = make("Frame", {
		Name = "CodeBody", BackgroundTransparency = 1, ClipsDescendants = true, LayoutOrder = 3,
		Size = collapsed and UDim2.new(1, 0, 0, CODE_MAX_LINES * CODE_LINE_H + 16) or UDim2.new(1, 0, 0, 0),
		AutomaticSize = collapsed and Enum.AutomaticSize.None or AUTO_Y,
	}, card)
	local codeLabel = make("TextLabel", {
		Name = "CodeText", BackgroundTransparency = 1, Font = F.code, TextSize = 12, TextColor3 = C.codeText,
		TextXAlignment = AX.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, Text = code,
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y,
	}, bodyFrame)
	pad(codeLabel, 10, 8, 10, 8)

	if collapsed then
		local more
		more = brick(card, {
			name = "CodeMore", text = "SHOW ALL " .. lines .. " LINES", ghost = true, fg = C.yellow, ts = 11, radius = 0,
			size = UDim2.new(1, 0, 0, 26), order = 4,
			onClick = function()
				collapsed = not collapsed
				if collapsed then
					bodyFrame.AutomaticSize = Enum.AutomaticSize.None
					bodyFrame.Size = UDim2.new(1, 0, 0, CODE_MAX_LINES * CODE_LINE_H + 16)
					more.Text = "SHOW ALL " .. lines .. " LINES"
				else
					bodyFrame.Size = UDim2.new(1, 0, 0, 0)
					bodyFrame.AutomaticSize = AUTO_Y
					more.Text = "SHOW LESS"
				end
			end,
		})
	end

	brick(card, {
		name = "CodeOpen", text = "OPEN CODE TO COPY OR SELECT", ghost = true, fg = C.sub, ts = 10, radius = 0,
		size = UDim2.new(1, 0, 0, 24), order = 6,
		onClick = function()
			view.showCode(name, code)
		end,
	})

	result = label(card, {
		name = "CodeResult", text = "", ts = 11, color = C.sub, wrap = true, size = UDim2.new(1, 0, 0, 0),
		auto = AUTO_Y, order = 7,
	})
	result.Visible = false
	pad(result, 10, 6, 10, 8)
	return card
end

function view.reply(reply, p, model, secs)
	local row = newRow()
	local bar = make("Frame", {Name = "ReplyBar", Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = C.blue, BorderSizePixel = 0}, row)
	corner(bar, 2)
	local content = make("Frame", {
		Name = "ReplyBody", BackgroundTransparency = 1, Position = UDim2.new(0, 14, 0, 0),
		Size = UDim2.new(1, -14, 0, 0), AutomaticSize = AUTO_Y,
	}, row)
	stack(content, 7)
	local order, codeIdx = 0, 0
	for _, seg in ipairs(parseReply(reply)) do
		order = order + 1
		if seg.t == "text" then
			local t = seg.v:gsub("^%s+", ""):gsub("%s+$", "")
			if t ~= "" then
				local l = label(content, {
					name = "ReplyText", text = md(t), rich = true, wrap = true, ts = 13,
					size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = order,
				})
				l.LineHeight = 1.1
			end
		else
			codeIdx = codeIdx + 1
			local ilow = seg.info:lower()
			if ilow:match("^%s*ops") or (ilow:match("^%s*json") and seg.v:find('"op"', 1, true)) then
				opsCard(content, seg.v, order)
			else
				codeCard(content, seg.info, seg.v, codeIdx, order)
			end
		end
	end
	order = order + 1
	local meta = make("Frame", {Name = "ReplyMeta", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = order}, content)
	label(meta, {
		name = "ReplyInfo", text = string.format("%s  /  %s  /  %.1fs", model or "model", p.name, secs or 0),
		font = F.med, ts = 10, color = C.faint, size = UDim2.new(1, -56, 1, 0),
	})
	brick(meta, {
		name = "ReplyCopy", text = "COPY", ghost = true, fg = C.sub, ts = 10, radius = 3,
		size = UDim2.new(0, 46, 0, 18), pos = UDim2.new(1, -46, 0, 0),
		onClick = function()
			view.copy(reply)
		end,
	})
end

local setup = make("ScrollingFrame", {
	Name = "SetupPage",
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = C.scroll,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = AUTO_Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Visible = false,
}, body)
local providerRow, providerValue, modelRow, modelValue, engineNote, quickMsg, onlineNote, onlineValue
local keyRows = {}

do
	pad(setup, 10, 4, 12, 14)
	stack(setup, 7)

	local setupOrder = 0
	local function nextOrder()
		setupOrder = setupOrder + 1
		return setupOrder
	end

	local function heading(text)
		local h = make("Frame", {Name = "Heading", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = nextOrder()}, setup)
		label(h, {name = "HeadingText", text = text:upper(), font = F.head, ts = 14, color = C.yellow, size = UDim2.new(1, 0, 0, 24), pos = UDim2.new(0, 2, 0, 2)})
		make("Frame", {Name = "HeadingLine", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = C.ink, BorderSizePixel = 0}, h)
		return h
	end

	local function paragraph(text)
		return label(setup, {
			name = "Paragraph", text = text, ts = 11, color = C.faint, wrap = true,
			size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = nextOrder(),
		})
	end

	local function group()
		local g = make("Frame", {
			Name = "Group", BackgroundColor3 = C.raised, BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, LayoutOrder = nextOrder(),
		}, setup)
		corner(g, 6)
		stroke(g, C.ink, 2)
		stack(g, 0)
		return g
	end

	local function divider(parent, order)
		make("Frame", {
			Name = "Divider", Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = C.ink,
			BackgroundTransparency = 0.45, BorderSizePixel = 0, LayoutOrder = order,
		}, parent)
	end

	local function pressFade(b)
		b.InputBegan:Connect(function(input)
			if isPress(input) then
				b.BackgroundTransparency = 0.5
			end
		end)
		b.InputEnded:Connect(function(input)
			if isPress(input) then
				b.BackgroundTransparency = 1
			end
		end)
	end

	local function selectRow(parent, name, labelText, order)
		local b = make("TextButton", {
			Name = name, Text = "", AutoButtonColor = false, BackgroundColor3 = C.raisedHi,
			BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 42), LayoutOrder = order,
		}, parent)
		pressFade(b)
		label(b, {name = "RowLabel", text = labelText:upper(), font = F.head, ts = 12, color = C.sub, size = UDim2.new(0, 64, 1, 0), pos = UDim2.new(0, 12, 0, 0)})
		local value = label(b, {
			name = "Value", font = F.bold, ts = 12, align = AX.Right,
			size = UDim2.new(1, -104, 1, 0), pos = UDim2.new(0, 80, 0, 0),
		})
		label(b, {name = "Chevron", text = ">", font = F.head, ts = 14, color = C.yellow, align = AX.Right, size = UDim2.new(0, 14, 1, 0), pos = UDim2.new(1, -24, 0, 0)})
		return b, value
	end

	heading("Add a key")
	do
		local line = make("Frame", {Name = "QuickLine", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = nextOrder()}, setup)
		local box = textBox(line, {name = "QuickKeyBox", placeholder = "Paste any API key", size = UDim2.new(1, -70, 1, 0)})
		local function submit()
			local t = box.Text
			box.Text = ""
			app.addAnyKey(t)
		end
		box.FocusLost:Connect(function()
			if box.Text ~= "" then
				submit()
			end
		end)
		brick(line, {
			name = "QuickAdd", text = "ADD", kind = "yellow", ts = 13,
			size = UDim2.new(0, 62, 1, 0), pos = UDim2.new(1, -62, 0, 0), onClick = submit,
		})
		quickMsg = label(setup, {
			name = "QuickMessage", text = "", ts = 11, color = C.sub, wrap = true,
			size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = nextOrder(),
		})
		quickMsg.Visible = false
		paragraph("Tonyo recognises most providers by how the key starts. Details for each provider are under API keys.")
	end

	heading("Engine")
	local engineGroup = group()
	providerRow, providerValue = selectRow(engineGroup, "ProviderRow", "Provider", 1)
	divider(engineGroup, 2)
	modelRow, modelValue = selectRow(engineGroup, "ModelRow", "Model", 3)
	engineNote = paragraph("")

	heading("API keys")
	paragraph("Add a key for any provider you like. Auto uses every provider that has one.")
	local keysGroup = group()

	function view.openKeyRow(id, forceOpen)
		for pid, r in pairs(keyRows) do
			r.details.Visible = (pid == id) and (forceOpen == true or not r.details.Visible)
		end
	end

	local function buildKeyRow(p, order)
		local row = make("Frame", {
			Name = "KeyRow_" .. p.id, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = AUTO_Y, LayoutOrder = order,
		}, keysGroup)
		stack(row, 0)

		local hd = make("TextButton", {
			Name = "KeyHeader_" .. p.id, Text = "", AutoButtonColor = false, BackgroundColor3 = C.raisedHi,
			BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 46), LayoutOrder = 1,
		}, row)
		pressFade(hd)
		local dot = make("Frame", {
			Name = "KeyDot", Size = UDim2.new(0, 10, 0, 10), Position = UDim2.new(0, 12, 0.5, -5),
			BackgroundColor3 = C.faint, BorderSizePixel = 0,
		}, hd)
		corner(dot, 2)
		stroke(dot, C.ink, 1)
		label(hd, {name = "KeyName", text = p.name, font = F.bold, ts = 13, size = UDim2.new(1, -150, 0, 18), pos = UDim2.new(0, 32, 0, 7)})
		label(hd, {name = "KeyTag", text = p.tag, ts = 11, color = C.faint, size = UDim2.new(1, -150, 0, 14), pos = UDim2.new(0, 32, 0, 25)})
		local status = label(hd, {
			name = "KeyStatus", font = F.med, ts = 11, color = C.sub, align = AX.Right,
			size = UDim2.new(0, 110, 1, 0), pos = UDim2.new(1, -120, 0, 0),
		})
		hd.Activated:Connect(function()
			view.openKeyRow(p.id)
		end)

		local details = make("Frame", {
			Name = "KeyDetails_" .. p.id, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = AUTO_Y, Visible = false, LayoutOrder = 2,
		}, row)
		pad(details, 12, 2, 12, 12)
		stack(details, 7)

		local o = 0
		local function nextO()
			o = o + 1
			return o
		end

		local urlBox
		if p.needsUrl then
			label(details, {name = "UrlLabel", text = "BASE URL", font = F.head, ts = 11, color = C.sub, size = UDim2.new(1, 0, 0, 14), order = nextO()})
			urlBox = textBox(details, {name = "UrlBox", placeholder = "https://host/v1", order = nextO()})
			urlBox.FocusLost:Connect(function()
				app.saveUrl(urlBox.Text)
			end)
		end

		local keyLine = make("Frame", {Name = "KeyLine", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = nextO()}, details)
		local keyBox = textBox(keyLine, {
			name = "KeyBox_" .. p.id, placeholder = p.keyOptional and "Key (optional)" or ("Paste your " .. p.name .. " key"),
			size = UDim2.new(1, -70, 1, 0),
		})
		local function saveFromBox()
			local t = keyBox.Text
			keyBox.Text = ""
			app.saveKey(p, t)
		end
		keyBox.FocusLost:Connect(function()
			if keyBox.Text ~= "" then
				saveFromBox()
			end
		end)
		brick(keyLine, {
			name = "SaveKey_" .. p.id, text = "SAVE", kind = "yellow", ts = 12,
			size = UDim2.new(0, 62, 1, 0), pos = UDim2.new(1, -62, 0, 0), onClick = saveFromBox,
		})

		if p.steps then
			label(details, {name = "StepsTitle", text = "HOW TO GET A KEY", font = F.head, ts = 11, color = C.sub, size = UDim2.new(1, 0, 0, 16), order = nextO()})
			label(details, {
				name = "KeySteps", text = p.steps, ts = 11, color = C.faint, wrap = true,
				size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = nextO(),
			})
		end

		local actions = make("Frame", {Name = "KeyActions", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = nextO()}, details)
		stack(actions, 7, true)
		brick(actions, {
			name = "TestKey_" .. p.id, text = "TEST", kind = "blue", ts = 12, size = UDim2.new(0, 58, 0, 26), order = 1,
			onClick = function()
				app.testKey(p)
			end,
		})
		if p.keyUrl then
			brick(actions, {
				name = "CopyLink_" .. p.id, text = "COPY LINK", kind = "gray", ts = 12, size = UDim2.new(0, 84, 0, 26), order = 2,
				onClick = function()
					view.copy("https://" .. p.keyUrl)
				end,
			})
		end
		brick(actions, {
			name = "RemoveKey_" .. p.id, text = "REMOVE", kind = "red", ts = 12, size = UDim2.new(0, 74, 0, 26), order = 3,
			onClick = function()
				app.removeKey(p)
			end,
		})

		local msg = label(details, {
			name = "KeyMessage_" .. p.id, text = "", ts = 11, color = C.sub, wrap = true,
			size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = nextO(),
		})
		msg.Visible = false

		keyRows[p.id] = {dot = dot, status = status, details = details, keyBox = keyBox, urlBox = urlBox, msg = msg}
	end

	for i, p in ipairs(PROVIDERS) do
		buildKeyRow(p, i * 2 - 1)
		if i < #PROVIDERS then
			divider(keysGroup, i * 2)
		end
	end

	heading("Spawn point")
	do
		local line = make("Frame", {Name = "SpawnLine", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = nextOrder()}, setup)
		local box = textBox(line, {name = "SpawnBox", placeholder = "x, y, z   for example -8.5, 0.6, -25", size = UDim2.new(1, -70, 1, 0)})
		local row = make("Frame", {Name = "SpawnButtons", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = nextOrder()}, setup)
		stack(row, 7, true)
		local msg = label(setup, {
			name = "SpawnMessage", ts = 11, color = C.sub, wrap = true,
			size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = nextOrder(),
		})
		local function refresh()
			if forge.manual then
				local v = forge.manual
				msg.Text = string.format("Spawning at %.1f, %.1f, %.1f every time. Type a spot next to you, not on top of you.", v.X, v.Y, v.Z)
			else
				msg.Text = "Automatic: in front of your character, or where the camera looks in Studio."
			end
		end
		local function setManual(v)
			forge.manual = v
			forge.origin = nil
			settings.spawnAt = v and {v.X, v.Y, v.Z} or nil
			saveSettings()
			refresh()
		end
		brick(line, {
			name = "SpawnSet", text = "SET", kind = "yellow", ts = 13, size = UDim2.new(0, 62, 1, 0), pos = UDim2.new(1, -62, 0, 0),
			onClick = function()
				local nums = {}
				for n in box.Text:gmatch("-?%d+%.?%d*") do
					nums[#nums + 1] = tonumber(n)
				end
				if #nums >= 3 then
					setManual(Vector3.new(nums[1], nums[2], nums[3]))
					box.Text = ""
				else
					msg.Text = "Type three numbers: x, y, z"
				end
			end,
		})
		brick(row, {
			name = "SpawnHere", text = "USE SPOT IN FRONT OF ME", kind = "blue", ts = 11, size = UDim2.new(0, 176, 0, 26), order = 1,
			onClick = function()
				forge.manual = nil
				forge.origin = nil
				setManual(forge.getOrigin())
			end,
		})
		brick(row, {
			name = "SpawnAuto", text = "AUTO", kind = "gray", ts = 11, size = UDim2.new(0, 60, 0, 26), order = 2,
			onClick = function()
				setManual(nil)
			end,
		})
		if type(settings.spawnAt) == "table" and #settings.spawnAt >= 3 then
			forge.manual = Vector3.new(tonumber(settings.spawnAt[1]) or 0, tonumber(settings.spawnAt[2]) or 0, tonumber(settings.spawnAt[3]) or 0)
		end
		refresh()
	end

	heading("Online counter")
	paragraph("TONYO shows who is using it. While sharing is on it sends your Roblox username, display name, user id, the game you are in, a random id for this device and the time you were last active. Other TONYO users can see your name and picture in the Online list and in Global Chat, and the developer sees you in the Admin tab. It never sends your AI chats or keys. Turn it off below any time.")
	local onlineGroup = group()
	do
		local b = make("TextButton", {
			Name = "PingRow", Text = "", AutoButtonColor = false, BackgroundColor3 = C.raisedHi,
			BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 42), LayoutOrder = 1,
		}, onlineGroup)
		pressFade(b)
		label(b, {name = "RowLabel", text = "SHARE COUNT PING", font = F.head, ts = 12, color = C.sub, size = UDim2.new(0.6, 0, 1, 0), pos = UDim2.new(0, 12, 0, 0)})
		onlineValue = label(b, {name = "Value", font = F.bold, ts = 12, align = AX.Right, size = UDim2.new(0.4, -24, 1, 0), pos = UDim2.new(0.6, 0, 0, 0)})
		b.Activated:Connect(function()
			settings.ping = not (settings.ping ~= false)
			saveSettings()
			if settings.ping == false then
				task.spawn(online.leave)
				online.count = nil
			else
				task.spawn(function()
					pcall(online.ping)
					refreshCounter()
					app.refreshSetup()
				end)
			end
			refreshCounter()
			app.refreshSetup()
		end)
	end
	onlineNote = paragraph("")

	heading("Chat")
	local chatGroup = group()
	do
		local clearRow = make("TextButton", {
			Name = "ClearRow", Text = "", AutoButtonColor = false, BackgroundColor3 = C.raisedHi,
			BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 42), LayoutOrder = 1,
		}, chatGroup)
		pressFade(clearRow)
		label(clearRow, {name = "RowLabel", text = "Clear chat and scan", font = F.med, ts = 12, size = UDim2.new(1, -24, 1, 0), pos = UDim2.new(0, 12, 0, 0)})
		clearRow.Activated:Connect(function()
			app.clear()
			view.selectTab("chat")
		end)
	end
	paragraph("Keys stay on this device, in workspace/TONYO_MODEL_settings.json. Tonyo 6.0")
end

local news = make("ScrollingFrame", {
	Name = "NewsPage", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 4, ScrollBarImageColor3 = C.scroll, CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = AUTO_Y, ScrollingDirection = Enum.ScrollingDirection.Y, Visible = false,
}, body)
do
	pad(news, 10, 6, 12, 14)
	stack(news, 10)
	local logGroup = make("Frame", {
		Name = "ActivityGroup", BackgroundColor3 = C.raised, BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, LayoutOrder = 0,
	}, news)
	corner(logGroup, 6)
	stroke(logGroup, C.ink, 2)
	pad(logGroup, 12, 10, 12, 12)
	stack(logGroup, 4)
	label(logGroup, {name = "ActivityTitle", text = "ACTIVITY", font = F.head, ts = 16, color = C.yellow, size = UDim2.new(1, 0, 0, 22), order = -1000000})
	local logEmpty = label(logGroup, {name = "ActivityEmpty", text = "Nothing yet. Spawns, scripts, scans and errors show up here with the time.", ts = 11, color = C.faint, wrap = true, size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = 0})
	local logLines, logCount = {}, 0
	function view.log(text, kind)
		logCount = logCount + 1
		logEmpty.Visible = false
		local stamp
		local okT = pcall(function()
			stamp = DateTime.now():FormatLocalTime("HH:mm:ss", "en-us")
		end)
		if not okT or not stamp then
			stamp = os.date("%H:%M:%S")
		end
		local color = C.sub
		if kind == "ok" then
			color = C.green
		elseif kind == "warn" then
			color = C.amber
		elseif kind == "bad" then
			color = C.redText
		end
		logLines[#logLines + 1] = label(logGroup, {
			name = "LogLine", text = stamp .. "   " .. text, ts = 11, color = color, wrap = true,
			size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = -logCount,
		})
		if #logLines > 40 then
			table.remove(logLines, 1):Destroy()
		end
	end
	local LOG = {
		{"v6.0", "Major update  /  Latest  /  Nov 7, 2026", {
			"New ASSETS tab with a live preview screen. Watch any animation or emote play on a copy of your character (drag to rotate, spin, zoom, loop, seek bar), or play any sound with volume, loop and seek.",
			"Emote catalog with 60,000+ emotes: search, thumbnails, VIEW to preview and COPY to copy the ID. It reads EmoteDataCache.json from your workspace, with a built-in starter list if the file is missing.",
			"ON ME plays the previewed animation on your own character. GAME ANIMS lists the animations from your AnimationCache.json.",
			"Lookup any asset by ID or link: type is detected automatically and the name, creator, price and date are shown. Browse the store for audio, music, sound FX, animations, models, decals and avatar items. Copy the ID, link or rbxassetid string.",
			"GLOBAL chat fixed. The safety check was calling a Roblox function that does not exist, so nothing could be sent or shown. It now uses Roblox's real text filter.",
			"GLOBAL chat also no longer shows the same message twice, shows the real reason when a send fails, and retries a message that can't be verified three times before hiding it, with a note.",
		}},
		{"v5.4", "Nov 5, 2026", {
			"13 more providers added: Cohere, DeepInfra, Chutes and Z.AI (free tiers), plus Moonshot, MiniMax, Qwen, Perplexity, AI21, Hyperbolic, Novita, Nebius and Venice (paid). 29 providers total.",
			"Cloudflare Workers AI can be used today too, through the existing Custom provider: paste its account-scoped base URL and an API token.",
		}},
		{"v5.3", "Nov 5, 2026", {
			"Every GLOBAL chat message now goes through Roblox's own text moderation twice: once when sent, and again on every device before it is shown. A message that can't be verified as safe is skipped rather than displayed.",
			"The online counter keeps the exact reason it failed (shown in Setup and ADMIN), instead of a generic message.",
		}},
		{"v5.2", "Nov 5, 2026", {
			"New GLOBAL tab: chat with everyone using TONYO in any game. Each message shows the sender's picture, display name and username, with mute, and a rate limit of one message every 2 seconds.",
			"ONLINE view lists everyone currently using TONYO, with their picture, and whether they are in your game.",
			"Announcements now show the sender's picture and name.",
			"PLAYERS tab can show only the players in your server who are using TONYO (on by default, one tap to switch).",
			"Spawned objects are now anchored and solid more reliably: fixed again after spawning, parts added later are caught, and rigged creatures always get an anchored root.",
		}},
		{"v5.1", "Nov 5, 2026", {
			"Auto place now works on every code block, even ones the AI forgot to label. Server code goes to Workspace.TONYO_Scripts.ServerScriptService and client code to Workspace.TONYO_Scripts.StarterPlayerScripts, with a note under each block.",
			"Blocks are sorted automatically: code that uses ServerScriptService, DataStoreService, PlayerAdded or RemoteEvent server events is treated as server code.",
		}},
		{"v5.0", "Nov 5, 2026", {
			"New BUILD tab: browse the game, pick anything, then set Anchored, Can Collide, clone, delete, go to it, or animate it with one tap.",
			"Auto anchor and auto collide for everything the AI builds, with rigged creatures left alone.",
			"New animate op: the AI can spin, bob, swing, pulse and slide models and parts by itself, and the effects stack.",
			"Auto place: AI server and client scripts are saved and placed in Workspace.TONYO_Scripts. Optional auto run for client code.",
		}},
		{"v4.13", "Nov 4, 2026", {
			"Restart can now deliver an actual code update instead of only resetting the window, if SCRIPT_URL at the top of the script points to your latest file. No rejoin needed for players.",
			"Falls back to a normal reset if the link is empty or can't be reached.",
		}},
		{"v4.12", "Restart timing  /  Nov 4, 2026", {
			"A scheduled restart now waits for your current message to finish instead of cutting it off, and can't crash the chat if something goes wrong.",
		}},
		{"v4.11", "Owner tools  /  Nov 4, 2026", {
			"ADMIN tab for dador_1234567 and ipoge6 only: see who is using TONYO by username, send an announcement banner to everyone, and schedule a restart with a countdown.",
			"The online counter now shares username and user id, not just an anonymous id. This is disclosed in Setup and can be turned off there.",
			"Presence checks run about every 20 seconds instead of 50.",
		}},
		{"v4.10", "Online counter  /  Nov 4, 2026", {
			"The header pill now shows how many people are using TONYO right now, once an online database is set up.",
			"Setup has an Online counter switch. It only sends a random anonymous id and the time.",
			"The PLAYERS tab has a USING stat next to the server player count.",
		}},
		{"v4.9", "Players  /  Nov 4, 2026", {
			"Live player counter in the header. Tap it to open the PLAYERS tab.",
			"PLAYERS tab: server FPS, ping and uptime, every player with distance and health, GO and VIEW buttons, plus copy position, clear spawns, reset camera and copy server id.",
			"AUDIT tab: lists every script players can read, biggest first, with a COPY LIST button.",
			"Quick start chips on the empty chat, and the tab bar now scrolls sideways.",
		}},
		{"v4.8", "Export  /  Nov 4, 2026", {
			"New EXPORT tab replaces INSPECT. It scans the whole workspace into an AI-ready report with the hierarchy, model details, joints and your character.",
			"Type a focus path to list every part of one model, like the dog.",
			"COPY the report for any AI, or SEND TO AI to attach it to this chat.",
		}},
		{"v4.7", "Inspect  /  Nov 4, 2026", {
			"INSPECT button: pick any folder or model in your game and send its names, sizes, offsets and joints to the AI.",
			"Spawn point setting: type exact x, y, z so things always appear where you want.",
			"Spawns that land far away are always moved back next to you.",
			"Activity log with the time of every spawn, script, scan, inspect and error.",
		}},
		{"v4.6", "Spawn point  /  Nov 4, 2026", {
			"The AI is told your spawn point, and spawns that land far away are moved back next to you.",
			"The spawn point refreshes when you walk away from it.",
		}},
		{"v4.5", "Finding it  /  Nov 4, 2026", {
			"Spawns land where the camera is looking in Studio, and the camera jumps to them.",
			"Spawn cards list where each model is and how big it is.",
			"Code cards have OPEN CODE TO COPY OR SELECT, because scripts made at runtime are read only.",
		}},
		{"v4.4", "Rigging  /  Nov 4, 2026", {
			"New rig command joins a model's parts so it can be animated.",
			"Script cards have a PLAY button that runs the animation on your client.",
			"The AI is now told how to build multi-part models like a dog and animate them.",
		}},
		{"v4.3", "Models  /  Nov 4, 2026", {
			"New insert command loads a catalog model by asset id.",
			"Cloning now works on models that are marked as not copyable.",
			"Spawn cards warn when nothing visible was made and count the visible parts.",
		}},
		{"v4.2", "Scripts  /  Nov 4, 2026", {
			"Scripts are placed in Workspace.TONYO_Scripts as real Script objects. Move them yourself.",
			"Spawn cards flash a highlight on new objects and have a GO button to walk you to them.",
			"Scripts are also saved to workspace/TONYO_Scripts when your executor can write files.",
			"New tab: what's new.",
		}},
		{"v4.1", "Spawning  /  Nov 4, 2026", {
			"Ask for anything to be spawned and it appears in front of you, inside Workspace.TONYO_Spawns.",
			"Create, edit, delete and clone objects. UNDO removes what a card spawned.",
			"Parts pop in with a small grow animation.",
		}},
		{"v4.0", "New look  /  Nov 4, 2026", {
			"Brick style UI with studs, lipped buttons and a tilted sticker.",
			"Code cards with CLIENT and SERVER tags, and a three block thinking indicator.",
			"Setup tab redone, with provider and model pickers.",
		}},
	}
	for i, entry in ipairs(LOG) do
		local g = make("Frame", {
			Name = "Entry" .. i, BackgroundColor3 = C.raised, BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, LayoutOrder = i,
		}, news)
		corner(g, 6)
		stroke(g, C.ink, 2)
		pad(g, 12, 10, 12, 12)
		stack(g, 6)
		local top = make("Frame", {Name = "EntryHead", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 0}, g)
		label(top, {name = "Version", text = entry[1], font = F.head, ts = 17, color = C.yellow, size = UDim2.new(0, 60, 1, 0)})
		label(top, {name = "Tag", text = entry[2]:upper(), font = F.head, ts = 11, color = C.sub, size = UDim2.new(1, -66, 1, 0), pos = UDim2.new(0, 66, 0, 1)})
		for j, line in ipairs(entry[3]) do
			label(g, {
				name = "Line" .. j, text = "\u{2022}  " .. line, ts = 12, wrap = true,
				size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = j,
			})
		end
	end
end

local function describeTree(root)
	local lines, count = {}, 0
	local pivot
	pcall(function()
		pivot = root:GetPivot()
	end)
	local function n2(x)
		return tostring(math.floor(x * 100 + 0.5) / 100)
	end
	local function walk(inst, depth)
		if count >= 220 then
			return
		end
		count = count + 1
		local info = inst.Name .. " [" .. inst.ClassName .. "]"
		pcall(function()
			if inst:IsA("BasePart") then
				local off = pivot and pivot:PointToObjectSpace(inst.Position) or inst.Position
				local c = inst.Color
				info = info .. string.format("  size %s,%s,%s  offset %s,%s,%s  color %d,%d,%d  %s%s", n2(inst.Size.X), n2(inst.Size.Y), n2(inst.Size.Z), n2(off.X), n2(off.Y), n2(off.Z), math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5), inst.Material.Name, inst.Anchored and "  anchored" or "")
			elseif inst:IsA("JointInstance") then
				info = info .. "  " .. (inst.Part0 and inst.Part0.Name or "nil") .. " -> " .. (inst.Part1 and inst.Part1.Name or "nil")
			elseif inst:IsA("Model") and inst.PrimaryPart then
				info = info .. "  primary " .. inst.PrimaryPart.Name
			elseif inst:IsA("LuaSourceContainer") then
				local okS, src = pcall(function()
					return inst.Source
				end)
				if okS and type(src) == "string" then
					info = info .. "  " .. #src .. " chars"
				end
			end
		end)
		lines[#lines + 1] = string.rep("  ", depth) .. info
		for _, ch in ipairs(inst:GetChildren()) do
			walk(ch, depth + 1)
		end
	end
	walk(root, 0)
	local path = root:GetFullName()
	local head = "[Inspected " .. path .. ", " .. count .. " objects. Offsets are relative to the model pivot, in studs. Use these exact names.]\n"
	return clip(head .. table.concat(lines, "\n"), 7000), count, path
end

local exportPage = make("ScrollingFrame", {
	Name = "ExportPage", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 4, ScrollBarImageColor3 = C.scroll, CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = AUTO_Y, ScrollingDirection = Enum.ScrollingDirection.Y, Visible = false,
}, body)
do
	pad(exportPage, 10, 6, 12, 14)
	stack(exportPage, 7)
	local order = 0
	local function nxt()
		order = order + 1
		return order
	end

	local CFG = {depth = 3, kids = 30, models = 25, details = true, character = true, preview = 6000}
	local GOAL_TOKEN = "{{GOAL}}"
	local DEFAULT_GOAL = "(Not specified yet. Before writing any code, ask me what I want to animate.)"
	local fullReport, scanning = "", false
	local yieldCounter = 0

	local function maybeYield()
		yieldCounter = yieldCounter + 1
		if yieldCounter % 300 == 0 then
			task.wait()
		end
	end

	local function fmtVec(v)
		return string.format("%.1f, %.1f, %.1f", v.X, v.Y, v.Z)
	end

	local function luaPath(inst)
		local segments = {}
		local cur = inst
		while cur and cur ~= workspace and cur ~= game do
			local n = cur.Name
			if n:match("^[%a_][%w_]*$") then
				table.insert(segments, 1, "." .. n)
			else
				local escaped = n:gsub('"', '\\"')
				table.insert(segments, 1, '["' .. escaped .. '"]')
			end
			cur = cur.Parent
		end
		return "workspace" .. table.concat(segments)
	end

	local function isSkipped(inst)
		if inst:IsA("Terrain") or inst == workspace.CurrentCamera then
			return true
		end
		if Players:GetPlayerFromCharacter(inst) then
			return true
		end
		return false
	end

	local function countWorkspace()
		local t = {
			folders = 0, models = 0, parts = 0, meshParts = 0, scripts = 0, humanoids = 0, motors = 0,
			animControllers = 0, animations = 0, sounds = 0, lights = 0, particles = 0,
		}
		for _, d in ipairs(workspace:GetDescendants()) do
			maybeYield()
			if d:IsA("BasePart") and not d:IsA("Terrain") then
				t.parts = t.parts + 1
				if d:IsA("MeshPart") then
					t.meshParts = t.meshParts + 1
				end
			elseif d:IsA("Model") then
				t.models = t.models + 1
			elseif d:IsA("Folder") then
				t.folders = t.folders + 1
			elseif d:IsA("LuaSourceContainer") then
				t.scripts = t.scripts + 1
			elseif d:IsA("Humanoid") then
				t.humanoids = t.humanoids + 1
			elseif d:IsA("Motor6D") then
				t.motors = t.motors + 1
			elseif d:IsA("AnimationController") then
				t.animControllers = t.animControllers + 1
			elseif d:IsA("Animation") then
				t.animations = t.animations + 1
			elseif d:IsA("Sound") then
				t.sounds = t.sounds + 1
			elseif d:IsA("Light") then
				t.lights = t.lights + 1
			elseif d:IsA("ParticleEmitter") then
				t.particles = t.particles + 1
			end
		end
		return t
	end

	local function analyze(root)
		local info = {
			parts = 0, anchored = 0, motorCount = 0, motors = {}, welds = 0, constraints = 0, attachments = 0,
			scripts = 0, scriptNames = {}, animations = {}, humanoid = nil, animator = false, animController = false,
			sampleParts = {},
		}
		for _, d in ipairs(root:GetDescendants()) do
			maybeYield()
			if d:IsA("BasePart") then
				info.parts = info.parts + 1
				if d.Anchored then
					info.anchored = info.anchored + 1
				end
				if #info.sampleParts < 8 then
					table.insert(info.sampleParts, d.Name .. " (" .. d.ClassName .. ")")
				end
			elseif d:IsA("Motor6D") then
				info.motorCount = info.motorCount + 1
				if #info.motors < 12 then
					local p0 = d.Part0 and d.Part0.Name or "nil"
					local p1 = d.Part1 and d.Part1.Name or "nil"
					table.insert(info.motors, d.Name .. " (" .. p0 .. " -> " .. p1 .. ")")
				end
			elseif d:IsA("JointInstance") or d:IsA("WeldConstraint") then
				info.welds = info.welds + 1
			elseif d:IsA("Constraint") then
				info.constraints = info.constraints + 1
			elseif d:IsA("Attachment") then
				info.attachments = info.attachments + 1
			elseif d:IsA("Humanoid") then
				info.humanoid = d
			elseif d:IsA("Animator") then
				info.animator = true
			elseif d:IsA("AnimationController") then
				info.animController = true
			elseif d:IsA("Animation") then
				if #info.animations < 6 then
					table.insert(info.animations, d.Name .. " = " .. tostring(d.AnimationId))
				end
			elseif d:IsA("LuaSourceContainer") then
				info.scripts = info.scripts + 1
				if #info.scriptNames < 6 then
					table.insert(info.scriptNames, d.Name .. " [" .. d.ClassName .. "]")
				end
			end
		end
		return info
	end

	local function isAnimatable(info)
		return info.humanoid ~= nil or info.animController or info.animator or info.motorCount > 0
	end

	local function sortedChildren(inst)
		local kids = inst:GetChildren()
		local function rank(i)
			if i:IsA("Folder") then
				return 1
			elseif i:IsA("Model") then
				return 2
			elseif i:IsA("BasePart") then
				return 3
			end
			return 4
		end
		table.sort(kids, function(a, b)
			local ra, rb = rank(a), rank(b)
			if ra ~= rb then
				return ra < rb
			end
			return a.Name < b.Name
		end)
		return kids
	end

	local function nodeLabel(inst)
		if inst:IsA("Model") then
			local n = 0
			for _, d in ipairs(inst:GetDescendants()) do
				if d:IsA("BasePart") then
					n = n + 1
				end
			end
			return string.format("%s [Model, %d parts]", inst.Name, n)
		elseif inst:IsA("Folder") then
			return string.format("%s [Folder, %d children]", inst.Name, #inst:GetChildren())
		elseif inst:IsA("BasePart") then
			return string.format("%s [%s, size %s]", inst.Name, inst.ClassName, fmtVec(inst.Size))
		end
		return string.format("%s [%s]", inst.Name, inst.ClassName)
	end

	local function buildTree(inst, depth, indent, lines, modelsFound)
		local eligible = {}
		for _, kid in ipairs(sortedChildren(inst)) do
			if not isSkipped(kid) then
				table.insert(eligible, kid)
			end
		end
		local limit = math.min(#eligible, CFG.kids)
		for i = 1, limit do
			local kid = eligible[i]
			maybeYield()
			lines[#lines + 1] = indent .. "- " .. nodeLabel(kid)
			if kid:IsA("Model") then
				modelsFound[#modelsFound + 1] = kid
			end
			if depth < CFG.depth and (kid:IsA("Folder") or kid:IsA("Model")) then
				buildTree(kid, depth + 1, indent .. "  ", lines, modelsFound)
			end
		end
		if #eligible > limit then
			lines[#lines + 1] = indent .. "- ... and " .. (#eligible - limit) .. " more items not shown"
		end
	end

	local function describeModel(model, info)
		local out = {}
		out[#out + 1] = "### " .. model.Name .. " [" .. model.ClassName .. "]"
		out[#out + 1] = "- Path: " .. luaPath(model)
		local size = select(2, pcall(function()
			return model:GetExtentsSize()
		end))
		local pivot = select(2, pcall(function()
			return model:GetPivot().Position
		end))
		local sizeText = typeof(size) == "Vector3" and fmtVec(size) or "unknown"
		local pivotText = typeof(pivot) == "Vector3" and fmtVec(pivot) or "unknown"
		out[#out + 1] = string.format("- Parts: %d (anchored: %d) | Size: %s | Pivot position: %s", info.parts, info.anchored, sizeText, pivotText)
		out[#out + 1] = "- PrimaryPart: " .. (model.PrimaryPart and model.PrimaryPart.Name or "none set")
		local rig = {}
		if info.humanoid then
			table.insert(rig, "Humanoid (" .. info.humanoid.RigType.Name .. ")")
		end
		if info.animator then
			table.insert(rig, "Animator")
		end
		if info.animController then
			table.insert(rig, "AnimationController")
		end
		out[#out + 1] = "- Rig: " .. (#rig > 0 and table.concat(rig, ", ") or "none (plain model)")
		if info.motorCount > 0 then
			out[#out + 1] = string.format("- Motor6D joints (%d): %s", info.motorCount, table.concat(info.motors, ", "))
		end
		out[#out + 1] = string.format("- Welds: %d | Constraints: %d | Attachments: %d", info.welds, info.constraints, info.attachments)
		if #info.animations > 0 then
			out[#out + 1] = "- Existing Animation objects: " .. table.concat(info.animations, "; ")
		end
		if info.scripts > 0 then
			out[#out + 1] = string.format("- Scripts inside (%d): %s", info.scripts, table.concat(info.scriptNames, ", "))
		end
		if #info.sampleParts > 0 then
			out[#out + 1] = "- Sample parts: " .. table.concat(info.sampleParts, ", ")
		end
		return table.concat(out, "\n")
	end

	local function describeCharacter()
		local out = {}
		local char = player.Character
		if not char then
			return "- Character not loaded."
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		out[#out + 1] = '- Path: workspace["' .. char.Name .. '"]'
		out[#out + 1] = "- Rig type: " .. (hum and hum.RigType.Name or "unknown")
		local motors, total = {}, 0
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("Motor6D") then
				total = total + 1
				if #motors < 25 then
					local p0 = d.Part0 and d.Part0.Name or "nil"
					local p1 = d.Part1 and d.Part1.Name or "nil"
					table.insert(motors, d.Name .. " (" .. p0 .. " -> " .. p1 .. ")")
				end
			end
		end
		out[#out + 1] = string.format("- Motor6D joints (%d): %s", total, table.concat(motors, ", "))
		local animator = hum and hum:FindFirstChildOfClass("Animator")
		if animator then
			local ok, tracks = pcall(function()
				return animator:GetPlayingAnimationTracks()
			end)
			if ok and #tracks > 0 then
				local names = {}
				for _, tr in ipairs(tracks) do
					table.insert(names, tr.Name .. " = " .. tostring(tr.Animation and tr.Animation.AnimationId or "?"))
				end
				out[#out + 1] = "- Currently playing animations: " .. table.concat(names, "; ")
			else
				out[#out + 1] = "- Currently playing animations: none"
			end
		end
		return table.concat(out, "\n")
	end

	local goalBox = textBox(exportPage, {name = "GoalBox", placeholder = "What do you want to animate? e.g. make the dog walk", order = nxt()})
	local focusBox = textBox(exportPage, {name = "FocusBox", placeholder = "Focus path (optional): Workspace.TONYO_Spawns.Dog", order = nxt()})

	local function buildReport()
		local gameName = "Unknown"
		local ok, product = pcall(function()
			return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
		end)
		if ok and product and product.Name then
			gameName = product.Name
		end
		local counts = countWorkspace()
		local out = {}
		local function add(s)
			out[#out + 1] = s
		end
		add("# ROBLOX WORKSPACE REPORT (for AI animation scripting)")
		add("")
		add("Game: " .. gameName .. " | PlaceId: " .. tostring(game.PlaceId))
		add("Generated: " .. os.date("%Y-%m-%d %H:%M:%S"))
		add("Environment: Roblox client-side Luau")
		add("")
		add("## 1. WHAT I WANT")
		add(GOAL_TOKEN)
		add("")
		add("## 2. SUMMARY")
		add("- Folders: " .. counts.folders)
		add("- Models: " .. counts.models)
		add("- Parts: " .. counts.parts .. " (MeshParts: " .. counts.meshParts .. ")")
		add("- Motor6D joints: " .. counts.motors)
		add("- Humanoids: " .. counts.humanoids .. " | AnimationControllers: " .. counts.animControllers)
		add("- Existing Animation objects: " .. counts.animations)
		add("- Scripts: " .. counts.scripts)
		add("- Sounds: " .. counts.sounds .. " | Lights: " .. counts.lights .. " | ParticleEmitters: " .. counts.particles)
		add("")
		add("## 3. HIERARCHY (depth " .. CFG.depth .. ", folders and models first)")
		add("workspace")
		local treeLines, modelsFound = {}, {}
		buildTree(workspace, 1, "", treeLines, modelsFound)
		for _, l in ipairs(treeLines) do
			add(l)
		end
		add("")
		local focusText = focusBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
		if focusText ~= "" then
			local root = forge.find(focusText)
			add("## 3B. FOCUS: every part of " .. focusText)
			if root then
				add((describeTree(root)))
			else
				add("Could not find " .. focusText)
			end
			add("")
		end
		if CFG.details and #modelsFound > 0 then
			add("## 4. MODEL DETAILS (animation-relevant models first)")
			local analyzed = {}
			for _, m in ipairs(modelsFound) do
				local info = analyze(m)
				table.insert(analyzed, {model = m, info = info, score = (isAnimatable(info) and 100000 or 0) + info.parts})
			end
			table.sort(analyzed, function(a, b)
				return a.score > b.score
			end)
			local limit = math.min(#analyzed, CFG.models)
			for i = 1, limit do
				add(describeModel(analyzed[i].model, analyzed[i].info))
				add("")
			end
			if #analyzed > limit then
				add("(... " .. (#analyzed - limit) .. " more models not detailed)")
				add("")
			end
		end
		if CFG.character then
			add("## 5. MY CHARACTER")
			add(describeCharacter())
			add("")
		end
		add("## 6. INSTRUCTIONS FOR THE AI")
		add("Write the animation script for the goal in section 1.")
		add("1. Output one complete Luau script for a Roblox executor (client-side). Do not use require() on unknown modules.")
		add("2. Use the exact paths above with FindFirstChild or WaitForChild, and check for nil before using anything.")
		add("3. For parts and models use TweenService (CFrame, Size, Transparency, Color) or PivotTo. For rigs use Motor6D C0 or Transform, or an Animator with Animation objects.")
		add("4. Changes made from the client are only visible to me, so do not rely on the server.")
		add("5. Wrap risky code in pcall and include a way to stop or reset the animation. Do not add comments to the code.")
		add("6. If anything is unclear, such as missing paths, rig type or timing, ask me before writing the code.")
		return table.concat(out, "\n"), counts
	end

	local chipRow = make("Frame", {Name = "ExportChips", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = nxt()}, exportPage)
	stack(chipRow, 6, true)
	local depthOptions, depthIndex = {2, 3, 4, 5}, 2
	local function onOff(b, label, value)
		b.Text = label .. (value and " ON" or " OFF")
		if value then
			paint(b, C.green, C.greenLip, C.ink)
		else
			paint(b, C.raised, C.raisedLip, C.sub)
		end
	end
	local depthChip
	depthChip = brick(chipRow, {
		name = "DepthChip", text = "DEPTH 3", kind = "gray", ts = 11, size = UDim2.new(0, 78, 0, 24), order = 1, radius = 4, lipH = 2,
		onClick = function()
			depthIndex = depthIndex % #depthOptions + 1
			CFG.depth = depthOptions[depthIndex]
			depthChip.Text = "DEPTH " .. CFG.depth
		end,
	})
	local detailsChip, meChip
	detailsChip = brick(chipRow, {
		name = "DetailsChip", kind = "gray", ts = 11, size = UDim2.new(0, 96, 0, 24), order = 2, radius = 4, lipH = 2,
		onClick = function()
			CFG.details = not CFG.details
			onOff(detailsChip, "DETAILS", CFG.details)
		end,
	})
	meChip = brick(chipRow, {
		name = "MeChip", kind = "gray", ts = 11, size = UDim2.new(0, 78, 0, 24), order = 3, radius = 4, lipH = 2,
		onClick = function()
			CFG.character = not CFG.character
			onOff(meChip, "ME", CFG.character)
		end,
	})
	onOff(detailsChip, "DETAILS", CFG.details)
	onOff(meChip, "ME", CFG.character)

	local actionRow = make("Frame", {Name = "ExportActions", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = nxt()}, exportPage)
	stack(actionRow, 6, true)
	local statsLabel = label(exportPage, {name = "ExportStats", text = "No scan yet", font = F.med, ts = 11, color = C.faint, wrap = true, size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = nxt()})
	local outWrap = make("Frame", {
		Name = "ExportOutput", BackgroundColor3 = C.code, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = AUTO_Y, LayoutOrder = nxt(),
	}, exportPage)
	corner(outWrap, 6)
	stroke(outWrap, C.ink, 2)
	local outBox = make("TextBox", {
		Name = "OutputBox", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y,
		Text = "Press SCAN to turn the whole workspace into a report an AI can animate from. Type your goal above first, and a focus path if you want every part of one model listed.",
		TextColor3 = C.codeText, TextSize = 11, Font = F.code, TextWrapped = true, MultiLine = true, ClearTextOnFocus = false,
		TextEditable = false, TextXAlignment = AX.Left, TextYAlignment = Enum.TextYAlignment.Top,
	}, outWrap)
	pad(outBox, 10, 8, 10, 8)
	local statusLine = label(exportPage, {name = "ExportStatus", text = "Ready", ts = 11, color = C.green, wrap = true, size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = nxt()})

	local function setStatus(text, color)
		statusLine.Text = text
		statusLine.TextColor3 = color or C.sub
	end

	local function currentText()
		local goal = goalBox.Text
		if goal:gsub("%s", "") == "" then
			goal = DEFAULT_GOAL
		end
		return (fullReport:gsub(GOAL_TOKEN, function()
			return goal
		end))
	end

	local function refreshPreview()
		if fullReport == "" then
			return
		end
		local text = currentText()
		if #text > CFG.preview then
			text = text:sub(1, CFG.preview) .. "\n\n... [Preview cut. COPY and SEND TO AI use the full report.]"
		end
		outBox.Text = text
	end
	goalBox.FocusLost:Connect(refreshPreview)

	local scanBtn
	scanBtn = brick(actionRow, {
		name = "ExportScan", text = "SCAN", kind = "blue", ts = 13, size = UDim2.new(0, 86, 0, 30), order = 1,
		onClick = function()
			if scanning then
				return
			end
			scanning = true
			scanBtn.Text = "..."
			setStatus("Analyzing the workspace, please wait", C.amber)
			yieldCounter = 0
			task.spawn(function()
				local ok, report, counts = pcall(buildReport)
				if ok then
					fullReport = report
					refreshPreview()
					statsLabel.Text = string.format("Folders %d  /  Models %d  /  Parts %d  /  Joints %d  /  Scripts %d", counts.folders, counts.models, counts.parts, counts.motors, counts.scripts)
					statsLabel.TextColor3 = C.yellow
					setStatus(string.format("Done. Report ready, %d characters.", #report), C.green)
					view.log("Exported workspace, " .. #report .. " characters", "ok")
				else
					setStatus("Scan failed: " .. tostring(report), C.redText)
					view.log("Export failed", "bad")
				end
				scanBtn.Text = "SCAN"
				scanning = false
			end)
		end,
	})
	local copyBtn
	copyBtn = brick(actionRow, {
		name = "ExportCopy", text = "COPY", kind = "green", ts = 13, size = UDim2.new(0, 70, 0, 30), order = 2,
		onClick = function()
			if fullReport == "" then
				setStatus("Nothing to copy yet. Press SCAN first.", C.amber)
				return
			end
			local clipFn = setclipboard or toclipboard
			if clipFn then
				local ok = pcall(clipFn, currentText())
				copyBtn.Text = ok and "COPIED" or "FAILED"
				setStatus(ok and "Full report copied. Paste it to any AI." or "Clipboard error. Long-press the report text to copy it.", ok and C.green or C.redText)
			else
				copyBtn.Text = "NO CLIP"
				setStatus("This executor has no clipboard. Long-press the report text to copy it.", C.amber)
			end
			task.delay(1.5, function()
				if copyBtn.Parent then
					copyBtn.Text = "COPY"
				end
			end)
		end,
	})
	brick(actionRow, {
		name = "ExportSend", text = "SEND TO AI", kind = "yellow", ts = 13, size = UDim2.new(0, 110, 0, 30), order = 3,
		onClick = function()
			if fullReport == "" then
				setStatus("Nothing to send yet. Press SCAN first.", C.amber)
				return
			end
			local text = currentText()
			local cut = text:find("\n## 6. INSTRUCTIONS", 1, true)
			if cut then
				text = text:sub(1, cut - 1)
			end
			contextText = text
			view.setScanned(true)
			view.note("Workspace report sent to the AI, " .. #text .. " characters. Ask it to animate or edit something now.")
			view.log("Sent workspace report to the AI", "ok")
			view.selectTab("chat")
		end,
	})
end

do
	local function base()
		local u = ONLINE_DB:gsub("%s", ""):gsub("/+$", "")
		if u == "" then
			return nil
		end
		return u
	end

	if type(settings.uid) ~= "string" or #settings.uid < 8 then
		settings.uid = HttpService:GenerateGUID(false):gsub("[^%w]", ""):sub(1, 24)
		saveSettings()
	end

	local function call(method, path, body)
		local b = base()
		if not b then
			online.lastError = "ONLINE_DB is empty"
			return nil
		end
		local ok, res = pcall(safeRequest, {
			Url = b .. path, Method = method, Headers = {["Content-Type"] = "application/json"}, Body = body,
		})
		if not ok then
			online.lastError = method .. " " .. path .. ": " .. oneLine(tostring(res), 160)
			return nil
		end
		local code = res and (res.StatusCode or 0) or 0
		if code >= 200 and code < 300 then
			online.lastError = ""
			return res.Body or ""
		end
		local snippet = res and type(res.Body) == "string" and res.Body or ""
		online.lastError = method .. " " .. path .. ": HTTP " .. tostring(code) .. (snippet ~= "" and ("  " .. oneLine(snippet, 140)) or "")
		return nil
	end

	-- Roblox's real text filter: TextService:FilterStringAsync, then read the result for broadcast or for this user.
	-- On a client the filter must run as the local player, so that id is always used.
	local TextService = game:GetService("TextService")
	local modCache, modCount = {}, 0
	online.modError = ""
	local function moderate(text, fromUserId, forBroadcast)
		if type(text) ~= "string" or text == "" then
			return nil
		end
		local cacheKey = (forBroadcast and "b:" or "r:") .. text
		if modCache[cacheKey] then
			return modCache[cacheKey]
		end
		local ok, result = pcall(function()
			return TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
		end)
		if not ok or not result then
			online.modError = oneLine(tostring(result), 120)
			return nil
		end
		local out
		if forBroadcast then
			local ok2, s2 = pcall(function()
				return result:GetNonChatStringForBroadcastAsync()
			end)
			if ok2 and type(s2) == "string" and s2 ~= "" then
				out = s2
			end
		end
		if not out then
			local ok3, s3 = pcall(function()
				return result:GetChatForUserAsync(player.UserId)
			end)
			if ok3 and type(s3) == "string" and s3 ~= "" then
				out = s3
			elseif not ok3 then
				online.modError = oneLine(tostring(s3), 120)
			end
		end
		if out then
			modCount = modCount + 1
			if modCount > 300 then
				modCache, modCount = {}, 0
			end
			modCache[cacheKey] = out
			online.modError = ""
		end
		return out
	end
	online.moderate = moderate

	local function pollControl()
		local body = call("GET", "/control.json")
		local data = decode(body)
		online.control = type(data) == "table" and data or {}
	end

	function online.ping()
		if not base() then
			online.status = "not set up"
			return
		end
		if settings.ping == false then
			online.status = "sharing is off"
			online.count = nil
			online.users = {}
			return
		end
		local now = os.time() * 1000
		local payload = HttpService:JSONEncode({t = now, n = player.Name, d = player.DisplayName, u = player.UserId, p = game.PlaceId})
		local sent = call("PUT", "/presence/" .. settings.uid .. ".json", payload)
		if sent == nil then
			online.status = "can't reach the database"
			return
		end
		local body = call("GET", '/presence.json?orderBy=%22t%22&startAt=' .. (now - 150000))
		local data = decode(body)
		if type(data) == "table" then
			online.users = data
			local n = 0
			for _ in pairs(data) do
				n = n + 1
			end
			online.count = math.max(n, 1)
			online.at = os.clock()
			online.status = "live"
		elseif body ~= nil and body:match("^%s*null") then
			online.users = {}
			online.count = 1
			online.status = "live"
		else
			online.status = "can't read the count"
		end
	end

	function online.leave()
		if base() and settings.ping ~= false then
			call("DELETE", "/presence/" .. settings.uid .. ".json")
		end
	end

	function online.sendAnnounce(text)
		text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if text == "" or not base() then
			return false
		end
		local body = HttpService:JSONEncode({text = text, id = os.time(), by = player.Name, d = player.DisplayName, u = player.UserId})
		return call("PUT", "/control/announce.json", body) ~= nil
	end

	function online.scheduleRestart(minutes)
		if not base() then
			return false
		end
		minutes = math.clamp(tonumber(minutes) or 1, 0.1, 60)
		local at = (os.time() + math.floor(minutes * 60 + 0.5)) * 1000
		local body = HttpService:JSONEncode({at = at, by = player.Name, minutes = minutes})
		local ok = call("PUT", "/control/restart.json", body) ~= nil
		if ok then
			pcall(pollControl)
		end
		return ok
	end

	function online.cancelRestart()
		local ok = call("DELETE", "/control/restart.json") ~= nil
		if ok then
			online.control.restart = nil
		end
		return ok
	end

	function online.chatSend(text)
		text = tostring(text or ""):gsub("%c", " "):gsub("^%s+", ""):gsub("%s+$", "")
		if text == "" or not base() then
			return false
		end
		if #text > 200 then
			text = text:sub(1, 200)
		end
		local len, bad = utf8.len(text)
		if not len then
			text = text:sub(1, math.max(bad - 1, 0))
		end
		local filtered = moderate(text, player.UserId, true)
		if not filtered then
			online.lastError = "message could not be checked for safety, so it was not sent"
				.. (online.modError ~= "" and (" (" .. online.modError .. ")") or "")
			return false
		end
		local body = HttpService:JSONEncode({m = filtered, n = player.Name, d = player.DisplayName, u = player.UserId, t = os.time() * 1000})
		return call("POST", "/chat.json", body) ~= nil
	end

	function online.chatFetch()
		local body = call("GET", "/chat.json?orderBy=%22%24key%22&limitToLast=40")
		if body == nil then
			return nil
		end
		local data = decode(body)
		return type(data) == "table" and data or {}
	end

	function online.chatDelete(key)
		if type(key) ~= "string" or not key:match("^[%w_%-]+$") then
			return false
		end
		return call("DELETE", "/chat/" .. key .. ".json") ~= nil
	end

	function online.refresh()
		pcall(online.ping)
		pcall(pollControl)
		refreshCounter()
	end

	local function fetchSource(url)
		local ok, src = pcall(function()
			if game.HttpGet then
				return game:HttpGet(url, true)
			end
			return game:HttpGetAsync(url, true)
		end)
		if ok and type(src) == "string" and #src > 200 then
			return src
		end
		return nil
	end

	local function hotReload()
		local url = SCRIPT_URL:gsub("%s", "")
		if url == "" or not loadstring then
			return false
		end
		local src = fetchSource(url)
		if not src then
			return false
		end
		local chunk = loadstring(src)
		if not chunk then
			return false
		end
		for _, c in ipairs(conns) do
			pcall(function()
				c:Disconnect()
			end)
		end
		local ok = pcall(chunk)
		return ok
	end

	local handledRestartAt, lastAnnounceId, announceShownAt
	local function updateBanner()
		local ctrl = online.control or {}
		local r = ctrl.restart
		if type(r) == "table" and type(r.at) == "number" then
			local remain = math.floor(r.at / 1000 - os.time())
			if remain > 0 then
				setBanner(true, string.format("Restarting in %d:%02d%s", math.floor(math.max(remain, 0) / 60), remain % 60, type(r.by) == "string" and ("  /  by " .. r.by) or ""), C.red)
				return
			elseif handledRestartAt ~= r.at then
				if app.isBusy and app.isBusy() then
					setBanner(true, "Restarting as soon as your current message finishes...", C.red)
					return
				end
				handledRestartAt = r.at
				setBanner(false)
				task.spawn(function()
					if hotReload() then
						return
					end
					local ok, err = pcall(app.restart)
					if not ok then
						pcall(view.log, "Restart failed: " .. tostring(err), "bad")
					end
				end)
				return
			end
		end
		local a = ctrl.announce
		if type(a) == "table" and type(a.text) == "string" and a.text ~= "" then
			if a.id ~= lastAnnounceId then
				lastAnnounceId = a.id
				announceShownAt = os.clock()
			end
			if announceShownAt and os.clock() - announceShownAt < 7 then
				local who = (type(a.d) == "string" and a.d ~= "" and a.d) or (type(a.by) == "string" and a.by) or "Announcement"
				setBanner(true, who .. ": " .. a.text, C.yellow, a.u)
				bannerLabel.TextColor3 = C.yellowInk
				return
			end
		end
		bannerLabel.TextColor3 = C.white
		setBanner(false)
	end

	task.spawn(function()
		while gui.Parent do
			online.refresh()
			for _ = 1, 20 do
				if not gui.Parent then
					break
				end
				pcall(updateBanner)
				task.wait(1)
			end
		end
	end)
end

local playersPage = make("ScrollingFrame", {
	Name = "PlayersPage", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 4, ScrollBarImageColor3 = C.scroll, CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = AUTO_Y, ScrollingDirection = Enum.ScrollingDirection.Y, Visible = false,
}, body)
local playersApi = {}
do
	pad(playersPage, 10, 6, 12, 14)
	stack(playersPage, 8)
	local order = 0
	local function nxt()
		order = order + 1
		return order
	end
	local RunService = game:GetService("RunService")
	local fps = 60
	conns[#conns + 1] = RunService.Heartbeat:Connect(function(dt)
		fps = fps * 0.92 + (1 / math.max(dt, 1 / 240)) * 0.08
	end)

	local statsRow = make("Frame", {Name = "ServerStats", BackgroundColor3 = C.raised, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 56), LayoutOrder = nxt()}, playersPage)
	corner(statsRow, 6)
	stroke(statsRow, C.ink, 2)
	local values = {}
	for i, cap in ipairs({"SERVER", "FPS", "PING", "UPTIME", "USING"}) do
		local col = make("Frame", {Name = "Stat" .. cap, BackgroundTransparency = 1, Size = UDim2.new(0.2, 0, 1, 0), Position = UDim2.new((i - 1) * 0.2, 0, 0, 0)}, statsRow)
		values[cap] = label(col, {name = "Value", text = "-", font = F.head, ts = 14, color = C.yellow, align = AX.Center, size = UDim2.new(1, 0, 0, 24), pos = UDim2.new(0, 0, 0, 8)})
		label(col, {name = "Caption", text = cap, font = F.med, ts = 9, color = C.faint, align = AX.Center, size = UDim2.new(1, 0, 0, 14), pos = UDim2.new(0, 0, 0, 33)})
	end

	local function heading(text)
		local h = make("Frame", {Name = "Heading", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = nxt()}, playersPage)
		label(h, {name = "HeadingText", text = text:upper(), font = F.head, ts = 14, color = C.yellow, size = UDim2.new(1, 0, 0, 22), pos = UDim2.new(0, 2, 0, 1)})
		make("Frame", {Name = "HeadingLine", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = C.ink, BorderSizePixel = 0}, h)
	end

	heading("Tools")
	local toolMsg
	local function say(text)
		toolMsg.Text = text
		view.log(text, "ok")
	end
	local row1 = make("Frame", {Name = "ToolsRow1", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = nxt()}, playersPage)
	stack(row1, 6, true)
	local row2 = make("Frame", {Name = "ToolsRow2", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = nxt()}, playersPage)
	stack(row2, 6, true)
	toolMsg = label(playersPage, {name = "ToolsMessage", ts = 11, color = C.sub, wrap = true, size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = nxt()})
	local function myRoot()
		local ch = player.Character
		return ch and ch:FindFirstChild("HumanoidRootPart")
	end
	brick(row1, {
		name = "CopyPosition", text = "COPY MY POSITION", kind = "blue", ts = 11, size = UDim2.new(0, 132, 0, 26), order = 1,
		onClick = function()
			local r = myRoot()
			if r then
				local p = r.Position
				local t = string.format("%.1f, %.1f, %.1f", p.X, p.Y, p.Z)
				if setclipboard then
					setclipboard(t)
				end
				say("Your position is " .. t)
			else
				toolMsg.Text = "No character to read a position from."
			end
		end,
	})
	brick(row1, {
		name = "ClearSpawns", text = "CLEAR SPAWNS", kind = "red", ts = 11, size = UDim2.new(0, 108, 0, 26), order = 2,
		onClick = function()
			local f = workspace:FindFirstChild("TONYO_Spawns")
			if f then
				f:ClearAllChildren()
			end
			forge.origin = nil
			say("Removed everything TONYO spawned.")
		end,
	})
	brick(row2, {
		name = "ResetCamera", text = "RESET CAMERA", kind = "gray", ts = 11, size = UDim2.new(0, 108, 0, 26), order = 1,
		onClick = function()
			local ch = player.Character
			local hum = ch and ch:FindFirstChildOfClass("Humanoid")
			local cam = workspace.CurrentCamera
			if hum and cam then
				cam.CameraSubject = hum
				say("Camera is back on you.")
			end
		end,
	})
	brick(row2, {
		name = "CopyJob", text = "COPY SERVER ID", kind = "gray", ts = 11, size = UDim2.new(0, 120, 0, 26), order = 2,
		onClick = function()
			if setclipboard then
				setclipboard(tostring(game.JobId))
			end
			say("Server id copied.")
		end,
	})

	heading("Players")
	local filterRow = make("Frame", {Name = "FilterRow", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = nxt()}, playersPage)
	local filterBtn
	local function paintFilter()
		filterBtn.Text = settings.playersOnlyTonyo ~= false and "SHOWING: TONYO USERS ONLY" or "SHOWING: EVERYONE IN THE SERVER"
	end
	filterBtn = brick(filterRow, {
		name = "FilterToggle", text = "", kind = "gray", ts = 11, size = UDim2.new(1, 0, 0, 26),
		onClick = function()
			settings.playersOnlyTonyo = not (settings.playersOnlyTonyo ~= false)
			saveSettings()
			paintFilter()
			playersApi.rebuild()
		end,
	})
	paintFilter()
	local listFrame = make("Frame", {Name = "PlayerList", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, LayoutOrder = nxt()}, playersPage)
	stack(listFrame, 6)
	local rows = {}

	local function infoFor(p)
		local ch = p.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		local mine = myRoot()
		local parts = {"@" .. p.Name}
		if root and mine and p ~= player then
			parts[#parts + 1] = math.floor((root.Position - mine.Position).Magnitude) .. " studs"
		end
		if hum then
			parts[#parts + 1] = math.floor(hum.Health) .. " HP"
		end
		return table.concat(parts, "  /  ")
	end

	function playersApi.rebuild()
		for _, r in pairs(rows) do
			r.frame:Destroy()
		end
		rows = {}
		local all = Players:GetPlayers()
		if settings.playersOnlyTonyo ~= false and next(online.users or {}) ~= nil then
			local using = {}
			for _, entry in pairs(online.users) do
				if type(entry) == "table" and tonumber(entry.u) then
					using[tonumber(entry.u)] = true
				end
			end
			local kept = {}
			for _, p in ipairs(all) do
				if p == player or using[p.UserId] then
					kept[#kept + 1] = p
				end
			end
			all = kept
		end
		table.sort(all, function(a, b)
			return a.Name:lower() < b.Name:lower()
		end)
		for i, p in ipairs(all) do
			local f = make("Frame", {Name = "Player_" .. p.Name, BackgroundColor3 = C.raised, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 56), LayoutOrder = i}, listFrame)
			corner(f, 6)
			stroke(f, C.ink, 2)
			local av = make("ImageLabel", {
				Name = "Avatar", Size = UDim2.new(0, 40, 0, 40), Position = UDim2.new(0, 8, 0, 8), BackgroundColor3 = C.well,
				BorderSizePixel = 0, Image = "rbxthumb://type=AvatarHeadShot&id=" .. p.UserId .. "&w=100&h=100",
			}, f)
			corner(av, 4)
			stroke(av, C.ink, 2)
			label(f, {name = "Name", text = p.DisplayName, font = F.bold, ts = 13, size = UDim2.new(1, -168, 0, 18), pos = UDim2.new(0, 56, 0, 8)})
			local info = label(f, {name = "Info", text = infoFor(p), ts = 10, color = C.faint, size = UDim2.new(1, -168, 0, 14), pos = UDim2.new(0, 56, 0, 29)})
			if p == player then
				local tag = make("Frame", {Name = "YouTag", Size = UDim2.new(0, 40, 0, 18), Position = UDim2.new(1, -50, 0, 19), BackgroundColor3 = C.yellow, BorderSizePixel = 0, Rotation = 4}, f)
				corner(tag, 3)
				stroke(tag, C.ink, 2)
				label(tag, {name = "YouText", text = "YOU", font = F.head, ts = 11, color = C.yellowInk, align = AX.Center, size = UDim2.new(1, 0, 1, 0)})
			else
				brick(f, {
					name = "GoTo", text = "GO", kind = "blue", ts = 11, size = UDim2.new(0, 42, 0, 26), pos = UDim2.new(1, -100, 0, 15), radius = 4, lipH = 2,
					onClick = function()
						local t = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
						local mine = myRoot()
						if t and mine then
							mine.CFrame = t.CFrame * CFrame.new(0, 0, 4)
							say("Moved next to " .. p.Name)
						else
							toolMsg.Text = "Can't reach " .. p.Name .. " right now."
						end
					end,
				})
				brick(f, {
					name = "ViewPlayer", text = "VIEW", kind = "gray", ts = 11, size = UDim2.new(0, 48, 0, 26), pos = UDim2.new(1, -54, 0, 15), radius = 4, lipH = 2,
					onClick = function()
						local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
						local cam = workspace.CurrentCamera
						if hum and cam then
							cam.CameraSubject = hum
							say("Watching " .. p.Name .. ". Press RESET CAMERA to return.")
						else
							toolMsg.Text = "Can't view " .. p.Name .. " right now."
						end
					end,
				})
			end
			rows[p] = {frame = f, info = info}
		end
	end

	function playersApi.tick()
		values.SERVER.Text = #Players:GetPlayers() .. "/" .. Players.MaxPlayers
		values.USING.Text = online.count and tostring(online.count) or "-"
		values.FPS.Text = tostring(math.floor(fps + 0.5))
		local okP, ping = pcall(function()
			return math.floor(player:GetNetworkPing() * 2000 + 0.5)
		end)
		values.PING.Text = okP and (ping .. "ms") or "-"
		local t = math.floor(workspace.DistributedGameTime)
		values.UPTIME.Text = string.format("%d:%02d:%02d", math.floor(t / 3600), math.floor(t / 60) % 60, t % 60)
		for p, r in pairs(rows) do
			if p.Parent then
				r.info.Text = infoFor(p)
			end
		end
	end

	conns[#conns + 1] = Players.PlayerAdded:Connect(function()
		refreshCounter()
		if playersPage.Visible then
			playersApi.rebuild()
		end
	end)
	conns[#conns + 1] = Players.PlayerRemoving:Connect(function()
		task.defer(function()
			refreshCounter()
			if playersPage.Visible then
				playersApi.rebuild()
			end
		end)
	end)
	task.spawn(function()
		while gui.Parent do
			task.wait(1)
			refreshCounter()
			if playersPage.Visible then
				pcall(playersApi.tick)
			end
		end
	end)
end

local auditPage = make("ScrollingFrame", {
	Name = "AuditPage", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 4, ScrollBarImageColor3 = C.scroll, CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = AUTO_Y, ScrollingDirection = Enum.ScrollingDirection.Y, Visible = false,
}, body)
do
	pad(auditPage, 10, 6, 12, 14)
	stack(auditPage, 8)
	local order = 0
	local function nxt()
		order = order + 1
		return order
	end
	label(auditPage, {
		name = "AuditIntro", text = "Every script listed here is sent to every player, so anyone can read or copy it. Move important logic into ServerScriptService or ServerStorage, where players can never see it.",
		ts = 11, color = C.sub, wrap = true, size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = nxt(),
	})
	local actions = make("Frame", {Name = "AuditActions", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = nxt()}, auditPage)
	stack(actions, 6, true)
	local stats = label(auditPage, {name = "AuditStats", text = "No audit yet", font = F.med, ts = 11, color = C.faint, wrap = true, size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = nxt()})
	local outWrap = make("Frame", {Name = "AuditOutput", BackgroundColor3 = C.code, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, LayoutOrder = nxt()}, auditPage)
	corner(outWrap, 6)
	stroke(outWrap, C.ink, 2)
	local outBox = make("TextBox", {
		Name = "AuditText", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y,
		Text = "Press SCAN to list every script players can read.", TextColor3 = C.codeText, TextSize = 11, Font = F.code,
		TextWrapped = true, MultiLine = true, ClearTextOnFocus = false, TextEditable = false,
		TextXAlignment = AX.Left, TextYAlignment = Enum.TextYAlignment.Top,
	}, outWrap)
	pad(outBox, 10, 8, 10, 8)
	local full = ""
	local busyScan = false

	local function runAudit()
		local roots = {
			workspace, game:GetService("ReplicatedStorage"), game:GetService("ReplicatedFirst"), game:GetService("StarterGui"),
			game:GetService("StarterPack"), game:GetService("StarterPlayer"), game:GetService("Lighting"), game:GetService("SoundService"),
			player:FindFirstChildOfClass("PlayerGui"), player:FindFirstChild("PlayerScripts"), player:FindFirstChild("Backpack"),
		}
		local ownFolder = workspace:FindFirstChild("TONYO_Scripts")
		local found, n = {}, 0
		local counts = {LocalScript = 0, Script = 0, ModuleScript = 0}
		for _, root in ipairs(roots) do
			if root then
				for _, d in ipairs(root:GetDescendants()) do
					n = n + 1
					if n % 300 == 0 then
						task.wait()
					end
					if d:IsA("LuaSourceContainer") and not (ownFolder and d:IsDescendantOf(ownFolder)) then
						local size
						pcall(function()
							size = #d.Source
						end)
						counts[d.ClassName] = (counts[d.ClassName] or 0) + 1
						found[#found + 1] = {class = d.ClassName, path = d:GetFullName(), size = size}
					end
				end
			end
		end
		table.sort(found, function(a, b)
			return (a.size or -1) > (b.size or -1)
		end)
		local lines = {}
		for i, f in ipairs(found) do
			if i > 120 then
				lines[#lines + 1] = "... and " .. (#found - 120) .. " more"
				break
			end
			local sizeText = f.size and (f.size .. " chars" .. (f.size > 3000 and "  BIG" or "")) or "source hidden"
			lines[#lines + 1] = "[" .. f.class .. "] " .. f.path .. "  (" .. sizeText .. ")"
		end
		return table.concat(lines, "\n"), #found, counts
	end

	local scanBtn
	scanBtn = brick(actions, {
		name = "AuditScan", text = "SCAN", kind = "blue", ts = 13, size = UDim2.new(0, 86, 0, 30), order = 1,
		onClick = function()
			if busyScan then
				return
			end
			busyScan = true
			scanBtn.Text = "..."
			task.spawn(function()
				local ok, text, total, counts = pcall(runAudit)
				if ok then
					full = text
					outBox.Text = #text > 6000 and (text:sub(1, 6000) .. "\n... [cut, COPY has the full list]") or (text ~= "" and text or "No scripts found.")
					stats.Text = string.format("%d scripts readable by players  /  LocalScript %d  /  ModuleScript %d  /  Script %d", total, counts.LocalScript or 0, counts.ModuleScript or 0, counts.Script or 0)
					stats.TextColor3 = total > 0 and C.amber or C.green
					view.log("Audit: " .. total .. " scripts readable by players", total > 0 and "warn" or "ok")
				else
					stats.Text = "Audit failed: " .. tostring(text)
					stats.TextColor3 = C.redText
				end
				scanBtn.Text = "SCAN"
				busyScan = false
			end)
		end,
	})
	brick(actions, {
		name = "AuditCopy", text = "COPY LIST", kind = "green", ts = 13, size = UDim2.new(0, 100, 0, 30), order = 2,
		onClick = function()
			if full ~= "" then
				view.copy(full)
			else
				view.flash("Scan first")
			end
		end,
	})
end

local adminPage = make("ScrollingFrame", {
	Name = "AdminPage", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 4, ScrollBarImageColor3 = C.scroll, CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = AUTO_Y, ScrollingDirection = Enum.ScrollingDirection.Y, Visible = false,
}, body)
if isAdmin() then
	pad(adminPage, 10, 6, 12, 14)
	stack(adminPage, 8)
	local order = 0
	local function nxt()
		order = order + 1
		return order
	end
	local function heading(text)
		local h = make("Frame", {Name = "Heading", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = nxt()}, adminPage)
		label(h, {name = "HeadingText", text = text:upper(), font = F.head, ts = 14, color = C.yellow, size = UDim2.new(1, 0, 0, 22), pos = UDim2.new(0, 2, 0, 1)})
		make("Frame", {Name = "HeadingLine", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = C.ink, BorderSizePixel = 0}, h)
	end

	label(adminPage, {
		name = "AdminWarn", text = "Owner tools. Only your account and ipoge6 can see this tab. Restart and announce reach everyone running TONYO, in any game, within about 20 seconds.",
		ts = 11, color = C.sub, wrap = true, size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = nxt(),
	})
	label(adminPage, {
		name = "ReloadNote",
		text = SCRIPT_URL:gsub("%s", "") == "" and "SCRIPT_URL is empty, so Restart only resets each player's window, not their code. Set SCRIPT_URL at the top of the script to a raw link of your latest file to make Restart pull the update too, no rejoin needed."
			or "SCRIPT_URL is set. Restart will fetch that link and run it fresh for everyone, which also delivers a code update, no rejoin needed. If the fetch fails, it falls back to a normal reset.",
		ts = 11, color = SCRIPT_URL:gsub("%s", "") == "" and C.amber or C.green, wrap = true, size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = nxt(),
	})

	heading("Who is using TONYO")
	local userList = make("Frame", {Name = "UserList", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, LayoutOrder = nxt()}, adminPage)
	stack(userList, 6)
	local userStats = label(adminPage, {name = "UserStats", ts = 11, color = C.faint, wrap = true, size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = nxt()})

	local function rebuildUsers()
		for _, c in ipairs(userList:GetChildren()) do
			c:Destroy()
		end
		local rows = {}
		for id, u in pairs(online.users or {}) do
			if type(u) == "table" then
				rows[#rows + 1] = {id = id, n = type(u.n) == "string" and u.n or "unknown", u = u.u, p = u.p, t = tonumber(u.t) or 0}
			end
		end
		table.sort(rows, function(a, b)
			return a.t > b.t
		end)
		for i, r in ipairs(rows) do
			if i > 100 then
				break
			end
			local f = make("Frame", {Name = "User" .. i, BackgroundColor3 = C.raised, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = i}, userList)
			corner(f, 5)
			stroke(f, C.ink, 2)
			local ago = math.max(0, math.floor(os.time() - r.t / 1000))
			local agoText = ago < 60 and (ago .. "s ago") or (math.floor(ago / 60) .. "m ago")
			label(f, {name = "Name", text = r.n, font = F.bold, ts = 12, size = UDim2.new(0.5, -8, 0, 18), pos = UDim2.new(0, 10, 0, 6)})
			label(f, {name = "Meta", text = "id " .. tostring(r.u or "?") .. "  /  place " .. tostring(r.p or "?"), ts = 10, color = C.faint, size = UDim2.new(0.5, -8, 0, 14), pos = UDim2.new(0, 10, 0, 22)})
			label(f, {name = "Ago", text = agoText, font = F.med, ts = 11, color = C.green, align = AX.Right, size = UDim2.new(0.5, -10, 1, 0), pos = UDim2.new(0.5, 0, 0, 0)})
		end
		userStats.Text = #rows .. " devices seen in the last 2.5 minutes  /  status: " .. online.status
	end

	brick(adminPage, {
		name = "RefreshUsers", text = "REFRESH", kind = "blue", ts = 12, size = UDim2.new(0, 84, 0, 26), order = nxt(),
		onClick = function()
			online.refresh()
			rebuildUsers()
		end,
	})

	heading("Announce")
	local annLine = make("Frame", {Name = "AnnLine", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = nxt()}, adminPage)
	local annBox = textBox(annLine, {name = "AnnounceBox", placeholder = "Message shown to everyone for a few seconds", size = UDim2.new(1, -74, 1, 0)})
	local annMsg = label(adminPage, {name = "AnnounceMsg", ts = 11, color = C.sub, wrap = true, size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = nxt()})
	brick(annLine, {
		name = "AnnounceSend", text = "SEND", kind = "yellow", ts = 12, size = UDim2.new(0, 68, 1, 0), pos = UDim2.new(1, -68, 0, 0),
		onClick = function()
			local t = annBox.Text
			local ok = online.sendAnnounce(t)
			annMsg.Text = ok and "Sent." or "Couldn't send. Check the database is set up."
			annMsg.TextColor3 = ok and C.green or C.redText
			if ok then
				annBox.Text = ""
			end
		end,
	})

	heading("Restart everyone")
	local restartLine = make("Frame", {Name = "RestartLine", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = nxt()}, adminPage)
	local minBox = textBox(restartLine, {name = "MinutesBox", placeholder = "Minutes, default 1", size = UDim2.new(0.5, -4, 1, 0)})
	local restartMsg = label(adminPage, {name = "RestartMsg", ts = 11, color = C.sub, wrap = true, size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = nxt()})
	brick(restartLine, {
		name = "ScheduleRestart", text = "SCHEDULE", kind = "red", ts = 12, size = UDim2.new(0.5, -4, 1, 0), pos = UDim2.new(0.5, 4, 0, 0),
		onClick = function()
			local ok = online.scheduleRestart(minBox.Text ~= "" and minBox.Text or 1)
			restartMsg.Text = ok and "Scheduled. Everyone will see a countdown and restart." or "Couldn't schedule. Check the database is set up."
			restartMsg.TextColor3 = ok and C.green or C.redText
		end,
	})
	brick(adminPage, {
		name = "CancelRestart", text = "CANCEL SCHEDULED RESTART", kind = "gray", ts = 12, size = UDim2.new(0, 190, 0, 26), order = nxt(),
		onClick = function()
			local ok = online.cancelRestart()
			restartMsg.Text = ok and "Cancelled." or "Couldn't cancel."
			restartMsg.TextColor3 = ok and C.sub or C.redText
		end,
	})

	task.spawn(function()
		while gui.Parent do
			task.wait(2)
			if adminPage.Visible then
				online.refresh()
				rebuildUsers()
			end
		end
	end)
end

local picker = {}
do
	local overlay = make("Frame", {
		Name = "Picker", Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = C.window, BorderSizePixel = 0,
		Visible = false, ZIndex = 30, Active = true,
	}, body)
	brick(overlay, {
		name = "PickerBack", text = "BACK", kind = "gray", ts = 12,
		size = UDim2.new(0, 60, 0, 26), pos = UDim2.new(0, 8, 0, 5),
		onClick = function()
			picker.close()
		end,
	})
	local title = label(overlay, {
		name = "PickerTitle", font = F.head, ts = 15, align = AX.Center, color = C.yellow,
		size = UDim2.new(1, -150, 0, 36), pos = UDim2.new(0, 75, 0, 0),
	})
	make("Frame", {Name = "PickerEdge", Position = UDim2.new(0, 0, 0, 38), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = C.ink, BorderSizePixel = 0}, overlay)
	local filter = textBox(overlay, {name = "PickerFilter", size = UDim2.new(1, -16, 0, 30), pos = UDim2.new(0, 8, 0, 48)})
	local note = label(overlay, {name = "PickerNote", ts = 11, color = C.faint, size = UDim2.new(1, -20, 0, 16), pos = UDim2.new(0, 10, 0, 82)})
	local scroll = make("ScrollingFrame", {
		Name = "PickerList", BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
		ScrollBarImageColor3 = C.scroll, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = AUTO_Y,
	}, overlay)
	pad(scroll, 0, 2, 4, 2)
	stack(scroll, 4)
	local state = {items = {}, filterOn = false, note = ""}

	local function layout()
		local top = state.filterOn and 104 or 66
		filter.Visible = state.filterOn
		note.Position = UDim2.new(0, 10, 0, state.filterOn and 82 or 46)
		note.Visible = state.note ~= ""
		scroll.Position = UDim2.new(0, 8, 0, top)
		scroll.Size = UDim2.new(1, -16, 1, -(top + 6))
	end

	function picker.render()
		for _, c in ipairs(scroll:GetChildren()) do
			if c:IsA("TextButton") then
				c:Destroy()
			end
		end
		local q = ""
		if state.filterOn then
			q = (filter.Text:lower():gsub("^%s+", ""):gsub("%s+$", ""))
		end
		local shown, matched = 0, 0
		for i, it in ipairs(state.items) do
			local hay = (it.label .. " " .. (it.sub or "")):lower()
			if q == "" or hay:find(q, 1, true) then
				matched = matched + 1
				if shown < 80 then
					shown = shown + 1
					local b = make("TextButton", {
						Name = "Pick_" .. i, Text = "", AutoButtonColor = false, BackgroundColor3 = C.raised,
						BackgroundTransparency = it.selected and 0 or 1, BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, it.sub and 48 or 36), LayoutOrder = i,
					}, scroll)
					corner(b, 5)
					if it.selected then
						stroke(b, C.yellow, 2)
					else
						b.InputBegan:Connect(function(input)
							if isPress(input) then
								b.BackgroundTransparency = 0.4
							end
						end)
						b.InputEnded:Connect(function(input)
							if isPress(input) then
								b.BackgroundTransparency = 1
							end
						end)
					end
					label(b, {
						name = "PickLabel", text = it.label, font = F.bold, ts = 12,
						size = UDim2.new(1, -44, 0, 18), pos = UDim2.new(0, 12, 0, it.sub and 7 or 9),
					})
					if it.sub then
						label(b, {
							name = "PickSub", text = it.sub, ts = 11, color = C.faint,
							size = UDim2.new(1, -44, 0, 14), pos = UDim2.new(0, 12, 0, 26),
						})
					end
					if it.selected then
						local mark = make("Frame", {
							Name = "PickMark", Size = UDim2.new(0, 10, 0, 10), AnchorPoint = Vector2.new(1, 0.5),
							Position = UDim2.new(1, -12, 0.5, 0), BackgroundColor3 = C.yellow, BorderSizePixel = 0, Rotation = 45,
						}, b)
						stroke(mark, C.ink, 1)
					end
					b.Activated:Connect(function()
						if state.onPick then
							state.onPick(it.value)
						end
					end)
				end
			end
		end
		local extra = ""
		if matched > shown then
			extra = string.format("Showing %d of %d. Type to narrow the list.", shown, matched)
		end
		note.Text = extra ~= "" and extra or state.note
		note.Visible = note.Text ~= ""
	end

	function picker.open(o)
		state.items = o.items or {}
		state.onPick = o.onPick
		state.onEnter = o.onEnter
		state.filterOn = o.filter == true
		state.note = o.note or ""
		title.Text = (o.title or ""):upper()
		filter.Text = ""
		filter.PlaceholderText = o.placeholder or ""
		layout()
		overlay.Visible = true
		picker.render()
	end

	function picker.update(items, noteText)
		state.items = items
		state.note = noteText or ""
		layout()
		picker.render()
	end

	function picker.close()
		overlay.Visible = false
	end

	filter:GetPropertyChangedSignal("Text"):Connect(function()
		picker.render()
	end)
	filter.FocusLost:Connect(function(enter)
		if enter and state.onEnter then
			local t = filter.Text:gsub("^%s+", ""):gsub("%s+$", "")
			if t ~= "" then
				state.onEnter(t)
			end
		end
	end)
end

-- BUILD tab: auto tools, a small explorer, a properties panel and animation presets.
;(function()
	local page = make("ScrollingFrame", {
		Name = "BuildPage", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 4, ScrollBarImageColor3 = C.scroll, CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = AUTO_Y, ScrollingDirection = Enum.ScrollingDirection.Y, Visible = false,
	}, body)
	TX.buildPage = page
	pad(page, 10, 6, 12, 14)
	stack(page, 8)

	local order = 0
	local function nxt()
		order = order + 1
		return order
	end

	local function heading(text)
		local h = make("Frame", {Name = "Heading", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = nxt()}, page)
		label(h, {name = "HeadingText", text = text:upper(), font = F.head, ts = 14, color = C.yellow, size = UDim2.new(1, 0, 0, 22), pos = UDim2.new(0, 2, 0, 1)})
		make("Frame", {Name = "HeadingLine", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = C.ink, BorderSizePixel = 0}, h)
	end

	local function note(text)
		return label(page, {name = "Note", text = text, ts = 11, color = C.sub, wrap = true, size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = nxt()})
	end

	local function group()
		local g = make("Frame", {Name = "Group", BackgroundColor3 = C.raised, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, LayoutOrder = nxt()}, page)
		corner(g, 6)
		stroke(g, C.ink, 2)
		stack(g, 0)
		return g
	end

	local function isOn(key)
		if key == "autoRun" then
			return settings[key] == true
		end
		return settings[key] ~= false
	end

	local function toggleRow(g, idx, text, key)
		local b = make("TextButton", {
			Name = "Toggle_" .. key, Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
			BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = idx,
		}, g)
		label(b, {name = "RowLabel", text = text, font = F.head, ts = 12, color = C.sub, size = UDim2.new(0.72, 0, 1, 0), pos = UDim2.new(0, 12, 0, 0)})
		local value = label(b, {name = "Value", font = F.bold, ts = 12, align = AX.Right, size = UDim2.new(0.28, -24, 1, 0), pos = UDim2.new(0.72, 0, 0, 0)})
		make("Frame", {Name = "Divider", BackgroundColor3 = C.line, BorderSizePixel = 0, Size = UDim2.new(1, -24, 0, 1), Position = UDim2.new(0, 12, 1, -1)}, b)
		local function paintValue()
			local on = isOn(key)
			value.Text = on and "ON" or "OFF"
			value.TextColor3 = on and C.green or C.faint
		end
		paintValue()
		b.Activated:Connect(function()
			settings[key] = not isOn(key)
			saveSettings()
			paintValue()
		end)
	end

	heading("Auto tools")
	local tools = group()
	toggleRow(tools, 1, "AUTO ANCHOR", "autoAnchor")
	toggleRow(tools, 2, "AUTO COLLIDE", "autoCollide")
	toggleRow(tools, 3, "AUTO ANIMATE", "autoAnimate")
	toggleRow(tools, 4, "AUTO PLACE SCRIPTS", "autoPlace")
	toggleRow(tools, 5, "AUTO RUN CLIENT CODE", "autoRun")
	note("Anchor and collide fix every part the AI builds, with ops or with code it runs. Rigged creatures keep their joints, and if the AI code sets Anchored = false or CanCollide = false itself, it is left alone. Auto animate tells the AI to add movement (spin, bob, swing, pulse, slide) by itself.")
	note("Auto place saves the AI's server code to workspace/TONYO_Scripts and places Script and LocalScript objects in Workspace.TONYO_Scripts. A client executor cannot run server scripts, so the server half only works after you paste it into your own game in Studio. Client code runs on your device only. Auto run runs labeled client code the moment the AI sends it.")

	-- ---------- explorer ----------
	local cur = workspace:FindFirstChild("TONYO_Spawns") or workspace
	local sel = nil
	local rows = {}
	local rebuild, updateInfo, choose

	local function eachPart(inst, fn)
		if inst:IsA("BasePart") then
			fn(inst)
		end
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then
				fn(d)
			end
		end
	end

	local function isProtected(inst)
		if inst == workspace or inst == game or inst:IsA("Terrain") or inst == workspace.CurrentCamera then
			return true
		end
		if inst:IsA("Model") and Players:GetPlayerFromCharacter(inst) then
			return true
		end
		return false
	end

	local function tagOf(inst)
		if inst:IsA("Folder") then
			return "DIR"
		elseif inst:IsA("Model") then
			return "MDL"
		elseif inst:IsA("BasePart") then
			return "PRT"
		elseif inst:IsA("LuaSourceContainer") then
			return "SCR"
		end
		return inst.ClassName:sub(1, 3):upper()
	end

	local function canEnter(inst)
		return #inst:GetChildren() > 0 and not inst:IsA("LuaSourceContainer")
	end

	heading("Explorer")
	local nav = make("Frame", {Name = "Nav", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = nxt()}, page)
	stack(nav, 6, true)
	local pathLabel = label(page, {name = "Path", text = "", ts = 11, color = C.faint, wrap = true, size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = nxt()})

	local listFrame = make("ScrollingFrame", {
		Name = "List", BackgroundColor3 = C.well, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 170),
		ScrollBarThickness = 4, ScrollBarImageColor3 = C.scroll, CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = AUTO_Y, ScrollingDirection = Enum.ScrollingDirection.Y, LayoutOrder = nxt(),
	}, page)
	corner(listFrame, 6)
	stroke(listFrame, C.ink, 2)
	stack(listFrame, 0)

	function rebuild()
		for _, r in ipairs(rows) do
			r:Destroy()
		end
		rows = {}
		if not (cur and cur.Parent) then
			cur = workspace
		end
		pathLabel.Text = cur == workspace and "Workspace" or cur:GetFullName()
		local kids = {}
		for _, k in ipairs(cur:GetChildren()) do
			if k.Name ~= "TONYO_Flash" then
				kids[#kids + 1] = k
			end
		end
		table.sort(kids, function(a, b)
			local ca = (a:IsA("Folder") or a:IsA("Model")) and 0 or 1
			local cb = (b:IsA("Folder") or b:IsA("Model")) and 0 or 1
			if ca ~= cb then
				return ca < cb
			end
			return a.Name:lower() < b.Name:lower()
		end)
		local shown = math.min(#kids, 80)
		for i = 1, shown do
			local kid = kids[i]
			local picked = kid == sel
			local row = make("TextButton", {
				Name = "Row", Text = "", AutoButtonColor = false, BorderSizePixel = 0,
				BackgroundColor3 = C.raisedHi, BackgroundTransparency = picked and 0.3 or 1,
				Size = UDim2.new(1, 0, 0, 28), LayoutOrder = i,
			}, listFrame)
			label(row, {name = "Tag", text = tagOf(kid), font = F.head, ts = 10, color = C.faint, size = UDim2.new(0, 34, 1, 0), pos = UDim2.new(0, 8, 0, 0)})
			label(row, {name = "Name", text = kid.Name, font = F.med, ts = 12, color = picked and C.yellow or C.text, size = UDim2.new(1, -90, 1, 0), pos = UDim2.new(0, 44, 0, 0)})
			row.Activated:Connect(function()
				choose(kid)
			end)
			if canEnter(kid) then
				local go = make("TextButton", {
					Name = "Enter", Text = ">", Font = F.head, TextSize = 14, TextColor3 = C.yellow,
					BackgroundTransparency = 1, Size = UDim2.new(0, 34, 1, 0), Position = UDim2.new(1, -36, 0, 0),
				}, row)
				go.Activated:Connect(function()
					cur = kid
					rebuild()
				end)
			end
			rows[#rows + 1] = row
		end
		if #kids == 0 then
			rows[#rows + 1] = label(listFrame, {name = "Empty", text = "Nothing here yet.", ts = 11, color = C.faint, size = UDim2.new(1, 0, 0, 28), pos = UDim2.new(0, 10, 0, 0), order = 1})
		elseif #kids > shown then
			rows[#rows + 1] = label(listFrame, {name = "More", text = "+ " .. (#kids - shown) .. " more not shown", ts = 11, color = C.faint, size = UDim2.new(1, 0, 0, 24), pos = UDim2.new(0, 10, 0, 0), order = 1000})
		end
	end

	local function navButton(text, w, fn)
		brick(nav, {name = "Nav_" .. text, text = text, kind = "gray", ts = 11, size = UDim2.new(0, w, 0, 26), onClick = fn})
	end
	navButton("SPAWNS", 62, function()
		local f = workspace:FindFirstChild("TONYO_Spawns")
		if f then
			cur = f
			rebuild()
		end
	end)
	navButton("WORLD", 56, function()
		cur = workspace
		rebuild()
	end)
	navButton("ME", 40, function()
		if player.Character then
			cur = player.Character
			rebuild()
		end
	end)
	navButton("UP", 40, function()
		if cur and cur ~= workspace and cur.Parent then
			cur = cur.Parent == game and workspace or cur.Parent
			rebuild()
		end
	end)

	-- ---------- selected object ----------
	heading("Selected")
	local infoCard = make("Frame", {Name = "Info", BackgroundColor3 = C.well, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, LayoutOrder = nxt()}, page)
	corner(infoCard, 6)
	stroke(infoCard, C.ink, 2)
	pad(infoCard, 10, 8, 10, 8)
	stack(infoCard, 3)
	local infoTitle = label(infoCard, {name = "Title", text = "Nothing selected", font = F.bold, ts = 13, color = C.yellow, wrap = true, size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = 1})
	local infoBody = label(infoCard, {name = "Body", text = "Tap a row in the list above.", ts = 11, color = C.sub, wrap = true, size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = 2})
	local status = label(page, {name = "Status", text = "", ts = 11, color = C.sub, wrap = true, size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = nxt()})

	local function setStatus(text, color)
		status.Text = text
		status.TextColor3 = color or C.sub
	end

	function updateInfo()
		if not (sel and sel.Parent) then
			sel = nil
			infoTitle.Text = "Nothing selected"
			infoBody.Text = "Tap a row in the list above."
			return
		end
		local total, anch, col = 0, 0, 0
		eachPart(sel, function(p)
			total = total + 1
			if p.Anchored or (p.AssemblyRootPart and p.AssemblyRootPart.Anchored) then
				anch = anch + 1
			end
			if p.CanCollide then
				col = col + 1
			end
		end)
		local function state(n)
			if total == 0 then
				return "-"
			elseif n == total then
				return "ON"
			elseif n == 0 then
				return "OFF"
			end
			return "MIXED"
		end
		infoTitle.Text = sel.Name .. "  [" .. sel.ClassName .. "]"
		infoBody.Text = sel:GetFullName() .. "\nParts: " .. total .. "    Anchored: " .. state(anch) .. "    Can collide: " .. state(col)
			.. "\nAnimated: " .. ((TX.anim and TX.anim.active[sel]) and "yes" or "no")
	end

	function choose(inst)
		sel = inst
		rebuild()
		updateInfo()
		setStatus("", C.sub)
	end

	local function needSel()
		if sel and sel.Parent then
			return true
		end
		setStatus("Select something in the list first.", C.amber)
		return false
	end

	local function changed(text)
		updateInfo()
		setStatus(text, C.green)
		view.log("BUILD " .. text .. " (" .. (sel and sel.Name or "?") .. ")", "ok")
	end

	local function actionGrid(cols, items)
		local f = make("Frame", {Name = "Grid", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, LayoutOrder = nxt()}, page)
		make("UIGridLayout", {
			CellSize = UDim2.new(1 / cols, -(6 * (cols - 1)) / cols, 0, 30),
			CellPadding = UDim2.new(0, 6, 0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
		}, f)
		for i, it in ipairs(items) do
			brick(f, {name = "Act_" .. it.text, text = it.text, kind = it.kind or "gray", ts = 11, order = i, onClick = it.fn})
		end
	end

	actionGrid(2, {
		{text = "ANCHOR", kind = "green", fn = function()
			if needSel() then
				eachPart(sel, function(p)
					p.Anchored = true
				end)
				changed("anchored")
			end
		end},
		{text = "UNANCHOR", fn = function()
			if needSel() then
				eachPart(sel, function(p)
					p.Anchored = false
				end)
				changed("unanchored")
			end
		end},
		{text = "CAN COLLIDE", kind = "green", fn = function()
			if needSel() then
				eachPart(sel, function(p)
					p.CanCollide = true
				end)
				changed("can collide on")
			end
		end},
		{text = "NO COLLIDE", fn = function()
			if needSel() then
				eachPart(sel, function(p)
					p.CanCollide = false
				end)
				changed("can collide off")
			end
		end},
		{text = "GO TO", kind = "blue", fn = function()
			if not needSel() then
				return
			end
			local ok = pcall(function()
				local cf = sel:GetPivot()
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if root then
					root.CFrame = CFrame.new(cf.Position + Vector3.new(0, 6, 16), cf.Position)
				else
					workspace.CurrentCamera.CFrame = CFrame.lookAt(cf.Position + Vector3.new(0, 10, 24), cf.Position)
				end
			end)
			setStatus(ok and "Moved you next to it." or "Can't go to that kind of object.", ok and C.green or C.redText)
		end},
		{text = "CLONE", kind = "blue", fn = function()
			if not needSel() then
				return
			end
			local ok, copy = pcall(function()
				return sel:Clone()
			end)
			if ok and copy then
				pcall(function()
					copy.Parent = sel.Parent
					copy:PivotTo(sel:GetPivot() + Vector3.new(6, 0, 0))
				end)
				rebuild()
				setStatus("Cloned " .. sel.Name .. ".", C.green)
			else
				setStatus("That object can't be cloned.", C.redText)
			end
		end},
		{text = "COPY PATH", fn = function()
			if needSel() then
				if setclipboard then
					setclipboard(sel:GetFullName())
					setStatus("Path copied.", C.green)
				else
					setStatus(sel:GetFullName(), C.sub)
				end
			end
		end},
		{text = "DELETE", kind = "red", fn = function()
			if not needSel() then
				return
			end
			if isProtected(sel) then
				setStatus("That one is protected.", C.redText)
				return
			end
			local nm = sel.Name
			if TX.anim then
				TX.anim.stop(sel, true)
			end
			pcall(function()
				sel:Destroy()
			end)
			sel = nil
			rebuild()
			updateInfo()
			setStatus("Deleted " .. nm .. " (only on your screen).", C.green)
			view.log("BUILD deleted " .. nm, "warn")
		end},
	})

	heading("Animate")
	local function animate(kind)
		if not needSel() then
			return
		end
		local ok, res = pcall(TX.anim.start, sel, kind, {})
		if ok then
			changed("animation " .. tostring(res))
		else
			local msg = tostring(res):gsub("^.-:%d+: ", "")
			setStatus(msg, C.redText)
		end
	end
	actionGrid(3, {
		{text = "SPIN", kind = "yellow", fn = function() animate("spin") end},
		{text = "BOB", kind = "yellow", fn = function() animate("bob") end},
		{text = "SWING", kind = "yellow", fn = function() animate("swing") end},
		{text = "PULSE", kind = "yellow", fn = function() animate("pulse") end},
		{text = "SLIDE", kind = "yellow", fn = function() animate("slide") end},
		{text = "STOP", kind = "gray", fn = function()
			if needSel() then
				TX.anim.stop(sel)
				changed("animation stopped")
			end
		end},
	})
	note("Presets stack: tap SPIN and BOB on the same object and it does both. Animations only exist on your screen and stop when you close TONYO.")

	function TX.buildRefresh()
		rebuild()
		updateInfo()
	end
end)()

-- GLOBAL tab: chat with everyone using TONYO, plus the list of who is online.
;(function()
	local page = make("Frame", {Name = "GlobalPage", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Visible = false}, body)
	TX.globalPage = page

	local mode = "chat"
	local unread = 0
	local seen, rowsByKey, muted = {}, {}, {}
	local firstLoad = true
	local lastSend = 0
	local orderN = 0
	local onlineRows = {}
	local flashText = nil

	local function joined()
		return settings.globalChat == true and settings.ping ~= false
	end

	local function avatarUrl(uid)
		uid = tonumber(uid)
		if not uid or uid < 1 then
			return ""
		end
		return "rbxthumb://type=AvatarHeadShot&id=" .. math.floor(uid) .. "&w=100&h=100"
	end

	local function cleanName(v, fallback)
		if type(v) ~= "string" then
			return fallback
		end
		v = v:gsub("%c", ""):sub(1, 40)
		if v == "" then
			return fallback
		end
		return v
	end

	local function cleanText(v)
		return (tostring(v):gsub("%c", " "):sub(1, 300))
	end

	-- ---------- top row ----------
	local top = make("Frame", {Name = "Top", BackgroundTransparency = 1, Size = UDim2.new(1, -24, 0, 28), Position = UDim2.new(0, 12, 0, 6)}, page)
	stack(top, 6, true)
	local chatBtn = brick(top, {name = "ModeChat", text = "CHAT", kind = "yellow", ts = 11, size = UDim2.new(0, 56, 0, 26), order = 1})
	local onlineBtn = brick(top, {name = "ModeOnline", text = "ONLINE", kind = "gray", ts = 11, size = UDim2.new(0, 64, 0, 26), order = 2})
	local countLabel = label(top, {name = "Count", text = "", ts = 11, color = C.faint, size = UDim2.new(1, -190, 1, 0), order = 3})
	local leaveBtn = brick(top, {name = "Leave", text = "LEAVE", kind = "gray", ts = 10, size = UDim2.new(0, 54, 0, 26), order = 4})

	-- ---------- areas ----------
	local area = make("Frame", {Name = "Area", BackgroundTransparency = 1, Size = UDim2.new(1, -24, 1, -82), Position = UDim2.new(0, 12, 0, 38), ClipsDescendants = true}, page)

	local function scroller(name)
		local sf = make("ScrollingFrame", {
			Name = name, BackgroundColor3 = C.well, BorderSizePixel = 0, Size = UDim2.new(1, 0, 1, 0),
			ScrollBarThickness = 4, ScrollBarImageColor3 = C.scroll, CanvasSize = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize = AUTO_Y, ScrollingDirection = Enum.ScrollingDirection.Y,
		}, area)
		corner(sf, 6)
		stroke(sf, C.ink, 2)
		pad(sf, 8, 8, 8, 8)
		stack(sf, 8)
		return sf
	end
	local msgScroll = scroller("Messages")
	local onlineScroll = scroller("OnlineList")
	onlineScroll.Visible = false

	local gate = make("Frame", {Name = "Gate", BackgroundColor3 = C.raised, BorderSizePixel = 0, Size = UDim2.new(1, 0, 1, 0), ZIndex = 5}, area)
	corner(gate, 6)
	stroke(gate, C.ink, 2)
	pad(gate, 14, 12, 14, 12)
	stack(gate, 8)
	label(gate, {name = "GateTitle", text = "JOIN GLOBAL CHAT", font = F.head, ts = 16, color = C.yellow, size = UDim2.new(1, 0, 0, 22), order = 1})
	label(gate, {
		name = "GateText", ts = 11, color = C.sub, wrap = true, size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = 2,
		text = "Chat with everyone using TONYO, in any game. Your Roblox name, display name and avatar picture are shown next to every message and in the online list. Every message is checked by Roblox's own filter before it is sent and again before anyone sees it, so a message that can't be verified as safe is quietly skipped instead of shown. Still, be kind and never share personal info, and use MUTE on anyone who bothers you. Joining also turns on the online counter in Setup.",
	})

	local inputRow = make("Frame", {Name = "InputRow", BackgroundTransparency = 1, Size = UDim2.new(1, -24, 0, 34), Position = UDim2.new(0, 12, 1, -40)}, page)
	local input = make("TextBox", {
		Name = "ChatInput", BackgroundColor3 = C.well, BorderSizePixel = 0, Font = F.reg, TextSize = 12, TextColor3 = C.text,
		PlaceholderText = "Message everyone using TONYO", PlaceholderColor3 = C.faint, Text = "", ClearTextOnFocus = false,
		TextXAlignment = AX.Left, Size = UDim2.new(1, -70, 1, 0),
	}, inputRow)
	corner(input, 6)
	stroke(input, C.ink, 2)
	pad(input, 8, 0, 8, 0)
	local sendBtn = brick(inputRow, {name = "ChatSend", text = "SEND", kind = "yellow", ts = 12, size = UDim2.new(0, 62, 1, 0), pos = UDim2.new(1, -62, 0, 0)})

	-- ---------- helpers ----------
	local function refreshCount()
		if flashText then
			countLabel.Text = flashText
			return
		end
		local n = 0
		for _ in pairs(online.users or {}) do
			n = n + 1
		end
		if not joined() then
			countLabel.Text = ""
		else
			countLabel.Text = math.max(n, 1) .. " online"
		end
	end

	local function flash(text)
		flashText = text
		refreshCount()
		task.delay(3, function()
			if flashText == text then
				flashText = nil
				refreshCount()
			end
		end)
	end

	local function refreshGate()
		local ok = joined()
		gate.Visible = not ok
		inputRow.Visible = ok and mode == "chat"
		leaveBtn.Visible = ok
		refreshCount()
	end

	local function scrollBottom()
		msgScroll.CanvasPosition = Vector2.new(0, math.max(0, msgScroll.AbsoluteCanvasSize.Y - msgScroll.AbsoluteSize.Y))
	end

	local function addMessage(key, m)
		orderN = orderN + 1
		local uid = tonumber(m.u)
		local handle = cleanName(m.n, "player")
		local name = cleanName(m.d, handle)
		local mine = uid == player.UserId

		local row = make("Frame", {Name = "Msg", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, LayoutOrder = orderN}, msgScroll)
		make("UISizeConstraint", {MinSize = Vector2.new(0, 36)}, row)
		local av = make("ImageLabel", {
			Name = "Avatar", Size = UDim2.new(0, 32, 0, 32), Position = UDim2.new(0, 0, 0, 2), BackgroundColor3 = C.raised,
			BorderSizePixel = 0, Image = avatarUrl(uid),
		}, row)
		corner(av, 4)
		stroke(av, C.ink, 2)

		local col = make("Frame", {Name = "Col", BackgroundTransparency = 1, Position = UDim2.new(0, 40, 0, 0), Size = UDim2.new(1, -40, 0, 0), AutomaticSize = AUTO_Y}, row)
		stack(col, 2)
		local head = make("Frame", {Name = "Head", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 1}, col)
		local stamp = ""
		pcall(function()
			stamp = os.date("%H:%M", math.floor((tonumber(m.t) or 0) / 1000))
		end)
		label(head, {
			name = "Name", text = name .. "  @" .. handle .. "   " .. stamp, font = F.bold, ts = 11,
			color = mine and C.yellow or C.text, size = UDim2.new(1, -78, 1, 0),
		})
		label(col, {name = "Text", text = m.m, ts = 12, color = C.text, wrap = true, size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = 2})

		local mutedKey = tostring(uid or handle)
		if not mine then
			brick(head, {
				name = "Mute", text = "MUTE", ghost = true, fg = C.faint, ts = 10, radius = 0,
				size = UDim2.new(0, 36, 1, 0), pos = UDim2.new(1, -36, 0, 0),
				onClick = function()
					muted[mutedKey] = true
					for k, r in pairs(rowsByKey) do
						if r.muteKey == mutedKey then
							r.frame:Destroy()
							rowsByKey[k] = nil
						end
					end
					flash("Muted " .. name .. " until you reopen TONYO.")
				end,
			})
		end
		if isAdmin() then
			brick(head, {
				name = "Del", text = "DEL", ghost = true, fg = C.redText, ts = 10, radius = 0,
				size = UDim2.new(0, 30, 1, 0), pos = UDim2.new(1, mine and -30 or -72, 0, 0),
				onClick = function()
					task.spawn(function()
						if online.chatDelete(key) then
							row:Destroy()
							rowsByKey[key] = nil
						end
					end)
				end,
			})
		end
		rowsByKey[key] = {frame = row, muteKey = mutedKey}
	end

	local rendering = false
	local failCount = {}
	local noteRow
	local function showNote(text)
		if noteRow then
			noteRow:Destroy()
			noteRow = nil
		end
		if not text or text == "" then
			return
		end
		noteRow = label(msgScroll, {name = "Notice", text = text, ts = 11, color = C.amber, wrap = true, size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = 1000000000})
		task.defer(function()
			scrollBottom()
		end)
	end

	local function renderInner(data)
		local hidden = 0
		for key, r in pairs(rowsByKey) do
			if data[key] == nil then
				r.frame:Destroy()
				rowsByKey[key] = nil
			end
		end
		local keys = {}
		for k in pairs(data) do
			keys[#keys + 1] = k
		end
		table.sort(keys)
		local fresh, added = 0, 0
		for _, k in ipairs(keys) do
			local m = data[k]
			if not seen[k] and type(m) == "table" and type(m.m) == "string" and m.m ~= "" then
				local mk = tostring(tonumber(m.u) or cleanName(m.n, "?"))
				if muted[mk] then
					seen[k] = true
				else
					-- Every incoming message is re-checked here, on the receiving client, through Roblox's own
					-- moderation, regardless of whether the sender's client filtered it. If it can't be verified,
					-- it is skipped (and retried on the next poll) rather than shown.
					local filtered = online.moderate(cleanText(m.m), m.u)
					if filtered then
						seen[k] = true
						addMessage(k, {m = filtered, n = m.n, d = m.d, u = m.u, t = m.t})
						added = added + 1
						if tonumber(m.u) ~= player.UserId then
							fresh = fresh + 1
						end
					else
						failCount[k] = (failCount[k] or 0) + 1
						if failCount[k] >= 3 then
							seen[k] = true
						end
						hidden = hidden + 1
					end
				end
			end
		end
		if firstLoad then
			firstLoad = false
			fresh = 0
		end
		if fresh > 0 and not page.Visible then
			unread = unread + fresh
			if tabs.global then
				tabs.global.Text = "GLOBAL " .. unread
			end
		end
		if hidden > 0 then
			showNote(hidden .. " message(s) not shown: Roblox couldn't verify them as safe."
				.. ((online.modError or "") ~= "" and ("\n" .. clip(online.modError, 90)) or ""))
		elseif added > 0 and noteRow then
			showNote(nil)
		end
		if added > 0 then
			task.wait()
			scrollBottom()
		end
	end

	-- One render at a time, so a slow safety check can't make the same message appear twice.
	local function render(data)
		if rendering then
			return
		end
		rendering = true
		local ok, err = pcall(renderInner, data)
		rendering = false
		if not ok then
			online.lastError = "chat: " .. oneLine(tostring(err), 120)
		end
	end

	local function poll()
		local data = online.chatFetch()
		if type(data) == "table" then
			render(data)
		end
	end

	local function refreshOnline()
		for _, r in ipairs(onlineRows) do
			r:Destroy()
		end
		onlineRows = {}
		local list = {}
		for _, u in pairs(online.users or {}) do
			if type(u) == "table" and type(u.n) == "string" then
				list[#list + 1] = {u = u, handle = cleanName(u.n, "player"), name = cleanName(u.d, cleanName(u.n, "player"))}
			end
		end
		table.sort(list, function(a, b)
			return a.name:lower() < b.name:lower()
		end)
		for i, e in ipairs(list) do
			local row = make("Frame", {Name = "Online_" .. e.handle, BackgroundColor3 = C.raised, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = i}, onlineScroll)
			corner(row, 6)
			stroke(row, C.ink, 2)
			local av = make("ImageLabel", {
				Name = "Avatar", Size = UDim2.new(0, 32, 0, 32), Position = UDim2.new(0, 6, 0, 6), BackgroundColor3 = C.well,
				BorderSizePixel = 0, Image = avatarUrl(e.u.u),
			}, row)
			corner(av, 4)
			stroke(av, C.ink, 2)
			label(row, {name = "Name", text = e.name, font = F.bold, ts = 12, size = UDim2.new(1, -100, 0, 16), pos = UDim2.new(0, 46, 0, 6)})
			local where = tonumber(e.u.p) == game.PlaceId and "same game as you" or "in another game"
			if tonumber(e.u.u) == player.UserId then
				where = "you"
			end
			label(row, {name = "Sub", text = "@" .. e.handle .. "  /  " .. where, ts = 10, color = C.faint, size = UDim2.new(1, -100, 0, 14), pos = UDim2.new(0, 46, 0, 24)})
			onlineRows[#onlineRows + 1] = row
		end
		if #list == 0 then
			onlineRows[#onlineRows + 1] = label(onlineScroll, {name = "None", text = "Nobody else is online right now.", ts = 11, color = C.faint, size = UDim2.new(1, 0, 0, 24), order = 1})
		end
		refreshCount()
	end

	local function setMode(m)
		mode = m
		msgScroll.Visible = m == "chat"
		onlineScroll.Visible = m == "online"
		if m == "chat" then
			paint(chatBtn, C.yellow, C.yellowLip, C.yellowInk)
			paint(onlineBtn, C.raised, C.raisedLip, C.sub)
		else
			paint(chatBtn, C.raised, C.raisedLip, C.sub)
			paint(onlineBtn, C.yellow, C.yellowLip, C.yellowInk)
			refreshOnline()
		end
		refreshGate()
	end

	local function send()
		local text = input.Text
		if text:gsub("%s", "") == "" or not joined() then
			return
		end
		if os.clock() - lastSend < 2 then
			flash("Slow down a little.")
			return
		end
		lastSend = os.clock()
		input.Text = ""
		task.spawn(function()
			if online.chatSend(text) then
				showNote(nil)
				pcall(poll)
			else
				flash("Couldn't send.")
				local why = (online.lastError or "") ~= "" and online.lastError or "check your connection"
				showNote("Couldn't send: " .. clip(why, 160))
			end
		end)
	end

	chatBtn.Activated:Connect(function()
		setMode("chat")
	end)
	onlineBtn.Activated:Connect(function()
		setMode("online")
	end)
	sendBtn.Activated:Connect(send)
	input.FocusLost:Connect(function(enter)
		if enter then
			send()
		end
	end)
	leaveBtn.Activated:Connect(function()
		settings.globalChat = false
		saveSettings()
		refreshGate()
	end)

	brick(gate, {
		name = "GateJoin", text = "JOIN", kind = "green", ts = 13, size = UDim2.new(1, 0, 0, 32), order = 3,
		onClick = function()
			settings.globalChat = true
			settings.ping = true
			saveSettings()
			refreshGate()
			task.spawn(function()
				pcall(online.ping)
				pcall(refreshCounter)
				pcall(function()
					app.refreshSetup()
				end)
				refreshGate()
				pcall(poll)
			end)
		end,
	})

	function TX.globalOpen()
		unread = 0
		if tabs.global then
			tabs.global.Text = "GLOBAL"
		end
		refreshGate()
		if mode == "online" then
			refreshOnline()
		end
		if joined() then
			task.spawn(function()
				pcall(poll)
			end)
		end
	end

	refreshGate()

	task.spawn(function()
		local tickN = 0
		while gui.Parent do
			tickN = tickN + 1
			if joined() then
				if page.Visible or tickN % 4 == 0 then
					pcall(poll)
				end
				if page.Visible and mode == "online" then
					pcall(refreshOnline)
				end
			end
			task.wait(page.Visible and 3 or 4)
		end
	end)
end)()

-- ASSETS tab: live preview (animation on a rig, sounds, thumbnails), emote catalog, asset lookup and store browse.
;(function()
	local MarketplaceService = game:GetService("MarketplaceService")
	local RunService = game:GetService("RunService")
	local KeyframeProvider = game:GetService("KeyframeSequenceProvider")

	local EMOTE_FILE, ANIM_FILE = "EmoteDataCache.json", "AnimationCache.json"
	local PER = 8
	local TOOLBOX_HOSTS = {"apis.roblox.com", "apis.roproxy.com"}
	local CATALOG_HOSTS = {"catalog.roblox.com", "catalog.roproxy.com"}

	-- Starter data used when the cache files are not found in your executor workspace.
	local EMBED_EMOTES = [=====[[{"id":3360689775,"name":"Salute"},{"id":5915779043,"name":"Applaud"},{"id":3360692915,"name":"Tilt"},{"id":15610015346,"name":"Yungblud Happier Jump"},{"id":14353423348,"name":"Baby Queen - Bouncy Twirl"},{"id":14353421343,"name":"Baby Queen - Face Frame"},{"id":3823158750,"name":"Godlike"},{"id":139021427684680,"name":"KATSEYE - Touch"},{"id":133596366979822,"name":"Biblically Accurate Emote"},{"id":108128682361404,"name":"Rambunctious"},{"id":79127989560307,"name":"Moon Walk"},{"id":5230661597,"name":"Bored"},{"id":14353425085,"name":"Baby Queen - Strut"},{"id":15694504637,"name":"d4vd - Backflip"},{"id":104142334418357,"name":"[Original] It's Gangnam Style!"},{"id":16553249658,"name":"Mae Stephens - Piano Hands"},{"id":12507097350,"name":"Alo Yoga Pose - Lotus Position"},{"id":15698511500,"name":"Cuco - Levitate"},{"id":4689362868,"name":"Sleep"},{"id":111426928948833,"name":"Floating on clouds"},{"id":130245358716273,"name":"The Weeknd Starboy Strut"},{"id":120642514156293,"name":"Secret Handshake Dance"},{"id":15506503658,"name":"Victory Dance"},{"id":3576717965,"name":"Shy"},{"id":73796726960568,"name":"Nyan Nyan! "},{"id":78758922757947,"name":"Kicking Feet Sit"},{"id":93511411593120,"name":"/e fly"},{"id":114899970878842,"name":"R15 Death (Accurate)"},{"id":5104377791,"name":"Hero Landing"},{"id":5917570207,"name":"Floss Dance"},{"id":131763631172236,"name":"Xaviersobased Emote"},{"id":132074413582912,"name":"California Girl Dance"},{"id":15554010118,"name":"Olivia Rodrigo Head Bop"},{"id":112758073578333,"name":"Bubbly Sit"},{"id":3716636630,"name":"Monkey"},{"id":123015710605336,"name":"Onion"},{"id":4646306583,"name":"Curtsy"},{"id":85936805522788,"name":"Caramell"},{"id":14900153406,"name":"TWICE Feel Special"},{"id":102492229412911,"name":"Deltarune - Tenna Dance"},{"id":133142324349281,"name":"Flopping Fish"},{"id":10214406616,"name":"Frosty Flair - Tommy Hilfiger"},{"id":120224229260879,"name":"Cute crouch "},{"id":15679955281,"name":"Festive Dance"},{"id":4849502101,"name":"Sad"},{"id":10214418283,"name":"V Pose - Tommy Hilfiger"},{"id":92853367837757,"name":"Garry's Dance"},{"id":104485625389237,"name":"Make You Mine"},{"id":139830733782518,"name":"Phut On"},{"id":132382355371060,"name":"Tank Transformation"},{"id":103046131635200,"name":"Scenario - LOVE SCENARIO"},{"id":15123050663,"name":"Bone Chillin' Bop"},{"id":124305244640379,"name":"Shattered"},{"id":134311528115559,"name":"how did he hit every beat"},{"id":17748346932,"name":"Elton John - Heart Shuffle"},{"id":93105950995997,"name":"Caramelldansen"},{"id":7466046574,"name":"Quiet Waves"},{"id":96557878503341,"name":"Caramell Dansen"},{"id":139859849852362,"name":"Dead"},{"id":17360720445,"name":"HUGO Let's Drive!"},{"id":103102322875221,"name":"Skibidi Toilet - Titan Speakerman Laser Spin"},{"id":3576968026,"name":"Shrug"},{"id":130998336536045,"name":"Gangnam Style"},{"id":84555218084038,"name":"Helicopter Spin"},{"id":71302743123422,"name":"Popular"},{"id":133765015173412,"name":"DearALICE - Ariana"},{"id":115319301809339,"name":"2 Phut Hon Dance"},{"id":70635223083942,"name":"Be Not Afraid"},{"id":17746270218,"name":"Sturdy Dance - Ice Spice"},{"id":129149402922241,"name":"griddy"},{"id":3576686446,"name":"Hello"},{"id":113547795536875,"name":"Gangnam Style"},{"id":126614732606871,"name":"Sit"},{"id":3762654854,"name":"Greatest"},{"id":16572756230,"name":"HIPMOTION - Amaarae"},{"id":16276506814,"name":"Sol de Janeiro - Samba"},{"id":3576823880,"name":"Point2"},{"id":78459263478161,"name":"Family Man Death Pose"},{"id":14900151704,"name":"TWICE LIKEY"},{"id":3360686498,"name":"Stadium"},{"id":15571540519,"name":"Nicki Minaj Starships"},{"id":4940597758,"name":"Cower"},{"id":11394056822,"name":"Elton John - Elevate"},{"id":117734400993750,"name":"Virtual Singer Dance"},{"id":97263450325496,"name":"Teto Territory"},{"id":4102315500,"name":"Haha"},{"id":79312439851071,"name":"Chappell Roan HOT TO GO!"},{"id":105851216004006,"name":"Electro Swing"},{"id":92707348383277,"name":"Mesmerizer"},{"id":103139492736941,"name":"Deltarune - Tenna Swing Dance"},{"id":15571538346,"name":"Nicki Minaj Boom Boom Boom"},{"id":15554016057,"name":"Olivia Rodrigo Fall Back to Float"},{"id":70615023659736,"name":"Floating"},{"id":136740085081295,"name":"/e hidden animation"},{"id":119431985170060,"name":"Helicopter"},{"id":87141651594092,"name":"No-Clip/Speed Glitch"},{"id":16303091119,"name":"Beauty Touchdown"},{"id":3934986896,"name":"Dizzy"},{"id":130726889233022,"name":"rolling crybaby"},{"id":11309263077,"name":"Elton John - Heart Skip"},{"id":84511772437190,"name":"Emote Loading. Please Wait... | spinning Robloxian"},{"id":14353417553,"name":"Baby Queen - Air Guitar & Knee Slide"},{"id":15392927897,"name":"Paris Hilton - Sliving For The Groove"},{"id":94796833553521,"name":"TWICE Takedown pt 1 from Kpop Demon Hunters"},{"id":120437019363089,"name":"peter griffin death pose"},{"id":15506506103,"name":"Flex Walk"},{"id":90608224567833,"name":"Proud to be Expendable - Pressure"},{"id":18526338976,"name":"Team USA Breaking Emote"},{"id":99818263438846,"name":"Default Dance"},{"id":103197720369544,"name":"Dani's Gangnam Style"},{"id":75017857395637,"name":"TV Time Dance"},{"id":73683655527605,"name":"Fashion Roadkill"},{"id":15392932768,"name":"Paris Hilton - Iconic IT-Grrrl"},{"id":82217023310738,"name":"Thanos Happy Jump - Squid Game"},{"id":102610758906338,"name":"Possessed"},{"id":95323795166399,"name":"Rat Dance"},{"id":127562607220778,"name":"Gangnam Style "},{"id":129132611803602,"name":"Helicopter"},{"id":82345302788133,"name":"Dia Delicia Dance"},{"id":15392937495,"name":"Paris Hilton - Checking My Angles"},{"id":4212496830,"name":"Zombie"},{"id":113016438012253,"name":"⌛ Best Mates EMOTE [LIMITED]"},{"id":110537281410647,"name":"[Aura Farm] Wall Lean Idle"},{"id":92903522317071,"name":"ILLIT - Magnetic"},{"id":122899100558551,"name":"It's TV Time!"},{"id":75528418031928,"name":"Rambunctious"},{"id":103040723950430,"name":"Gojo Floating"},{"id":70788193750089,"name":"Kickn around"},{"id":5915776835,"name":"High Wave"},{"id":84195923658292,"name":"Jojo"},{"id":110731335896907,"name":"[⌛ Limited]  HEADLESS EMOTE "},{"id":139271706064778,"name":"Hip Bounce"},{"id":4849499887,"name":"Happy"},{"id":127271798262177,"name":"M3GAN's Dance"},{"id":104304182344567,"name":"ONCE HOP HOP!"},{"id":85623000473425,"name":"TWICE Takedown pt 2 from KPop Demon Hunters"},{"id":84067050907557,"name":"Pickle Rick Dance"},{"id":86982022610765,"name":"Caramelldansen"},{"id":117301403779781,"name":"Im Talm Bout Innit"},{"id":84822284410814,"name":"Maraschino Step"},{"id":97847706148165,"name":"[NEW !] Caramelldansen Kawaii Dance"},{"id":89174456614428,"name":"Laying Down - Daydreaming"},{"id":91023138078288,"name":"OH WHO IS YOU"},{"id":107978036345855,"name":"Prince Of Egypt Dance / What You Want"},{"id":71363859760586,"name":"Golden Freddy Pose"},{"id":80877772569772,"name":"Default Dance | OG"},{"id":80436375269036,"name":"HEADLESS HOOPER"},{"id":93262662842394,"name":"Sit"},{"id":75703899901487,"name":"6 7 Transformation"},{"id":100773414188482,"name":"Stray Kids Walkin On Water"},{"id":131544122623505,"name":"Become A Car!"},{"id":99005087791705,"name":"Death Pose"},{"id":132384701706046,"name":"💀MM2 Fake Dead"},{"id":129916107176034,"name":"Discombobulated"},{"id":88598010609888,"name":"Angry Stomp "},{"id":132508867759412,"name":"xavier so based emote"},{"id":121167704249654,"name":"Hide"},{"id":137873580964093,"name":"Floating Human Spinner (LIMITED) "},{"id":76700167742736,"name":"Belly Dance"},{"id":87826892596287,"name":"levitate"},{"id":70972410468289,"name":"Fake Dead (Troll Emote)"},{"id":134615135651900,"name":"Young-hee Head Spin - Squid Game"},{"id":13823339506,"name":"Tommy - Archer"},{"id":109755476052324,"name":"IShowSpeed Dance"},{"id":124828909173982,"name":"Skibidi"},{"id":4272351660,"name":"Fast Hands"},{"id":137006085779408,"name":"Speed Glitch+"},{"id":89633087256727,"name":"Weird Spin"},{"id":125032357496729,"name":"Fake Death (BEST)"},{"id":81177294287826,"name":"Hug"},{"id":88721672617892,"name":"P.B.J.T."},{"id":121259524934987,"name":"Xaviersobased Jig"},{"id":121067808279598,"name":"PARROT PARTY DANCE"},{"id":7202898984,"name":"Show Dem Wrists - KSI"},{"id":120377619472998,"name":"Macarena"},{"id":4940602656,"name":"Jumping Wave"},{"id":94663026124741,"name":"Torture Dance"},{"id":120896030393583,"name":"Get Sturdy"},{"id":137261874619072,"name":"Sponge Dance"},{"id":119746055344304,"name":"Plane"},{"id":78620443286892,"name":"Cute Laying Down"},{"id":108922782921118,"name":"📸 Pose for the Pic "},{"id":131221550165951,"name":"Heart Hands Pose 3.0"},{"id":119454955259757,"name":"Caramel Hip Sway"},{"id":7202900159,"name":"Wake Up Call - KSI"},{"id":79752538807060,"name":"Griddy"},{"id":140466682449054,"name":"head spin"},{"id":107899954696611,"name":"Spongebob Shuffle Dance 🧽"},{"id":96405718067779,"name":"Cute Sit"},{"id":4849497510,"name":"Power Blast"},{"id":89413575288931,"name":"Blue Shirt Guy Dancing"},{"id":112924687333965,"name":"Aura Farm"},{"id":100782362883099,"name":"Car Transformation"},{"id":102323907950469,"name":"Space Dance"},{"id":110521067391235,"name":"The Old Jitterbug"},{"id":111304332281521,"name":"Druski Shuffle"},{"id":133600250245899,"name":"🥤 Soda Pop - Saja Boys"},{"id":133477296392756,"name":"Rasputin – Boney M."},{"id":122949892043249,"name":"[Aura Farm] Sit Idle"},{"id":82739386299071,"name":"Jackpot Groove"},{"id":80422524668416,"name":"Dreamer"},{"id":97968838104258,"name":"Subject Three / AI Cat Chinese Dance"},{"id":91274761264433,"name":"Macarena"},{"id":3994130516,"name":"Bodybuilder"},{"id":5938365243,"name":"Dolphin Dance"},{"id":99563839802389,"name":"Jumpstyle"},{"id":85361710130557,"name":"Caramelldansen"},{"id":74646784680842,"name":"Ishowspeed shake "},{"id":5230615437,"name":"Beckon"},{"id":135489824748823,"name":"Magical Pose"},{"id":98603994713783,"name":"Rat Dance"},{"id":14353419229,"name":"Baby Queen - Dramatic Bow"},{"id":84052327668385,"name":"Floating"},{"id":97999370392804,"name":"Spin my Head"},{"id":94319114655768,"name":"Rat Dance"},{"id":86849720336961,"name":"Mr. Ant Tennas Dance - DELTARUNE"},{"id":124754178569693,"name":"Die Lit!"},{"id":80544397800234,"name":"Helicopter"},{"id":100532972764499,"name":"MONSTER MASH"},{"id":88922397617835,"name":"What You Want"},{"id":115810068374896,"name":"Garry's Dance"},{"id":75842745124834,"name":"Human Snake"},{"id":94451497143711,"name":"Hakari Dance"},{"id":128972617664804,"name":"Fortnite Default Dance"},{"id":73556976257737,"name":"Saja Boy Pose - Jinu"},{"id":81390693780805,"name":"PROXIMA"},{"id":17000058939,"name":"Mini Kong"},{"id":97629500912487,"name":"BlockyKick Dance"},{"id":112949099442762,"name":"Griddy"},{"id":130641944883645,"name":" Jinu Pose - Saja Boys"},{"id":108474079699304,"name":"Dep"},{"id":4049646104,"name":"Line Dance"},{"id":91423783304464,"name":"criss cross sit"},{"id":90524692306889,"name":"[⏳] Chill Sit"},{"id":15506496093,"name":"Rock n Roll"},{"id":134737246939931,"name":"GAG IT DEATH DROP"},{"id":71787387963141,"name":"Worm Dance"},{"id":128658037413893,"name":"I'm Going To Die Here - Pressure"},{"id":99568437064777,"name":"Relaxed Sit"},{"id":83018514370428,"name":"Stargazing"},{"id":92859581691366,"name":"ALTÉGO - Couldn’t Care Less"},{"id":94534169345613,"name":"Casual Sit"},{"id":16126526506,"name":"Paris Hilton Sanasa"},{"id":140037329261678,"name":"Caramel dance"},{"id":94118707925458,"name":"Go Mufasa"},{"id":105730788757021,"name":"Dani's BIRDBRAIN"},{"id":91927498467600,"name":"Koto Nai Meme Dance"},{"id":117450501566142,"name":"Hide Hidden Box Invisible Camo Emote Small tiny"},{"id":4272484885,"name":"Baby Dance"},{"id":88024974500195,"name":"Oppa Gangnam Style"},{"id":7202896732,"name":"Boxing Punch - KSI"},{"id":128792127841374,"name":"Watching silly videos (Or texting)"},{"id":87756443172440,"name":"xavier so based dance"},{"id":116770268279002,"name":"BirdBrain Teto"},{"id":124935873390035,"name":"Hiding Human Box"},{"id":94121796810251,"name":"Kicking Feet And Blushing"},{"id":91945243106968,"name":"Hood Dance"},{"id":18148839527,"name":"Rolling Stones Guitar Strum"},{"id":4940592718,"name":"Confused"},{"id":10370922566,"name":"Sidekicks - George Ezra"},{"id":111481711726876,"name":"JUMP K-POP Dance Choreo"},{"id":114443541753616,"name":"Big Papa Squat"},{"id":96927087453178,"name":"Cursed Floating Rotating Head"},{"id":114695623925996,"name":"Cute Lie"},{"id":82407315928589,"name":"24 Hour Cinderella"},{"id":100576647621125,"name":"What You Want"},{"id":131875333242836,"name":"cute sit"},{"id":3576745472,"name":"Fashionable"},{"id":79681561839536,"name":"Otsukare Summer Dance"},{"id":133160900449608,"name":"[BEST] Orange Justice"},{"id":12804173616,"name":"Ay-Yo Dance Move - NCT 127"},{"id":131643212415034,"name":"Cute Feet Kicks"},{"id":138929851868463,"name":"おつかれSUMMER DANCE"},{"id":124031351335869,"name":"[🎀CUTE] Kayah's Pose"},{"id":11753545334,"name":"Elton John - Rock Out"},{"id":137987340488409,"name":"what happened bro"},{"id":114428584463004,"name":"Territory"},{"id":119868674917432,"name":"[HOT] Caramelldansen"},{"id":133948663586698,"name":"Fastest Speedster Run"},{"id":101037410151868,"name":"Macarena"},{"id":133461102795137,"name":"RAT DANCE"},{"id":140406175549428,"name":"Tenna's Cabbage Dance"},{"id":109664116234926,"name":"head walks away"},{"id":103323241937359,"name":"MM2 Sit Emote"},{"id":81621254772462,"name":"Head Banger"},{"id":98318652597666,"name":"Take The L Emote ✅"},{"id":133999268647970,"name":"Shy Cute Pose"},{"id":110833764398565,"name":"Im a mystery"},{"id":121643381580730,"name":"Gojo Honored One"},{"id":82664964457620,"name":"ISHOWSPEED DANCE"},{"id":126228947948058,"name":"♡ kawaii magical girl kpop idle pose"},{"id":16392120020,"name":"Jawny - Stomp"},{"id":131499177714385,"name":"Playing Dead"},{"id":91749862405391,"name":"🥤｡˚○ | Soda Pop Dance"},{"id":90831367043789,"name":"♡ cute kawaii girly idle pose 2"},{"id":82749804870046,"name":"Griffin Fall"},{"id":78085025505710,"name":"Floating Relaxation "},{"id":127507691649322,"name":"Ballroom Dance"},{"id":99563207397301,"name":"The Worm"},{"id":90929823390861,"name":"Cute Kpop Poses"},{"id":75773776265985,"name":"Candy Emote"},{"id":135922662345048,"name":"Snow angels"},{"id":6869813008,"name":"Samba"},{"id":124481227791432,"name":"Folding, Hide [Animated]"},{"id":78792474294700,"name":"Default Dance"},{"id":95926628409657,"name":"Take The L"},{"id":5915782672,"name":"Rock On"},{"id":134928834792631,"name":"Elevation"},{"id":140333668677501,"name":"L Dance"},{"id":70978791982917,"name":"cat loaf"},{"id":134521545276284,"name":"Peter Griffin Pose (Family Guy Death Pose)"},{"id":130655908439646,"name":"Beat Da Koto Nai"},{"id":76503754262527,"name":"Proxima Creatura"},{"id":78164771288203,"name":"talmbout INNIT"},{"id":81780730637211,"name":"Torture Dance"},{"id":99565933541178,"name":"Falling back Death"},{"id":76080208205057,"name":"Popular"},{"id":88969192102242,"name":"Wall Lean"},{"id":84061944625677,"name":"Company Dance"},{"id":82761302670038,"name":"Skinwalker"},{"id":73946479113094,"name":"Macarena"},{"id":77975534812454,"name":"Bring it around"},{"id":107091254142209,"name":"Cute Anime Bouncy Dance"},{"id":81005824258133,"name":"Jackpot Dance"},{"id":114092281019046,"name":"Shimmer (ORIGINAL)"},{"id":85051384683771,"name":"Cat Dance"},{"id":124664935927071,"name":"Mr. Skier"},{"id":128800625861321,"name":"Honored One"},{"id":99453823712550,"name":"Caffeinated"},{"id":107012521566800,"name":"Snoop Dance"},{"id":3994127840,"name":"Celebrate"},{"id":96847244958186,"name":"Unemployment Dance"},{"id":98064631733787,"name":"Do That Thang"},{"id":90334065717691,"name":"Classic R6 Dance Potion"},{"id":101425980133974,"name":"Speed Try not to laugh"},{"id":84306405425879,"name":"[BEST] Caramell Dansen"},{"id":78107150834426,"name":"Rin"},{"id":110932994930898,"name":"Hide And Seek"},{"id":89721517985713,"name":"OOF"},{"id":121838903053629,"name":"Rat dance"},{"id":15698510244,"name":"ericdoa - dance"},{"id":123282496097076,"name":"Whimsical Laying Down"},{"id":119095524735341,"name":"Classic Retro Jump"},{"id":110179881906079,"name":"Take The L"},{"id":108099880348985,"name":"Firework"},{"id":107300313701198,"name":"Arsenal: Parker Pride"},{"id":116838897398428,"name":"Head toss"},{"id":76250099012024,"name":"Monster mash emote R15"},{"id":122404842843791,"name":"JUMP - BP (KPOP)"},{"id":84932726570047,"name":"E Girl"},{"id":16646438742,"name":"Wanna play?"},{"id":138171891850624,"name":"Dance If You're Peak"},{"id":122687759897103,"name":"Sturdy NYC Dance "},{"id":18665886405,"name":"TMNT Dance"},{"id":108408215437382,"name":"chinese dance"},{"id":94618867444235,"name":"Macarena"},{"id":71912700800803,"name":"Mr \"ant\" Tenna's Kick - Deltarune"},{"id":86588737455577,"name":"Sit"},{"id":101397505086633,"name":"Rampage (Lonely Lonely)"},{"id":115584191221260,"name":"Girly Outfit-Check "},{"id":124970376117840,"name":"Infinite R6 Backflips"},{"id":4849487550,"name":"Agree"},{"id":109763881381610,"name":"Push Up"},{"id":131987997650304,"name":"AI Cat Dance"},{"id":85347533889715,"name":"Gojo Honored One Floating Flying Toji Itadori Yuji"},{"id":131873902790140,"name":"Horror Slow Turn"},{"id":73715378215546,"name":"Deltarune Tenna Dance"},{"id":135545153917736,"name":"Miku Beam Emote"},{"id":76904955984085,"name":"Hugging Idle"},{"id":89115363544461,"name":"Play Dead Troll Trick Emote mm2"},{"id":123955691598090,"name":"Whip Nae Nae"},{"id":96045408942158,"name":"Caramelldansen"},{"id":128771561752851,"name":"Scenario - Roblox"},{"id":125478215073174,"name":"Deactivated Sit"},{"id":115925652377890,"name":"Shuffling"},{"id":18225077553,"name":"Rock Out - Bebe Rexha"},{"id":96251764572550,"name":"67 Transformation [NEW]"},{"id":119256963154827,"name":"Dougie Meme Dance"},{"id":89227290900829,"name":"sinking"},{"id":102348999290457,"name":"Caramelldansen"},{"id":104491001585941,"name":"float"},{"id":78755795767408,"name":"Aura RNG Fly Idle ✨"},{"id":10275057230,"name":"Uprise - Tommy Hilfiger"},{"id":124072098165199,"name":"/e dance2"},{"id":84624658497647,"name":"TENNA"},{"id":129128109582733,"name":"I Wanna Run Away"},{"id":115919902019037,"name":"Spongebob Shuffle"},{"id":85748580511408,"name":"Superman Emote"},{"id":124783960722552,"name":"Rat Dance"},{"id":102822553233176,"name":"Hug 🤗❤️"},{"id":87275228219621,"name":"[BEST] Caramell Dansen"},{"id":89614983665331,"name":"Jumpstyle Dance"},{"id":127882676467351,"name":"Worm"},{"id":114756515400742,"name":"Everybody Loves Me (Dougie)"},{"id":84881027922455,"name":"Penguin dance"},{"id":130358790702800,"name":"Dropper"},{"id":79314952379576,"name":"Folding"},{"id":119673857864183,"name":"Shadow DIO Jojo Pose"},{"id":110226648097430,"name":"2013 Dance"},{"id":122463450997235,"name":"Golden Freddy Glitch Emote"},{"id":135564949884122,"name":"Play Dead"},{"id":107585922448809,"name":"Levitating"},{"id":126485791512520,"name":"Animatronic Jumpscare 🐻🐰🐔🦊"},{"id":131421601916582,"name":"Jelly Dance!"},{"id":92376846011129,"name":"Druski Dance"},{"id":108515849894347,"name":"Family Guy Death"},{"id":102370555981017,"name":"♡ Cute Wave Pose ♡"},{"id":75036900568119,"name":"JELLYOUS Step Dance"},{"id":113455609109484,"name":"Hug"},{"id":122241742551119,"name":"Monster Mash"},{"id":122738273085390,"name":"Alone Sad Sit "},{"id":97102348463163,"name":"Invisible"},{"id":118729994124535,"name":"Takedown"},{"id":15689314578,"name":"Imagine Dragons - “Bones” Dance"},{"id":120302905807132,"name":"STURDY"},{"id":101655341443738,"name":"Contort"},{"id":89968618726000,"name":"headpet"},{"id":134912081679730,"name":"Car Animation"},{"id":125650734535029,"name":"Saja Boys - Soda Pop"},{"id":131724539637653,"name":"Friendly Crouch Emote"},{"id":137271629569769,"name":"Druski Dance"},{"id":130199646045694,"name":"Silly Rest Animation"},{"id":16584496781,"name":"Mae Stephens – Arm Wave"},{"id":136227069460494,"name":"Kawaii Dance"},{"id":93738573538058,"name":"Pushup"},{"id":111458350944165,"name":"Tail Wag"},{"id":15963348695,"name":"Mean Girls Dance Break"},{"id":98522218962476,"name":"Strongest Split"},{"id":103463979134756,"name":"Silly Cat AI Dance"},{"id":133152734782309,"name":"Lord X - I Miss The Quiet"},{"id":102075861555461,"name":"The Worm Emote"},{"id":81671884508244,"name":"Confess Dance"},{"id":114715429199895,"name":"Dance if You're Peak🕺"},{"id":122117255044047,"name":"/e dance1"},{"id":128802284955903,"name":"Tell Me Dance - Wonder Girls "},{"id":107082340537189,"name":"Jellyous - Illit | Kpop Dance"},{"id":123525328389185,"name":"Deltarune Hip Shop"},{"id":78432587555168,"name":"sit"},{"id":124284624810032,"name":"Kawaii Kicking Legs"},{"id":100113161020168,"name":"Touhou Chirumiru"},{"id":87447252507832,"name":"Headbanguing"},{"id":73593666217037,"name":"Take The L"},{"id":120536224720146,"name":"Lonely Dance"},{"id":109572304000648,"name":"Gojo Levitate"},{"id":132031811973422,"name":"Locked In"},{"id":104206611396634,"name":"Blaze Spin"},{"id":110526195609302,"name":"drone"},{"id":90638843981281,"name":"Hair Toss"},{"id":106873371348612,"name":"Rat Dance!"},{"id":111220691268309,"name":"Sleeping"},{"id":126987957251462,"name":"Circus Head Balance"},{"id":125608243857862,"name":"MM2 Headless Emote"},{"id":104063186482642,"name":"Model Waiting Idle"},{"id":77935599895175,"name":"Andy's Coming!"},{"id":128304380307036,"name":"Curled Up Sit"},{"id":132414237338543,"name":"Headlock"},{"id":105957314997150,"name":"/e dance 2013 "},{"id":76095183942765,"name":"Zen (MM2)"},{"id":70380575572008,"name":"Griddy"},{"id":100708682907084,"name":"Packaged"},{"id":4849495710,"name":"Disagree"},{"id":115411666488357,"name":"Flying Helicopter"},{"id":101706709936834,"name":"Griddy"},{"id":88398357963696,"name":"Saja Boys - Soda Pop"},{"id":123098778062901,"name":"Walter's Reaction"},{"id":92258642491902,"name":"Andy's Blue Shirt Dance"},{"id":114945252132705,"name":"Around the World"},{"id":132593821491008,"name":"HAKARI DANCE"},{"id":140160851481660,"name":"Iconic Lay"},{"id":78009699867177,"name":"67"},{"id":102596825732373,"name":"MM2 Zen Emote"},{"id":81958729909618,"name":"Default Dance"},{"id":111530990006064,"name":"got me kicking my feet in the air chill sit"},{"id":88125174734309,"name":"Fake Death Pose 1"},{"id":105370785868536,"name":"Chill Sit"},{"id":95732629932363,"name":"Family Guy \"oof\" Pose"},{"id":105033930313087,"name":"Fake Dead"},{"id":85608190427964,"name":"Sturdy Dance"},{"id":85169458046509,"name":"Thriller"},{"id":15689315657,"name":"GloRilla - \"Tomorrow\" Dance"},{"id":133113167814737,"name":"Aura Farming"},{"id":95838285527052,"name":"Pose 28"},{"id":107299223712510,"name":"Basketball Head Spin"},{"id":100297498958164,"name":"R15 run (Fake lag)"},{"id":108759049195603,"name":"Fake Death (Troll)"},{"id":117511481049460,"name":"NBA Monster Dunk"},{"id":134071732994313,"name":"⌛ [Limited] Headless Emote "},{"id":76798144984399,"name":"🍃 Relax Sitting"},{"id":109747189853899,"name":"Headspin"},{"id":102531713386788,"name":"Human Gun"},{"id":92016245582796,"name":"Electro Swing"},{"id":136914725915863,"name":"Aura Sit"},{"id":90960391618876,"name":"Cute"},{"id":80659943987339,"name":"Vegetable Dance"},{"id":104321872987170,"name":"Corrupted Entity"},{"id":99033587367752,"name":"Flying Head Glitch"},{"id":129365081834801,"name":"Kicking Feet Emote"},{"id":130341818591295,"name":"⛄😇Snow angel"},{"id":93777414456517,"name":"Spinning"},{"id":134898183859788,"name":"Explosive Bark"},{"id":139058906415119,"name":"Floating"},{"id":87629170042137,"name":"Orange Justice"},{"id":121303504693693,"name":"Upside Down Hanging"},{"id":101743582461626,"name":"Sit"},{"id":95300714212921,"name":"cat cleaning"},{"id":86676584790347,"name":"Laying Down"},{"id":116665722283847,"name":"Menacing Vampire"},{"id":120694986087334,"name":"Static Hatsune Miku"},{"id":121066336114466,"name":"Floating Relaxed"},{"id":90928199211879,"name":"Side Step"},{"id":133290706719218,"name":"Caramell Dance"},{"id":107123910784384,"name":"How You Like That KPop"},{"id":98261665240055,"name":"hmph! pouting"},{"id":95938106134169,"name":"Basketball Head Dribble"},{"id":84439193655671,"name":"Popular Vibe"},{"id":122211769878169,"name":"Popularity"},{"id":132602449607962,"name":"Super Sonic "},{"id":124361134174082,"name":"Druski Dance"},{"id":81752296152717,"name":"lie down levitation"},{"id":100319995972885,"name":"Salsa Shuffle"},{"id":130772845072136,"name":"Jabba Switchway"},{"id":7405123844,"name":"Dancin' Shoes - Twenty One Pilots"},{"id":102134421623467,"name":"Red Flavor Kpop Choreo"},{"id":88834614877886,"name":"The Run Around"},{"id":114829405776021,"name":"Building Back Up"},{"id":90418369153054,"name":"Shy sit"},{"id":108709786297341,"name":"Animated Fake Death"},{"id":97680948715657,"name":"Cute Ostukare Summer"},{"id":85599022914880,"name":"Say So"},{"id":74525507319582,"name":"Levitating"},{"id":79907707913769,"name":"hide"},{"id":120616295001236,"name":"Feelin' Cute "},{"id":16215060261,"name":"TWICE I GOT YOU part 1"},{"id":110568614907294,"name":"Friday Funk"},{"id":112820395289785,"name":"/e dance3"},{"id":81045684456123,"name":" Blue Shirt Guy"},{"id":80144240019571,"name":"Sad Sit"},{"id":112121068852761,"name":"R6 Sitting Classic"},{"id":78993833641127,"name":"Cute Feet Kicking"},{"id":114129849164140,"name":"/e epic dance [⏳]"},{"id":83186041767510,"name":"Floating sitting "},{"id":136991458173691,"name":"Take The L"},{"id":129518041239052,"name":"Han Solo"},{"id":136245370202570,"name":"Snow Angel"},{"id":123275002792718,"name":"Helicopter"},{"id":128779579295748,"name":"Hot Backflip "},{"id":88738094720907,"name":"Japanese greeting bow"},{"id":103789826265487,"name":"Slickback Dance"},{"id":112708855940282,"name":"Billy Bouncin"},{"id":93870759476993,"name":"MM2 Sit"},{"id":17370797454,"name":"Wisp - air guitar"},{"id":87111382267514,"name":"Fairy Fly Animation"},{"id":98815823529140,"name":"Yamcha Defeat"},{"id":132668925457202,"name":"Chill Sit"},{"id":95287623772532,"name":"DayDreaming"},{"id":5938394742,"name":"Old Town Road Dance - Lil Nas X (LNX)"},{"id":99031916674986,"name":"Dance 'n Prance"},{"id":71709151401273,"name":"Cute Pose - Profile Pose"},{"id":90774237362669,"name":"Korean Chicken Dance"},{"id":77123035565474,"name":"Interdimensional Breakdancing"},{"id":108510354615694,"name":"China dance emote"},{"id":82424654082141,"name":"Hood Dance 2"},{"id":104390496874805,"name":"PushUp"},{"id":108776997290935,"name":"griddy"},{"id":71136284141200,"name":"Zen MM2 Emote"},{"id":3716633898,"name":"Twirl"},{"id":117738851054326,"name":"the walk"},{"id":106711371603182,"name":"Take The L"},{"id":136162554289402,"name":"Fighting Stance"},{"id":3762641826,"name":"Side to Side"},{"id":95339652051393,"name":" Sad Depressed Crying Sit / Sitting"},{"id":93675237485386,"name":"Dougie"},{"id":81119661589122,"name":"Crossarms"},{"id":71389516735424,"name":"The Zabb"},{"id":134984552283077,"name":"Lay on Face"},{"id":72054495779747,"name":"Cute Sit"},{"id":76668656027928,"name":"Hidden Invisible Body Glitched Emote ✅"},{"id":80829371325436,"name":":spin me"},{"id":117145961689749,"name":"Depressed Sit"},{"id":82345000649867,"name":"Crip Walk"},{"id":6865013133,"name":"Cha Cha"},{"id":121345281331429,"name":"Roaring Knight DELTARUNE"},{"id":70960148440574,"name":"Garrys Dance"},{"id":103544183787174,"name":"[🎀CUTE] Toesies"},{"id":110962488186848,"name":"Minaj Stiletto Challenge"},{"id":93903979507056,"name":"Relaxed Sit"},{"id":118913521478652,"name":"Cutesy Profile Pose"},{"id":105263617496688,"name":"Cutesy Lay Down"},{"id":71738794486531,"name":"Lose Your Head"},{"id":133417254179183,"name":"Ride The Pony (ORIGINAL)"},{"id":109300073879832,"name":"Pats & Pets"},{"id":93829686572194,"name":"L Dance"},{"id":100081021028089,"name":"Levitated Lounge"},{"id":73998106231134,"name":"Cute Pose"},{"id":129884292496413,"name":"Relaxed Sit"},{"id":111901279618983,"name":"Scenario"},{"id":78949019843685,"name":"♡ ~ vampire princess idle"},{"id":119905031885664,"name":"Play Dead"},{"id":127439660946486,"name":"Pose for the Camera !!!"},{"id":92120288726557,"name":"/e sit"},{"id":94341051549220,"name":"02 Dance trend"},{"id":120622104297893,"name":"Sit"},{"id":136419441438548,"name":"Soda Pop Demon Dance"},{"id":3934984583,"name":"Get Out"},{"id":109297343168114,"name":"Tweaker"},{"id":77399834026056,"name":"Cute Laid Legs Kicking"},{"id":83733151910269,"name":"Ride the Pony"},{"id":93968837624319,"name":"Bhangra Dance"},{"id":76736978166708,"name":"Shadow Stand Guy Aura Pose"},{"id":117609375743036,"name":"Floating Item"},{"id":119030831418253,"name":"Immortality Cultivator Meditation"},{"id":107473897055619,"name":"Cute Heart Pose"},{"id":120645783243861,"name":"Fantasy Feet"},{"id":115444596282608,"name":"Billy Bounce"},{"id":86704411577730,"name":"Levitating Sit"},{"id":116946092067772,"name":"Default Dance"},{"id":80556794144838,"name":"Cute Jump"},{"id":109417173715464,"name":"Macarena"},{"id":129110288248645,"name":"Classic R6 Sit"},{"id":91817821197452,"name":"Default Dance"},{"id":93471342782066,"name":"PB & J"},{"id":114560694139962,"name":"Floating Head Spinning Portal"},{"id":74374155705537,"name":"Spongebob Shuffle 🧽"},{"id":129646368643979,"name":"Silly Sit Spin"},{"id":109019084680469,"name":"♡ cute kawaii girly idle pose 1"},{"id":79460913196046,"name":"Rat Dance Meme"},{"id":83261816934732,"name":"Virtual Insanity 🕺"},{"id":123509995733480,"name":"Phut Hon Hip Dance"},{"id":110145155419199,"name":"Locked In"},{"id":118244276616379,"name":"Thanos Mingle Dance - Squid Game"},{"id":134859909130355,"name":"dance2 R6"},{"id":79017838826757,"name":"Andy's Oh Who Is You"},{"id":73394913763818,"name":"Wally West Pose"},{"id":81046473188216,"name":"Woo Walk"},{"id":96713654903032,"name":"Pose 28"},{"id":124636504502331,"name":"Bird"},{"id":124522011862575,"name":"rollie "},{"id":126647057611522,"name":"Nya Anime Dance"},{"id":91695115886964,"name":"Sit Depressed"},{"id":10478368365,"name":"Super Charge"},{"id":131726032766729,"name":"CIRCUS IN THE SKY"},{"id":114539386088263,"name":"Get Sturdy Revamp"},{"id":82003739769858,"name":"R6 Sit"},{"id":86106484612825,"name":"One Hand Push Up"},{"id":81074563419184,"name":"Jabba Switchaway"},{"id":134861929761233,"name":"Flying Superhero "},{"id":128011595312625,"name":"Instant 180° Flip"},{"id":137672653673059,"name":"Cute Anime Dance"},{"id":98221876584229,"name":"Haunted Spare Parts"},{"id":80384978884234,"name":"Sitting Down"},{"id":118388524393240,"name":"Druski Dance"},{"id":108690398745615,"name":"Aura emote"},{"id":103662526275016,"name":"Classic Car"},{"id":120147525269613,"name":"Creature"},{"id":94177618177661,"name":"Penguin Iceberg Shuffle"},{"id":128893142111054,"name":"Peanut Butter Jelly Time (R15)"},{"id":94826765103324,"name":"Get Griddy"},{"id":89014870839642,"name":"Fashion Model Pose Spin"},{"id":116390341517359,"name":"Scenario"},{"id":12507120275,"name":"Alo Yoga Pose - Triangle"},{"id":74206806848577,"name":"Sunflower - Zombies On Your Lawn"},{"id":125623825085795,"name":"Speedy"},{"id":113571015109107,"name":"Slip N' Slide"},{"id":18443268949,"name":"SpongeBob Imaginaaation 🌈"},{"id":112671387660656,"name":"Silent Anger"},{"id":77780996762045,"name":"Gangnam Style"},{"id":111679706035551,"name":"Zero Gravity Shattering"},{"id":93829190507289,"name":"Diva Runway Catwalk"},{"id":112458012124991,"name":"Snoop's Walk"},{"id":102282575857491,"name":"intimidating slide"},{"id":89543481489067,"name":"Flying Bird"},{"id":103547741685910,"name":"Beat Da Kotonai"},{"id":7466047578,"name":"Flowing Breeze"},{"id":106715239721951,"name":"Griddy"},{"id":81021771707988,"name":"Sans UNDERTALE (Sprite Accurate)"},{"id":6797938823,"name":"Take Me Under - Zara Larsson"},{"id":91839607010745,"name":"Sukuna Sit Animation"},{"id":131278934948544,"name":"Squat Kick Dance"},{"id":110835051438795,"name":"Phut Hon ZeroTwo"},{"id":123084211047054,"name":"Discombobulated Wiggle"},{"id":125981188999661,"name":"AURA Wall Lean Idle"},{"id":98401523334482,"name":"Push Up 💪"},{"id":139657570966300,"name":"Flippin McCool"},{"id":16256253954,"name":"TWICE I GOT YOU part 2"},{"id":88633941508826,"name":"Low bow Emote (Limited!)"},{"id":11435177473,"name":"Elton John - Still Standing"},{"id":85845857592424,"name":"Cutesy Sitting Pose"},{"id":78248081330604,"name":"Head Gift - Animation"},{"id":10370929905,"name":"Cartwheel - George Ezra"},{"id":123105264683590,"name":"Wally West"},{"id":113235959868929,"name":"[20% OFF!] Diva Trend Dance - EMOVA"},{"id":90647613676431,"name":"F1 Racecar"},{"id":98120534063281,"name":"Saiyan Walk"},{"id":104891288225055,"name":"Boo Thing"},{"id":12507106431,"name":"Alo Yoga Pose - Warrior II"},{"id":135763292953782,"name":"Do It Left Do It Right"},{"id":136936175263593,"name":"Miss The Quiet [BEST]"},{"id":97045997772923,"name":"Orange Justice"},{"id":4049634387,"name":"Tree"},{"id":87458964172227,"name":"Head Roll"},{"id":76754578230348,"name":"Chilling"},{"id":104165684983914,"name":"Classic Sit "},{"id":95905660853535,"name":"Play Dead"},{"id":132635230507772,"name":"Exorcism"},{"id":97547486465713,"name":"RONALDO"},{"id":93620702247417,"name":"Wave"},{"id":107225120695886,"name":"Roaring Knight Deltarune IDLE (BETTER VERSION)"},{"id":127058223933069,"name":"💀 Fake Death MM2 Trolling "},{"id":105959744896663,"name":"Love Hate Dance"},{"id":100031612342600,"name":"griddy"},{"id":126069437165634,"name":"Odyssey"},{"id":83465000189935,"name":"hiding"},{"id":93031502567721,"name":"Teto Dance"},{"id":71166489923890,"name":"Vilan Idle"},{"id":132569947289841,"name":"Aura Farming"},{"id":78773506370628,"name":"Smug"},{"id":87440858620113,"name":"I'm sat."},{"id":81298983417869,"name":"Get Jiggy"},{"id":110535588920489,"name":"Assumptions Blue Shirt"},{"id":77847525794065,"name":"⏳[LIMITED] Hi Pose"},{"id":89120984307039,"name":"Spin"},{"id":140435963895367,"name":"Sitting"},{"id":134149640725489,"name":"Andy's Headlock"},{"id":135644510792196,"name":"The Crip Walk"},{"id":139403183178750,"name":"Fish Animation"},{"id":84684551359155,"name":"Chill Leg Cross Sit"},{"id":123407495927344,"name":"Stuck In Place"},{"id":108381529878396,"name":"Robloxian Helicopter! (FUNNY)"},{"id":138744663844242,"name":"Bouncing DVD Screensaver Classic"},{"id":88443724456532,"name":"Classic /e dance 2013"},{"id":112150504089416,"name":"Japanese Sit "},{"id":85891978889580,"name":"ERROR"},{"id":3576719440,"name":"T"},{"id":123268767568740,"name":"Peter Pain"},{"id":96406780440488,"name":"💖 Cute Sit 💖 "},{"id":112553206572593,"name":"Rat Dance"},{"id":92846015938931,"name":"Trendy Nicki Leg Pose"},{"id":128185840424518,"name":"Caramelldansen dance"},{"id":133847045910443,"name":"Lay"},{"id":78199122665975,"name":"LOL"},{"id":111918469246503,"name":"(Aura Farm) Handstand Pushup"},{"id":127297129390567,"name":"Otsukare Summer Dance"},{"id":16276501655,"name":"Dave's Spin Move - Glass Animals"},{"id":71056659089869,"name":"Hakari (FULL)"},{"id":113036186850286,"name":"Spongebob"},{"id":131821033642603,"name":"✅ Take The L Emote Sped Up ✅"},{"id":109777105517178,"name":"Magical Girl v1 [Flying]"},{"id":12259888240,"name":"Kick It Dance Move - NCT 127"},{"id":113841393102239,"name":"Everybody Loves Me (Dougie)"},{"id":98754040888252,"name":"Jumpstyle"},{"id":107923895478370,"name":"Floating In Space"},{"id":140168097524408,"name":"Touhou Hina Spin"},{"id":102688787055697,"name":"Warm hug"},{"id":134825580538672,"name":"Take The L "},{"id":136030942777883,"name":"Crazy Air Spin"},{"id":80157450897510,"name":"Retro /e Dance"},{"id":139675183645978,"name":"Weird Spin 2"},{"id":122416394696289,"name":"Macarena Emote ✅"},{"id":117043806735297,"name":"Gon"},{"id":138213548155901,"name":"Retro Spin/Dance Tool"},{"id":87955697811902,"name":"The Worm"},{"id":113772829398170,"name":"do that thang"},{"id":82004281891216,"name":"Snow Angel"},{"id":102969703404968,"name":"Go Mufasa "},{"id":78155330696606,"name":"Skipping"},{"id":114915444133199,"name":"Outfit View"},{"id":123159156696507,"name":"Take The L"},{"id":137282858118997,"name":"SIUU"},{"id":123241974228701,"name":"Classy"},{"id":129702304069841,"name":"Getting jiggy"},{"id":72191221096013,"name":"Sit"},{"id":135253072333106,"name":"Gun Transformation + Shooting"},{"id":100231701240052,"name":"Rambunctious"},{"id":104934807111638,"name":"Popular Vibe Dance"},{"id":107476481439242,"name":"⭐️ HELICOPTER"},{"id":115769285345982,"name":"OH YEA!"},{"id":122623026395755,"name":"Love Sign"},{"id":138946866858913,"name":"🔫 Gun Morph"},{"id":99245053698139,"name":"Roll"},{"id":73332973606418,"name":"Conquest"},{"id":73990846892571,"name":"Blow Kiss"},{"id":104916602460299,"name":"Nicki Minaj Pose"},{"id":116909481264292,"name":"Sit (MM2)"},{"id":112349735441889,"name":"Druski Crank Dat"},{"id":97560315899262,"name":"Silent Hill Nurse"},{"id":127998433031434,"name":"Sit"},{"id":118115683204335,"name":"Boy's a Liar"},{"id":75954155820284,"name":"Kazotsky Kick Dance"},{"id":107890403470280,"name":"Rizz Pose"},{"id":92676668301699,"name":"♡ [LOOP] cute sitting kicking feet emote"},{"id":133156019892327,"name":"Jackhammer"},{"id":128719021861443,"name":"GANGNAM STYLE"},{"id":140185130376422,"name":"Headflip"},{"id":96632355269853,"name":"kick n giggle"},{"id":118304558494693,"name":"I aint got no pants on dance"},{"id":140547238892659,"name":"Helicopter"},{"id":116728536568950,"name":"Dead"},{"id":109639716887832,"name":"Take The L"},{"id":128004594505261,"name":"praying"},{"id":140509014658063,"name":"Box Swing"},{"id":116416703003358,"name":"Rat Dance"},{"id":97502008524120,"name":"Jabba Switchaway"},{"id":132899021100548,"name":"Birdbrain Emote🐔"},{"id":130815556553873,"name":"Static Outmanic!"},{"id":110827382619943,"name":"Rollie Dance"},{"id":121469443662693,"name":"Dab"},{"id":140143347648362,"name":"giraffe"},{"id":132352706877382,"name":"♡ cute kawaii hold my plushie... ! idle pose"},{"id":116522367399217,"name":"Take The L"},{"id":90425743502387,"name":"Crying"},{"id":110067764106480,"name":"Smug Dance"},{"id":93796458163488,"name":"Otsukare Summer ☀️"},{"id":99766711630226,"name":"Lay"},{"id":138779856593589,"name":"The Griddy"},{"id":95861380714385,"name":"aespa - Whiplash"},{"id":123516013924276,"name":"Fragmented"},{"id":118679993855133,"name":"The Chicken Nugget Dance"},{"id":137865090089996,"name":"Ride The Pony!"},{"id":74435375782890,"name":"Sit"},{"id":118410457961703,"name":"Admire"},{"id":92300395650613,"name":"Helicopter Meme spin 🚁"},{"id":138030172409402,"name":"Get Jiggy"},{"id":97955437622500,"name":"I Have The Power"},{"id":4391208058,"name":"Shuffle"},{"id":120426139200972,"name":"Pooping"},{"id":102814839657347,"name":"Astro Dance"},{"id":122740887243484,"name":"Get Griddy"},{"id":132885029786945,"name":"DJ Khaled Dance"},{"id":96573402798618,"name":"Crossed Legs Vibin Sit"},{"id":140536066847994,"name":"Jojo Pose Test"},{"id":73470392753674,"name":"Supermodel Fantasy (LOOP)"},{"id":98193399505416,"name":"my head gone bruh (headless)"},{"id":113312808145333,"name":"FREAKY FLOPPY WORM"},{"id":119266290026621,"name":"Joe Pose"},{"id":5915773992,"name":"Break Dance"},{"id":90478640060356,"name":"Luffy Second Gear"},{"id":77488869538841,"name":"Bike "},{"id":97159207958280,"name":"Freaky Jumpscare"},{"id":126068021063465,"name":"Tuff [itoshi Rin]"},{"id":87587450444673,"name":"Spinning"},{"id":14022978026,"name":"YUNGBLUD – HIGH KICK"},{"id":135969054380167,"name":"gwiddy"},{"id":5895009708,"name":"Jumping Cheer"},{"id":137646250335504,"name":"Demonic Possession"},{"id":74022705210142,"name":"Neko Scratch"},{"id":91325819213930,"name":"Little Demon Exorcism"},{"id":74318414570029,"name":"Levitate Shatter Rotate"},{"id":104649607521292,"name":"Six Seven! (67)"},{"id":118365750845245,"name":"Engineer Dance"},{"id":100700616516922,"name":"Knightly Stance"},{"id":87084947602260,"name":"Mr. Ant Tennas Battle - DELTARUNE"},{"id":118447146432576,"name":"Basketball Head Dribble (left&right)"},{"id":139121423735400,"name":"Lay down glitch emote🤑"},{"id":115306436976323,"name":"smug dancin"},{"id":129579733620258,"name":"Head Shake"},{"id":104552918224011,"name":"Fake Run Lag"},{"id":114380999425365,"name":"Take the L"},{"id":123125237932854,"name":"Boogie Down"},{"id":76545568367601,"name":"Jojo Dio Pose"},{"id":102076956367441,"name":"HeadSpin"},{"id":133005847117851,"name":"Take The L"},{"id":129934497203769,"name":"The Honoured One (Gojo)"},{"id":115502757897723,"name":"Griddy [✅] "},{"id":91811231498287,"name":"Rampage"},{"id":83559276301867,"name":"Default Dance"},{"id":132950274861655,"name":"Worm Dance"},{"id":110009750068352,"name":"Dying"},{"id":79928863970461,"name":"MM2 Headless Emote"},{"id":139681015298158,"name":"Princess kiss under the moonlight ♡"},{"id":126302138178332,"name":"Fake Dead Troll"},{"id":124512151372711,"name":"Fancy Feets"},{"id":96183325107876,"name":"Hip Hop - Bop"},{"id":82224981519682,"name":"Head Juggling (PoF)"},{"id":77234582148139,"name":"/e float"},{"id":138904082598629,"name":"Bizarre Dance"},{"id":127643942754639,"name":"Spinning Zen Yoga Pose"},{"id":75670006412707,"name":"Toprock Dance"},{"id":97888577750809,"name":"Da Hood Macro"},{"id":123374576841498,"name":"Migu"},{"id":114001572163832,"name":"Caffeinated"},{"id":135740020061537,"name":"Just Vibin' Dance"},{"id":110407203358363,"name":"Kitty Cat"},{"id":126404410751441,"name":"Dinnerbone"},{"id":94376665318956,"name":"Goat Dance"},{"id":89420560138060,"name":"Observant Sitting"},{"id":116376650217945,"name":"Mingle Dance [ Squid Game ]"},{"id":98751825568530,"name":"Take the W"},{"id":93292747769457,"name":"Rewrite Idle"},{"id":85362492536029,"name":"Cool Spin"},{"id":115141808329063,"name":"OFFICIAL HONORED ONE"},{"id":91280162000203,"name":"Take The L"},{"id":72059847540792,"name":"Bouncing Headless"},{"id":120359706938440,"name":"Fake Death"},{"id":82151370935308,"name":"Cute Girl Squat"},{"id":119438952396414,"name":"Blocky Crouch Jump"},{"id":115080543751957,"name":"Helicopter"},{"id":73475641337651,"name":"R6 Backflip"},{"id":130260688519268,"name":"L Dance"},{"id":80973196392401,"name":"Super Earth Salute"},{"id":96968555068754,"name":"Spiderman's Evil Dance"},{"id":98205207941430,"name":"Boogie Emote"},{"id":97996450818876,"name":"The Honored One"},{"id":103709181489605,"name":"Futebol de Cabeça"},{"id":132322435157678,"name":"Admin Dance"},{"id":10214411646,"name":"Floor Rock Freeze - Tommy Hilfiger"},{"id":119216965926731,"name":"Player 456 Fall"},{"id":77166149654675,"name":"Electric Angel"},{"id":107330941192204,"name":"Kita dance / Doodle Dance"},{"id":83809559049428,"name":"Helicopter Helicopter"},{"id":116065653184749,"name":"Griddy"},{"id":88202198147922,"name":"Hakari Dance Remastered R15"},{"id":139708452356331,"name":"Jugglehead"},{"id":83356347458061,"name":"2010 Classic Dance"},{"id":97151170886466,"name":"Wonderful Day for Pie"},{"id":130055095963705,"name":"Push Up"},{"id":131242989055598,"name":"I Just Wanna Rock / Get Sturdy"},{"id":104555342633439,"name":"Chill Floor Sit"},{"id":106381695975693,"name":"Spicy Life Dance"},{"id":70811858807338,"name":"Spongebob Shuffle🧽"},{"id":97161625230640,"name":"Im going crazy"},{"id":109500204688576,"name":"Boxify (Troll)"},{"id":115883628797443,"name":"Peanut Butter Jelly Time"},{"id":82285837400526,"name":"Rat Dance"},{"id":102917457169467,"name":"Rat dance"},{"id":130846510021578,"name":"Compressed"},{"id":74435627155065,"name":"Spinning"},{"id":114790274109603,"name":"Billy Bounce"},{"id":122756345628791,"name":"Joyful Jump"},{"id":86408375048761,"name":"Macarena"},{"id":136489093136465,"name":"Head Pat [Bundle/Matching/Duo]"},{"id":128589766828505,"name":"Peter Parker"},{"id":75817748922762,"name":"Mu Profile Pose"},{"id":99782749331888,"name":"Popular Vibe"},{"id":108668045601612,"name":"cool sit"},{"id":76332513040721,"name":"Breakdance"},{"id":113236164765359,"name":"Getting pats [Bundle/Matching/Duo]"},{"id":122763219460340,"name":"Goofy Sway"},{"id":88705764492034,"name":"Goofy Chicken Dance"},{"id":108010590407956,"name":"Mischievous Function"},{"id":91037041171855,"name":"Burn and ice"},{"id":109304407588214,"name":"Freddy Fazbear Stage Performance"},{"id":88437776322553,"name":"OH A RAT "},{"id":94960135681008,"name":"Never Gonna - (Rick Roll)"},{"id":107557715852038,"name":"Vibey"},{"id":120617840401424,"name":"Capoeira"},{"id":139351413969659,"name":"Ragdoll Death Pose"},{"id":78957942093953,"name":"floating stare"},{"id":130654870902211,"name":"Joyful Jump"},{"id":98943918958782,"name":"TF2 Laughing (Demoman)"},{"id":124605833322882,"name":"ROLLIE"},{"id":97537006592057,"name":"I wanna Rollie"},{"id":138120364313393,"name":"Flip"},{"id":110720144495202,"name":"WoW"},{"id":80564851360892,"name":"Gojo Run"},{"id":123756721005460,"name":"Crybaby Tantrum Sit"},{"id":137515797332664,"name":"Play Dead"},{"id":124029773563065,"name":"Headless Horseman Head Toss"},{"id":72473645937395,"name":"Andy's Hakari (Lonely Lonely)"},{"id":117552763704832,"name":"SODA POP! - KPOP Demon Hunters"},{"id":121231858727693,"name":"Andy's DELICIA DANCE (DANCE IF YOU'RE PEAK)"},{"id":124778241398875,"name":"Spinning Top"},{"id":118214278778249,"name":"Smelly / You're Stinky!"},{"id":129953639906823,"name":"Deltarune Spin Action"},{"id":83362515790472,"name":"Classic Celebration"},{"id":88504681684408,"name":"Baby Tu Eres MALA dance"},{"id":112534953476344,"name":"no u"},{"id":73561648394427,"name":"Gon's Rage"},{"id":116288930106470,"name":"WIGGLE"},{"id":87319540808191,"name":"Kawaii Caramelldansen Dance"},{"id":72779337007744,"name":"Bring it around"},{"id":89623728108712,"name":"Gojo Hollow Purple"},{"id":88799212885495,"name":"Bizarre Jojo Pose"},{"id":106587392229504,"name":"Meditating"},{"id":74931167859088,"name":"HELLO Transformation"},{"id":106569806588657,"name":"They Don't Love you Like I Do"},{"id":109969619039056,"name":"Korean Greeting"},{"id":72323852254395,"name":"Classic Penguin Dance"},{"id":104796070065311,"name":"Chinese Cat Dance !"},{"id":124660959977138,"name":"Tenna seeing Spamton crashout"},{"id":85997349806865,"name":"[ R6 ] Floating Chilling"},{"id":71176955262462,"name":"Cute Sit"},{"id":110511723808460,"name":"SpiderMan Hanging Pose"},{"id":80963031817715,"name":"Plane Transformation"},{"id":82566336345109,"name":"Phut Hon Dance"},{"id":82395078099296,"name":"Clouds"},{"id":102708060056165,"name":"Fancy Man In Suit"},{"id":116713028797359,"name":"Hype Dance"},{"id":118870859905794,"name":"Chopper Dance"},{"id":112768599000894,"name":"Everybody do the Flop"},{"id":76005751608819,"name":"Goofy Spin"},{"id":85875089814466,"name":"Sitting"},{"id":127206686429639,"name":"spikes dance"},{"id":78010827974170,"name":"Marashin Dance"},{"id":106530036522183,"name":"Friendly Wave"},{"id":118351352716855,"name":"Dionela Pose"},{"id":127620425336765,"name":"R6 Sit"},{"id":75208907352465,"name":"Snoop Mlg Dance"},{"id":90223032116721,"name":"HJD Noli's Jig"},{"id":76597096771848,"name":"Arrow Pointing"},{"id":110742001792116,"name":"Rage Quit"}]]=====]
	local EMBED_ANIMS = [=====[{"210907322997142":[{"name":"Animation1","weights":[3],"animationId":"rbxassetid://99348968698598","category":"idle"},{"name":"Animation2","weights":[9],"animationId":"rbxassetid://77285810249910","category":"idle"},{"name":"RunAnim","weights":[],"animationId":"rbxassetid://75387202603190","category":"run"},{"name":"WalkAnim","weights":[],"animationId":"rbxassetid://85417603155757","category":"walk"},{"name":"FallAnim","weights":[],"animationId":"rbxassetid://113712806865164","category":"fall"},{"name":"JumpAnim","weights":[],"animationId":"rbxassetid://91838721738454","category":"jump"},{"name":"SwimIdleAnim","weights":[],"animationId":"rbxassetid://78921418753060","category":"swimidle"},{"name":"SwimAnim","weights":[],"animationId":"rbxassetid://138106456920836","category":"swim"},{"name":"ClimbAnim","weights":[],"animationId":"rbxassetid://121758628717056","category":"climb"}],"240236445576310":[{"animationId":"rbxassetid://82612876991767","weights":[10],"name":"Animation1","category":"idle"},{"animationId":"rbxassetid://77912189459957","weights":[],"name":"RunAnim","category":"run"},{"animationId":"rbxassetid://132676835675871","weights":[],"name":"WalkAnim","category":"walk"},{"animationId":"rbxassetid://129485543302178","weights":[],"name":"FallAnim","category":"fall"},{"animationId":"rbxassetid://100301020636083","weights":[],"name":"JumpAnim","category":"jump"},{"animationId":"rbxassetid://132410458504813","weights":[],"name":"SwimIdleAnim","category":"swimidle"},{"animationId":"rbxassetid://95791079400210","weights":[],"name":"SwimAnim","category":"swim"},{"animationId":"rbxassetid://99268523567760","weights":[],"name":"ClimbAnim","category":"climb"}],"49496419877527":[{"name":"Animation2","weights":[3],"animationId":"rbxassetid://123093764222478","category":"idle"},{"name":"Animation1","weights":[9],"animationId":"rbxassetid://131621056321423","category":"idle"},{"name":"RunAnim","weights":[],"animationId":"rbxassetid://83249833523956","category":"run"},{"name":"WalkAnim","weights":[],"animationId":"rbxassetid://138758221036799","category":"walk"},{"name":"FallAnim","weights":[],"animationId":"rbxassetid://74887319607376","category":"fall"},{"name":"JumpAnim","weights":[],"animationId":"rbxassetid://123331727863333","category":"jump"},{"name":"SwimIdleAnim","weights":[],"animationId":"rbxassetid://130041952489073","category":"swimidle"},{"name":"SwimAnim","weights":[],"animationId":"rbxassetid://101810393286995","category":"swim"},{"name":"ClimbAnim","weights":[],"animationId":"rbxassetid://128255430810629","category":"climb"}],"49965701347149":[{"name":"Animation1","weights":[9],"animationId":"rbxassetid://135041952606054","category":"idle"},{"name":"Animation2","weights":[3],"animationId":"rbxassetid://126090090182268","category":"idle"},{"name":"RunAnim","weights":[],"animationId":"rbxassetid://102013027668172","category":"run"},{"name":"WalkAnim","weights":[],"animationId":"rbxassetid://102013027668172","category":"walk"},{"name":"FallAnim","weights":[],"animationId":"rbxassetid://113712806865164","category":"fall"},{"name":"JumpAnim","weights":[],"animationId":"rbxassetid://91838721738454","category":"jump"},{"name":"SwimIdleAnim","weights":[],"animationId":"rbxassetid://78921418753060","category":"swimidle"},{"name":"SwimAnim","weights":[],"animationId":"rbxassetid://138106456920836","category":"swim"},{"name":"ClimbAnim","weights":[],"animationId":"rbxassetid://121758628717056","category":"climb"}],"205257210032765":[{"animationId":"rbxassetid://77491435683874","weights":[10],"name":"Animation1","category":"idle"},{"animationId":"rbxassetid://130290582963053","weights":[],"name":"RunAnim","category":"run"},{"animationId":"rbxassetid://124290108275158","weights":[],"name":"WalkAnim","category":"walk"},{"animationId":"rbxassetid://79589005860504","weights":[],"name":"FallAnim","category":"fall"},{"animationId":"rbxassetid://86704327418504","weights":[],"name":"JumpAnim","category":"jump"},{"animationId":"rbxassetid://104225340875894","weights":[],"name":"SwimIdleAnim","category":"swimidle"},{"animationId":"rbxassetid://124332169688708","weights":[],"name":"SwimAnim","category":"swim"},{"animationId":"rbxassetid://77329335879554","weights":[],"name":"ClimbAnim","category":"climb"}],"254591073575789":[{"animationId":"rbxassetid://72538958625011","weights":[],"name":"Animation1","category":"idle"},{"animationId":"rbxassetid://133992795364436","weights":[],"name":"RunAnim","category":"run"},{"animationId":"rbxassetid://120693235054342","weights":[],"name":"WalkAnim","category":"walk"},{"animationId":"rbxassetid://93059842690707","weights":[],"name":"FallAnim","category":"fall"},{"animationId":"rbxassetid://87979788466140","weights":[],"name":"JumpAnim","category":"jump"},{"animationId":"rbxassetid://87715827819034","weights":[],"name":"SwimAnim","category":"swim"},{"animationId":"rbxassetid://85857425544075","weights":[],"name":"SwimIdleAnim","category":"swimidle"},{"animationId":"rbxassetid://83630937743392","weights":[],"name":"ClimbAnim","category":"climb"}],"37695258771355":[{"animationId":"rbxassetid://83282444234216","weights":[9],"name":"Animation1","category":"idle"},{"animationId":"rbxassetid://103094926352098","weights":[1],"name":"Animation2","category":"idle"},{"animationId":"rbxassetid://70518517580083","weights":[],"name":"RunAnim","category":"run"},{"animationId":"rbxassetid://118858804231947","weights":[],"name":"WalkAnim","category":"walk"},{"animationId":"rbxassetid://113447600152765","weights":[],"name":"FallAnim","category":"fall"},{"animationId":"rbxassetid://138337673882830","weights":[],"name":"JumpAnim","category":"jump"},{"animationId":"rbxassetid://124365751986652","weights":[],"name":"SwimIdleAnim","category":"swimidle"},{"animationId":"rbxassetid://112748945612036","weights":[],"name":"SwimAnim","category":"swim"},{"animationId":"rbxassetid://137681066246294","weights":[],"name":"ClimbAnim","category":"climb"}],"178030229597008":[{"animationId":"rbxassetid://73747925448100","weights":[4],"name":"Animation1","category":"idle"},{"animationId":"rbxassetid://126686423325261","weights":[9],"name":"Animation2","category":"idle"},{"animationId":"rbxassetid://78100072664167","weights":[],"name":"RunAnim","category":"run"},{"animationId":"rbxassetid://117170375377200","weights":[],"name":"WalkAnim","category":"walk"},{"animationId":"rbxassetid://138692399454828","weights":[],"name":"FallAnim","category":"fall"},{"animationId":"rbxassetid://96612115817107","weights":[],"name":"JumpAnim","category":"jump"},{"animationId":"rbxassetid://79339122708199","weights":[],"name":"SwimIdleAnim","category":"swimidle"},{"animationId":"rbxassetid://114485426526644","weights":[],"name":"SwimAnim","category":"swim"},{"animationId":"rbxassetid://89672071392114","weights":[],"name":"ClimbAnim","category":"climb"}],"63":[{"animationId":"http://www.roblox.com/asset/?id=10921148209","weights":[],"name":"RunAnim","category":"run"},{"animationId":"http://www.roblox.com/asset/?id=10921148939","weights":[],"name":"FallAnim","category":"fall"},{"animationId":"http://www.roblox.com/asset/?id=10921152678","weights":[],"name":"WalkAnim","category":"walk"},{"animationId":"http://www.roblox.com/asset/?id=10921144709","weights":[9],"name":"Animation1","category":"idle"},{"animationId":"http://www.roblox.com/asset/?id=10921145797","weights":[1],"name":"Animation2","category":"idle"},{"animationId":"http://www.roblox.com/asset/?id=10921146941","weights":[0],"name":"MagePose","category":"pose"},{"animationId":"http://www.roblox.com/asset/?id=10921149743","weights":[],"name":"JumpAnim","category":"jump"},{"animationId":"http://www.roblox.com/asset/?id=10921143404","weights":[],"name":"ClimbAnim","category":"climb"},{"animationId":"http://www.roblox.com/asset/?id=10921150788","weights":[],"name":"Swim","category":"swim"},{"animationId":"http://www.roblox.com/asset/?id=10921151661","weights":[],"name":"SwimIdle","category":"swimidle"}],"212695588376538":[{"animationId":"rbxassetid://127586590696082","weights":[9],"name":"Animation1","category":"idle"},{"animationId":"rbxassetid://98191424195415","weights":[1],"name":"Animation2","category":"idle"},{"animationId":"rbxassetid://134111328603168","weights":[],"name":"RunAnim","category":"run"},{"animationId":"rbxassetid://112678016601672","weights":[],"name":"WalkAnim","category":"walk"},{"animationId":"rbxassetid://85086835473694","weights":[],"name":"FallAnim","category":"fall"},{"animationId":"rbxassetid://113225611173823","weights":[],"name":"JumpAnim","category":"jump"},{"animationId":"rbxassetid://107506516996760","weights":[],"name":"SwimIdleAnim","category":"swimidle"},{"animationId":"rbxassetid://83710358528092","weights":[],"name":"SwimAnim","category":"swim"},{"animationId":"rbxassetid://128188622579540","weights":[],"name":"ClimbAnim","category":"climb"}],"55325510769404":[{"animationId":"rbxassetid://77673650899263","weights":[8],"name":"Animation1","category":"idle"},{"animationId":"rbxassetid://100025236988273","weights":[2],"name":"Animation2","category":"idle"},{"animationId":"rbxassetid://117940181096969","weights":[],"name":"RunAnim","category":"run"},{"animationId":"rbxassetid://120240481303112","weights":[],"name":"WalkAnim","category":"walk"},{"animationId":"rbxassetid://125321626958367","weights":[],"name":"FallAnim","category":"fall"},{"animationId":"rbxassetid://125173106616793","weights":[],"name":"JumpAnim","category":"jump"},{"animationId":"rbxassetid://121805733024028","weights":[],"name":"SwimAnim","category":"swim"},{"animationId":"rbxassetid://70820058557427","weights":[],"name":"SwimIdleAnim","category":"swimidle"},{"animationId":"rbxassetid://87126632628475","weights":[],"name":"ClimbAnim","category":"climb"}],"163960030123548":[{"animationId":"rbxassetid://73391793305727","weights":[1],"name":"Animation1","category":"idle"},{"animationId":"rbxassetid://135524474393183","weights":[],"name":"RunAnim","category":"run"},{"animationId":"rbxassetid://127859929581786","weights":[],"name":"WalkAnim","category":"walk"},{"animationId":"rbxassetid://94958409423385","weights":[],"name":"FallAnim","category":"fall"},{"animationId":"rbxassetid://125179952767111","weights":[],"name":"JumpAnim","category":"jump"},{"animationId":"rbxassetid://108007276441568","weights":[],"name":"SwimAnim","category":"swim"},{"animationId":"rbxassetid://86962420508838","weights":[],"name":"SwimIdleAnim","category":"swimidle"},{"animationId":"rbxassetid://120618541608403","weights":[],"name":"ClimbAnim","category":"climb"}],"33279376625986":[{"animationId":"rbxassetid://75822810238289","weights":[9],"name":"Animation1","category":"idle"},{"animationId":"rbxassetid://139851788042135","weights":[1],"name":"Animation2","category":"idle"},{"animationId":"rbxassetid://116107272697063","weights":[],"name":"RunAnim","category":"run"},{"animationId":"rbxassetid://134969953396271","weights":[],"name":"WalkAnim","category":"walk"},{"animationId":"rbxassetid://85652388786153","weights":[],"name":"FallAnim","category":"fall"},{"animationId":"rbxassetid://102527897855571","weights":[],"name":"JumpAnim","category":"jump"},{"animationId":"rbxassetid://123961643107004","weights":[],"name":"SwimAnim","category":"swim"},{"animationId":"rbxassetid://122190598415520","weights":[],"name":"SwimIdleAnim","category":"swimidle"},{"animationId":"rbxassetid://117309533128411","weights":[],"name":"ClimbAnim","category":"climb"}],"94415078985878":[{"animationId":"rbxassetid://73816523486887","weights":[1],"name":"Animation0","category":"idle"},{"animationId":"rbxassetid://133454853586825","weights":[9],"name":"Animation1","category":"idle"},{"animationId":"rbxassetid://72050416840567","weights":[],"name":"RunAnim","category":"run"},{"animationId":"rbxassetid://82846237669221","weights":[],"name":"WalkAnim","category":"walk"},{"animationId":"rbxassetid://138844903858376","weights":[],"name":"FallAnim","category":"fall"},{"animationId":"rbxassetid://82649217445851","weights":[],"name":"JumpAnim","category":"jump"},{"animationId":"rbxassetid://103689140170432","weights":[],"name":"SwimAnim","category":"swim"},{"animationId":"rbxassetid://71421908111330","weights":[],"name":"SwimIdleAnim","category":"swimidle"},{"animationId":"rbxassetid://97826222936099","weights":[],"name":"ClimbAnim","category":"climb"}],"4164795":[{"animationId":"rbxassetid://121145883950231","weights":[],"name":"ClimbAnim","category":"climb"},{"animationId":"rbxassetid://121454505477205","weights":[],"name":"JumpAnim","category":"jump"},{"animationId":"rbxassetid://94788218468396","weights":[],"name":"FallAnim","category":"fall"},{"animationId":"rbxassetid://98281136301627","weights":[9],"name":"Animation1","category":"idle"},{"animationId":"rbxassetid://138183121662404","weights":[1],"name":"Animation2","category":"idle"},{"animationId":"rbxassetid://133117300343405","weights":[0],"name":"StylishPose","category":"pose"},{"animationId":"rbxassetid://134824450619865","weights":[],"name":"RunAnim","category":"run"},{"animationId":"rbxassetid://90478085024465","weights":[],"name":"WalkAnim","category":"walk"},{"animationId":"rbxassetid://105962919001086","weights":[],"name":"Swim","category":"swim"},{"animationId":"rbxassetid://129126268464847","weights":[],"name":"SwimIdle","category":"swimidle"}],"230426786805569":[{"animationId":"rbxassetid://127680121515160","weights":[9],"name":"Animation1","category":"idle"},{"animationId":"rbxassetid://73274636962312","weights":[1],"name":"Animation2","category":"idle"},{"animationId":"rbxassetid://87479640280026","weights":[],"name":"RunAnim","category":"run"},{"animationId":"rbxassetid://100122714444641","weights":[],"name":"WalkAnim","category":"walk"},{"animationId":"rbxassetid://72969651053552","weights":[],"name":"FallAnim","category":"fall"},{"animationId":"rbxassetid://105574240138506","weights":[],"name":"JumpAnim","category":"jump"},{"animationId":"rbxassetid://139832599845817","weights":[],"name":"SwimAnim","category":"swim"},{"animationId":"rbxassetid://98010676861018","weights":[],"name":"SwimIdleAnim","category":"swimidle"},{"animationId":"rbxassetid://124774536823493","weights":[],"name":"ClimbAnim","category":"climb"}],"36827598340607":[{"animationId":"rbxassetid://131818288653669","weights":[1],"name":"Animation1","category":"idle"},{"animationId":"rbxassetid://131818288653669","weights":[2],"name":"Animation2","category":"idle"},{"animationId":"rbxassetid://72238413320821","weights":[],"name":"RunAnim","category":"run"},{"animationId":"rbxassetid://131187541060181","weights":[],"name":"WalkAnim","category":"walk"},{"animationId":"rbxassetid://137181853228837","weights":[],"name":"FallAnim","category":"fall"},{"animationId":"rbxassetid://95529859363895","weights":[],"name":"JumpAnim","category":"jump"},{"animationId":"rbxassetid://110843295569163","weights":[],"name":"SwimAnim","category":"swim"},{"animationId":"rbxassetid://137505307707414","weights":[],"name":"SwimIdleAnim","category":"swimidle"},{"animationId":"rbxassetid://129368486129485","weights":[],"name":"ClimbAnim","category":"climb"}],"133029085353625":[{"name":"Animation1","weights":[10],"animationId":"rbxassetid://96708826087005","category":"idle"},{"name":"RunAnim","weights":[],"animationId":"rbxassetid://127164887915027","category":"run"},{"name":"WalkAnim","weights":[],"animationId":"rbxassetid://100783666275892","category":"walk"},{"name":"FallAnim","weights":[],"animationId":"rbxassetid://140287076214596","category":"fall"},{"name":"JumpAnim","weights":[],"animationId":"rbxassetid://119697945159028","category":"jump"},{"name":"SwimIdleAnim","weights":[],"animationId":"rbxassetid://88473439275134","category":"swimidle"},{"name":"SwimAnim","weights":[],"animationId":"rbxassetid://118064807649088","category":"swim"},{"name":"ClimbAnim","weights":[],"animationId":"rbxassetid://132800247547755","category":"climb"}],"280512673311723":[{"animationId":"rbxassetid://78788007182057","weights":[1],"name":"Animation1","category":"idle"},{"animationId":"rbxassetid://99686194237390","weights":[2],"name":"Animation2","category":"idle"},{"animationId":"rbxassetid://73564415656085","weights":[],"name":"RunAnim","category":"run"},{"animationId":"rbxassetid://86581281495746","weights":[],"name":"WalkAnim","category":"walk"},{"animationId":"rbxassetid://88389650871979","weights":[],"name":"FallAnim","category":"fall"},{"animationId":"rbxassetid://124663540272175","weights":[],"name":"JumpAnim","category":"jump"},{"animationId":"rbxassetid://72766872622691","weights":[],"name":"SwimAnim","category":"swim"},{"animationId":"rbxassetid://127278123803134","weights":[],"name":"SwimIdleAnim","category":"swimidle"},{"animationId":"rbxassetid://137059146147985","weights":[],"name":"ClimbAnim","category":"climb"}],"151647769563297":[{"animationId":"rbxassetid://129767927032151","weights":[9],"name":"Animation1","category":"idle"},{"animationId":"rbxassetid://137437858757905","weights":[1],"name":"Animation2","category":"idle"},{"animationId":"rbxassetid://119773713017109","weights":[],"name":"RunAnim","category":"run"},{"animationId":"rbxassetid://71636452780322","weights":[],"name":"WalkAnim","category":"walk"},{"animationId":"rbxassetid://90880441738824","weights":[],"name":"FallAnim","category":"fall"},{"animationId":"rbxassetid://118838561581658","weights":[],"name":"JumpAnim","category":"jump"},{"animationId":"rbxassetid://73694077746463","weights":[],"name":"SwimAnim","category":"swim"},{"animationId":"rbxassetid://88791170263484","weights":[],"name":"SwimIdleAnim","category":"swimidle"},{"animationId":"rbxassetid://135795899709073","weights":[],"name":"ClimbAnim","category":"climb"}],"9055161851876":[{"animationId":"rbxassetid://132827767229593","weights":[],"name":"Animation1","category":"idle"},{"animationId":"rbxassetid://121695063061152","weights":[],"name":"RunAnim","category":"run"},{"animationId":"rbxassetid://96251594453721","weights":[],"name":"WalkAnim","category":"walk"},{"animationId":"rbxassetid://125634617115817","weights":[],"name":"FallAnim","category":"fall"},{"animationId":"rbxassetid://135520282315546","weights":[],"name":"JumpAnim","category":"jump"},{"animationId":"rbxassetid://133184966907153","weights":[],"name":"SwimAnim","category":"swim"},{"animationId":"rbxassetid://138765568746898","weights":[],"name":"SwimIdleAnim","category":"swimidle"},{"animationId":"rbxassetid://140285751631802","weights":[],"name":"ClimbAnim","category":"climb"}],"28426574933955":[{"animationId":"rbxassetid://109756943881830","weights":[6],"name":"Animation1","category":"idle"},{"animationId":"rbxassetid://136938465860499","weights":[1],"name":"Animation2","category":"idle"},{"animationId":"rbxassetid://123784939438585","weights":[],"name":"RunAnim","category":"run"},{"animationId":"rbxassetid://91102359119023","weights":[],"name":"WalkAnim","category":"walk"},{"animationId":"rbxassetid://99327613669264","weights":[],"name":"FallAnim","category":"fall"},{"animationId":"rbxassetid://135658461353990","weights":[],"name":"JumpAnim","category":"jump"},{"animationId":"rbxassetid://138066340860791","weights":[],"name":"SwimIdleAnim","category":"swimidle"},{"animationId":"rbxassetid://130502154096804","weights":[],"name":"SwimAnim","category":"swim"},{"animationId":"rbxassetid://132357138176615","weights":[],"name":"ClimbAnim","category":"climb"}],"86270790880748":[{"animationId":"rbxassetid://118195246541519","weights":[],"name":"Animation1","category":"idle"},{"animationId":"rbxassetid://133291236719695","weights":[],"name":"RunAnim","category":"run"},{"animationId":"rbxassetid://70532084598346","weights":[],"name":"WalkAnim","category":"walk"},{"animationId":"rbxassetid://88817521039352","weights":[],"name":"FallAnim","category":"fall"},{"animationId":"rbxassetid://87784517289295","weights":[],"name":"JumpAnim","category":"jump"},{"animationId":"rbxassetid://124314548544388","weights":[],"name":"SwimIdleAnim","category":"swimidle"},{"animationId":"rbxassetid://70788156947773","weights":[],"name":"SwimAnim","category":"swim"},{"animationId":"rbxassetid://99974229390885","weights":[],"name":"ClimbAnim","category":"climb"}],"243332947630422":[{"animationId":"rbxassetid://85489838146032","weights":[],"name":"Animation1","category":"idle"},{"animationId":"rbxassetid://112691442311927","weights":[],"name":"RunAnim","category":"run"},{"animationId":"rbxassetid://94747963182802","weights":[],"name":"WalkAnim","category":"walk"},{"animationId":"rbxassetid://110943391271325","weights":[],"name":"FallAnim","category":"fall"},{"animationId":"rbxassetid://93675325575511","weights":[],"name":"JumpAnim","category":"jump"},{"animationId":"rbxassetid://125165733619521","weights":[],"name":"SwimAnim","category":"swim"},{"animationId":"rbxassetid://98699020440262","weights":[],"name":"SwimIdleAnim","category":"swimidle"},{"animationId":"rbxassetid://94079571267061","weights":[],"name":"ClimbAnim","category":"climb"}],"63500895841526":[{"animationId":"rbxassetid://102180910456512","weights":[],"name":"Animation1","category":"idle"},{"animationId":"rbxassetid://73785433980023","weights":[],"name":"RunAnim","category":"run"},{"animationId":"rbxassetid://79874841657002","weights":[],"name":"WalkAnim","category":"walk"},{"animationId":"rbxassetid://134899569108920","weights":[],"name":"FallAnim","category":"fall"},{"animationId":"rbxassetid://139309093359088","weights":[],"name":"JumpAnim","category":"jump"},{"animationId":"rbxassetid://86882151233402","weights":[],"name":"SwimAnim","category":"swim"},{"animationId":"rbxassetid://91610745365597","weights":[],"name":"SwimIdleAnim","category":"swimidle"},{"animationId":"rbxassetid://110150233430382","weights":[],"name":"ClimbAnim","category":"climb"}],"117879278582279":[{"name":"Animation1","weights":[10],"animationId":"rbxassetid://79896925666200","category":"idle"},{"name":"Animation2","weights":[2],"animationId":"rbxassetid://136024113274118","category":"idle"},{"name":"RunAnim","weights":[],"animationId":"rbxassetid://102662693903883","category":"run"},{"name":"WalkAnim","weights":[],"animationId":"rbxassetid://102662693903883","category":"walk"},{"name":"FallAnim","weights":[],"animationId":"rbxassetid://93082543985034","category":"fall"},{"name":"JumpAnim","weights":[],"animationId":"rbxassetid://95748338021420","category":"jump"},{"name":"SwimIdleAnim","weights":[],"animationId":"rbxassetid://76540730986377","category":"swimidle"},{"name":"SwimAnim","weights":[],"animationId":"rbxassetid://120938975328193","category":"swim"},{"name":"ClimbAnim","weights":[],"animationId":"rbxassetid://76230248181654","category":"climb"}],"62932449623969":[{"name":"Animation1","weights":[8],"animationId":"rbxassetid://140624633058655","category":"idle"},{"name":"Animation2","weights":[2],"animationId":"rbxassetid://122877411870697","category":"idle"},{"name":"RunAnim","weights":[],"animationId":"rbxassetid://114109287841425","category":"run"},{"name":"WalkAnim","weights":[],"animationId":"rbxassetid://74829299292350","category":"walk"},{"name":"FallAnim","weights":[],"animationId":"rbxassetid://128843247724636","category":"fall"},{"name":"JumpAnim","weights":[],"animationId":"rbxassetid://115431307725600","category":"jump"},{"name":"SwimAnim","weights":[],"animationId":"rbxassetid://138398654147849","category":"swim"},{"name":"SwimIdleAnim","weights":[],"animationId":"rbxassetid://138985135506970","category":"swimidle"},{"name":"ClimbAnim","weights":[],"animationId":"rbxassetid://92965330562263","category":"climb"}],"53839815522532":[{"name":"Animation1","weights":[9],"animationId":"rbxassetid://98885527817892","category":"idle"},{"name":"Animation2","weights":[1],"animationId":"rbxassetid://84830094561643","category":"idle"},{"name":"RunAnim","weights":[],"animationId":"rbxassetid://114347504241885","category":"run"},{"name":"WalkAnim","weights":[],"animationId":"rbxassetid://92526215150559","category":"walk"},{"name":"FallAnim","weights":[],"animationId":"rbxassetid://75792358925194","category":"fall"},{"name":"JumpAnim","weights":[],"animationId":"rbxassetid://102374936017891","category":"jump"},{"name":"SwimAnim","weights":[],"animationId":"rbxassetid://87288233406324","category":"swim"},{"name":"SwimIdleAnim","weights":[],"animationId":"rbxassetid://87984871211603","category":"swimidle"},{"name":"ClimbAnim","weights":[],"animationId":"rbxassetid://134650279454559","category":"climb"}]}]=====]

	local TYPE_NAMES = {
		[1] = "Image", [2] = "T-Shirt", [3] = "Audio", [4] = "Mesh", [5] = "Lua", [8] = "Hat", [9] = "Place",
		[10] = "Model", [11] = "Shirt", [12] = "Pants", [13] = "Decal", [17] = "Head", [18] = "Face", [19] = "Gear",
		[21] = "Badge", [24] = "Animation", [32] = "Package", [34] = "Game Pass", [38] = "Plugin", [40] = "MeshPart",
		[41] = "Hair Accessory", [42] = "Face Accessory", [43] = "Neck Accessory", [44] = "Shoulder Accessory",
		[45] = "Front Accessory", [46] = "Back Accessory", [47] = "Waist Accessory", [48] = "Climb Animation",
		[49] = "Death Animation", [50] = "Fall Animation", [51] = "Idle Animation", [52] = "Jump Animation",
		[53] = "Run Animation", [54] = "Swim Animation", [55] = "Walk Animation", [56] = "Pose Animation",
		[61] = "Emote", [62] = "Video", [78] = "Mood Animation", [79] = "Dynamic Head",
	}
	local MONTHS = {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}

	local function fmtId(n)
		return string.format("%.0f", tonumber(n) or 0)
	end

	local function commas(n)
		local s = tostring(math.floor(n))
		local f = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
		return (f:gsub("^,", ""))
	end

	local function fmtDate(iso)
		local y, m, d = tostring(iso or ""):match("^(%d+)%-(%d+)%-(%d+)")
		local month = MONTHS[tonumber(m or "")]
		if not (y and month) then
			return "-"
		end
		return string.format("%s %d, %s", month, tonumber(d), y)
	end

	local function fmtTime(t)
		t = math.max(0, tonumber(t) or 0)
		return string.format("%d:%02d", math.floor(t / 60), math.floor(t % 60))
	end

	local function priceText(data)
		if data.IsPublicDomain then
			return "Free"
		end
		if data.IsForSale then
			if type(data.PriceInRobux) == "number" then
				return data.PriceInRobux == 0 and "Free" or ("R$ " .. commas(data.PriceInRobux))
			end
			return "For sale"
		end
		return "Off sale"
	end

	local function parseAssetId(text)
		text = tostring(text or "")
		local digits = text:match("asset/(%d+)") or text:match("catalog/(%d+)") or text:match("library/(%d+)")
			or text:match("[?&]id=(%d+)") or text:match("%d+")
		if not digits then
			return nil, "Enter a numeric asset ID or paste an asset link."
		end
		digits = digits:gsub("^0+", "")
		if digits == "" then
			return nil, "Asset IDs start at 1."
		end
		if #digits > 16 then
			return nil, "That ID is too long to be a Roblox asset ID."
		end
		return digits
	end

	local function kindOf(typeId)
		if typeId == nil then
			return nil
		end
		if typeId == 3 then
			return "sound"
		end
		if typeId == 24 or typeId == 61 or typeId == 78 or (typeId >= 48 and typeId <= 56) then
			return "anim"
		end
		return "image"
	end

	local function isDirectAnimType(typeId)
		return typeId ~= nil and (typeId == 24 or (typeId >= 48 and typeId <= 56))
	end

	-- ---------- files and web ----------
	local function readJsonFile(name)
		local ok, text = pcall(function()
			if not (isfile and readfile) then
				return nil
			end
			if isfile(name) then
				return readfile(name)
			end
			if listfiles and isfolder then
				for _, f in ipairs(listfiles("")) do
					if isfolder(f) and isfile(f .. "/" .. name) then
						return readfile(f .. "/" .. name)
					end
				end
			end
			return nil
		end)
		if ok and type(text) == "string" and text ~= "" then
			return decode(text)
		end
		return nil
	end

	local function httpJson(hosts, path)
		local lastErr = "no response"
		for _, host in ipairs(hosts) do
			local ok, res = pcall(safeRequest, {Url = "https://" .. host .. path, Method = "GET"})
			if ok and type(res) == "table" then
				local code = tonumber(res.StatusCode) or 0
				if code >= 200 and code < 300 then
					local data = decode(res.Body)
					if type(data) == "table" then
						return true, data
					end
					lastErr = "bad response"
				else
					lastErr = "HTTP " .. code
				end
			else
				lastErr = tostring(res)
			end
		end
		return false, lastErr
	end

	local infoCache = {}
	local function fetchInfo(assetId)
		if infoCache[assetId] then
			return true, infoCache[assetId]
		end
		local ok, res = pcall(function()
			return MarketplaceService:GetProductInfo(assetId, Enum.InfoType.Asset)
		end)
		if ok and type(res) == "table" then
			infoCache[assetId] = res
			return true, res
		end
		return false, res
	end

	-- ---------- page frame ----------
	local page = make("ScrollingFrame", {
		Name = "AssetsPage", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 4, ScrollBarImageColor3 = C.scroll, CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = AUTO_Y, ScrollingDirection = Enum.ScrollingDirection.Y, Visible = false,
	}, body)
	TX.assetsPage = page
	pad(page, 10, 6, 12, 14)
	stack(page, 8)

	local order = 0
	local function nxt()
		order = order + 1
		return order
	end

	local function heading(text)
		local h = make("Frame", {Name = "Heading", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = nxt()}, page)
		label(h, {name = "HeadingText", text = text:upper(), font = F.head, ts = 14, color = C.yellow, size = UDim2.new(1, 0, 0, 22), pos = UDim2.new(0, 2, 0, 1)})
		make("Frame", {Name = "HeadingLine", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = C.ink, BorderSizePixel = 0}, h)
	end

	local function note(text)
		return label(page, {name = "Note", text = text, ts = 11, color = C.sub, wrap = true, size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = nxt()})
	end

	local setStatus
	local function copyText(text, what)
		local fn = setclipboard or toclipboard
		if fn then
			local ok = pcall(fn, text)
			setStatus(ok and ("Copied " .. what .. ": " .. clip(text, 60)) or "Copy failed.", ok and C.green or C.redText)
		else
			setStatus("Copy isn't supported by this executor. Select the ID in the lookup box instead.", C.amber)
		end
	end

	-- ================= PREVIEW =================
	heading("Preview")
	local card = make("Frame", {
		Name = "PreviewCard", BackgroundColor3 = C.raised, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = AUTO_Y, LayoutOrder = nxt(),
	}, page)
	corner(card, 6)
	stroke(card, C.ink, 2)
	pad(card, 8, 8, 8, 8)
	stack(card, 6)

	local stage = make("Frame", {
		Name = "Stage", BackgroundColor3 = C.code, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 176),
		ClipsDescendants = true, LayoutOrder = 1,
	}, card)
	corner(stage, 5)
	stroke(stage, C.ink, 2)

	local vp = make("ViewportFrame", {
		Name = "RigView", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Ambient = Color3.fromRGB(190, 190, 200),
		LightColor = Color3.new(1, 1, 1), LightDirection = Vector3.new(-0.4, -0.7, -0.6), Visible = false, Active = true,
	}, stage)
	local cam = make("Camera", {FieldOfView = 40}, vp)
	vp.CurrentCamera = cam
	local worldModel = make("WorldModel", {}, vp)

	local img = make("ImageLabel", {Name = "Thumb", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), ScaleType = Enum.ScaleType.Fit, Visible = false}, stage)
	local soundView = make("Frame", {Name = "SoundView", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Visible = false}, stage)
	label(soundView, {name = "SoundTitle", text = "SOUND", font = F.head, ts = 28, color = C.yellow, align = AX.Center, size = UDim2.new(1, 0, 0, 34), pos = UDim2.new(0, 0, 0.5, -34)})
	local soundBig = label(soundView, {name = "SoundTime", text = "0:00 / 0:00", font = F.bold, ts = 13, color = C.sub, align = AX.Center, size = UDim2.new(1, 0, 0, 18), pos = UDim2.new(0, 0, 0.5, 4)})
	local msg = label(stage, {
		name = "Msg", text = "Pick an emote below, or paste an asset ID in Lookup.", ts = 12, color = C.sub, wrap = true,
		align = AX.Center, size = UDim2.new(1, -24, 1, 0), pos = UDim2.new(0, 12, 0, 0),
	})

	local titleLbl = label(card, {name = "AssetName", text = "Nothing selected", font = F.bold, ts = 13, color = C.yellow, wrap = true, size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = 2})
	local metaLbl = label(card, {name = "AssetMeta", text = "Animations play on a copy of your character. Sounds play for you only.", ts = 11, color = C.sub, wrap = true, size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = 3})

	local bar = make("TextButton", {
		Name = "Seek", Text = "", AutoButtonColor = false, BackgroundColor3 = C.well, BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 12), LayoutOrder = 4, Visible = false,
	}, card)
	corner(bar, 4)
	stroke(bar, C.ink, 2)
	local fill = make("Frame", {Name = "Fill", BackgroundColor3 = C.yellow, BorderSizePixel = 0, Size = UDim2.new(0, 0, 1, 0)}, bar)
	corner(fill, 3)
	local timeLbl = label(card, {name = "Time", text = "", ts = 11, color = C.sub, align = AX.Center, size = UDim2.new(1, 0, 0, 14), order = 5})
	timeLbl.Visible = false

	local function btnRow(ord)
		local r = make("Frame", {Name = "BtnRow", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = ord}, card)
		stack(r, 6, true)
		return r
	end
	local function rb(row, text, kind, n, fn)
		local gaps = (n - 1) * 6
		return brick(row, {text = text, kind = kind, ts = 11, size = UDim2.new(1 / n, -gaps / n, 1, 0), onClick = fn})
	end

	local rowPlay = btnRow(6)
	local rowAnim = btnRow(7)
	local rowSound = btnRow(8)
	local rowCopy = btnRow(9)
	rowPlay.Visible, rowAnim.Visible, rowSound.Visible, rowCopy.Visible = false, false, false, false

	-- ---------- preview state ----------
	local pv = {kind = nil, id = nil, token = 0, track = nil, myTrack = nil, winner = nil, loop = true, spin = false, zoom = 1, vol = 0.5}
	local snd = make("Sound", {Name = "TONYO_AssetPreview", Volume = pv.vol}, gui)

	local rig, rigAnimator, rigSource = nil, nil, nil
	local yaw = math.pi + 0.35
	local dragging, lastX = false, 0

	local function setStage(mode, text)
		vp.Visible = mode == "anim"
		soundView.Visible = mode == "sound"
		img.Visible = mode == "image"
		msg.Visible = text ~= nil
		msg.Text = text or ""
		local timed = mode == "anim" or mode == "sound"
		bar.Visible = timed
		timeLbl.Visible = timed
		rowPlay.Visible = timed
		rowAnim.Visible = mode == "anim"
		rowSound.Visible = mode == "sound"
		rowCopy.Visible = pv.id ~= nil
		if not timed then
			fill.Size = UDim2.new(0, 0, 1, 0)
		end
	end

	local function haltPlayback()
		if pv.track then
			pcall(function()
				pv.track:Stop(0.1)
			end)
		end
		pcall(function()
			snd:Stop()
		end)
	end

	local function dropTrack()
		if pv.track then
			pcall(function()
				pv.track:Stop(0)
				pv.track:Destroy()
			end)
			pv.track = nil
		end
		pv.winner = nil
	end

	-- ---------- rig ----------
	local function clearRig()
		pv.track = nil
		if rig then
			pcall(function()
				rig:Destroy()
			end)
		end
		rig, rigAnimator, rigSource = nil, nil, nil
	end

	local function buildRig()
		if rig and rig.Parent and rigSource == player.Character and rigAnimator and rigAnimator.Parent then
			return true
		end
		clearRig()
		local char = player.Character
		local clone
		if char then
			local prev = char.Archivable
			char.Archivable = true
			local ok, res = pcall(function()
				return char:Clone()
			end)
			char.Archivable = prev
			if ok then
				clone = res
			end
		end
		if not clone then
			local ok, res = pcall(function()
				return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
			end)
			if ok then
				clone = res
			end
		end
		if not clone then
			return false
		end
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("ForceField") or d:IsA("BillboardGui")
				or d:IsA("Tool") or d:IsA("Highlight") or d:IsA("ParticleEmitter") then
				pcall(function()
					d:Destroy()
				end)
			end
		end
		local hum = clone:FindFirstChildOfClass("Humanoid")
		local root = clone:FindFirstChild("HumanoidRootPart")
		if not (hum and root) then
			clone:Destroy()
			return false
		end
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		root.Anchored = true
		clone.Name = "TONYO_Rig"
		clone:PivotTo(CFrame.new(0, 0, 0))
		clone.Parent = worldModel
		rig = clone
		rigSource = char
		rigAnimator = hum:FindFirstChildOfClass("Animator") or make("Animator", {}, hum)
		return true
	end

	-- ---------- animation loading ----------
	local function animCandidates(idText, direct)
		local list, seen = {}, {}
		local function add(a)
			if a and a ~= "" and not seen[a] then
				seen[a] = true
				list[#list + 1] = a
			end
		end
		local raw = "rbxassetid://" .. idText
		if direct then
			add(raw)
		end
		local ok, objs = pcall(function()
			return game:GetObjects(raw)
		end)
		if ok and type(objs) == "table" then
			for _, o in ipairs(objs) do
				pcall(function()
					local found = o:IsA("Animation") and o or o:FindFirstChildWhichIsA("Animation", true)
					if found then
						add(found.AnimationId)
					end
					local ks = o:IsA("KeyframeSequence") and o or o:FindFirstChildWhichIsA("KeyframeSequence", true)
					if ks then
						local rok, hash = pcall(function()
							return KeyframeProvider:RegisterKeyframeSequence(ks)
						end)
						if rok and hash then
							add(tostring(hash))
						end
					end
				end)
			end
		end
		add(raw)
		return list
	end

	local function loadAnimOn(animator, candidates)
		for _, aid in ipairs(candidates) do
			local anim = make("Animation", {AnimationId = aid})
			local ok, track = pcall(function()
				return animator:LoadAnimation(anim)
			end)
			if ok and track then
				local t0 = os.clock()
				while track.Length <= 0 and os.clock() - t0 < 5 do
					task.wait(0.1)
				end
				if track.Length > 0 then
					return track, aid
				end
				pcall(function()
					track:Destroy()
				end)
			end
		end
		return nil
	end

	-- ---------- recents + rows (forward declared) ----------
	local openAsset
	local recent = {}
	local recentFrame
	local addRow

	local function renderRecent()
		if not recentFrame then
			return
		end
		for _, ch in ipairs(recentFrame:GetChildren()) do
			if ch:IsA("GuiObject") then
				ch:Destroy()
			end
		end
		for i, it in ipairs(recent) do
			addRow(recentFrame, it, i)
		end
	end

	local function pushRecent(idText, name, kind)
		for i = #recent, 1, -1 do
			if recent[i].id == idText then
				table.remove(recent, i)
			end
		end
		table.insert(recent, 1, {id = idText, name = name, kind = kind, sub = "ID " .. idText})
		while #recent > 5 do
			table.remove(recent)
		end
		renderRecent()
	end

	-- ---------- open an asset in the preview ----------
	local lookupBox

	function openAsset(idText, hint)
		pv.token = pv.token + 1
		local token = pv.token
		haltPlayback()
		dropTrack()
		pv.kind = nil
		pv.id = idText
		if lookupBox then
			lookupBox.Text = idText
		end
		titleLbl.Text = hint and hint.name or ("Asset " .. idText)
		metaLbl.Text = "ID " .. idText
		setStage(nil, "Loading info...")
		setStatus("", C.sub)

		task.spawn(function()
			local ok, info = fetchInfo(tonumber(idText))
			if token ~= pv.token then
				return
			end
			local typeId = ok and tonumber(info.AssetTypeId) or nil
			local kind = kindOf(typeId) or (hint and hint.kind)
			if ok then
				titleLbl.Text = tostring(info.Name or titleLbl.Text)
				local creator = type(info.Creator) == "table" and info.Creator.Name and tostring(info.Creator.Name) or "Unknown"
				metaLbl.Text = (TYPE_NAMES[typeId] or "Asset"):upper() .. "  •  ID " .. idText .. "\nby " .. creator
					.. "  •  " .. priceText(info) .. "  •  Created " .. fmtDate(info.Created)
			elseif not kind then
				setStage(nil, "Couldn't find that asset. It may not exist, or Roblox is rate limiting you. Try again in a few seconds.")
				return
			else
				metaLbl.Text = "ID " .. idText .. "  •  details unavailable"
			end
			pushRecent(idText, titleLbl.Text, kind)

			if kind == "anim" then
				setStage(nil, "Loading animation...")
				if not buildRig() then
					setStage(nil, "Couldn't build the preview rig. Wait for your character to load and try again.")
					return
				end
				local direct = (hint and hint.direct) or isDirectAnimType(typeId)
				local cands = animCandidates(idText, direct)
				if token ~= pv.token then
					return
				end
				local track, winner = loadAnimOn(rigAnimator, cands)
				if token ~= pv.token then
					if track then
						pcall(function()
							track:Destroy()
						end)
					end
					return
				end
				if not track then
					setStage(nil, "This animation couldn't be loaded. It may be private, not an animation, or made for a different rig type (R6 vs R15).")
					return
				end
				pv.track, pv.winner = track, winner
				pv.kind = "anim"
				track.Priority = Enum.AnimationPriority.Action4
				track.Looped = pv.loop
				setStage("anim")
				track:Play(0)
			elseif kind == "sound" then
				setStage(nil, "Loading sound...")
				pcall(function()
					snd:Stop()
				end)
				snd.SoundId = "rbxassetid://" .. idText
				local t0 = os.clock()
				while not snd.IsLoaded and os.clock() - t0 < 8 and token == pv.token do
					task.wait(0.1)
				end
				if token ~= pv.token then
					return
				end
				if not snd.IsLoaded then
					setStage(nil, "This sound can't be loaded. It may be private, moderated or removed.")
					return
				end
				pv.kind = "sound"
				snd.Looped = pv.loop
				snd.Volume = pv.vol
				setStage("sound")
				snd.TimePosition = 0
				snd:Play()
			else
				pv.kind = "image"
				img.Image = "rbxthumb://type=Asset&id=" .. idText .. "&w=420&h=420"
				setStage("image")
			end
		end)
	end

	-- ---------- preview controls ----------
	local loopBtn, spinBtn, volBtn

	rb(rowPlay, "PLAY", "green", 3, function()
		if pv.kind == "anim" and pv.track then
			pcall(function()
				pv.track:Stop(0)
				pv.track.Looped = pv.loop
				pv.track:Play(0)
			end)
		elseif pv.kind == "sound" and snd.IsLoaded then
			snd.Looped = pv.loop
			snd.TimePosition = 0
			snd:Play()
		end
	end)
	rb(rowPlay, "STOP", "red", 3, function()
		haltPlayback()
	end)
	loopBtn = rb(rowPlay, "LOOP: ON", "gray", 3, function()
		pv.loop = not pv.loop
		loopBtn.Text = "LOOP: " .. (pv.loop and "ON" or "OFF")
		if pv.track then
			pcall(function()
				pv.track.Looped = pv.loop
			end)
		end
		snd.Looped = pv.loop
	end)

	local function myAnimator()
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum then
			return nil
		end
		return hum:FindFirstChildOfClass("Animator") or make("Animator", {}, hum)
	end

	rb(rowAnim, "ON ME", "blue", 4, function()
		if pv.kind ~= "anim" or not pv.winner then
			setStatus("Preview an animation first.", C.amber)
			return
		end
		local animator = myAnimator()
		if not animator then
			setStatus("Your character isn't loaded.", C.redText)
			return
		end
		if pv.myTrack then
			pcall(function()
				pv.myTrack:Stop(0.1)
			end)
			pv.myTrack = nil
		end
		local winner = pv.winner
		task.spawn(function()
			local track = loadAnimOn(animator, {winner})
			if track then
				track.Priority = Enum.AnimationPriority.Action4
				track.Looped = pv.loop
				track:Play(0.1)
				pv.myTrack = track
				setStatus("Playing on your character.", C.green)
			else
				setStatus("Couldn't load it on your character.", C.redText)
			end
		end)
	end)
	rb(rowAnim, "STOP ME", "gray", 4, function()
		if pv.myTrack then
			pcall(function()
				pv.myTrack:Stop(0.1)
			end)
			pv.myTrack = nil
		end
		setStatus("", C.sub)
	end)
	spinBtn = rb(rowAnim, "SPIN: OFF", "gray", 4, function()
		pv.spin = not pv.spin
		spinBtn.Text = "SPIN: " .. (pv.spin and "ON" or "OFF")
	end)
	local zooms = {1, 0.7, 1.4}
	local zoomIdx = 1
	rb(rowAnim, "ZOOM", "gray", 4, function()
		zoomIdx = zoomIdx % #zooms + 1
		pv.zoom = zooms[zoomIdx]
	end)

	local vols = {0.25, 0.5, 0.75, 1}
	local volIdx = 2
	volBtn = rb(rowSound, "VOLUME: 50%", "gray", 1, function()
		volIdx = volIdx % #vols + 1
		pv.vol = vols[volIdx]
		snd.Volume = pv.vol
		volBtn.Text = "VOLUME: " .. math.floor(pv.vol * 100) .. "%"
	end)

	rb(rowCopy, "COPY ID", "yellow", 3, function()
		if pv.id then
			copyText(pv.id, "ID")
		end
	end)
	rb(rowCopy, "COPY LINK", "gray", 3, function()
		if pv.id then
			copyText("https://create.roblox.com/store/asset/" .. pv.id, "link")
		end
	end)
	rb(rowCopy, "RBXASSETID", "gray", 3, function()
		if pv.id then
			copyText("rbxassetid://" .. pv.id, "asset string")
		end
	end)

	-- seek bar
	bar.InputBegan:Connect(function(input)
		if not isPress(input) then
			return
		end
		local rel = math.clamp((input.Position.X - bar.AbsolutePosition.X) / math.max(1, bar.AbsoluteSize.X), 0, 1)
		if pv.kind == "anim" and pv.track and pv.track.Length > 0 then
			pcall(function()
				if not pv.track.IsPlaying then
					pv.track:Play(0)
				end
				pv.track.TimePosition = rel * pv.track.Length
			end)
		elseif pv.kind == "sound" and snd.TimeLength > 0 then
			snd.TimePosition = rel * snd.TimeLength
		end
	end)

	-- drag the rig view to rotate it
	vp.InputBegan:Connect(function(input)
		if isPress(input) then
			dragging, lastX = true, input.Position.X
		end
	end)
	conns[#conns + 1] = UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			yaw = yaw - (input.Position.X - lastX) * 0.012
			lastX = input.Position.X
		end
	end)
	conns[#conns + 1] = UserInputService.InputEnded:Connect(function(input)
		if isPress(input) then
			dragging = false
		end
	end)

	conns[#conns + 1] = RunService.RenderStepped:Connect(function(dt)
		if not page.Visible then
			return
		end
		if pv.kind == "anim" and rig and rig.Parent then
			if pv.spin and not dragging then
				yaw = yaw + dt * 0.9
			end
			local root = rig:FindFirstChild("HumanoidRootPart")
			if root then
				local focus = root.Position
				local dist = 9.5 * pv.zoom
				cam.CFrame = CFrame.lookAt(focus + Vector3.new(math.sin(yaw) * dist, 1.4, math.cos(yaw) * dist), focus)
			end
			local t = pv.track
			if t and t.Length > 0 then
				fill.Size = UDim2.new(math.clamp(t.TimePosition / t.Length, 0, 1), 0, 1, 0)
				timeLbl.Text = string.format("%.2fs / %.2fs%s", t.TimePosition, t.Length, t.IsPlaying and "" or "  (stopped)")
			end
		elseif pv.kind == "sound" and snd.IsLoaded and snd.TimeLength > 0 then
			fill.Size = UDim2.new(math.clamp(snd.TimePosition / snd.TimeLength, 0, 1), 0, 1, 0)
			local text = fmtTime(snd.TimePosition) .. " / " .. fmtTime(snd.TimeLength)
			soundBig.Text = text
			timeLbl.Text = snd.IsPlaying and "Playing" or "Stopped"
		end
	end)

	-- status line under the preview
	local statusLbl = label(page, {name = "Status", text = "", ts = 11, color = C.sub, wrap = true, size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = nxt()})
	function setStatus(text, color)
		statusLbl.Text = text or ""
		statusLbl.TextColor3 = color or C.sub
	end

	-- ================= LOOKUP =================
	heading("Lookup")
	local lookupRow = make("Frame", {Name = "LookupRow", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = nxt()}, page)
	lookupBox = textBox(lookupRow, {name = "LookupBox", placeholder = "Asset ID or link...", size = UDim2.new(1, -64, 1, 0)})
	local function runLookup()
		local idText, err = parseAssetId(lookupBox.Text)
		if not idText then
			setStatus(err, C.redText)
			return
		end
		openAsset(idText, nil)
	end
	brick(lookupRow, {name = "LookupGo", text = "GO", kind = "blue", ts = 13, size = UDim2.new(0, 58, 1, 0), pos = UDim2.new(1, -58, 0, 0), onClick = runLookup})
	lookupBox.FocusLost:Connect(function(enter)
		if enter then
			runLookup()
		end
	end)
	note("Works with animations, emotes, sounds, images, models and more. The type is detected automatically.")

	-- ================= CATALOG =================
	heading("Catalog")

	local SOURCES = {
		{name = "EMOTES", set = "emotes", kind = "anim"},
		{name = "GAME ANIMS", set = "anims", kind = "anim", direct = true},
		{name = "AUDIO", toolbox = 3, kind = "sound"},
		{name = "MUSIC", toolbox = 300, kind = "sound"},
		{name = "SOUND FX", toolbox = 301, kind = "sound"},
		{name = "STORE ANIMS", toolbox = 24, kind = "anim"},
		{name = "MODELS", toolbox = 10},
		{name = "DECALS", toolbox = 13},
		{name = "AVATAR", catalog = 1},
	}
	local cat = {src = 1, query = "", page = 1, matches = nil, token = 0, cursors = {}, hasMore = false, started = false, total = 0}

	local chipFrame = make("Frame", {Name = "Sources", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, LayoutOrder = nxt()}, page)
	do
		local l = stack(chipFrame, 5, true)
		l.Wraps = true
	end
	local chips = {}
	local function styleChips()
		for i, b in ipairs(chips) do
			if i == cat.src then
				paint(b, C.yellow, C.yellowLip, C.yellowInk)
			else
				paint(b, C.raised, C.raisedLip, C.sub)
			end
		end
	end

	local searchRow = make("Frame", {Name = "SearchRow", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = nxt()}, page)
	local searchBox = textBox(searchRow, {name = "CatalogSearch", placeholder = "Search the catalog (leave empty for all)...", size = UDim2.new(1, -64, 1, 0)})

	local statusRow = make("Frame", {Name = "CatalogStatusRow", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = nxt()}, page)
	local catStatus = label(statusRow, {name = "CatalogStatus", text = "", ts = 11, color = C.sub, size = UDim2.new(1, -68, 1, 0)})

	local listFrame = make("Frame", {Name = "CatalogList", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, LayoutOrder = nxt()}, page)
	stack(listFrame, 6)
	local listMsg = label(listFrame, {name = "ListMsg", text = "", ts = 12, color = C.sub, wrap = true, align = AX.Center, size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = 0})

	local pager = make("Frame", {Name = "Pager", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = nxt()}, page)
	local pageLbl = label(pager, {name = "PageLabel", text = "", font = F.bold, ts = 11, color = C.sub, align = AX.Center, size = UDim2.new(1, -200, 1, 0), pos = UDim2.new(0, 100, 0, 0)})

	-- ---------- rows ----------
	local TAGS = {anim = "ANIM", sound = "SOUND"}
	function addRow(parent, it, idx)
		local row = make("Frame", {Name = "Row", BackgroundColor3 = C.raised, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 54), LayoutOrder = idx}, parent)
		corner(row, 6)
		stroke(row, C.ink, 2)

		local thumb = make("Frame", {Name = "ThumbBox", BackgroundColor3 = C.well, BorderSizePixel = 0, Size = UDim2.new(0, 42, 0, 42), Position = UDim2.new(0, 6, 0, 6)}, row)
		corner(thumb, 4)
		label(thumb, {name = "Tag", text = it.emote and "EMOTE" or (TAGS[it.kind] or "ASSET"), font = F.bold, ts = 8, color = C.faint, align = AX.Center, size = UDim2.new(1, 0, 1, 0)})
		if it.emote or not (it.kind == "sound" or it.kind == "anim") then
			local im = make("ImageLabel", {Name = "Thumb", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), ScaleType = Enum.ScaleType.Fit, Image = "rbxthumb://type=Asset&id=" .. it.id .. "&w=150&h=150"}, thumb)
			corner(im, 4)
		end

		label(row, {name = "Name", text = it.name, font = F.bold, ts = 12, color = C.text, size = UDim2.new(1, -120, 0, 18), pos = UDim2.new(0, 54, 0, 8)})
		label(row, {name = "Sub", text = (it.sub and it.sub ~= "") and it.sub or ("ID " .. it.id), ts = 10, color = C.faint, size = UDim2.new(1, -120, 0, 16), pos = UDim2.new(0, 54, 0, 28)})

		local hit = make("TextButton", {Name = "Hit", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.new(1, -62, 1, 0)}, row)
		hit.Activated:Connect(function()
			openAsset(it.id, it)
		end)
		brick(row, {name = "View", text = "VIEW", kind = "blue", ts = 10, size = UDim2.new(0, 48, 0, 20), pos = UDim2.new(1, -54, 0, 5), onClick = function()
			openAsset(it.id, it)
		end})
		brick(row, {name = "Copy", text = "COPY", kind = "yellow", ts = 10, size = UDim2.new(0, 48, 0, 20), pos = UDim2.new(1, -54, 0, 29), onClick = function()
			copyText(it.id, "ID")
		end})
		return row
	end

	local function clearList()
		for _, ch in ipairs(listFrame:GetChildren()) do
			if ch:IsA("GuiObject") and ch ~= listMsg then
				ch:Destroy()
			end
		end
	end

	-- ---------- offline data sets ----------
	local sets = {
		emotes = {ids = {}, names = {}, lower = {}, subs = {}, count = 0, loaded = false, origin = ""},
		anims = {ids = {}, names = {}, lower = {}, subs = {}, count = 0, loaded = false, origin = ""},
	}

	local function trim(s)
		s = tostring(s or "")
		s = s:gsub("^%s+", "")
		s = s:gsub("%s+$", "")
		return s
	end

	local function loadSet(which)
		local set = sets[which]
		if set.loaded then
			return
		end
		while set.loading do
			task.wait(0.1)
			if set.loaded then
				return
			end
		end
		set.loading = true
		local isEmote = which == "emotes"
		local file = isEmote and EMOTE_FILE or ANIM_FILE
		local data = readJsonFile(file)
		local origin = file
		local good
		if isEmote then
			good = type(data) == "table" and #data > 0
		else
			good = type(data) == "table" and next(data) ~= nil
		end
		if not good then
			data = decode(isEmote and EMBED_EMOTES or EMBED_ANIMS) or {}
			origin = "built-in"
		end

		local ids, names, lower, subs, n = {}, {}, {}, {}, 0
		if isEmote then
			for _, e in ipairs(data) do
				local id = type(e) == "table" and tonumber(e.id)
				if id then
					n = n + 1
					local idText = fmtId(id)
					local name = trim(e.name)
					if name == "" then
						name = "Emote " .. idText
					end
					ids[n], names[n], lower[n], subs[n] = idText, name, name:lower(), "Emote  •  " .. idText
					if n % 6000 == 0 then
						task.wait()
					end
				end
			end
		else
			local keys = {}
			for k in pairs(data) do
				keys[#keys + 1] = tostring(k)
			end
			table.sort(keys)
			for _, gameId in ipairs(keys) do
				local list = data[gameId]
				if type(list) == "table" then
					for _, e in ipairs(list) do
						local idText = type(e) == "table" and tostring(e.animationId or ""):match("%d+")
						if idText then
							n = n + 1
							local name = tostring(e.category or "anim") .. " - " .. trim(e.name)
							local sub = "Game " .. gameId .. "  •  " .. idText
							ids[n], names[n], subs[n] = idText, name, sub
							lower[n] = (name .. " " .. sub):lower()
						end
					end
				end
			end
		end
		set.ids, set.names, set.lower, set.subs, set.count = ids, names, lower, subs, n
		set.origin = origin
		set.loaded = true
		set.loading = false
	end

	local function filterSet(set, query)
		query = trim(query):lower()
		local terms = {}
		for w in query:gmatch("%S+") do
			terms[#terms + 1] = w
		end
		if #terms == 0 then
			return nil
		end
		local out, n = {}, 0
		local lower, ids = set.lower, set.ids
		for i = 1, set.count do
			local hay = lower[i]
			local ok = true
			for _, t in ipairs(terms) do
				if not hay:find(t, 1, true) and not ids[i]:find(t, 1, true) then
					ok = false
					break
				end
			end
			if ok then
				n = n + 1
				out[n] = i
			end
		end
		return out
	end

	-- ---------- store browse ----------
	local function fetchStore(src, query, pageNo, cursor)
		local kw = HttpService:UrlEncode(query)
		local items = {}
		if src.toolbox then
			local path = string.format("/toolbox-service/v1/marketplace/%d?limit=%d&pageNumber=%d&keyword=%s", src.toolbox, PER, pageNo, kw)
			local ok, data = httpJson(TOOLBOX_HOSTS, path)
			if not ok then
				return false, data
			end
			if type(data.data) ~= "table" then
				return false, "unexpected response"
			end
			local ids = {}
			for _, entry in ipairs(data.data) do
				local raw = entry.id
				if raw == nil and type(entry.asset) == "table" then
					raw = entry.asset.id
				end
				if raw then
					ids[#ids + 1] = fmtId(raw)
				end
			end
			local details = {}
			if #ids > 0 then
				local dok, dd = httpJson(TOOLBOX_HOSTS, "/toolbox-service/v1/items/details?assetIds=" .. HttpService:UrlEncode(table.concat(ids, ",")))
				if dok and type(dd.data) == "table" then
					for _, entry in ipairs(dd.data) do
						local asset = type(entry.asset) == "table" and entry.asset or entry
						if asset.id then
							details[fmtId(asset.id)] = {name = asset.name, creator = type(entry.creator) == "table" and entry.creator.name or nil}
						end
					end
				end
			end
			for _, id in ipairs(ids) do
				local d = details[id]
				items[#items + 1] = {
					id = id, kind = src.kind, direct = src.direct,
					name = d and d.name and tostring(d.name) or ("Asset " .. id),
					sub = d and d.creator and ("by " .. tostring(d.creator) .. "  •  " .. id) or ("ID " .. id),
				}
			end
			return true, items, #ids >= PER, nil
		end

		local path = string.format("/v1/search/items/details?Category=%d&Limit=10&Keyword=%s", src.catalog, kw)
		if cursor then
			path = path .. "&Cursor=" .. HttpService:UrlEncode(cursor)
		end
		local ok, data = httpJson(CATALOG_HOSTS, path)
		if not ok then
			return false, data
		end
		if type(data.data) ~= "table" then
			return false, "unexpected response"
		end
		for _, entry in ipairs(data.data) do
			if entry.id and entry.itemType ~= "Bundle" and entry.bundleType == nil then
				local id = fmtId(entry.id)
				items[#items + 1] = {
					id = id, name = tostring(entry.name or ("Asset " .. id)),
					sub = entry.creatorName and ("by " .. tostring(entry.creatorName) .. "  •  " .. id) or ("ID " .. id),
				}
			end
		end
		local nextCursor = type(data.nextPageCursor) == "string" and data.nextPageCursor or nil
		return true, items, nextCursor ~= nil, nextCursor
	end

	-- ---------- refresh ----------
	local jumpBtns = {}
	local function setPagerMode(offline)
		for _, b in ipairs(jumpBtns) do
			b.Visible = offline
		end
	end

	local function showMsg(text)
		clearList()
		listMsg.Text = text
		listMsg.Visible = text ~= ""
	end

	local refresh
	function refresh(reset)
		local src = SOURCES[cat.src]
		if reset then
			cat.page = 1
			cat.cursors = {}
			cat.matches = nil
		end
		cat.token = cat.token + 1
		local token = cat.token
		setPagerMode(src.set ~= nil)

		if src.set then
			local set = sets[src.set]
			if not set.loaded then
				showMsg("Loading " .. src.name:lower() .. "...")
				catStatus.Text = "Loading..."
				loadSet(src.set)
				if token ~= cat.token then
					return
				end
			end
			if reset then
				cat.matches = filterSet(set, cat.query)
			end
			local total = cat.matches and #cat.matches or set.count
			local pages = math.max(1, math.ceil(total / PER))
			cat.page = math.clamp(cat.page, 1, pages)
			cat.total = total
			local items = {}
			for k = (cat.page - 1) * PER + 1, math.min(total, cat.page * PER) do
				local i = cat.matches and cat.matches[k] or k
				items[#items + 1] = {
					id = set.ids[i], name = set.names[i], sub = set.subs[i], kind = src.kind, direct = src.direct,
					emote = src.set == "emotes",
				}
			end
			clearList()
			listMsg.Visible = total == 0
			listMsg.Text = total == 0 and "Nothing matches that search." or ""
			for i, it in ipairs(items) do
				addRow(listFrame, it, i)
			end
			pageLbl.Text = commas(cat.page) .. " / " .. commas(pages)
			local origin = set.origin == "built-in" and "built-in list (put " .. (src.set == "emotes" and EMOTE_FILE or ANIM_FILE) .. " in your workspace for the full catalog)" or set.origin
			catStatus.Text = (cat.matches and (commas(total) .. " of " .. commas(set.count) .. " match") or (commas(set.count) .. " total")) .. "  •  " .. origin
			catStatus.TextColor3 = set.origin == "built-in" and C.amber or C.sub
			return
		end

		showMsg("Loading...")
		catStatus.Text = "Loading..."
		catStatus.TextColor3 = C.sub
		local ok, items, hasMore, nextCursor = fetchStore(src, cat.query, cat.page, cat.cursors[cat.page])
		if token ~= cat.token then
			return
		end
		if not ok then
			showMsg("Couldn't load (" .. clip(items, 80) .. ").\nStore browsing needs an executor with request(). Tap RELOAD to retry.")
			catStatus.Text = "Failed to load"
			catStatus.TextColor3 = C.redText
			return
		end
		cat.cursors[cat.page + 1] = nextCursor
		cat.hasMore = hasMore
		clearList()
		listMsg.Visible = #items == 0
		listMsg.Text = #items == 0 and "No results found." or ""
		for i, it in ipairs(items) do
			addRow(listFrame, it, i)
		end
		pageLbl.Text = "Page " .. cat.page .. (hasMore and "" or "  (end)")
		catStatus.Text = src.name .. "  •  " .. #items .. " shown"
		catStatus.TextColor3 = C.sub
	end

	local function go(reset)
		task.spawn(refresh, reset)
	end

	local function submitSearch()
		cat.query = searchBox.Text
		go(true)
	end
	brick(searchRow, {name = "SearchGo", text = "GO", kind = "blue", ts = 13, size = UDim2.new(0, 58, 1, 0), pos = UDim2.new(1, -58, 0, 0), onClick = submitSearch})
	searchBox.FocusLost:Connect(function(enter)
		if enter then
			submitSearch()
		end
	end)
	brick(statusRow, {
		name = "Reload", text = "RELOAD", kind = "gray", ts = 10, size = UDim2.new(0, 62, 0, 22), pos = UDim2.new(1, -62, 0, 1),
		onClick = function()
			local src = SOURCES[cat.src]
			if src.set then
				sets[src.set].loaded = false
			end
			go(true)
		end,
	})

	for i, src in ipairs(SOURCES) do
		local b = brick(chipFrame, {
			name = "Src_" .. src.name, text = src.name, kind = "gray", ts = 10, fg = C.sub, order = i,
			size = UDim2.new(0, math.max(46, #src.name * 8 + 14), 0, 24),
			onClick = function()
				cat.src = i
				styleChips()
				go(true)
			end,
		})
		chips[i] = b
	end
	styleChips()

	-- pager buttons
	local function step(n)
		local src = SOURCES[cat.src]
		if src.set then
			local pages = math.max(1, math.ceil(cat.total / PER))
			cat.page = math.clamp(cat.page + n, 1, pages)
		else
			if n > 0 and not cat.hasMore then
				return
			end
			if n < 0 and cat.page <= 1 then
				return
			end
			cat.page = cat.page + n
		end
		go(false)
	end
	jumpBtns[1] = brick(pager, {name = "Back10", text = "-10", kind = "gray", ts = 11, size = UDim2.new(0, 38, 1, 0), pos = UDim2.new(0, 0, 0, 0), onClick = function() step(-10) end})
	brick(pager, {name = "Prev", text = "PREV", kind = "gray", ts = 11, size = UDim2.new(0, 54, 1, 0), pos = UDim2.new(0, 42, 0, 0), onClick = function() step(-1) end})
	brick(pager, {name = "Next", text = "NEXT", kind = "gray", ts = 11, size = UDim2.new(0, 54, 1, 0), pos = UDim2.new(1, -96, 0, 0), onClick = function() step(1) end})
	jumpBtns[2] = brick(pager, {name = "Fwd10", text = "+10", kind = "gray", ts = 11, size = UDim2.new(0, 38, 1, 0), pos = UDim2.new(1, -38, 0, 0), onClick = function() step(10) end})

	-- ================= RECENT =================
	heading("Recent")
	recentFrame = make("Frame", {Name = "RecentList", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, LayoutOrder = nxt()}, page)
	stack(recentFrame, 6)
	note("Animations load on a copy of your character, so R15 animations need an R15 avatar. Sounds and animations that are private, moderated or removed will not load.")

	setStage(nil, "Pick an emote below, or paste an asset ID in Lookup.")

	function TX.assetsOpen()
		if not cat.started then
			cat.started = true
			go(true)
		end
	end

	function TX.assetsHide()
		haltPlayback()
	end
end)()

function view.selectTab(id)
	if id == "admin" and not isAdmin() then
		id = "chat"
	end
	picker.close()
	viewer.Visible = false
	chat.Visible = id == "chat"
	setup.Visible = id == "setup"
	news.Visible = id == "news"
	exportPage.Visible = id == "export"
	playersPage.Visible = id == "players"
	auditPage.Visible = id == "audit"
	adminPage.Visible = id == "admin"
	if TX.buildPage then
		TX.buildPage.Visible = id == "build"
		if id == "build" and TX.buildRefresh then
			pcall(TX.buildRefresh)
		end
	end
	if TX.assetsPage then
		TX.assetsPage.Visible = id == "assets"
		if id == "assets" then
			if TX.assetsOpen then
				pcall(TX.assetsOpen)
			end
		elseif TX.assetsHide then
			pcall(TX.assetsHide)
		end
	end
	if TX.globalPage then
		TX.globalPage.Visible = id == "global"
		if id == "global" and TX.globalOpen then
			pcall(TX.globalOpen)
		end
	end
	if id == "players" then
		playersApi.rebuild()
		pcall(playersApi.tick)
	end
	for k, b in pairs(tabs) do
		if k == id then
			paint(b, C.yellow, C.yellowLip, C.yellowInk)
		else
			paint(b, C.raised, C.raisedLip, C.sub)
		end
	end
	if id == "setup" then
		app.refreshSetup()
	end
end

local history = {}
local busy = false
local minimized = false
local scanning = false

function app.isBusy()
	return busy
end
local testing = {}
local pickToken = 0

local function anyKey()
	for _, p in ipairs(PROVIDERS) do
		if hasKey(p) then
			return true
		end
	end
	return false
end

local function routeText()
	if isAuto() then
		local n = 0
		for _, p in ipairs(PROVIDERS) do
			if hasKey(p) then
				n = n + 1
			end
		end
		if n == 0 then
			return "Auto, add a key in Setup"
		end
		if lastGood and PROVIDER_BY_ID[lastGood] then
			return "Auto, last used " .. PROVIDER_BY_ID[lastGood].name
		end
		return "Auto, " .. n .. (n == 1 and " provider" or " providers")
	end
	local p = getProvider()
	if not hasKey(p) then
		return p.name .. ", add a key in Setup"
	end
	local pin = pinnedModel(p)
	return p.name .. (pin and (", " .. pin) or ", auto model")
end

local function refreshRoute()
	if not busy then
		view.setStatus("idle", routeText())
	end
end

local function modelLabel(p)
	local pin = pinnedModel(p)
	if pin then
		return pin
	end
	local f = settings.found[p.id]
	if type(f) == "table" and type(f.ids) == "table" and f.ids[1] then
		return "Auto (" .. f.ids[1] .. ")"
	end
	return "Auto"
end

function app.refreshSetup()
	if onlineValue then
		onlineValue.Text = settings.ping == false and "OFF" or "ON"
		onlineValue.TextColor3 = settings.ping == false and C.faint or C.green
		if ONLINE_DB:gsub("%s", "") == "" then
			onlineNote.Text = "Not set up. The script owner pastes a database link into ONLINE_DB at the top of the script."
		elseif online.count then
			onlineNote.Text = "Live. " .. online.count .. " people are using TONYO right now."
		else
			onlineNote.Text = "Status: " .. online.status
		end
	end
	providerValue.Text = isAuto() and "Auto" or getProvider().name
	if isAuto() then
		modelValue.Text = "Chosen for you"
		modelValue.TextColor3 = C.faint
		engineNote.Text = "Auto uses every provider that has a key, starting with the one that worked last. If one is rate limited or out of credit, it moves to the next. Each provider uses the best model it has."
	else
		local p = getProvider()
		modelValue.Text = modelLabel(p)
		modelValue.TextColor3 = C.text
		engineNote.Text = "Auto model reads " .. p.name .. "'s model list and picks a good one. Tap Model to pin a different one."
	end
	for _, p in ipairs(PROVIDERS) do
		local r = keyRows[p.id]
		local saved = hasKey(p)
		local cool = (cooldown[p.id] or 0) - os.clock()
		local k = settings.keys[p.id]
		r.dot.BackgroundColor3 = saved and (cool > 5 and C.amber or C.green) or C.faint
		local text
		if saved and cool > 5 then
			text = "Busy " .. math.ceil(cool) .. "s"
		elseif p.id == "custom" then
			text = saved and "Ready" or "Set a URL"
		elseif saved then
			text = "Saved ..." .. tostring(k):sub(-4)
		else
			text = "Add key"
		end
		r.status.Text = text
		if type(k) == "string" and k ~= "" then
			r.keyBox.PlaceholderText = "Saved (..." .. k:sub(-4) .. "), paste to replace"
		else
			r.keyBox.PlaceholderText = p.keyOptional and "Key (optional)" or ("Paste your " .. p.name .. " key")
		end
	end
end

local function pickProvider()
	pickToken = pickToken + 1
	local items = {{label = "Auto", sub = "Best available. Switches provider if one fails.", value = "auto", selected = isAuto()}}
	for _, p in ipairs(PROVIDERS) do
		items[#items + 1] = {
			label = p.name,
			sub = hasKey(p) and "Key saved" or "No key yet",
			value = p.id,
			selected = not isAuto() and settings.engine == p.id,
		}
	end
	picker.open({
		title = "Provider",
		items = items,
		onPick = function(id)
			settings.engine = id
			saveSettings()
			picker.close()
			app.refreshSetup()
			refreshRoute()
			if id ~= "auto" and not hasKey(PROVIDER_BY_ID[id]) then
				view.openKeyRow(id, true)
			end
		end,
	})
end

local function pickModel()
	if isAuto() then
		return
	end
	pickToken = pickToken + 1
	local mine = pickToken
	local p = getProvider()

	local function build(ids)
		local pin = pinnedModel(p)
		local out = {{label = "Auto", sub = "Picks the best model for you", value = "", selected = pin == nil}}
		if pin and not hasValue(ids, pin) then
			out[#out + 1] = {label = pin, value = pin, selected = true}
		end
		for _, id in ipairs(ids) do
			out[#out + 1] = {label = id, value = id, selected = pin == id}
		end
		return out
	end

	local function choose(value)
		settings.models[p.id] = value ~= "" and value or nil
		saveSettings()
		picker.close()
		app.refreshSetup()
		refreshRoute()
	end

	picker.open({
		title = "Model for " .. p.name,
		items = build({}),
		filter = true,
		placeholder = "Filter, or type a name and press enter",
		note = "Loading models...",
		onPick = choose,
		onEnter = choose,
	})
	if not hasKey(p) then
		picker.update(build({}), "Add a key first to load the model list.")
		return
	end
	task.spawn(function()
		local ids = discoverModels(p, settings.keys[p.id] or "", false)
		if mine ~= pickToken then
			return
		end
		if ids then
			picker.update(build(ids), #ids .. " models, best first")
		else
			picker.update(build({}), "Couldn't load the list. Type a model name and press enter.")
		end
	end)
end

providerRow.Activated:Connect(pickProvider)
modelRow.Activated:Connect(pickModel)

local function resetProviderCache(p)
	settings.found[p.id] = nil
	liveRanked[p.id] = nil
	listFailedUntil[p.id] = nil
	cooldown[p.id] = nil
end

function app.saveKey(p, text)
	local s = tostring(text or ""):gsub("%s", "")
	if s == "" then
		return
	end
	local found, strong = detectProvider(s)
	local target = p
	if found and strong and found ~= p and p.id ~= "custom" then
		target = found
		local r = keyRows[p.id]
		r.msg.Visible = true
		r.msg.TextColor3 = C.amber
		r.msg.Text = "That looks like a " .. found.name .. " key, so it was saved there."
	end
	settings.keys[target.id] = s
	resetProviderCache(target)
	saveSettings()
	app.refreshSetup()
	refreshRoute()
	if target ~= p then
		view.openKeyRow(target.id, true)
	end
	app.testKey(target)
end

function app.addAnyKey(text)
	local s = tostring(text or ""):gsub("%s", "")
	if s == "" then
		return
	end
	quickMsg.Visible = true
	local p = detectProvider(s)
	if not p then
		quickMsg.TextColor3 = C.redText
		quickMsg.Text = "Couldn't tell which provider that key belongs to. Open the provider under API keys and paste it there."
		return
	end
	quickMsg.TextColor3 = C.green
	quickMsg.Text = "Looks like a " .. p.name .. " key. Saved, checking it now."
	settings.keys[p.id] = s
	resetProviderCache(p)
	saveSettings()
	app.refreshSetup()
	refreshRoute()
	view.openKeyRow(p.id, true)
	app.testKey(p)
end

function app.removeKey(p)
	settings.keys[p.id] = nil
	resetProviderCache(p)
	saveSettings()
	local r = keyRows[p.id]
	r.msg.Visible = true
	r.msg.TextColor3 = C.sub
	r.msg.Text = "Key removed."
	app.refreshSetup()
	refreshRoute()
end

function app.saveUrl(text)
	local u = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if u == settings.customUrl then
		return
	end
	settings.customUrl = u
	resetProviderCache(PROVIDER_BY_ID.custom)
	saveSettings()
	app.refreshSetup()
	refreshRoute()
end

function app.testKey(p)
	if testing[p.id] then
		return
	end
	testing[p.id] = true
	local r = keyRows[p.id]
	r.msg.Visible = true
	r.msg.TextColor3 = C.sub
	r.msg.Text = "Checking..."
	task.spawn(function()
		local ok, state, text = pcall(testProvider, p)
		testing[p.id] = nil
		if not ok then
			state, text = "fail", "The check failed: " .. oneLine(state, 120)
		end
		r.msg.Text = text
		if state == "ok" then
			r.msg.TextColor3 = C.green
		elseif state == "warn" then
			r.msg.TextColor3 = C.amber
		elseif state == "fail" then
			r.msg.TextColor3 = C.redText
		else
			r.msg.TextColor3 = C.sub
		end
		app.refreshSetup()
	end)
end

function app.scan()
	if scanning then
		return
	end
	scanning = true
	task.spawn(function()
		view.setStatus("busy", "Scanning the game")
		local ok, text, count = pcall(scanGame)
		scanning = false
		if ok then
			contextText = text
			view.setScanned(true)
			view.setStatus("ok", "Scanned " .. count .. " objects")
			view.log("Scanned " .. count .. " objects", "ok")
			view.note("Scanned " .. count .. " objects. They are attached to every message now. Type @Workspace.Path to read one object or script.")
		else
			view.setStatus("fail", "Scan failed")
			view.note("The scan failed: " .. clip(text, 160), C.redText)
		end
		task.delay(3, refreshRoute)
	end)
end

function app.clear()
	forge.origin = nil
	history = {}
	contextText = ""
	view.setScanned(false)
	view.clearMessages()
	view.setEmpty(true, anyKey())
	refreshRoute()
end

local function send(text)
	if busy then
		return
	end
	local usable
	if isAuto() then
		usable = anyKey()
	else
		usable = hasKey(getProvider())
	end
	if not usable then
		view.user(text)
		if isAuto() then
			view.error({title = "No API key yet", hint = "Open Setup and add a key for any provider.", fix = "setup"})
		else
			view.error({
				title = "Add a " .. getProvider().name .. " key",
				hint = "Or set Provider to Auto and use any provider you have a key for.",
				fix = "setup",
			})
		end
		return
	end

	busy = true
	view.setBusy(true)
	view.user(text)
	local think = view.thinking(isAuto() and "Choosing a provider" or ("Asking " .. getProvider().name))
	view.setStatus("busy", "Working")
	local started = os.clock()

	local okRun, perr = pcall(function()
		local sent = expandMentions(text) .. forge.playerNote()
		local msgs = copyList(history)
		msgs[#msgs + 1] = {role = "user", text = sent}

		local ok, res, p, model, fails = route(msgs, function(note)
			think.set(note)
			view.setStatus("busy", note)
		end)
		think.stop()

		if not ok then
			if res.noKeys then
				view.error({title = "No API key yet", hint = "Open Setup and add a key for any provider.", fix = "setup"})
				view.setStatus("fail", "No key")
				return
			end
			local info = explainFailures(fails)
			view.log("Request failed: " .. info.title, "bad")
			view.error(info)
			view.setStatus("fail", info.title)
			return
		end

		local reply = cleanReply(res)
		if reply == "" then
			view.error({title = p.name .. " sent an empty reply", hint = "Try again, or use another provider."})
			view.setStatus("warn", "Empty reply")
			return
		end

		view.log(string.format("Reply from %s in %.1fs", p.name, os.clock() - started), "ok")
		view.reply(reply, p, model, os.clock() - started)
		view.setStatus("ok", routeText())
		history[#history + 1] = {role = "user", text = sent}
		history[#history + 1] = {role = "assistant", text = reply}
		while #history > MAX_HISTORY do
			table.remove(history, 1)
		end
	end)

	if not okRun then
		think.stop()
		view.error({title = "Something went wrong inside Tonyo", raw = oneLine(perr, 200)})
		view.setStatus("fail", "Internal error")
	end
	busy = false
	view.setBusy(false)
end

function app.submit()
	local t = input.Text:gsub("^%s+", ""):gsub("%s+$", "")
	if t == "" or busy then
		return
	end
	input.Text = ""
	task.spawn(send, t)
end

function app.toggleMin()
	minimized = not minimized
	body.Visible = not minimized
	tabStrip.Visible = not minimized
	tween(panel, {Size = UDim2.new(0, PANEL_W, 0, minimized and HEAD_H or PANEL_H)}, 0.2)
end

function app.restart()
	picker.close()
	view.selectTab("chat")
	app.clear()
	minimized = false
	body.Visible = true
	tabStrip.Visible = true
	panel.Size = UDim2.new(0, PANEL_W, 0, PANEL_H)
	panel.Position = UDim2.new(0.5, 0, 0, -PANEL_H - 30)
	tween(panel, {Position = UDim2.new(0.5, 0, 0, 14)}, 0.45, Enum.EasingStyle.Back)
	view.note("TONYO was restarted by the developer.")
	view.log("Restarted", "warn")
end

function app.close()
	task.spawn(online.leave)
	for _, c in ipairs(conns) do
		c:Disconnect()
	end
	gui:Destroy()
end

do
	local keyed = anyKey()
	local customRow = keyRows.custom
	if customRow and customRow.urlBox then
		customRow.urlBox.Text = settings.customUrl
	end
	refreshCounter()
	view.setEmpty(true, keyed)
	view.setScanned(false)
	view.selectTab(keyed and "chat" or "setup")
	if not keyed then
		view.openKeyRow("gemini", true)
	end
	refreshRoute()
	app.refreshSetup()
	panel.Position = UDim2.new(0.5, 0, 0, -PANEL_H - 30)
	tween(panel, {Position = UDim2.new(0.5, 0, 0, 14)}, 0.45, Enum.EasingStyle.Back)
end

print("TONYO MODEL v6.0 loaded")
