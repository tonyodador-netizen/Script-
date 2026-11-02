-- TONYO MODEL - Full AI Suite for Delta (Pure Client Execution)
-- Redesigned for stable executor use

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local guiParent = gethui and gethui() or (syn and syn.protect_gui and game:GetService("CoreGui")) or game:GetService("CoreGui")

local function safeRequest(requestData)
	if syn and syn.request then
		return syn.request(requestData)
	elseif http_request then
		return http_request(requestData)
	elseif request then
		return request(requestData)
	else
		local success, res = pcall(function()
			return HttpService:RequestAsync({
				Url = requestData.Url,
				Method = requestData.Method or "GET",
				Headers = requestData.Headers,
				Body = requestData.Body
			})
		end)
		if success then
			return {
				StatusCode = res.StatusCode,
				Body = res.Body,
				Success = res.Success
			}
		else
			error(res)
		end
	end
end

local AI_MODELS = {
	{
		name = "Gemini Flash",
		id = "gemini",
		endpoint = function(key)
			return "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=" .. key
		end,
		formatBody = function(system, contents)
			return HttpService:JSONEncode({
				systemInstruction = {parts = {{text = system}}},
				contents = contents,
				generationConfig = {responseMimeType = "application/json"}
			})
		end,
		parseResponse = function(data)
			local text = ""
			if data.candidates and data.candidates[1] and data.candidates[1].content then
				for _, p in ipairs(data.candidates[1].content.parts) do
					if p.text then
						text = text .. p.text
					end
				end
			end
			return text
		end,
		testEndpoint = function(key)
			return "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=" .. key
		end,
		testPayload = function()
			return HttpService:JSONEncode({contents = {{parts = {{text = "ping"}}}}})
		end,
		validateResponse = function(res)
			return res and (res.StatusCode == 200 or res.Success == true)
		end
	},
	{
		name = "Claude Sonnet",
		id = "claude",
		endpoint = function(key)
			return "https://api.anthropic.com/v1/messages"
		end,
		headers = function(key)
			return {
				["Content-Type"] = "application/json",
				["x-api-key"] = key,
				["anthropic-version"] = "2023-06-01"
			}
		end,
		formatBody = function(system, contents)
			local messages = {}
			for _, item in ipairs(contents) do
				local role = item.role == "model" and "assistant" or item.role
				local text = item.parts and item.parts[1] and item.parts[1].text or ""
				table.insert(messages, {role = role, content = text})
			end
			return HttpService:JSONEncode({
				model = "claude-3-5-sonnet-20241022",
				max_tokens = 1024,
				system = system,
				messages = messages
			})
		end,
		parseResponse = function(data)
			local text = ""
			if data.content then
				for _, block in ipairs(data.content) do
					if block.type == "text" then
						text = text .. block.text
					end
				end
			end
			return text
		end,
		testEndpoint = function(key)
			return "https://api.anthropic.com/v1/messages"
		end,
		testPayload = function()
			return HttpService:JSONEncode({
				model = "claude-3-5-sonnet-20241022",
				max_tokens = 5,
				messages = {{role = "user", content = "ping"}}
			})
		end,
		validateResponse = function(res)
			return res and (res.StatusCode == 200 or res.Success == true)
		end
	},
	{
		name = "OpenAI GPT-4o",
		id = "openai",
		endpoint = function(key)
			return "https://api.openai.com/v1/chat/completions"
		end,
		headers = function(key)
			return {
				["Content-Type"] = "application/json",
				["Authorization"] = "Bearer " .. key
			}
		end,
		formatBody = function(system, contents)
			local messages = {{role = "system", content = system}}
			for _, item in ipairs(contents) do
				local role = item.role == "model" and "assistant" or item.role
				local text = item.parts and item.parts[1] and item.parts[1].text or ""
				table.insert(messages, {role = role, content = text})
			end
			return HttpService:JSONEncode({
				model = "gpt-4o-mini",
				messages = messages
			})
		end,
		parseResponse = function(data)
			if data.choices and data.choices[1] and data.choices[1].message then
				return data.choices[1].message.content
			end
			return ""
		end,
		testEndpoint = function(key)
			return "https://api.openai.com/v1/models"
		end,
		testPayload = function()
			return nil
		end,
		validateResponse = function(res)
			return res and (res.StatusCode == 200 or res.Success == true)
		end
	}
}

