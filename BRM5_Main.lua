-- 🔧 SERVICES
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

-- ⚙️ SETTINGS
local aimbotSmoothing = 5
local aimbotFOV = 60
local scanCooldown = 0.15
local aimbotEnabled = false
local silentAimEnabled = false
local silentAimFOV = 100
local silentAimPrediction = false
local silentAimHitChance = 100

-- 🔁 VARIABLES
local aiming = false
local currentTarget = nil
local lastScan = 0
local cachedNPCs = {}
local fullBrightEnabled = false
local noFogEnabled = false
local originalFogEnd = Lighting.FogEnd
local originalAtmospheres = {}
local createdESP = {}
local silentAimTarget = nil

-- 🎯 ALLOWED NPC WEAPONS
local allowedWeapons = {
    ["AI_AK"] = true, ["igla"] = true, ["AI_RPD"] = true, ["AI_PKM"] = true,
    ["AI_SVD"] = true, ["rpg7v2"] = true, ["AI_PP19"] = true, ["AI_RPK"] = true,
    ["AI_SAIGA"] = true, ["AI_MAKAROV"] = true, ["AI_PPSH"] = true, ["AI_DB"] = true,
    ["AI_MOSIN"] = true, ["AI_VZ"] = true, ["AI_6B47_Rifleman"] = true,
    ["AI_6B45_Commander"] = true, ["AI_6B47_Commander"] = true, ["AI_6B45_Rifleman"] = true,
    ["AI_KSVK"] = true, ["AI_Chicom"] = true, ["AI_6B26"] = true, ["AI_6B3M"] = true, 
    ["Machete"] = true, ["AI_Beanie"] = true, ["AI_FaceCover"] = true
}

-- 🛠️ HELPER FUNCTIONS
local function hasAllowedWeapon(npc)
    for weapon in pairs(allowedWeapons) do
        if npc:FindFirstChild(weapon) then return true end
    end
    return false
end

local function isAlive(npc)
    for _, d in ipairs(npc:GetDescendants()) do
        if d:IsA("BallSocketConstraint") then return false end
    end
    return true
end

-- 🔲 ESP
local function createNpcHeadESP(npc)
    if createdESP[npc] then return end
    local head = npc:FindFirstChild("Head")
    if head and not head:FindFirstChild("HeadESP") then
        local esp = Instance.new("BoxHandleAdornment")
        esp.Name = "HeadESP"
        esp.Adornee = head
        esp.AlwaysOnTop = true
        esp.ZIndex = 5
        esp.Size = head.Size
        esp.Transparency = 0.5
        esp.Color3 = Color3.new(0, 1, 0)
        esp.Parent = head
        createdESP[npc] = true

        task.spawn(function()
            while isAlive(npc) do task.wait(0.5) end
            if esp and esp.Parent then esp:Destroy() end
            createdESP[npc] = nil
        end)
    end
end

-- ♻️ CACHING NPCS
task.spawn(function()
    while true do
        cachedNPCs = {}
        for _, npc in ipairs(workspace:GetChildren()) do
            if npc:IsA("Model") and npc.Name == "Male" and hasAllowedWeapon(npc) and isAlive(npc) then
                local head = npc:FindFirstChild("Head")
                if head then
                    table.insert(cachedNPCs, {npc = npc, head = head})
                    createNpcHeadESP(npc)
                end
            end
        end
        task.wait(1)
    end
end)

-- ☀️ FULLBRIGHT & NOFOG
local brightLoop = nil
local function LoopFullBright()
    if brightLoop then brightLoop:Disconnect() end
    brightLoop = RunService.RenderStepped:Connect(function()
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
        Lighting.FogEnd = 100000
        Lighting.GlobalShadows = false
        Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
        Lighting.Ambient = Color3.fromRGB(200, 200, 200)
    end)
end

local function StopFullBright()
    if brightLoop then brightLoop:Disconnect() brightLoop = nil end
    Lighting.Brightness = 1
    Lighting.GlobalShadows = true
    Lighting.FogEnd = originalFogEnd
end

