--[[
    ╔══════════════════════════════════════════════════════════════╗
    ║      ULTRA LAG FIX v4 — SMART RENDER DISTANCE                ║
    ║   Không xóa vĩnh viễn · Tự render lại khi lại gần            ║
    ╚══════════════════════════════════════════════════════════════╝
    
    CƠ CHẾ:
        ✦ Part xa → ẩn (Transparency=1) + tắt collide
        ✦ Đến gần → hiện lại (restore transparency gốc)
        ✦ Effect/Decal → giữ trạng thái, tự restore
        ✦ FPS unlock 240+ (nếu executor hỗ trợ)
        ✦ Không xóa gì → không lo mất map
    
    DÙNG CHO:
        ✓ Map rộng (1000+ studs)
        ✓ Game survival (99 Nights, Dead Rails...)
        ✓ Máy yếu nhưng muốn thấy map khi lại gần
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local CoreGui = game:GetService("CoreGui")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local LP = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- ═══ LOAD UI ═══
local URL = "https://raw.githubusercontent.com/idkshdcs/DoeakHub_UILib/main/DoeakHub_UILib.lua?t=" .. os.time()
local ok, Lib = pcall(function() return loadstring(game:HttpGet(URL))() end)
if not ok or type(Lib) ~= "table" then Lib = nil end

-- ════════════════════════════════════════════════════════════════
--  STATE
-- ════════════════════════════════════════════════════════════════
local State = {
    Enabled = true,
    -- Khoảng cách
    HIDE_DIST = 500,       -- ẩn part xa hơn X studs
    RESTORE_DIST = 400,    -- hiện lại khi gần hơn Y studs (hysteresis)
    EFFECT_DIST = 200,     -- tắt effect xa hơn Z studs
    PHYSICS_DIST = 150,    -- tắt physics part xa hơn
    
    -- Tracking
    HiddenParts = {},      -- [part] = {transparency, cancollide, canquery, cantouch}
    DisabledEffects = {},  -- [obj] = true
    
    -- FPS
    FPS = 0,
    StartTime = tick(),
    
    -- Backup
    Backup = {},
    
    -- Stats
    Stats = {hidden = 0, restored = 0, effects_off = 0, effects_on = 0},
}

local function log(...) print("[SmartRender]", ...) end
local function notify(t, txt, dur)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = t, Text = txt, Duration = dur or 3,
        })
    end)
end

local function getMyPos()
    local c = LP.Character
    local h = c and c:FindFirstChild("HumanoidRootPart")
    return h and h.Position or Vector3.new(0, 0, 0)
end

-- ════════════════════════════════════════════════════════════════
--  FPS UNLOCK
-- ════════════════════════════════════════════════════════════════
local function unlockFPS()
    if setfpscap then pcall(function() setfpscap(9999) end) end
    if setfflag then
        pcall(function()
            setfflag("TaskSchedulerTargetFps", "9999")
            setfflag("DFIntTaskSchedulerTargetFps", "9999")
        end)
    end
    pcall(function()
        if settings and settings().Rendering then
            settings().Rendering.FramerateCap = 9999
        end
    end)
end

-- ════════════════════════════════════════════════════════════════
--  BACKUP
-- ════════════════════════════════════════════════════════════════
local function backupAll()
    State.Backup.Lighting = {
        GlobalShadows = Lighting.GlobalShadows,
        FogEnd = Lighting.FogEnd,
        FogStart = Lighting.FogStart,
    }
    pcall(function()
        State.Backup.Terrain = {
            WaterWaveSize = Workspace.Terrain.WaterWaveSize,
            WaterWaveSpeed = Workspace.Terrain.WaterWaveSpeed,
            WaterReflectance = Workspace.Terrain.WaterReflectance,
            WaterTransparency = Workspace.Terrain.WaterTransparency,
        }
    end)
end

