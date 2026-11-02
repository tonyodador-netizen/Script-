-- TONYO MODEL v2 - Multi-provider AI chat for executors (pure client)
-- Providers: Gemini, Claude, OpenAI, Groq, OpenRouter, Mistral, Cerebras, DeepSeek
-- Fixes: real error messages, automatic 429 retry/backoff, no background pinging,
--        editable model names (so retired models never break the script again)

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
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

--------------------------------------------------------------------------
-- HTTP
--------------------------------------------------------------------------
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

--------------------------------------------------------------------------
-- Settings (saved per provider; uses executor file API when available)
--------------------------------------------------------------------------
local SAVE_FILE = "TONYO_MODEL_settings.json"
local settings = {engine = "gemini", keys = {}, models = {}}

pcall(function()
	if isfile and readfile and isfile(SAVE_FILE) then
		local d = HttpService:JSONDecode(readfile(SAVE_FILE))
		if type(d) == "table" then
			settings.engine = d.engine or settings.engine
			settings.keys = type(d.keys) == "table" and d.keys or {}
			settings.models = type(d.models) == "table" and d.models or {}
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

--------------------------------------------------------------------------
-- Providers
--------------------------------------------------------------------------
local function jsonHeaders(extra)
	local h = {["Content-Type"] = "application/json"}
	for k, v in pairs(extra or {}) do
		h[k] = v
	end
	return h
end

-- Most providers copy OpenAI's chat-completions format
local function openAICompat(def)
	return {
		id = def.id,
		name = def.name,
		tag = def.tag,
		keyUrl = def.keyUrl,
		model = def.model,
		ctx = def.ctx,
		build = function(key, model, system, msgs)
			local m = {{role = "system", content = system}}
			for _, x in ipairs(msgs) do
				table.insert(m, {role = x.role, content = x.text})
			end
			return {
				Url = def.url,
				Headers = jsonHeaders({Authorization = "Bearer " .. key}),
				Body = HttpService:JSONEncode({model = model, messages = m}),
			}
		end,
		parse = function(data)
			local c = data.choices and data.choices[1] and data.choices[1].message
				and data.choices[1].message.content
			return type(c) == "string" and c or ""
		end,
	}
end

local PROVIDERS = {
	{
		id = "gemini",
		name = "Gemini",
		tag = "free tier",
		keyUrl = "aistudio.google.com/apikey",
		model = "gemini-2.5-flash",
		build = function(key, model, system, msgs)
			local contents = {}
			for _, x in ipairs(msgs) do
				table.insert(contents, {
					role = x.role == "assistant" and "model" or "user",
					parts = {{text = x.text}},
				})
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
				for _, p in ipairs(c.parts) do
					if p.text then
						text = text .. p.text
					end
				end
			end
			return text
		end,
	},
	{
		id = "claude",
		name = "Claude",
		tag = "paid",
		keyUrl = "console.anthropic.com",
		model = "claude-sonnet-5-5",
		build = function(key, model, system, msgs, maxTokens)
			local m = {}
			for _, x in ipairs(msgs) do
				table.insert(m, {role = x.role, content = x.text})
			end
			return {
				Url = "https://api.anthropic.com/v1/messages",
				Headers = jsonHeaders({["x-api-key"] = key, ["anthropic-version"] = "2023-06-01"}),
				Body = HttpService:JSONEncode({
					model = model,
					max_tokens = maxTokens or 1024,
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
	},
	openAICompat({
		id = "openai", name = "OpenAI", tag = "paid (needs credits)",
		keyUrl = "platform.openai.com/api-keys", model = "gpt-4o-mini",
		url = "https://api.openai.com/v1/chat/completions",
	}),
	openAICompat({
		id = "groq", name = "Groq", tag = "free tier",
		keyUrl = "console.groq.com/keys", model = "llama-3.3-70b-versatile",
		url = "https://api.groq.com/openai/v1/chat/completions",
		ctx = 4000, -- Groq free tier allows ~8000 tokens per minute
	}),
	openAICompat({
		id = "openrouter", name = "OpenRouter", tag = "has free models",
		keyUrl = "openrouter.ai/keys", model = "meta-llama/llama-3.3-70b-instruct:free",
		url = "https://openrouter.ai/api/v1/chat/completions",
	}),
	openAICompat({
		id = "mistral", name = "Mistral", tag = "free tier",
		keyUrl = "console.mistral.ai", model = "mistral-small-latest",
		url = "https://api.mistral.ai/v1/chat/completions",
	}),
	openAICompat({
		id = "cerebras", name = "Cerebras", tag = "free tier",
		keyUrl = "cloud.cerebras.ai", model = "llama3.1-8b",
		url = "https://api.cerebras.ai/v1/chat/completions",
	}),
	openAICompat({
		id = "deepseek", name = "DeepSeek", tag = "very cheap",
		keyUrl = "platform.deepseek.com", model = "deepseek-chat",
		url = "https://api.deepseek.com/chat/completions",
	}),
}

local function getProvider()
	for _, p in ipairs(PROVIDERS) do
		if p.id == settings.engine then
			return p
		end
	end
	settings.engine = PROVIDERS[1].id
	return PROVIDERS[1]
end

local function getModel(p)
	local m = settings.models[p.id]
	return (m and m ~= "") and m or p.model
end

--------------------------------------------------------------------------
-- Request layer: real errors + automatic retry on 429
--------------------------------------------------------------------------
local MAX_RETRIES = 3
local MAX_WAIT = 45

local function decode(raw)
	if type(raw) ~= "string" or raw == "" then
		return nil
	end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	return ok and data or nil
end

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
end

-- returns true, text  |  false, errInfo
local function callProvider(p, key, model, system, msgs, maxTokens, maxRetries, onRetry)
	local req = p.build(key, model, system, msgs, maxTokens)
	local attempt = 0
	while true do
		attempt += 1
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

local function explainError(err, p)
	if err.network then
		return "Connection failed: " .. tostring(err.message)
	end
	local s = err.status
	local head
	if err.noCredits then
		head = p.name .. " says this key has no credits/balance. Add billing or pick a free engine."
	elseif s == 429 then
		head = "Rate limited by " .. p.name .. " even after retrying."
		if err.retryIn then
			head = head .. " Try again in ~" .. math.ceil(err.retryIn) .. "s."
		else
			head = head .. " Wait a minute or switch engine."
		end
	elseif s == 401 or s == 403 then
		head = "Invalid or unauthorized API key for " .. p.name .. "."
	elseif s == 413 then
		head = "Request too big for " .. p.name .. "'s per-minute token limit. Press clear chat, rescan, or use a provider with bigger limits."
	elseif s == 404 then
		head = "Model not found. Edit the model name box above."
	else
		head = "Request failed."
	end
	local detail = tostring(err.message):gsub("%s+", " ")
	if #detail > 180 then
		detail = detail:sub(1, 180) .. "..."
	end
	return string.format("Error (HTTP %s): %s\n%s", tostring(s), head, detail)
end

--------------------------------------------------------------------------
-- UI (compact, sits at the top of the screen so the keyboard never covers it)
--------------------------------------------------------------------------
local C = {
	BG = Color3.fromRGB(17, 17, 19),
	SURFACE = Color3.fromRGB(27, 27, 30),
	INPUT = Color3.fromRGB(36, 36, 40),
	ACCENT = Color3.fromRGB(222, 160, 62),
	TEXT = Color3.fromRGB(226, 226, 222),
	DIM = Color3.fromRGB(122, 122, 128),
	WHITE = Color3.fromRGB(255, 255, 255),
	OK = Color3.fromRGB(104, 188, 120),
	WARN = Color3.fromRGB(222, 160, 62),
	FAIL = Color3.fromRGB(214, 92, 84),
	USER = Color3.fromRGB(56, 46, 28),
}

local camera = workspace.CurrentCamera
local viewport = camera and camera.ViewportSize or Vector2.new(800, 450)
local PANEL_W = math.clamp(math.floor(viewport.X * 0.42), 280, 360)
local PANEL_H = math.clamp(math.floor(viewport.Y * 0.62), 220, 340)
local HEADER_H, INPUT_H = 28, 30
local MAX_HISTORY = 12
local SYSTEM_PROMPT = "You are TONYO Model, an AI assistant inside a Roblox executor UI, running on the player's client. "
	.. "Help with Luau scripting, Roblox development and general questions. Be concise. "
	.. "Game info may appear under [Game context] (a scan of the game tree) or [Game data] (details of objects the user @mentioned, "
	.. "including script source when available). Use it, and never invent objects that are not listed; "
	.. "if you need more, ask the user to press Scan or @mention an object by its path (e.g. @Workspace.Map.Door). "
	.. "You can create anything with Luau (Instance.new parts, models, GUIs, effects, sounds, tools, and script logic). "
	.. "Reply with Luau inside code blocks. Label each block's script type on the opening fence line: "
	.. "```lua local:Name for client code (the user taps Run and it executes on the client only, other players will not see it), "
	.. "or ```lua server:Name for server Script code (it cannot run from the client, so the user saves it and pastes it into a Script "
	.. "in ServerScriptService in Studio). Remember server code uses ServerScriptService/ServerStorage and RemoteEvents for client communication. "
	.. "Use print() for output. Keep each script focused and safe."

local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
	return c
end

local function stroke(inst, transparency, color)
	local s = Instance.new("UIStroke")
	s.Color = color or C.WHITE
	s.Transparency = transparency or 0.85
	s.Thickness = 1
	s.Parent = inst
	return s
end

local function padding(inst, l, t, r, b)
	local p = Instance.new("UIPadding")
	p.PaddingLeft, p.PaddingTop, p.PaddingRight, p.PaddingBottom = UDim.new(0, l), UDim.new(0, t), UDim.new(0, r), UDim.new(0, b)
	p.Parent = inst
	return p
end

local function makeButton(parent, text, pos, size, bg, textColor)
	local b = Instance.new("TextButton")
	b.Position, b.Size = pos, size
	b.BackgroundColor3 = bg or C.INPUT
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Font = Enum.Font.SourceSansSemibold
	b.TextSize = 14
	b.TextColor3 = textColor or C.TEXT
	b.Text = text
	b.Parent = parent
	corner(b, 4)
	return b
end

local function makeBox(parent, placeholder, pos, size)
	local t = Instance.new("TextBox")
	t.Position, t.Size = pos, size
	t.BackgroundColor3 = C.INPUT
	t.BorderSizePixel = 0
	t.Font = Enum.Font.SourceSans
	t.TextSize = 14
	t.TextColor3 = C.TEXT
	t.PlaceholderColor3 = C.DIM
	t.PlaceholderText = placeholder
	t.Text = ""
	t.ClearTextOnFocus = false
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Parent = parent
	corner(t, 4)
	stroke(t, 0.85)
	padding(t, 7, 0, 7, 0)
	return t
end

if guiParent:FindFirstChild("TONYOModel_UI") then
	guiParent.TONYOModel_UI:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TONYOModel_UI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 999999
screenGui.Parent = guiParent

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.Position = UDim2.new(0.5, 0, 0, 6)
panel.Size = UDim2.new(0, PANEL_W, 0, PANEL_H)
panel.BackgroundColor3 = C.BG
panel.BorderSizePixel = 0
panel.ClipsDescendants = true
panel.Parent = screenGui
corner(panel, 6)
stroke(panel, 0.55, C.DIM)

-- Header (drag here)
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, HEADER_H)
header.BackgroundColor3 = C.SURFACE
header.BorderSizePixel = 0
header.Parent = panel
corner(header, 6)

local headerFill = Instance.new("Frame")
headerFill.Position = UDim2.new(0, 0, 1, -6)
headerFill.Size = UDim2.new(1, 0, 0, 6)
headerFill.BackgroundColor3 = C.SURFACE
headerFill.BorderSizePixel = 0
headerFill.Parent = header

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 9, 0, 0)
title.Size = UDim2.new(0, 44, 1, 0)
title.Font = Enum.Font.SourceSansBold
title.TextSize = 16
title.TextColor3 = C.TEXT
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "tonyo"
title.Parent = header

local dot = Instance.new("Frame")
dot.Position = UDim2.new(0, 56, 0.5, -3)
dot.Size = UDim2.new(0, 7, 0, 7)
dot.BackgroundColor3 = C.DIM
dot.BorderSizePixel = 0
dot.Parent = header
corner(dot, 4)

local statusLabel = Instance.new("TextLabel")
statusLabel.BackgroundTransparency = 1
statusLabel.Position = UDim2.new(0, 68, 0, 0)
statusLabel.Size = UDim2.new(1, -(68 + 134), 1, 0)
statusLabel.Font = Enum.Font.SourceSans
statusLabel.TextSize = 13
statusLabel.TextColor3 = C.DIM
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
statusLabel.Text = "no key"
statusLabel.Parent = header

local function headerButton(text, rightOffset, width)
	local b = makeButton(header, text, UDim2.new(1, -rightOffset, 0.5, -10), UDim2.new(0, width, 0, 20), C.INPUT, C.DIM)
	b.TextSize = 13
	return b
end
local closeBtn = headerButton("x", 28, 22)
local minBtn = headerButton("-", 54, 22)
local cfgBtn = headerButton("cfg", 90, 32)
local scanBtn = headerButton("scan", 130, 36)
scanBtn.TextColor3 = C.TEXT

local STATUS_COLORS = {idle = C.DIM, checking = C.ACCENT, ok = C.OK, warn = C.WARN, fail = C.FAIL}
local lastState, lastText = "idle", "no key"
local function setStatus(state, text)
	lastState, lastText = state, text
	dot.BackgroundColor3 = STATUS_COLORS[state] or C.DIM
	statusLabel.Text = text
end

local function flashStatus(text)
	local s, t = lastState, lastText
	statusLabel.Text = text
	task.delay(1.4, function()
		if statusLabel.Parent and statusLabel.Text == text then
			setStatus(s, t)
		end
	end)
end

do -- dragging
	local dragging, dragStart, startPos
	header.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging, dragStart, startPos = true, input.Position, panel.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - dragStart
			panel.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
end

-- Body (everything under the header)
local body = Instance.new("Frame")
body.Position = UDim2.new(0, 0, 0, HEADER_H)
body.Size = UDim2.new(1, 0, 1, -HEADER_H)
body.BackgroundTransparency = 1
body.Parent = panel

-- Chat list
local listContainer = Instance.new("ScrollingFrame")
listContainer.Position = UDim2.new(0, 6, 0, 4)
listContainer.Size = UDim2.new(1, -12, 1, -(INPUT_H + 14))
listContainer.BackgroundTransparency = 1
listContainer.BorderSizePixel = 0
listContainer.ScrollBarThickness = 2
listContainer.ScrollBarImageColor3 = C.DIM
listContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
listContainer.Parent = body

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 5)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = listContainer

listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	local h = listLayout.AbsoluteContentSize.Y
	listContainer.CanvasSize = UDim2.new(0, 0, 0, h + 4)
	listContainer.CanvasPosition = Vector2.new(0, math.max(0, h - listContainer.AbsoluteSize.Y + 4))
end)