local function applyNoFog()
    Lighting.FogEnd = 100000
    for _, v in pairs(Lighting:GetDescendants()) do
        if v:IsA("Atmosphere") then
            table.insert(originalAtmospheres, v:Clone())
            v:Destroy()
        end
    end
end

local function disableNoFog()
    Lighting.FogEnd = originalFogEnd
    for _, v in pairs(originalAtmospheres) do
        v.Parent = Lighting
    end
    originalAtmospheres = {}
end

-- 🎯 SILENT AIM FUNCTIONS
local function getSilentAimTarget()
    if not silentAimEnabled then return nil end
    
    local mousePos = UserInputService:GetMouseLocation()
    local closestDist = math.huge
    local target = nil
    
    for _, data in ipairs(cachedNPCs) do
        local npc = data.npc
        local head = data.head
        
        if head and head:IsA("BasePart") then
            local screen3D, onScreen = Camera:WorldToViewportPoint(head.Position)
            if onScreen then
                local screenPos = Vector2.new(screen3D.X, screen3D.Y)
                local dist = (screenPos - Vector2.new(mousePos.X, mousePos.Y)).Magnitude
                
                if dist < silentAimFOV and dist < closestDist then
                    local rayParams = RaycastParams.new()
                    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
                    rayParams.FilterDescendantsInstances = {LocalPlayer.Character, Camera}
                    
                    local direction = (head.Position - Camera.CFrame.Position).Unit * 1000
                    local result = workspace:Raycast(Camera.CFrame.Position, direction, rayParams)
                    
                    if result and result.Instance and result.Instance:IsDescendantOf(npc) then
                        closestDist = dist
                        target = head
                    end
                end
            end
        end
    end
    
    return target
end

-- 👆 MOUSE
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        aiming = true
    end
end)

UserInputService.InputEnded:Connect(function(input, gp)
    if gp then return end
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        aiming = false
        currentTarget = nil
    end
end)

-- 🎯 AIMBOT
RunService.RenderStepped:Connect(function()
    -- Silent Aim Update
    silentAimTarget = getSilentAimTarget()
    
    -- Regular Aimbot
    if not aiming or not aimbotEnabled then
        currentTarget = nil
        return
    end

    local mousePos = UserInputService:GetMouseLocation()
    
    if tick() - lastScan > scanCooldown or not currentTarget or not currentTarget:IsDescendantOf(workspace) or not isAlive(currentTarget.Parent) then
        lastScan = tick()
        local closestDist = math.huge
        local newTarget = nil

        for _, data in ipairs(cachedNPCs) do
            local npc = data.npc
            local head = data.head

            if head and head:IsA("BasePart") then
                local screen3D, onScreen = Camera:WorldToViewportPoint(head.Position)
                if onScreen then
                    local screenPos = Vector2.new(screen3D.X, screen3D.Y)
                    local dist = (screenPos - Vector2.new(mousePos.X, mousePos.Y)).Magnitude

                    if dist < aimbotFOV and dist < closestDist then
                        local rayParams = RaycastParams.new()
                        rayParams.FilterType = Enum.RaycastFilterType.Blacklist
                        rayParams.FilterDescendantsInstances = {LocalPlayer.Character, Camera}

                        local direction = (head.Position - Camera.CFrame.Position).Unit * 1000
                        local result = workspace:Raycast(Camera.CFrame.Position, direction, rayParams)

                        if result and result.Instance and result.Instance:IsDescendantOf(npc) then
                            closestDist = dist
                            newTarget = head
                        end
                    end
                end
            end
        end

        currentTarget = newTarget
    end

    if currentTarget then
        local head = currentTarget
        if head and head:IsA("BasePart") then
            local screen3D, onScreen = Camera:WorldToViewportPoint(head.Position)
            if onScreen then
                local screenPos = Vector2.new(screen3D.X, screen3D.Y)
                local dx = (screenPos.X - mousePos.X) / math.clamp(aimbotSmoothing, 0.6, 100)
                local dy = (screenPos.Y - mousePos.Y) / math.clamp(aimbotSmoothing, 0.6, 100)

                if typeof(mousemoverel) == "function" then
                    mousemoverel(dx, dy)
                end
            end
        end
    end
end)