-- ════════════════════════════════════════════════════════════════
--  HIDE PART (lưu trạng thái gốc)
-- ════════════════════════════════════════════════════════════════
local function hidePart(part)
    if State.HiddenParts[part] then return end
    -- Không ẩn part quan trọng
    if part:IsA("Terrain") then return end
    if part:IsDescendantOf(LP.Character) then return end
    if part.Anchored and part.Size.Magnitude > 500 then return end  -- base lớn
    
    -- Lưu trạng thái gốc
    State.HiddenParts[part] = {
        Transparency = part.Transparency,
        CanCollide = part.CanCollide,
        CanQuery = part.CanQuery,
        CanTouch = part.CanTouch,
        CastShadow = part.CastShadow,
    }
    
    -- Ẩn
    pcall(function()
        part.Transparency = 1
        part.CanCollide = false
        part.CanQuery = false
        part.CanTouch = false
        part.CastShadow = false
    end)
    
    State.Stats.hidden = State.Stats.hidden + 1
end

local function showPart(part)
    local orig = State.HiddenParts[part]
    if not orig then return end
    
    pcall(function()
        if part.Parent then
            part.Transparency = orig.Transparency
            part.CanCollide = orig.CanCollide
            part.CanQuery = orig.CanQuery
            part.CanTouch = orig.CanTouch
            part.CastShadow = orig.CastShadow
        end
    end)
    
    State.HiddenParts[part] = nil
    State.Stats.restored = State.Stats.restored + 1
end

-- ════════════════════════════════════════════════════════════════
--  HIDE EFFECTS (particle, fire, light...)
-- ════════════════════════════════════════════════════════════════
local function hideEffect(obj)
    if State.DisabledEffects[obj] then return end
    State.DisabledEffects[obj] = {
        Enabled = obj.Enabled,
    }
    pcall(function() obj.Enabled = false end)
    State.Stats.effects_off = State.Stats.effects_off + 1
end

local function showEffect(obj)
    local orig = State.DisabledEffects[obj]
    if not orig then return end
    if obj.Parent then
        pcall(function() obj.Enabled = orig.Enabled end)
    end
    State.DisabledEffects[obj] = nil
    State.Stats.effects_on = State.Stats.effects_on + 1
end

-- ════════════════════════════════════════════════════════════════
--  MAIN LOOP — Chạy mỗi 0.5s
-- ════════════════════════════════════════════════════════════════
local function renderLoop()
    if not State.Enabled then return end
    
    local myPos = getMyPos()
    local hideDist2 = State.HIDE_DIST * State.HIDE_DIST
    local restoreDist2 = State.RESTORE_DIST * State.RESTORE_DIST
    local effectDist2 = State.EFFECT_DIST * State.EFFECT_DIST
    local physicsDist2 = State.PHYSICS_DIST * State.PHYSICS_DIST
    
    -- ==== 1. PART XA ====
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("BasePart") and not obj:IsA("Terrain") then
            local isHidden = State.HiddenParts[obj] ~= nil
            local dist2 = (obj.Position - myPos).Magnitude ^ 2
            
            if isHidden then
                -- Đang ẩn, check xem gần lại chưa
                if dist2 < restoreDist2 then
                    showPart(obj)
                end
            else
                -- Đang hiện, check xem xa quá chưa
                if dist2 > hideDist2 then
                    hidePart(obj)
                end
            end
        end
    end
    
    -- ==== 2. EFFECT XA ====
    for _, obj in ipairs(Workspace:GetDescendants()) do
        local isEffect = obj:IsA("ParticleEmitter") or obj:IsA("Fire")
            or obj:IsA("Smoke") or obj:IsA("Sparkles")
            or obj:IsA("Trail") or obj:IsA("Beam")
            or obj:IsA("PointLight") or obj:IsA("SpotLight")
            or obj:IsA("SurfaceLight") or obj:IsA("Decal")
            or obj:IsA("Texture")
        
        if isEffect then
            -- Tìm parent BasePart để lấy vị trí
            local pos = nil
            if obj:IsA("BasePart") then
                pos = obj.Position
            else
                local p = obj.Parent
                if p and p:IsA("BasePart") then
                    pos = p.Position
                elseif p and p.Parent and p.Parent:IsA("BasePart") then
                    pos = p.Parent.Position
                end
            end
            
            if pos then
                local isDisabled = State.DisabledEffects[obj] ~= nil
                local dist2 = (pos - myPos).Magnitude ^ 2
                
                if isDisabled then
                    if dist2 < restoreDist2 then
                        showEffect(obj)
                    end
                else
                    if dist2 > effectDist2 then
                        hideEffect(obj)
                    end
                end
            end
        end
    end
    
    -- ==== 3. BILLBOARD XA ====
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("BillboardGui") and obj.Enabled then
            local adornee = obj.Adornee or obj.Parent
            if adornee and adornee:IsA("BasePart") then
                local dist2 = (adornee.Position - myPos).Magnitude ^ 2
                if dist2 > effectDist2 and not State.DisabledEffects[obj] then
                    State.DisabledEffects[obj] = {Enabled = true}
                    obj.Enabled = false
                end
            end
        end
    end