local order = 0
local function newRow()
	order += 1
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 0)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.LayoutOrder = order
	row.Parent = listContainer
	return row
end

local function addSystem(text)
	local row = newRow()
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.Font = Enum.Font.SourceSans
	l.TextSize = 13
	l.TextColor3 = C.DIM
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.Text = text
	l.Parent = row
	return l
end

-- role: "user" or "ai"
local function addBubble(role, text)
	local row = newRow()
	local b = Instance.new(role == "ai" and "TextButton" or "TextLabel")
	b.AutomaticSize = Enum.AutomaticSize.XY
	b.Size = UDim2.new(0, 0, 0, 0)
	b.AnchorPoint = Vector2.new(role == "user" and 1 or 0, 0)
	b.Position = UDim2.new(role == "user" and 1 or 0, 0, 0, 0)
	b.BackgroundColor3 = role == "user" and C.USER or C.SURFACE
	b.BorderSizePixel = 0
	b.Font = Enum.Font.SourceSans
	b.TextSize = 14
	b.TextColor3 = C.TEXT
	b.TextWrapped = true
	b.TextXAlignment = Enum.TextXAlignment.Left
	b.TextYAlignment = Enum.TextYAlignment.Top
	b.Text = text
	b.Parent = row
	if role == "ai" then
		b.AutoButtonColor = false
		b.Activated:Connect(function()
			if setclipboard then
				setclipboard(b.Text)
				flashStatus("copied")
			end
		end)
	end
	corner(b, 4)
	padding(b, 8, 5, 8, 5)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new((PANEL_W - 12) * 0.9, math.huge)
	limit.Parent = b
	return b