-- 🔫 SILENT AIM HOOK
local OldNamecall = nil
OldNamecall = hookmetamethod(game, "__namecall", function(Self, ...)
    if silentAimTarget and silentAimEnabled and getnamecallmethod() == "Raycast" then
        if math.random(100) <= silentAimHitChance then
            local Args = {...}
            
            if Args[1] == Camera.CFrame.Position then
                Args[2] = silentAimTarget.Position - Camera.CFrame.Position
            end
            
            return OldNamecall(Self, unpack(Args))
        end
    end
    
    return OldNamecall(Self, ...)
end)

-- 🎨 ANONYMOUS GUI
local gui = Instance.new("ScreenGui")
gui.Name = "AnonymousGUI"
gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
gui.ResetOnSpawn = false

-- 🎭 STARTUP SCREEN
local startupFrame = Instance.new("Frame")
startupFrame.Name = "StartupFrame"
startupFrame.Size = UDim2.new(1, 0, 1, 0)
startupFrame.Position = UDim2.new(0, 0, 0, 0)
startupFrame.BackgroundColor3 = Color3.new(0, 0, 0)
startupFrame.BorderSizePixel = 0
startupFrame.Parent = gui

local startupLogo = Instance.new("TextLabel")
startupLogo.Name = "StartupLogo"
startupLogo.Size = UDim2.new(0, 400, 0, 100)
startupLogo.Position = UDim2.new(0.5, -200, 0.4, -50)
startupLogo.BackgroundTransparency = 1
startupLogo.Text = "ANONYMOUS"
startupLogo.TextColor3 = Color3.new(0, 1, 0)
startupLogo.TextScaled = true
startupLogo.Font = Enum.Font.Code
startupLogo.TextStrokeTransparency = 0
startupLogo.TextStrokeColor3 = Color3.new(0, 0, 0)
startupLogo.Parent = startupFrame

local createdBy = Instance.new("TextLabel")
createdBy.Name = "CreatedBy"
createdBy.Size = UDim2.new(0, 200, 0, 30)
createdBy.Position = UDim2.new(0.5, -100, 0.6, 0)
createdBy.BackgroundTransparency = 1
createdBy.Text = "Created by ORBI"
createdBy.TextColor3 = Color3.new(0, 0.8, 0)
createdBy.TextScaled = true
createdBy.Font = Enum.Font.Code
createdBy.Parent = startupFrame

-- 🎬 STARTUP ANIMATION
local fadeIn = TweenService:Create(startupLogo, TweenInfo.new(1.5, Enum.EasingStyle.Quad), {TextTransparency = 0})
local fadeOut = TweenService:Create(startupFrame, TweenInfo.new(1, Enum.EasingStyle.Quad), {BackgroundTransparency = 1})

fadeIn:Play()
fadeIn.Completed:Connect(function()
    wait(2)
    fadeOut:Play()
    fadeOut.Completed:Connect(function()
        startupFrame:Destroy()
    end)
end)

-- 🖥️ MAIN GUI
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 650, 0, 450)
mainFrame.Position = UDim2.new(0.5, -325, 0.5, -225)
mainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = gui
mainFrame.Visible = false

-- 🎨 MAIN FRAME STYLING
local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 10)
mainCorner.Parent = mainFrame

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = Color3.fromRGB(0, 255, 0)
mainStroke.Thickness = 2
mainStroke.Parent = mainFrame

-- 📊 HEADER
local headerFrame = Instance.new("Frame")
headerFrame.Name = "HeaderFrame"
headerFrame.Size = UDim2.new(1, 0, 0, 50)
headerFrame.Position = UDim2.new(0, 0, 0, 0)
headerFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
headerFrame.BorderSizePixel = 0
headerFrame.Parent = mainFrame

local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 10)
headerCorner.Parent = headerFrame