end

-- ════════════════════════════════════════════════════════════════
--  LIGHTING OPTIMIZE (tĩnh)
-- ════════════════════════════════════════════════════════════════
local function applyLighting()
    pcall(function()
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 600
        Lighting.FogStart = 200
        Lighting.EnvironmentDiffuseScale = 0
        Lighting.EnvironmentSpecularScale = 0
    end)
    -- Tắt post effects (không restore vì ít ảnh hưởng)
    for _, obj in ipairs(Lighting:GetChildren()) do
        if obj:IsA("PostEffect") or obj:IsA("Atmosphere") or obj:IsA("Clouds") then
            pcall(function() obj.Enabled = false end)
        end
    end
    pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
    pcall(function() settings().Rendering.MeshPartDetailLevel = Enum.MeshPartDetailLevel.Level01 end)
end

-- ════════════════════════════════════════════════════════════════
--  RESTORE TOÀN BỘ (khi tắt)
-- ════════════════════════════════════════════════════════════════
local function restoreAll()
    log("Restoring all hidden parts...")
    for part, _ in pairs(State.HiddenParts) do
        showPart(part)
    end
    for effect, _ in pairs(State.DisabledEffects) do
        showEffect(effect)
    end
    -- Lighting
    pcall(function()
        for k, v in pairs(State.Backup.Lighting or {}) do Lighting[k] = v end
        for k, v in pairs(State.Backup.Terrain or {}) do Workspace.Terrain[k] = v end
    end)
    notify("Smart Render", "Đã restore toàn bộ map", 3)
    log("Restored!")
end

-- ════════════════════════════════════════════════════════════════
--  AUTO RENDER LOOP (Heartbeat, giới hạn 2Hz)
-- ════════════════════════════════════════════════════════════════
local renderConn
task.spawn(function()
    while true do
        task.wait(0.5)
        if State.Enabled then
            pcall(renderLoop)
        end
    end
end)

-- ════════════════════════════════════════════════════════════════
--  FPS COUNTER
-- ════════════════════════════════════════════════════════════════
local fpsGui, fpsLabel
pcall(function()
    fpsGui = Instance.new("ScreenGui")
    fpsGui.Name = "SmartRender_FPS"
    fpsGui.ResetOnSpawn = false
    fpsGui.DisplayOrder = 10000
    fpsGui.Parent = CoreGui

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 140, 0, 38)
    frame.Position = UDim2.new(1, -160, 0, 10)
    frame.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
    frame.BackgroundTransparency = 0.1
    frame.BorderSizePixel = 0
    frame.Parent = fpsGui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

    fpsLabel = Instance.new("TextLabel")
    fpsLabel.Size = UDim2.new(1, 0, 1, 0)
    fpsLabel.BackgroundTransparency = 1
    fpsLabel.Text = "FPS: --"
    fpsLabel.TextColor3 = Color3.fromRGB(120, 195, 140)
    fpsLabel.TextSize = 14
    fpsLabel.Font = Enum.Font.GothamBold
    fpsLabel.Parent = frame
end)

task.spawn(function()
    local frames = 0
    local last = tick()
    RunService.RenderStepped:Connect(function()
        frames = frames + 1
        if tick() - last >= 1 then
            State.FPS = frames
            frames = 0
            last = tick()
            if fpsLabel and fpsLabel.Parent then
                local c = Color3.fromRGB(120, 195, 140)
                if State.FPS < 30 then c = Color3.fromRGB(220, 115, 125)
                elseif State.FPS < 60 then c = Color3.fromRGB(225, 180, 110) end
                fpsLabel.Text = "FPS: " .. State.FPS
                fpsLabel.TextColor3 = c
            end
        end
    end)
end)