end

-- Input bar
local inputContainer = Instance.new("Frame")
inputContainer.Position = UDim2.new(0, 6, 1, -(INPUT_H + 6))
inputContainer.Size = UDim2.new(1, -12, 0, INPUT_H)
inputContainer.BackgroundColor3 = C.INPUT
inputContainer.BorderSizePixel = 0
inputContainer.Parent = body
corner(inputContainer, 4)
stroke(inputContainer, 0.85)

local inputField = Instance.new("TextBox")
inputField.Size = UDim2.new(1, -54, 1, 0)
inputField.BackgroundTransparency = 1
inputField.Font = Enum.Font.SourceSans
inputField.TextSize = 14
inputField.TextColor3 = C.TEXT
inputField.PlaceholderColor3 = C.DIM
inputField.PlaceholderText = "message, or @path to read an object"
inputField.Text = ""
inputField.TextXAlignment = Enum.TextXAlignment.Left
inputField.TextTruncate = Enum.TextTruncate.AtEnd
inputField.ClearTextOnFocus = false
inputField.Parent = inputContainer
padding(inputField, 8, 0, 0, 0)

local sendBtn = makeButton(inputContainer, "send", UDim2.new(1, -50, 0.5, -11), UDim2.new(0, 46, 0, 22), C.ACCENT, C.BG)