local headerTitle = Instance.new("TextLabel")
headerTitle.Name = "HeaderTitle"
headerTitle.Size = UDim2.new(0, 200, 1, 0)
headerTitle.Position = UDim2.new(0, 15, 0, 0)
headerTitle.BackgroundTransparency = 1
headerTitle.Text = "ANONYMOUS AIMBOT"
headerTitle.TextColor3 = Color3.new(0, 1, 0)
headerTitle.TextScaled = true
headerTitle.Font = Enum.Font.Code
headerTitle.TextXAlignment = Enum.TextXAlignment.Left
headerTitle.Parent = headerFrame

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.Size = UDim2.new(0, 30, 0, 30)
closeButton.Position = UDim2.new(1, -40, 0, 10)
closeButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
closeButton.Text = "X"
closeButton.TextColor3 = Color3.new(1, 1, 1)
closeButton.TextScaled = true
closeButton.Font = Enum.Font.CodeBold
closeButton.Parent = headerFrame

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 5)
closeCorner.Parent = closeButton

closeButton.MouseButton1Click:Connect(function()
    gui:Destroy()
end)

-- 📱 TABS
local tabFrame = Instance.new("Frame")
tabFrame.Name = "TabFrame"
tabFrame.Size = UDim2.new(0, 150, 1, -50)
tabFrame.Position = UDim2.new(0, 0, 0, 50)
tabFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
tabFrame.BorderSizePixel = 0
tabFrame.Parent = mainFrame

local contentFrame = Instance.new("Frame")
contentFrame.Name = "ContentFrame"
contentFrame.Size = UDim2.new(1, -150, 1, -50)
contentFrame.Position = UDim2.new(0, 150, 0, 50)
contentFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
contentFrame.BorderSizePixel = 0
contentFrame.Parent = mainFrame

-- 🎯 TAB SYSTEM
local tabs = {}
local currentTab = nil

local function createTab(name, icon)
    local tab = Instance.new("TextButton")
    tab.Name = name .. "Tab"
    tab.Size = UDim2.new(1, -10, 0, 40)
    tab.Position = UDim2.new(0, 5, 0, #tabs * 45 + 10)
    tab.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    tab.Text = icon .. " " .. name
    tab.TextColor3 = Color3.new(0.7, 0.7, 0.7)
    tab.TextScaled = true
    tab.Font = Enum.Font.Code
    tab.Parent = tabFrame
    
    local tabCorner = Instance.new("UICorner")
    tabCorner.CornerRadius = UDim.new(0, 5)
    tabCorner.Parent = tab
    
    local content = Instance.new("ScrollingFrame")
    content.Name = name .. "Content"
    content.Size = UDim2.new(1, -20, 1, -20)
    content.Position = UDim2.new(0, 10, 0, 10)
    content.BackgroundTransparency = 1
    content.BorderSizePixel = 0
    content.ScrollBarThickness = 8
    content.ScrollBarImageColor3 = Color3.new(0, 1, 0)
    content.Parent = contentFrame
    content.Visible = false
    
    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 10)
    layout.Parent = content
    
    tab.MouseButton1Click:Connect(function()
        if currentTab then
            currentTab.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
            currentTab.TextColor3 = Color3.new(0.7, 0.7, 0.7)
            contentFrame:FindFirstChild(currentTab.Name:gsub("Tab", "Content")).Visible = false
        end
        
        currentTab = tab
        tab.BackgroundColor3 = Color3.fromRGB(0, 100, 0)
        tab.TextColor3 = Color3.new(1, 1, 1)
        content.Visible = true
    end)
    
    table.insert(tabs, tab)
    return content
end

-- 🎯 AIMBOT TAB
local aimbotContent = createTab("Aimbot", "🎯")