local CONFIG = {
	MAX_HISTORY = 12,
	PANEL_SIZE = Vector2.new(360, 470),
	COLOR_BG = Color3.fromRGB(15, 15, 18),
	COLOR_SURFACE = Color3.fromRGB(22, 22, 28),
	COLOR_INPUT = Color3.fromRGB(30, 30, 38),
	COLOR_ACCENT = Color3.fromRGB(99, 102, 241),
	COLOR_TEXT = Color3.fromRGB(240, 240, 245),
	COLOR_DIM = Color3.fromRGB(140, 140, 155),
	COLOR_WHITE = Color3.fromRGB(255, 255, 255),
	COLOR_SUCCESS = Color3.fromRGB(34, 197, 94),
	COLOR_FAIL = Color3.fromRGB(239, 68, 68)
}

local SYSTEM_PROMPT = [[You are TONYO Model, an advanced AI development assistant embedded directly inside a Roblox game.
Your job is to understand user requests, assist with scripting, and analyze the workspace. Return responses in valid JSON containing optional say string and ops array. Example: {"say": "Done!", "ops": []}]]

local selectedModelIndex = _G.TonyoModelIndex or 1
local key = _G.TonyoKey or ""

local function createCorner(instance, radius)
	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, radius)
	uiCorner.Parent = instance
	return uiCorner
end

local function createStroke(instance, transparency, color, thickness)
	local uiStroke = Instance.new("UIStroke")
	uiStroke.Color = color or Color3.fromRGB(255, 255, 255)
	uiStroke.Transparency = transparency or 0.85
	uiStroke.Thickness = thickness or 1
	uiStroke.Parent = instance
	return uiStroke
end

if guiParent:FindFirstChild("TONYOModel_UI") then
	guiParent.TONYOModel_UI:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TONYOModel_UI"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 999999
screenGui.Parent = guiParent

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.Size = UDim2.new(0, CONFIG.PANEL_SIZE.X, 0, CONFIG.PANEL_SIZE.Y)
panel.BackgroundColor3 = CONFIG.COLOR_BG
panel.BorderSizePixel = 0
panel.ClipsDescendants = true
panel.Parent = screenGui

createCorner(panel, 14)
createStroke(panel, 0.75, CONFIG.COLOR_ACCENT, 1)

local body = Instance.new("Frame")
body.Size = UDim2.new(1, 0, 1, 0)
body.BackgroundTransparency = 1
body.Parent = panel

local headerBar = Instance.new("Frame")
headerBar.Size = UDim2.new(1, 0, 0, 42)
headerBar.BackgroundColor3 = CONFIG.COLOR_SURFACE
headerBar.BorderSizePixel = 0
headerBar.Parent = body
createCorner(headerBar, 14)

local titleLabel = Instance.new("TextLabel")
titleLabel.BackgroundTransparency = 1
titleLabel.Position = UDim2.new(0, 14, 0, 0)
titleLabel.Size = UDim2.new(0, 120, 1, 0)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 13
titleLabel.TextColor3 = CONFIG.COLOR_WHITE
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Text = "TONYO MODEL"
titleLabel.Parent = headerBar

local statusIndicator = Instance.new("Frame")
statusIndicator.Position = UDim2.new(0, 134, 0.5, -4)
statusIndicator.Size = UDim2.new(0, 8, 0, 8)
statusIndicator.BackgroundColor3 = CONFIG.COLOR_DIM
statusIndicator.BorderSizePixel = 0
statusIndicator.Parent = headerBar
createCorner(statusIndicator, 4)

local keyBox = Instance.new("TextBox")
keyBox.Position = UDim2.new(0, 148, 0.5, -12)
keyBox.Size = UDim2.new(1, -188, 0, 24)
keyBox.BackgroundColor3 = CONFIG.COLOR_INPUT
keyBox.BorderSizePixel = 0
keyBox.Font = Enum.Font.Gotham
keyBox.TextSize = 11
keyBox.TextColor3 = CONFIG.COLOR_TEXT
keyBox.PlaceholderColor3 = CONFIG.COLOR_DIM
keyBox.PlaceholderText = key ~= "" and "Key Saved" or "API Key..."
keyBox.Text = ""
keyBox.ClearTextOnFocus = false
keyBox.Parent = headerBar
createCorner(keyBox, 6)
createStroke(keyBox, 0.85, CONFIG.COLOR_WHITE, 1)

local function updateStatusIndicator(isValid)
	if key == "" then
		statusIndicator.BackgroundColor3 = CONFIG.COLOR_DIM
	elseif isValid then
		statusIndicator.BackgroundColor3 = CONFIG.COLOR_SUCCESS
	else
		statusIndicator.BackgroundColor3 = CONFIG.COLOR_FAIL
	end
end