-- Settings drawer (covers the chat; created last so it draws on top)
local drawer = Instance.new("Frame")
drawer.Position = UDim2.new(0, 0, 0, 0)
drawer.Size = UDim2.new(1, 0, 1, -(INPUT_H + 10))
drawer.BackgroundColor3 = C.BG
drawer.BorderSizePixel = 0
drawer.Active = true
drawer.Visible = false
drawer.Parent = body

local function drawerLabel(pos, size, font, textSize, color, align)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position, l.Size = pos, size
	l.Font = font
	l.TextSize = textSize
	l.TextColor3 = color
	l.TextXAlignment = align
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Text = ""
	l.Parent = drawer
	return l
end

local prevBtn = makeButton(drawer, "<", UDim2.new(0, 6, 0, 4), UDim2.new(0, 26, 0, 24), C.INPUT, C.TEXT)
local nextBtn = makeButton(drawer, ">", UDim2.new(1, -32, 0, 4), UDim2.new(0, 26, 0, 24), C.INPUT, C.TEXT)
local engineLabel = drawerLabel(UDim2.new(0, 38, 0, 4), UDim2.new(1, -76, 0, 24), Enum.Font.SourceSansBold, 15, C.TEXT, Enum.TextXAlignment.Center)
local hintLabel = drawerLabel(UDim2.new(0, 8, 0, 30), UDim2.new(1, -16, 0, 14), Enum.Font.SourceSans, 13, C.DIM, Enum.TextXAlignment.Left)
local keyBox = makeBox(drawer, "api key", UDim2.new(0, 6, 0, 46), UDim2.new(1, -62, 0, 24))
local testBtn = makeButton(drawer, "test", UDim2.new(1, -52, 0, 46), UDim2.new(0, 46, 0, 24), C.ACCENT, C.BG)
local modelBox = makeBox(drawer, "model name", UDim2.new(0, 6, 0, 74), UDim2.new(1, -12, 0, 24))
local clearBtn = makeButton(drawer, "clear chat", UDim2.new(0, 6, 0, 102), UDim2.new(0.5, -9, 0, 24), C.INPUT, C.DIM)
local doneBtn = makeButton(drawer, "done", UDim2.new(0.5, 3, 0, 102), UDim2.new(0.5, -9, 0, 24), C.INPUT, C.TEXT)