local function createToggle(parent, name, callback, defaultValue)
    local toggle = Instance.new("Frame")
    toggle.Name = name .. "Toggle"
    toggle.Size = UDim2.new(1, 0, 0, 30)
    toggle.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    toggle.Parent = parent
    
    local toggleCorner = Instance.new("UICorner")
    toggleCorner.CornerRadius = UDim.new(0, 5)
    toggleCorner.Parent = toggle
    
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -60, 1, 0)
    label.Position = UDim2.new(0, 10, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = name
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextScaled = true
    label.Font = Enum.Font.Code
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = toggle
    
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(0, 40, 0, 20)
    button.Position = UDim2.new(1, -50, 0, 5)
    button.BackgroundColor3 = defaultValue and Color3.fromRGB(0, 150, 0) or Color3.fromRGB(150, 0, 0)
    button.Text = defaultValue and "ON" or "OFF"
    button.TextColor3 = Color3.new(1, 1, 1)
    button.TextScaled = true
    button.Font = Enum.Font.CodeBold
    button.Parent = toggle
    
    local buttonCorner = Instance.new("UICorner")
    buttonCorner.CornerRadius = UDim.new(0, 3)
    buttonCorner.Parent = button
    
    local isEnabled = defaultValue
    button.MouseButton1Click:Connect(function()
        isEnabled = not isEnabled
        button.BackgroundColor3 = isEnabled and Color3.fromRGB(0, 150, 0) or Color3.fromRGB(150, 0, 0)
        button.Text = isEnabled and "ON" or "OFF"
        callback(isEnabled)
    end)
    
    return toggle
end

local function createSlider(parent, name, min, max, default, callback)
    local slider = Instance.new("Frame")
    slider.Name = name .. "Slider"
    slider.Size = UDim2.new(1, 0, 0, 50)
    slider.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    slider.Parent = parent
    
    local sliderCorner = Instance.new("UICorner")
    sliderCorner.CornerRadius = UDim.new(0, 5)
    sliderCorner.Parent = slider
    
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0, 20)
    label.Position = UDim2.new(0, 10, 0, 5)
    label.BackgroundTransparency = 1
    label.Text = name .. ": " .. default
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextScaled = true
    label.Font = Enum.Font.Code
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = slider
    
    local track = Instance.new("Frame")
    track.Size = UDim2.new(1, -20, 0, 6)
    track.Position = UDim2.new(0, 10, 0, 30)
    track.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    track.Parent = slider
    
    local trackCorner = Instance.new("UICorner")
    trackCorner.CornerRadius = UDim.new(0, 3)
    trackCorner.Parent = track
    
    local fill = Instance.new("Frame")
    fill.Size = UDim2.new((default - min) / (max - min), 0, 1, 0)
    fill.Position = UDim2.new(0, 0, 0, 0)
    fill.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
    fill.Parent = track
    
    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 3)
    fillCorner.Parent = fill
    
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(0, 20, 0, 20)
    button.Position = UDim2.new((default - min) / (max - min), -10, 0, -7)
    button.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
    button.Text = ""
    button.Parent = track
    
    local buttonCorner = Instance.new("UICorner")
    buttonCorner.CornerRadius = UDim.new(0, 10)
    buttonCorner.Parent = button
    
    local dragging = false
    local currentValue = default
    
    button.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
        end
    end)
    
    button.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local mouseX = input.Position.X
            local trackX = track.AbsolutePosition.X
            local trackWidth = track.AbsoluteSize.X
            local percent = math.clamp((mouseX - trackX) / trackWidth, 0, 1)
            
            currentValue = math.floor(min + (max - min) * percent)
            label.Text = name .. ": " .. currentValue
            
            fill.Size = UDim2.new(percent, 0, 1, 0)
            button.Position = UDim2.new(percent, -10, 0, -7)
            
            callback(currentValue)
        end
    end)
    
    return slider
end

-- 🎯 AIMBOT CONTROLS
createToggle(aimbotContent, "Aimbot", function(value)
    aimbotEnabled = value
end, false)

createSlider(aimbotContent, "Smoothing", 1, 20, 5, function(value)
    aimbotSmoothing = value
end)

createSlider(aimbotContent, "FOV", 10, 200, 60, function(value)
    aimbotFOV = value
end)

-- 🔫 SILENT AIM TAB
local silentAimContent = createTab("Silent Aim", "🔫")

createToggle(silentAimContent, "Silent Aim", function(value)
    silentAimEnabled = value
end, false)

createSlider(silentAimContent, "FOV", 10, 300, 100, function(value)
    silentAimFOV = value
end)