-- ════════════════════════════════════════════════════════════════
--  UI
-- ════════════════════════════════════════════════════════════════
if Lib then
    backupAll()
    unlockFPS()
    applyLighting()

    local Window = Lib:CreateWindow({
        Name = "Smart Render",
        Subtitle = "FPS Boost v4",
        Author = "Doeak",
        Size = UDim2.new(0, 620, 0, 480),
    })

    local MainTab = Window:CreateTab("Main", "◈")
    local DistTab = Window:CreateTab("Distance", "⚙")
    local InfoTab = Window:CreateTab("Info", "◉")

    -- ═══ MAIN ═══
    MainTab:CreateSection("🚀 FPS Unlock")

    MainTab:CreateButton({
        Name = "⚡  Unlock FPS (bỏ giới hạn 60)",
        Callback = function()
            unlockFPS()
            Lib.Banner("FPS", "Đã unlock! Kiểm tra FPS góc phải.", Color3.fromRGB(120, 195, 140), 3, "⚡")
        end,
    })

    MainTab:CreateSection("🎯 Smart Render Distance")

    MainTab:CreateToggle({
        Name = "BẬT tối ưu thông minh",
        Flag = "Enabled",
        CurrentValue = true,
        Callback = function(v)
            State.Enabled = v
            if Lib.Banner then
                Lib.Banner("Smart Render", v and "Đã BẬT" or "Đã TẮT",
                    v and Color3.fromRGB(120, 195, 140) or Color3.fromRGB(220, 115, 125), 2,
                    v and "●" or "○")
            end
        end,
    })

    MainTab:CreateSection("Preset")

    MainTab:CreateButton({
        Name = "🌤  Light (giữ đồ họa đẹp)",
        Callback = function()
            State.HIDE_DIST = 1500
            State.RESTORE_DIST = 1200
            State.EFFECT_DIST = 800
            State.PHYSICS_DIST = 500
            State.Enabled = true
            restoreAll()
            Lib.Banner("Preset", "Light — render xa", Color3.fromRGB(120, 195, 140), 2, "◈")
        end,
    })

    MainTab:CreateButton({
        Name = "⛅  Balanced (khuyên dùng)",
        Callback = function()
            State.HIDE_DIST = 500
            State.RESTORE_DIST = 400
            State.EFFECT_DIST = 200
            State.PHYSICS_DIST = 150
            State.Enabled = true
            Lib.Banner("Preset", "Balanced", Color3.fromRGB(110, 145, 235), 2, "◈")
        end,
    })

    MainTab:CreateButton({
        Name = "🌪  Extreme (máy yếu cực)",
        Callback = function()
            State.HIDE_DIST = 250
            State.RESTORE_DIST = 200
            State.EFFECT_DIST = 100
            State.PHYSICS_DIST = 80
            State.Enabled = true
            Lib.Banner("Preset", "Extreme", Color3.fromRGB(220, 115, 125), 2, "◈")
        end,
    })

    MainTab:CreateSection("↻ Restore")

    MainTab:CreateButton({
        Name = "🔄  Khôi phục toàn bộ map",
        Callback = function()
            restoreAll()
        end,
    })

    MainTab:CreateSection("Trạng thái")

    local infoP = MainTab:CreateParagraph({
        Title = "Live Stats",
        Content = "Đang chạy...",
    })

    task.spawn(function()
        while true do
            task.wait(1)
            pcall(function()
                if infoP and infoP.Set then
                    local s = State.Stats
                    infoP:Set(string.format(
                        "FPS: %d\nPart ẩn: %d | Part hiện: %d\nEffect tắt: %d | Effect bật: %d",
                        State.FPS, s.hidden, s.restored, s.effects_off, s.effects_on))
                end
            end)
        end
    end)

    -- ═══ DISTANCE ═══
    DistTab:CreateSection("Khoảng cách tùy chỉnh")

    DistTab:CreateSlider({
        Name = "Ẩn Part khi xa hơn (studs)",
        Min = 100, Max = 3000, Default = 500,
        Callback = function(v) State.HIDE_DIST = v end,
    })

    DistTab:CreateSlider({
        Name = "Hiện lại Part khi gần hơn (studs)",
        Min = 50, Max = 2500, Default = 400,
        Callback = function(v) State.RESTORE_DIST = v end,
    })

    DistTab:CreateSlider({
        Name = "Tắt Effect khi xa hơn (studs)",
        Min = 50, Max = 1500, Default = 200,
        Callback = function(v) State.EFFECT_DIST = v end,
    })

    DistTab:CreateSlider({
        Name = "Tắt Physics khi xa hơn (studs)",
        Min = 50, Max = 1000, Default = 150,
        Callback = function(v) State.PHYSICS_DIST = v end,
    })

    DistTab:CreateLabel("Gợi ý: RESTORE < HIDE để tránh giật (hysteresis)")

    DistTab:CreateSection("Debug")

    DistTab:CreateButton({
        Name = "In stats ra Console",
        Callback = function()
            print("=== SMART RENDER STATS ===")
            for k, v in pairs(State.Stats) do print("  " .. k .. ":", v) end
            print("  HIDE_DIST:", State.HIDE_DIST)
            print("  RESTORE_DIST:", State.RESTORE_DIST)
            print("  Hidden parts còn lại:", #State.HiddenParts)
        end,
    })

    -- ═══ INFO ═══
    InfoTab:CreateSection("ℹ️ Cách hoạt động")

    InfoTab:CreateLabel("• Part xa → ẩn (transparency=1)")
    InfoTab:CreateLabel("• Lại gần → tự hiện lại")
    InfoTab:CreateLabel("• Effect/Decal xa → tắt")
    InfoTab:CreateLabel("• Lại gần → tự bật lại")
    InfoTab:CreateLabel("• Không xóa gì → map còn nguyên")

    InfoTab:CreateSection("Điều kiện an toàn")

    InfoTab:CreateLabel("• Không ẩn Character của bạn")
    InfoTab:CreateLabel("• Không ẩn Terrain")
    InfoTab:CreateLabel("• Không ẩn Base lớn (anchored)")
    InfoTab:CreateLabel("• Có thể Restore mọi lúc")

    InfoTab:CreateSection("FPS unlock")

    InfoTab:CreateLabel("setfpscap: " .. type(setfpscap))
    InfoTab:CreateLabel("setfflag: " .. type(setfflag))

    InfoTab:CreateLabel("Nếu cả 2 nil → executor không unlock được")
end

-- ════════════════════════════════════════════════════════════════
--  AUTO CLEANUP + STARTUP
-- ════════════════════════════════════════════════════════════════
backupAll()
unlockFPS()
applyLighting()

-- Bật tối ưu mặc định
State.Enabled = true

notify("Smart Render v4", "Đã bật! Part xa tự ẩn, lại gần tự hiện.", 5)

log("=== SMART RENDER v4 READY ===")
log("HIDE_DIST:", State.HIDE_DIST, "| RESTORE_DIST:", State.RESTORE_DIST)
log("Effect xa:", State.EFFECT_DIST, "| Physics xa:", State.PHYSICS_DIST)
log("FPS counter: góc phải trên")

-- ════════════════════════════════════════════════════════════════
--  API NGOÀI
-- ════════════════════════════════════════════════════════════════
_G.SmartRender = {
    Toggle = function()
        State.Enabled = not State.Enabled
        log("Enabled:", State.Enabled)
    end,
    Restore = restoreAll,
    SetDistances = function(hide, restore, effect, physics)
        if hide then State.HIDE_DIST = hide end
        if restore then State.RESTORE_DIST = restore end
        if effect then State.EFFECT_DIST = effect end
        if physics then State.PHYSICS_DIST = physics end
        log("Distances updated")
    end,
    GetStats = function() return State.Stats end,
    GetFPS = function() return State.FPS end,
}

log("API: _G.SmartRender.Toggle() / .Restore() / .SetDistances(hide, restore, effect, physics)")