--------------------------------------------------------------------------
-- Logic
--------------------------------------------------------------------------
local history = {}
local busy = false
local testing = false
local selectEngine

local function refreshDrawer()
	local p = getProvider()
	engineLabel.Text = p.name .. "  -  " .. p.tag
	hintLabel.Text = "get a key: " .. p.keyUrl
end

selectEngine = function(id)
	settings.engine = id
	saveSettings()
	local p = getProvider()
	refreshDrawer()
	modelBox.Text = getModel(p)
	keyBox.Text = ""
	local k = settings.keys[p.id]
	if k and k ~= "" then
		keyBox.PlaceholderText = "saved (..." .. k:sub(-4) .. ")"
		setStatus("idle", p.name .. " - key saved")
	else
		keyBox.PlaceholderText = "paste " .. p.name .. " key"
		setStatus("idle", "no key for " .. p.name)
	end
end

local function cycleEngine(step)
	local idx = 1
	for i, p in ipairs(PROVIDERS) do
		if p.id == settings.engine then
			idx = i
		end
	end
	idx = (idx - 1 + step) % #PROVIDERS + 1
	selectEngine(PROVIDERS[idx].id)
end

local function runTest()
	if testing then
		return
	end
	local p = getProvider()
	local key = settings.keys[p.id]
	if not key or key == "" then
		setStatus("idle", "no key for " .. p.name)
		return
	end
	testing = true
	setStatus("checking", "testing " .. p.name .. "...")
	local ok, res = callProvider(p, key, getModel(p), "Reply with OK.", {{role = "user", text = "ping"}}, 8, 0)
	testing = false
	if ok then
		setStatus("ok", p.name .. " ready")
		drawer.Visible = false
	elseif res.status == 429 and not res.noCredits then
		setStatus("warn", "key ok, rate limited")
	elseif res.noCredits then
		setStatus("fail", "no credits on key")
	elseif res.status == 404 then
		setStatus("fail", "model not found")
	elseif res.status == 401 or res.status == 403 then
		setStatus("fail", "invalid key")
	else
		setStatus("fail", "failed (HTTP " .. tostring(res.status or "?") .. ")")
	end