createSlider(silentAimContent, "Hit Chance", 0, 100, 100, function(value)
    silentAimHitChance = value
end)

createToggle(silentAimContent, "Prediction", function(value)
    silentAimPrediction = value
end, false)

-- 🎨 VISUALS TAB
local visualsContent = createTab("Visuals", "👁️")

createToggle(visualsContent, "FullBright", function(value)
    fullBrightEnabled = value
    if fullBrightEnabled then
        LoopFullBright()
    else
        StopFullBright()
    end
end, false)

createToggle(visualsContent, "No Fog", function(value)
    noFogEnabled = value
    if noFogEnabled then
        applyNoFog()
    else
        disableNoFog()
    end
end, false)

-- ⚙️ SETTINGS TAB
local settingsContent = createTab("Settings", "⚙️")

local infoLabel = Instance.new("TextLabel")
infoLabel.Size = UDim2.new(1, 0, 0, 100)
infoLabel.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
infoLabel.Text = "ANONYMOUS AIMBOT v2.0\nCreated by ORBI\n\nFeatures:\n• Advanced Aimbot\n• Silent Aim\n• ESP System\n• Visual Enhancements"
infoLabel.TextColor3 = Color3.new(0, 1, 0)
infoLabel.TextScaled = true
infoLabel.Font = Enum.Font.Code
infoLabel.Parent = settingsContent

local infoCorner = Instance.new("UICorner")
infoCorner.CornerRadius = UDim.new(0, 5)
infoCorner.Parent = infoLabel

-- 🔧 DRAG SYSTEM
local dragging = false
local dragStart = nil
local startPos = nil

headerFrame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPos = mainFrame.Position
    end
end)

headerFrame.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStart
        mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

headerFrame.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)

-- 🎮 TOGGLE GUI
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.Insert then
        mainFrame.Visible = not mainFrame.Visible
    end
end)

-- 🎬 SHOW MAIN GUI AFTER STARTUP
wait(4)
mainFrame.Visible = true
if #tabs > 0 then
    tabs[1]:Fire()
end

-- 🎯 FOV CIRCLE FOR AIMBOT
local aimbotFOVCircle = Drawing.new("Circle")
aimbotFOVCircle.Thickness = 2
aimbotFOVCircle.NumSides = 30
aimbotFOVCircle.Radius = aimbotFOV
aimbotFOVCircle.Filled = false
aimbotFOVCircle.Visible = false
aimbotFOVCircle.Color = Color3.new(1, 0, 0)
aimbotFOVCircle.Transparency = 0.5

-- 🔫 FOV CIRCLE FOR SILENT AIM
local silentAimFOVCircle = Drawing.new("Circle")
silentAimFOVCircle.Thickness = 2
silentAimFOVCircle.NumSides = 30
silentAimFOVCircle.Radius = silentAimFOV
silentAimFOVCircle.Filled = false
silentAimFOVCircle.Visible = false
silentAimFOVCircle.Color = Color3.new(0, 1, 0)
silentAimFOVCircle.Transparency = 0.5

-- 🔄 FOV CIRCLE UPDATE
RunService.RenderStepped:Connect(function()
    local mouseLocation = UserInputService:GetMouseLocation()
    
    -- Update Aimbot FOV Circle
    if aimbotEnabled then
        aimbotFOVCircle.Position = Vector2.new(mouseLocation.X, mouseLocation.Y)
        aimbotFOVCircle.Radius = aimbotFOV
        aimbotFOVCircle.Visible = true
    else
        aimbotFOVCircle.Visible = false
    end
    
    -- Update Silent Aim FOV Circle
    if silentAimEnabled then
        silentAimFOVCircle.Position = Vector2.new(mouseLocation.X, mouseLocation.Y)
        silentAimFOVCircle.Radius = silentAimFOV
        silentAimFOVCircle.Visible = true
    else
        silentAimFOVCircle.Visible = false
    end
end)