local function validateApiKey(testKey)
	if testKey == "" then
		return false
	end
	local model = AI_MODELS[selectedModelIndex]
	local endpoint = model.testEndpoint(testKey)
	local payload = model.testPayload()
	local headers = model.headers and model.headers(testKey) or {["Content-Type"] = "application/json"}

	local success, response = pcall(function()
		return safeRequest({
			Url = endpoint,
			Method = payload and "POST" or "GET",
			Headers = headers,
			Body = payload
		})
	end)

	if success and response then
		return model.validateResponse(response)
	end
	return false
end

if key ~= "" then
	task.spawn(function()
		updateStatusIndicator(validateApiKey(key))
	end)
end

keyBox.FocusLost:Connect(function()
	local sanitizedText = string.gsub(keyBox.Text, "%s", "")
	if sanitizedText == "" then
		return
	end

	key = sanitizedText
	_G.TonyoKey = sanitizedText
	keyBox.Text = ""
	keyBox.PlaceholderText = "Validating..."
	statusIndicator.BackgroundColor3 = CONFIG.COLOR_ACCENT

	task.spawn(function()
		local isValid = validateApiKey(key)
		updateStatusIndicator(isValid)
		keyBox.PlaceholderText = isValid and "Verified & Saved" or "Invalid Key!"
	end)
end)

local closeButton = Instance.new("TextButton")
closeButton.Position = UDim2.new(1, -32, 0.5, -12)
closeButton.Size = UDim2.new(0, 24, 0, 24)
closeButton.BackgroundColor3 = CONFIG.COLOR_INPUT
closeButton.BorderSizePixel = 0
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 12
closeButton.TextColor3 = CONFIG.COLOR_DIM
closeButton.Text = "X"
closeButton.Parent = headerBar
createCorner(closeButton, 6)
closeButton.Activated:Connect(function()
	screenGui:Destroy()
end)

local modelButton = Instance.new("TextButton")
modelButton.Position = UDim2.new(0, 10, 0, 48)
modelButton.Size = UDim2.new(1, -20, 0, 26)
modelButton.BackgroundColor3 = CONFIG.COLOR_SURFACE
modelButton.BorderSizePixel = 0
modelButton.Font = Enum.Font.GothamMedium
modelButton.TextSize = 11
modelButton.TextColor3 = CONFIG.COLOR_TEXT
modelButton.Text = "Engine: " .. AI_MODELS[selectedModelIndex].name .. " ▾"
modelButton.Parent = body
createCorner(modelButton, 6)
createStroke(modelButton, 0.85, CONFIG.COLOR_ACCENT, 1)

modelButton.Activated:Connect(function()
	selectedModelIndex = (selectedModelIndex % #AI_MODELS) + 1
	_G.TonyoModelIndex = selectedModelIndex
	modelButton.Text = "Engine: " .. AI_MODELS[selectedModelIndex].name .. " ▾"
	if key ~= "" then
		task.spawn(function()
			statusIndicator.BackgroundColor3 = CONFIG.COLOR_ACCENT
			updateStatusIndicator(validateApiKey(key))
		end)
	end
end)

local listContainer = Instance.new("ScrollingFrame")
listContainer.Position = UDim2.new(0, 10, 0, 80)
listContainer.Size = UDim2.new(1, -20, 1, -132)
listContainer.BackgroundTransparency = 1
listContainer.BorderSizePixel = 0
listContainer.ScrollBarThickness = 3
listContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
listContainer.Parent = body

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 8)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = listContainer

listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	local contentHeight = listLayout.AbsoluteContentSize.Y
	listContainer.CanvasSize = UDim2.new(0, 0, 0, contentHeight + 4)
	listContainer.CanvasPosition = Vector2.new(0, math.max(0, contentHeight - listContainer.AbsoluteSize.Y + 4))
end)

local function addMessage(role, text, isSubtext)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = isSubtext and 12 or 13
	label.TextColor3 = isSubtext and CONFIG.COLOR_DIM or CONFIG.COLOR_TEXT
	label.TextWrapped = true
	label.TextXAlignment = (role == "user") and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left
	label.Text = text
	label.Parent = listContainer
	return label
end

local inputContainer = Instance.new("Frame")
inputContainer.Position = UDim2.new(0, 10, 1, -44)
inputContainer.Size = UDim2.new(1, -20, 0, 36)
inputContainer.BackgroundColor3 = CONFIG.COLOR_SURFACE
inputContainer.BorderSizePixel = 0
inputContainer.Parent = body
createCorner(inputContainer, 18)
createStroke(inputContainer, 0.85, CONFIG.COLOR_ACCENT, 1)