end


--------------------------------------------------------------------------
-- Game access: Scan, @mentions, Run code
--------------------------------------------------------------------------
local contextText = ""
local ROOTS = {
	"Workspace", "ReplicatedStorage", "ReplicatedFirst", "StarterGui", "StarterPack", "StarterPlayer",
	"Lighting", "SoundService", "Teams", "Chat", "TextChatService", "MaterialService",
}
-- Full scan limits. Lower SCAN_CHARS if a free provider complains about request size (413 / rate limit).
local SCAN_PER_ROOT, SCAN_DEPTH, SCAN_KIDS, SCAN_CHARS = 160, 6, 30, 16000

local function isScript(inst)
	return inst:IsA("LuaSourceContainer")
end

local function clip(s, n)
	s = tostring(s)
	return #s > (n or 500) and (s:sub(1, n or 500) .. "...") or s
end

local function scanGame()
	local lines, count = {}, 0
	local function walk(inst, depth, limit)
		if #lines >= limit then
			return
		end
		local tag = inst.ClassName .. (isScript(inst) and " *script*" or "")
		table.insert(lines, string.rep("  ", depth) .. inst.Name .. " [" .. tag .. "]")
		count += 1
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

	-- every script the client can see, with its full path
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
			-- bare name like @Door: search the whole game
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