-- 🎨 ENHANCED VISUAL EFFECTS
local function createGlowEffect(object)
    local glow = Instance.new("ImageLabel")
    glow.Name = "GlowEffect"
    glow.Size = UDim2.new(1, 20, 1, 20)
    glow.Position = UDim2.new(0, -10, 0, -10)
    glow.BackgroundTransparency = 1
    glow.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"
    glow.ImageColor3 = Color3.new(0, 1, 0)
    glow.ImageTransparency = 0.8
    glow.ScaleType = Enum.ScaleType.Slice
    glow.SliceCenter = Rect.new(10, 10, 10, 10)
    glow.ZIndex = object.ZIndex - 1
    glow.Parent = object.Parent
    
    local glowTween = TweenService:Create(glow, TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
        ImageTransparency = 0.5
    })
    glowTween:Play()
    
    return glow
end

-- 🎇 PARTICLE EFFECTS
local function createParticleEffect()
    local particles = {}
    
    for i = 1, 20 do
        local particle = Instance.new("Frame")
        particle.Size = UDim2.new(0, 2, 0, 2)
        particle.Position = UDim2.new(math.random(), 0, math.random(), 0)
        particle.BackgroundColor3 = Color3.new(0, 1, 0)
        particle.BorderSizePixel = 0
        particle.Parent = gui
        
        local particleCorner = Instance.new("UICorner")
        particleCorner.CornerRadius = UDim.new(0, 1)
        particleCorner.Parent = particle
        
        table.insert(particles, particle)
        
        -- Animate particle
        local moveTween = TweenService:Create(particle, TweenInfo.new(math.random(3, 6), Enum.EasingStyle.Linear), {
            Position = UDim2.new(math.random(), 0, math.random(), 0)
        })
        
        local fadeTween = TweenService:Create(particle, TweenInfo.new(2, Enum.EasingStyle.Quad), {
            BackgroundTransparency = 1
        })
        
        moveTween:Play()
        wait(math.random(1, 3))
        fadeTween:Play()
        
        fadeTween.Completed:Connect(function()
            particle:Destroy()
        end)
    end
end

-- 🎵 SOUND EFFECTS
local function playSound(soundId, volume)
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxasset://sounds/" .. soundId
    sound.Volume = volume or 0.5
    sound.Parent = workspace
    sound:Play()
    
    sound.Ended:Connect(function()
        sound:Destroy()
    end)
end

-- 🎯 TARGET INDICATOR
local targetIndicator = Instance.new("Frame")
targetIndicator.Name = "TargetIndicator"
targetIndicator.Size = UDim2.new(0, 50, 0, 50)
targetIndicator.BackgroundTransparency = 1
targetIndicator.Parent = gui

local targetIcon = Instance.new("ImageLabel")
targetIcon.Size = UDim2.new(1, 0, 1, 0)
targetIcon.BackgroundTransparency = 1
targetIcon.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"
targetIcon.ImageColor3 = Color3.new(1, 0, 0)
targetIcon.Parent = targetIndicator

-- 📊 STATUS BAR
local statusBar = Instance.new("Frame")
statusBar.Name = "StatusBar"
statusBar.Size = UDim2.new(0, 300, 0, 80)
statusBar.Position = UDim2.new(0, 10, 1, -90)
statusBar.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
statusBar.BorderSizePixel = 0
statusBar.Parent = gui

local statusCorner = Instance.new("UICorner")
statusCorner.CornerRadius = UDim.new(0, 10)
statusCorner.Parent = statusBar

local statusStroke = Instance.new("UIStroke")
statusStroke.Color = Color3.fromRGB(0, 255, 0)
statusStroke.Thickness = 1
statusStroke.Parent = statusBar

local statusTitle = Instance.new("TextLabel")
statusTitle.Size = UDim2.new(1, 0, 0, 20)
statusTitle.Position = UDim2.new(0, 0, 0, 5)
statusTitle.BackgroundTransparency = 1
statusTitle.Text = "ANONYMOUS STATUS"
statusTitle.TextColor3 = Color3.new(0, 1, 0)
statusTitle.TextScaled = true
statusTitle.Font = Enum.Font.Code
statusTitle.Parent = statusBar

