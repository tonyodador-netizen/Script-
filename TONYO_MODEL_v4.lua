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

local settings = {engine = "auto", keys = {}, models = {}, found = {}, customUrl = "", ping = true}
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
		return SYSTEM_PROMPT
	end
	local limit = math.floor((p.ctx or 12000) * (scale or 1))
	local ctx = contextText
	if #ctx > limit then
		ctx = ctx:sub(1, limit) .. "\n...[context trimmed to fit this provider's limit]"
	end
	return SYSTEM_PROMPT .. "\n\n[Game context]\n" .. ctx
end

local function runCode(code)
	if not loadstring then
		return false, "This executor has no loadstring."
	end
	local logs = {}
	local conn = LogService.MessageOut:Connect(function(msg)
		table.insert(logs, msg)
	end)
	local fn, err = loadstring(code)
	local ok, res
	if not fn then
		ok, res = false, err
	else
		ok, res = pcall(fn)
	end
	task.wait(0.3)
	conn:Disconnect()
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
label(sticker, {name = "StickerText", text = "v4", font = F.head, ts = 12, color = C.yellowInk, align = AX.Center, size = UDim2.new(1, 0, 1, 0)})

local ONLINE_DB = "https://last1-d8426-default-rtdb.firebaseio.com"
local SCRIPT_URL = ""
local online = {count = nil, at = 0, status = "not set up", users = {}, control = {}}

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
if isAdmin() then
	addTab("admin", "ADMIN", 466, 66)
	tabStrip.CanvasSize = UDim2.new(0, 546, 0, 0)
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
local function setBanner(show, text, color)
	banner.Visible = show
	if show then
		banner.BackgroundColor3 = color
		bannerLabel.Text = text
		banner.Size = UDim2.new(1, 0, 0, 24)
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
			if inst:IsA("BasePart") and props.Anchored == nil then
				inst.Anchored = true
			end
			local errs = setProps(inst, props, rel)
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

	function forge.placeScript(class, name, code)
		local folder = workspace:FindFirstChild("TONYO_Scripts")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "TONYO_Scripts"
			folder.Parent = workspace
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
					if setclipboard then
						setclipboard(code)
					end
					result.Text = (saved and ("Saved to workspace/TONYO_Scripts/" .. name .. ".server.lua. ") or "Couldn't save a file. ")
						.. (setclipboard and "Code copied. " or "")
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
			end,
		})
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
	paragraph("TONYO lets the developer see who is using it. It sends your Roblox username, user id, a random id for this device and the time you were last active. It never sends your chats, keys or anything else you type. Turn it off below any time.")
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
	paragraph("Keys stay on this device, in workspace/TONYO_MODEL_settings.json. Tonyo 4.0")
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
		{"v4.13", "Latest  /  Nov 4, 2026", {
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
			return nil
		end
		local ok, res = pcall(safeRequest, {
			Url = b .. path, Method = method, Headers = {["Content-Type"] = "application/json"}, Body = body,
		})
		local code = ok and res and (res.StatusCode or 0) or 0
		if code >= 200 and code < 300 then
			return res.Body or ""
		end
		return nil
	end

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
		local payload = HttpService:JSONEncode({t = now, n = player.Name, u = player.UserId, p = game.PlaceId})
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
		local body = HttpService:JSONEncode({text = text, id = os.time(), by = player.Name})
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
				setBanner(true, a.text, C.yellow)
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

print("TONYO MODEL v4.13 loaded")