-- "@Workspace.Map.Door" in a message gets expanded with that object's details
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

-- Adds a Run button under the AI reply for each ```code block```
local function addRunButtons(reply)
	local n = 0
	for info, code in reply:gmatch("```([^\r\n]*)\r?\n(.-)```") do
		n += 1
		if n > 4 then
			break
		end
		local snippet = code
		local isServer = info:lower():find("server", 1, true) ~= nil
		local name = info:match(":%s*([%w_%-]+)%s*$") or ("Script" .. n)
		local row = newRow()

		local btn = makeButton(row, isServer and ("save " .. name) or ("run " .. name),
			UDim2.new(0, 0, 0, 0), UDim2.new(0, 130, 0, 22), isServer and C.ACCENT or C.OK, C.BG)
		btn.BackgroundTransparency = 0.2
		btn.TextTruncate = Enum.TextTruncate.AtEnd
		local copyBtn = makeButton(row, "copy", UDim2.new(0, 136, 0, 0), UDim2.new(0, 44, 0, 22), C.INPUT, C.DIM)

		copyBtn.Activated:Connect(function()
			if setclipboard then
				setclipboard(snippet)
				flashStatus("code copied")
			else
				flashStatus("copy not supported")
			end
		end)

		btn.Activated:Connect(function()
			if isServer then
				-- A client executor can't run server scripts, so save the file for pasting into Studio
				local saved = false
				pcall(function()
					if writefile then
						if makefolder and isfolder and not isfolder("TONYO_Scripts") then
							makefolder("TONYO_Scripts")
						end
						writefile("TONYO_Scripts/" .. name .. ".server.lua", snippet)
						saved = true
					end
				end)
				if setclipboard then
					setclipboard(snippet)
				end
				addSystem((saved and ("Saved to workspace/TONYO_Scripts/" .. name .. ".server.lua. ") or "Couldn't save a file. ")
					.. (setclipboard and "Code copied. " or "")
					.. "Server scripts can't run from a client executor: paste it into a Script in ServerScriptService in Studio.")
				return
			end
			btn.Text = "running..."
			task.spawn(function()
				local ok, out = runCode(snippet)
				btn.Text = "run again"
				if ok then
					addSystem("Ran OK." .. (out ~= "" and ("\nOutput:\n" .. clip(out, 500)) or ""))
				else
					addSystem("Run error: " .. clip(out, 500)).TextColor3 = C.FAIL
				end
			end)
		end)
	end
end

local function cleanReply(text)
	local t = text:gsub("^%s+", ""):gsub("%s+$", "")
	-- tolerate models that still answer with {"say": "..."}
	if t:sub(1, 1) == "{" then
		local d = decode(t)
		if type(d) == "table" and type(d.say) == "string" then
			return d.say
		end
	end
	return t
end

local function send(text)
	if busy or text == "" then
		return
	end
	local p = getProvider()
	local key = settings.keys[p.id]
	if not key or key == "" then
		addSystem("Paste your " .. p.name .. " API key above first.")
		return
	end

	busy = true
	addBubble("user", text)
	local bubble = addBubble("ai", "Thinking")
	local thinking, note = true, "Thinking"
	task.spawn(function()
		local n = 0
		while thinking do
			n = n % 3 + 1
			bubble.Text = note .. string.rep(".", n)
			task.wait(0.4)
		end
	end)

	local msgs = {}
	for _, h in ipairs(history) do
		table.insert(msgs, h)
	end
	local sentText = expandMentions(text)
	table.insert(msgs, {role = "user", text = sentText})

	local ok, res
	local scale = 1
	for _ = 1, 3 do
		ok, res = callProvider(p, key, getModel(p), buildSystem(p, scale), msgs, nil, MAX_RETRIES, function(attempt, wait)
			note = string.format("Rate limited - retrying in %ds (%d/%d)", math.ceil(wait), attempt, MAX_RETRIES)
		end)
		if ok or res.status ~= 413 then
			break
		end
		-- too big for this provider: halve the game context and drop the oldest exchange, then retry
		scale = scale / 2
		note = "Too large - trimming and retrying"
		if #msgs > 2 then
			table.remove(msgs, 1)
			table.remove(msgs, 1)
		end
	end
	thinking = false

	if not ok then
		bubble.Text = explainError(res, p)
		bubble.TextColor3 = C.FAIL
		setStatus(res.status == 429 and "warn" or "fail", res.status == 429 and "Rate limited" or "Request failed")
		busy = false
		return
	end

	local reply = cleanReply(res)
	if reply == "" then
		bubble.Text = "Empty response from " .. p.name .. ". Try again or switch model."
		bubble.TextColor3 = C.WARN
		busy = false
		return
	end

	bubble.Text = reply
	bubble.TextColor3 = C.TEXT
	setStatus("ok", p.name .. " ready")
	addRunButtons(reply)
	table.insert(history, {role = "user", text = sentText})
	table.insert(history, {role = "assistant", text = reply})
	while #history > MAX_HISTORY do
		table.remove(history, 1)
	end
	busy = false