local statusText = Instance.new("TextLabel")
statusText.Size = UDim2.new(1, -10, 1, -25)
statusText.Position = UDim2.new(0, 5, 0, 25)
statusText.BackgroundTransparency = 1
statusText.Text = "Aimbot: OFF\nSilent Aim: OFF\nTargets: 0"
statusText.TextColor3 = Color3.new(1, 1, 1)
statusText.TextScaled = true
statusText.Font = Enum.Font.Code
statusText.TextYAlignment = Enum.TextYAlignment.Top
statusText.Parent = statusBar

-- 🔄 STATUS UPDATE
RunService.Heartbeat:Connect(function()
    local targetCount = #cachedNPCs
    statusText.Text = string.format(
        "Aimbot: %s\nSilent Aim: %s\nTargets: %d\nFPS: %d",
        aimbotEnabled and "ON" or "OFF",
        silentAimEnabled and "ON" or "OFF",
        targetCount,
        math.floor(1 / RunService.Heartbeat:Wait())
    )
end)

-- 🎮 KEYBINDS INFO
local keybindsFrame = Instance.new("Frame")
keybindsFrame.Name = "KeybindsFrame"
keybindsFrame.Size = UDim2.new(0, 200, 0, 100)
keybindsFrame.Position = UDim2.new(1, -210, 1, -110)
keybindsFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
keybindsFrame.BorderSizePixel = 0
keybindsFrame.Parent = gui

local keybindsCorner = Instance.new("UICorner")
keybindsCorner.CornerRadius = UDim.new(0, 10)
keybindsCorner.Parent = keybindsFrame

local keybindsStroke = Instance.new("UIStroke")
keybindsStroke.Color = Color3.fromRGB(0, 255, 0)
keybindsStroke.Thickness = 1
keybindsStroke.Parent = keybindsFrame

local keybindsTitle = Instance.new("TextLabel")
keybindsTitle.Size = UDim2.new(1, 0, 0, 25)
keybindsTitle.Position = UDim2.new(0, 0, 0, 0)
keybindsTitle.BackgroundTransparency = 1
keybindsTitle.Text = "KEYBINDS"
keybindsTitle.TextColor3 = Color3.new(0, 1, 0)
keybindsTitle.TextScaled = true
keybindsTitle.Font = Enum.Font.Code
keybindsTitle.Parent = keybindsFrame

local keybindsText = Instance.new("TextLabel")
keybindsText.Size = UDim2.new(1, -10, 1, -25)
keybindsText.Position = UDim2.new(0, 5, 0, 25)
keybindsText.BackgroundTransparency = 1
keybindsText.Text = "INSERT - Toggle GUI\nRMB - Aimbot\nF1 - Toggle Aimbot\nF2 - Toggle Silent Aim"
keybindsText.TextColor3 = Color3.new(1, 1, 1)
keybindsText.TextScaled = true
keybindsText.Font = Enum.Font.Code
keybindsText.TextYAlignment = Enum.TextYAlignment.Top
keybindsText.Parent = keybindsFrame

-- 🎹 ADDITIONAL KEYBINDS
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    if input.KeyCode == Enum.KeyCode.F1 then
        aimbotEnabled = not aimbotEnabled
        playSound("button_click", 0.3)
    elseif input.KeyCode == Enum.KeyCode.F2 then
        silentAimEnabled = not silentAimEnabled
        playSound("button_click", 0.3)
    elseif input.KeyCode == Enum.KeyCode.F3 then
        fullBrightEnabled = not fullBrightEnabled
        if fullBrightEnabled then
            LoopFullBright()
        else
            StopFullBright()
        end
    elseif input.KeyCode == Enum.KeyCode.F4 then
        noFogEnabled = not noFogEnabled
        if noFogEnabled then
            applyNoFog()
        else
            disableNoFog()
        end
    end
end)

-- 🎊 INITIALIZATION COMPLETE
createParticleEffect()
playSound("chime", 0.5)

print("ANONYMOUS AIMBOT v2.0 - Created by ORBI")
print("GUI loaded successfully!")
print("Press INSERT to toggle GUI")
print("Press F1-F4 for quick toggles")