local inputField = Instance.new("TextBox")
inputField.Size = UDim2.new(1, -40, 1, 0)
inputField.Position = UDim2.new(0, 0, 0, 0)
inputField.BackgroundTransparency = 1
inputField.Font = Enum.Font.Gotham
inputField.TextSize = 13
inputField.TextColor3 = CONFIG.COLOR_TEXT
inputField.PlaceholderColor3 = CONFIG.COLOR_DIM
inputField.PlaceholderText = "Type a command or request..."
inputField.Text = ""
inputField.TextXAlignment = Enum.TextXAlignment.Left
inputField.ClearTextOnFocus = false
inputField.Parent = inputContainer

local inputPadding = Instance.new("UIPadding")
inputPadding.PaddingLeft = UDim.new(0, 14)
inputPadding.Parent = inputField

local history = {}
local busy = false

local function requestAI(contents)
	local currentModel = AI_MODELS[selectedModelIndex]
	local endpoint = currentModel.endpoint(key)
	local requestBody = currentModel.formatBody(SYSTEM_PROMPT, contents)
	local reqHeaders = currentModel.headers and currentModel.headers(key) or {["Content-Type"] = "application/json"}

	local success, response = pcall(function()
		return safeRequest({
			Url = endpoint,
			Method = "POST",
			Headers = reqHeaders,
			Body = requestBody
		})
	end)

	if not success or not response then
		return nil, "Connection failed: " .. tostring(response)
	end

	local statusCode = response.StatusCode or 200
	local responseBody = response.Body

	local decodeSuccess, data = pcall(function()
		return HttpService:JSONDecode(responseBody)
	end)
	if not decodeSuccess then
		return nil, "Unreadable response (HTTP " .. tostring(statusCode) .. ")"
	end
	if statusCode ~= 200 then
		return nil, "HTTP Error " .. tostring(statusCode)
	end

	local extractedText = currentModel.parseResponse(data)
	if not extractedText or extractedText == "" then
		return nil, "Empty response from AI"
	end
	return extractedText
end

local function processMessageSend(userInputText)
	if busy or userInputText == "" then
		return
	end
	if key == "" then
		addMessage("ai", "Please enter your API key first.", true)
		return
	end

	busy = true
	addMessage("user", userInputText)
	local aiMsg = addMessage("ai", "TONYO Model is thinking...", true)

	local contentsPayload = {}
	for i = 1, #history do
		table.insert(contentsPayload, history[i])
	end
	table.insert(contentsPayload, {role = "user", parts = {{text = userInputText}}})

	local rawResponse, err = requestAI(contentsPayload)

	if not rawResponse then
		aiMsg.Text = "Error: " .. tostring(err)
		aiMsg.TextColor3 = CONFIG.COLOR_FAIL
		busy = false
		return
	end

	local cleanedRaw = string.gsub(rawResponse, "^%s*```%a*%s*", "")
	cleanedRaw = string.gsub(cleanedRaw, "%s*```%s*$", "")

	local jsonOk, parsedData = pcall(function()
		return HttpService:JSONDecode(cleanedRaw)
	end)
	if not jsonOk or type(parsedData) ~= "table" then
		aiMsg.Text = cleanedRaw
	else
		aiMsg.Text = tostring(parsedData.say or "Done.")
	end

	aiMsg.TextColor3 = CONFIG.COLOR_TEXT

	table.insert(history, {role = "user", parts = {{text = userInputText}}})
	table.insert(history, {role = "model", parts = {{text = cleanedRaw}}})
	while #history > CONFIG.MAX_HISTORY do
		table.remove(history, 1)
	end
	busy = false
end

local function submitInput()
	local trimmed = string.gsub(inputField.Text, "^%s+", "")
	trimmed = string.gsub(trimmed, "%s+$", "")
	if trimmed == "" then
		return
	end
	inputField.Text = ""
	processMessageSend(trimmed)
end

inputField.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		submitInput()
	end
end)

local sendButton = Instance.new("TextButton")
sendButton.Position = UDim2.new(1, -32, 0.5, -14)
sendButton.Size = UDim2.new(0, 28, 0, 28)
sendButton.BackgroundColor3 = CONFIG.COLOR_ACCENT
sendButton.BorderSizePixel = 0
sendButton.Font = Enum.Font.GothamBold
sendButton.TextSize = 14
sendButton.TextColor3 = CONFIG.COLOR_WHITE
sendButton.Text = "↑"
sendButton.Parent = inputContainer
createCorner(sendButton, 14)
sendButton.Activated:Connect(submitInput)

addMessage("ai", "Hello! I am TONYO MODEL. Paste your API key above to start.", true)
print("TONYO MODEL: Fully loaded and running!")