end

local function submitInput()
	local t = inputField.Text:gsub("^%s+", ""):gsub("%s+$", "")
	if t == "" then
		return
	end
	inputField.Text = ""
	task.spawn(send, t)
end

--------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------
prevBtn.Activated:Connect(function()
	cycleEngine(-1)
end)
nextBtn.Activated:Connect(function()
	cycleEngine(1)
end)
cfgBtn.Activated:Connect(function()
	drawer.Visible = not drawer.Visible
end)
doneBtn.Activated:Connect(function()
	drawer.Visible = false
end)

keyBox.FocusLost:Connect(function()
	local s = keyBox.Text:gsub("%s", "")
	if s == "" then
		return
	end
	local p = getProvider()
	settings.keys[p.id] = s
	saveSettings()
	keyBox.Text = ""
	keyBox.PlaceholderText = "saved (..." .. s:sub(-4) .. ")"
	task.spawn(runTest)
end)

modelBox.FocusLost:Connect(function()
	local p = getProvider()
	local m = modelBox.Text:gsub("%s", "")
	if m == "" or m == p.model then
		settings.models[p.id] = nil
		m = p.model
	else
		settings.models[p.id] = m
	end
	modelBox.Text = m
	saveSettings()
end)

testBtn.Activated:Connect(function()
	task.spawn(runTest)
end)

scanBtn.Activated:Connect(function()
	drawer.Visible = false
	task.spawn(function()
		setStatus("checking", "scanning game...")
		local ok, text, count = pcall(scanGame)
		if ok then
			contextText = text
			setStatus("ok", "scanned " .. count .. " objects")
			addSystem("scanned " .. count .. " objects, attached as context. @Workspace.Path reads one object or script.")
		else
			setStatus("fail", "scan failed")
		end
	end)
end)

clearBtn.Activated:Connect(function()
	history = {}
	contextText = ""
	drawer.Visible = false
	for _, ch in ipairs(listContainer:GetChildren()) do
		if ch:IsA("Frame") then
			ch:Destroy()
		end
	end
	addSystem("chat cleared.")
end)

inputField.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		submitInput()
	end
end)
sendBtn.Activated:Connect(submitInput)

local minimized = false
minBtn.Activated:Connect(function()
	minimized = not minimized
	body.Visible = not minimized
	panel.Size = UDim2.new(0, PANEL_W, 0, minimized and HEADER_H or PANEL_H)
	minBtn.Text = minimized and "+" or "-"
end)

closeBtn.Activated:Connect(function()
	screenGui:Destroy()
end)

--------------------------------------------------------------------------
-- Start
--------------------------------------------------------------------------
selectEngine(getProvider().id)
local startKey = settings.keys[getProvider().id]
drawer.Visible = not (startKey and startKey ~= "")
addSystem("tonyo ready.\ncfg: engine and key   scan: read the game   @path: read one object")
print("TONYO MODEL v2 loaded")
