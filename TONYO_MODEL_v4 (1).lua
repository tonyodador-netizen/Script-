local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local LogService = game:GetService("LogService")

local player = Players.LocalPlayer

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

local settings = {engine = "auto", keys = {}, models = {}, found = {}, customUrl = ""}
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
	.. 'Positions of things inside Spawns are relative to a spawn point on the ground in front of the player, so [0,2,0] puts a 4 stud tall part standing right there. Add "abs":true for exact world coordinates. '
	.. 'Build bigger things (houses, cars, towers, trees) from several create ops, give every object a unique name, and keep it under 60 ops. Scripts cannot be made with ops, use code blocks for logic. '
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
label(sticker, {name = "StickerText", text = "v4", font = F.head, ts = 12, color = C.yellowInk, align = AX.Center, size = UDim2.new(1, 0, 1, 0)})

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

local tabStrip = make("Frame", {
	Name = "TabStrip", Position = UDim2.new(0, 0, 0, HEAD_H), Size = UDim2.new(1, 0, 0, TAB_H), BackgroundTransparency = 1,
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
addTab("chat", "CHAT", 10, 84)
addTab("setup", "SETUP", 100, 84)

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
local statusLabel = label(foot, {name = "StatusText", font = F.med, ts = 11, color = C.sub, size = UDim2.new(1, -172, 0, 18), pos = UDim2.new(0, 30, 0, 5)})

local scanButton = brick(foot, {
	name = "ScanButton", text = "SCAN", ts = 11, kind = "gray", radius = 4, lipH = 2,
	size = UDim2.new(0, 62, 0, 20), pos = UDim2.new(1, -134, 0, 4),
	onClick = function()
		app.scan()
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

local function codeCard(parent, info, code, idx, order)
	local lang = (info:match("^%s*([%w_]+)") or ""):lower()
	local isServer = info:lower():find("server", 1, true) ~= nil
	local name = info:match(":%s*([%w_%-]+)%s*$") or ("Script" .. idx)
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
		size = UDim2.new(0, 50, 0, 22), pos = UDim2.new(1, runnable and -118 or -58, 0, 5), radius = 4, lipH = 2,
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

	result = label(card, {
		name = "CodeResult", text = "", ts = 11, color = C.sub, wrap = true, size = UDim2.new(1, 0, 0, 0),
		auto = AUTO_Y, order = 5,
	})
	result.Visible = false
	pad(result, 10, 6, 10, 8)
	return card
end

local forge = {origin = nil, folder = nil}
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
		if not forge.origin then
			local char = player.Character
			local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
			local cf = root and root.CFrame
			if not cf then
				local cam = workspace.CurrentCamera
				cf = cam and cam.CFrame or CFrame.new(0, 10, 0)
			end
			local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
			if look.Magnitude < 0.01 then
				look = Vector3.new(0, 0, -1)
			end
			forge.origin = cf.Position + look.Unit * 14 - Vector3.new(0, root and 3 or 0, 0)
		end
		return forge.origin
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
		if inst:IsA("BasePart") and inst.Anchored then
			local target = inst.Size
			inst.Size = target * 0.05
			TweenService:Create(inst, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = target}):Play()
		end
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
			local okc, copy = pcall(function()
				return src:Clone()
			end)
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
		return lines, made, failed, batch
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
	local countLabel = label(top, {name = "OpsCount", font = F.med, ts = 11, color = C.sub, size = UDim2.new(1, -210, 1, 0), pos = UDim2.new(0, 76, 0, 0)})

	make("Frame", {Name = "OpsDivider", Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = C.ink, BorderSizePixel = 0, LayoutOrder = 2}, card)
	local resultLabel = label(card, {
		name = "OpsResult", rich = true, wrap = true, ts = 11, font = F.code, size = UDim2.new(1, 0, 0, 0), auto = AUTO_Y, order = 3,
	})
	pad(resultLabel, 10, 8, 10, 8)

	local current = {}
	local function render(lines, made, failed)
		local out = {}
		for _, l in ipairs(lines) do
			local color = l.bad and "#FF9488" or "#7FE29A"
			out[#out + 1] = '<font color="' .. color .. '">' .. escapeRich(l.text) .. "</font>"
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
		local ok, lines, made, failed, list = pcall(forge.apply, ops)
		if not ok then
			countLabel.Text = "failed"
			resultLabel.Text = '<font color="#FF9488">' .. escapeRich(oneLine(lines, 140)) .. "</font>"
			return
		end
		current = list
		render(lines, made, failed)
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
		name = "OpsAgain", text = "AGAIN", kind = "green", ts = 11, size = UDim2.new(0, 60, 0, 22), pos = UDim2.new(1, -128, 0, 5),
		radius = 4, lipH = 2,
		onClick = run,
	})
	task.defer(run)
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
local providerRow, providerValue, modelRow, modelValue, engineNote, quickMsg
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
	picker.close()
	chat.Visible = id == "chat"
	setup.Visible = id == "setup"
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
		local sent = expandMentions(text)
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

function app.close()
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

print("TONYO MODEL v4.1 loaded")
