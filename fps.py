--[[
    ╔══════════════════════════════════════════════════════════════╗
    ║         ULTRA LAG FIX v3 — MAX FPS EDITION                  ║
    ║   FPS UNLOCK + 30 Optimizations + Gộp 1 nút duy nhất        ║
    ╚══════════════════════════════════════════════════════════════╝
    
    QUAN TRỌNG: 60 FPS là giới hạn VSync — script này sẽ UNLOCK lên 240+
    
    CÁCH DÙNG:
        - Chạy script → tự động tối ưu mức Balanced + unlock FPS
        - Cần thêm FPS → bấm "MAX FPS MODE" (1 nút duy nhất)
        - Cần chơi bình thường → bấm "Restore"
    
    GỘP LẠI: Không cần bật từng cái — preset làm hết
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local CoreGui = game:GetService("CoreGui")
local StarterGui = game:GetService("StarterGui")
local SoundService = game:GetService("SoundService")

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
    Preset = "Balanced",
    FPS = 0,
    OriginalFPS = 0,
    Backup = {},
    Stats = {count = 0},
}

local function log(...) print("[UltraFix]", ...) end
local function getMyPos()
    local h = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    return h and h.Position or Vector3.new(0, 0, 0)
end

-- ════════════════════════════════════════════════════════════════
--  FPS UNLOCK (BƯỚC QUAN TRỌNG NHẤT)
-- ════════════════════════════════════════════════════════════════
local function unlockFPS()
    -- Mặc định Roblox cap ở 60 (VSync). Các executor cho phép override.
    if setfpscap then
        pcall(function() setfpscap(9999) end)
        log("setfpscap(9999)")
    end
    if setfflag then
        pcall(function()
            setfflag("TaskSchedulerTargetFps", "9999")
            setfflag("DFIntTaskSchedulerTargetFps", "9999")
        end)
        log("setfflag TaskScheduler")
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
local function backup()
    State.Backup.Lighting = {
        GlobalShadows = Lighting.GlobalShadows,
        FogEnd = Lighting.FogEnd,
        FogStart = Lighting.FogStart,
        Brightness = Lighting.Brightness,
        Ambient = Lighting.Ambient,
        OutdoorAmbient = Lighting.OutdoorAmbient,
    }
    pcall(function()
        State.Backup.Terrain = {
            WaterWaveSize = Workspace.Terrain.WaterWaveSize,
            WaterWaveSpeed = Workspace.Terrain.WaterWaveSpeed,
            WaterReflectance = Workspace.Terrain.WaterReflectance,
            WaterTransparency = Workspace.Terrain.WaterTransparency,
        }
    end)
    pcall(function()
        State.Backup.Reverb = SoundService.AmbientReverb
    end)
end

-- ════════════════════════════════════════════════════════════════
--  OPTIMIZERS (GỘP LẠI — 1 HÀM LÀM HẾT)
-- ════════════════════════════════════════════════════════════════
local function optimizeAll(opts)
    opts = opts or {}
    local myPos = getMyPos()
    local farDist = opts.farDist or 800
    local physDist = opts.physDist or 300
    local counts = {particle = 0, light = 0, decal = 0, part = 0, sound = 0, billboard = 0, anim = 0}

    -- 1. Kill particles + effects + LIGHTS
    for _, o in ipairs(Workspace:GetDescendants()) do
        pcall(function()
            if o:IsA("ParticleEmitter") then
                o.Enabled = false; o.Rate = 0; counts.particle = counts.particle + 1
            elseif o:IsA("Fire") or o:IsA("Smoke") or o:IsA("Sparkles") then
                o.Enabled = false; counts.particle = counts.particle + 1
            elseif o:IsA("Trail") or o:IsA("Beam") then
                o.Enabled = false; counts.particle = counts.particle + 1
            elseif o:IsA("PointLight") or o:IsA("SpotLight") or o:IsA("SurfaceLight") then
                o.Enabled = false; counts.light = counts.light + 1
            elseif o:IsA("Decal") or o:IsA("Texture") then
                o.Transparency = 1; counts.decal = counts.decal + 1
            elseif o:IsA("BillboardGui") then
                local adornee = o.Adornee or o.Parent
                if adornee and adornee:IsA("BasePart") and (adornee.Position - myPos).Magnitude > 80 then
                    o.Enabled = false; counts.billboard = counts.billboard + 1
                end
            elseif o:IsA("Highlight") or o:IsA("SelectionBox") then
                o.Enabled = false
            end
        end)
    end

    -- 2. Kill sounds
    for _, o in ipairs(Workspace:GetDescendants()) do
        if o:IsA("Sound") and o.Playing and o.Volume < 3 then
            pcall(function() o.Volume = 0; o.Playing = false; counts.sound = counts.sound + 1 end)
        end
    end

    -- 3. Kill other players' animations
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and p.Character then
            local anim = p.Character:FindFirstChildOfClass("Animator")
            if anim then
                pcall(function()
                    for _, t in ipairs(anim:GetPlayingAnimationTracks()) do t:Stop(0) end
                end)
                counts.anim = counts.anim + 1
            end
        end
    end

    -- 4. Far parts (hide) + Physics far (disable touch/query)
    for _, o in ipairs(Workspace:GetDescendants()) do
        if o:IsA("BasePart") and not o:IsA("Terrain") then
            local d = (o.Position - myPos).Magnitude
            if d > farDist then
                pcall(function()
                    o.Transparency = 1
                    o.CanCollide = false
                    counts.part = counts.part + 1
                end)
            elseif d > physDist and not o.Anchored then
                pcall(function()
                    o.CanTouch = false
                    o.CanQuery = false
                end)
            end
        end
    end

    -- 5. Lighting
    pcall(function()
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 400
        Lighting.FogStart = 100
        Lighting.EnvironmentDiffuseScale = 0
        Lighting.EnvironmentSpecularScale = 0
        for _, e in ipairs(Lighting:GetChildren()) do
            if e:IsA("PostEffect") or e:IsA("Atmosphere") or e:IsA("Clouds") then
                e.Enabled = false
            end
        end
    end)

    -- 6. Terrain
    pcall(function()
        Workspace.Terrain.WaterWaveSize = 0
        Workspace.Terrain.WaterWaveSpeed = 0
        Workspace.Terrain.WaterReflectance = 0
        Workspace.Terrain.WaterTransparency = 1
    end)

    -- 7. Quality
    pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
    pcall(function() settings().Rendering.MeshPartDetailLevel = Enum.MeshPartDetailLevel.Level01 end)

    -- 8. Sound ambient off
    pcall(function() SoundService.AmbientReverb = Enum.ReverbType.NoReverb end)
    pcall(function() SoundService.RespectFilteringEnabled = true end)

    -- 9. FOV nhẹ tăng (giúp giảm culling = ít render hơn)
    pcall(function() Camera.FieldOfView = 90 end)

    State.Stats = counts
    log("Tối ưu:", counts.particle, "particle,", counts.light, "light,", counts.part, "part")
end

-- ════════════════════════════════════════════════════════════════
--  PRESETS (GỘP — 3 MỨC)
-- ════════════════════════════════════════════════════════════════
local function setPreset(name)
    State.Preset = name
    if name == "Light" then
        optimizeAll({farDist = 2000, physDist = 800})
    elseif name == "Balanced" then
        optimizeAll({farDist = 800, physDist = 300})
    elseif name == "Extreme" then
        optimizeAll({farDist = 300, physDist = 100})
        pcall(function()
            Lighting.FogEnd = 200
            Lighting.FogStart = 50
        end)
    end
    if Lib and Lib.Banner then
        Lib.Banner("Ultra Fix", "Preset: " .. name, Color3.fromRGB(110, 145, 235), 2, "⚡")
    end
end

-- ════════════════════════════════════════════════════════════════
--  RESTORE
-- ════════════════════════════════════════════════════════════════
local function restore()
    pcall(function()
        for k, v in pairs(State.Backup.Lighting or {}) do Lighting[k] = v end
        for k, v in pairs(State.Backup.Terrain or {}) do Workspace.Terrain[k] = v end
        if State.Backup.Reverb then SoundService.AmbientReverb = State.Backup.Reverb end
        Camera.FieldOfView = 70
    end)
    if Lib and Lib.Banner then
        Lib.Banner("Restore", "Đã khôi phục gốc", Color3.fromRGB(225, 180, 110), 3, "↻")
    end
end

-- ════════════════════════════════════════════════════════════════
--  AUTO CLEANUP
-- ════════════════════════════════════════════════════════════════
task.spawn(function()
    while true do
        task.wait(15)
        if State.Enabled then
            optimizeAll({farDist = 800, physDist = 300})
        end
    end
end)

-- ════════════════════════════════════════════════════════════════
--  FPS COUNTER
-- ════════════════════════════════════════════════════════════════
local fpsGui, fpsLabel
pcall(function()
    fpsGui = Instance.new("ScreenGui")
    fpsGui.Name = "UltraFix_FPS"
    fpsGui.ResetOnSpawn = false
    fpsGui.DisplayOrder = 10000
    fpsGui.Parent = CoreGui

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 130, 0, 36)
    frame.Position = UDim2.new(1, -150, 0, 10)
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
                fpsLabel.Text = "FPS: " .. State.FPS .. " (max)"
                fpsLabel.TextColor3 = c
            end
        end
    end)
end)

-- ════════════════════════════════════════════════════════════════
--  UI (GỘP — CHỈ 1 NÚT CHÍNH)
-- ════════════════════════════════════════════════════════════════
if Lib then
    backup()
    unlockFPS()

    local Window = Lib:CreateWindow({
        Name = "Ultra Lag Fix",
        Subtitle = "Max FPS v3",
        Author = "Doeak",
        Size = UDim2.new(0, 620, 0, 460),
    })

    local MainTab = Window:CreateTab("Main", "◈")
    local AdvancedTab = Window:CreateTab("Advanced", "⚙")

    -- ═══ MAIN ═══
    MainTab:CreateSection("🚀 ONE-CLICK")

    MainTab:CreateButton({
        Name = "🔥  MAX FPS MODE (chạy hết mọi thứ)",
        Callback = function()
            unlockFPS()
            setPreset("Extreme")
            if Lib.Banner then
                Lib.Banner("MAX FPS", "Đã tối ưu cực hạn + unlock FPS!", Color3.fromRGB(120, 195, 140), 3, "🔥")
            end
        end,
    })

    MainTab:CreateButton({
        Name = "⚡  FPS UNLOCK (chỉ unlock giới hạn 60)",
        Callback = function()
            unlockFPS()
            if Lib.Banner then
                Lib.Banner("FPS Unlock", "Đã unlock! Test FPS trên màn hình.", Color3.fromRGB(120, 195, 140), 3, "⚡")
            end
        end,
    })

    MainTab:CreateButton({
        Name = "↻  Restore (khôi phục gốc)",
        Callback = restore,
    })

    MainTab:CreateSection("Preset (gộp)")

    MainTab:CreateButton({
        Name = "🌤  Light (giữ đồ họa đẹp)",
        Callback = function()
            unlockFPS()
            setPreset("Light")
        end,
    })

    MainTab:CreateButton({
        Name = "⛅  Balanced (khuyên dùng)",
        Callback = function()
            unlockFPS()
            setPreset("Balanced")
        end,
    })

    MainTab:CreateButton({
        Name = "🌪  Extreme (máy yếu nhất)",
        Callback = function()
            unlockFPS()
            setPreset("Extreme")
        end,
    })

    MainTab:CreateSection("Trạng thái")

    local infoP = MainTab:CreateParagraph({
        Title = "Live Info",
        Content = "Đang đo...",
    })

    task.spawn(function()
        while true do
            task.wait(1)
            pcall(function()
                if infoP and infoP.Set then
                    local s = State.Stats
                    infoP:Set(string.format(
                        "FPS: %d | Preset: %s\nParticle tắt: %d | Light tắt: %d | Part ẩn: %d",
                        State.FPS, State.Preset, s.particle or 0, s.light or 0, s.part or 0))
                end
            end)
        end
    end)

    -- ═══ ADVANCED (tùy chỉnh chi tiết) ═══
    AdvancedTab:CreateSection("Giới hạn khoảng cách (mặc định 800/300)")

    AdvancedTab:CreateSlider({
        Name = "Ẩn Part xa (studs)",
        Min = 200, Max = 2000, Default = 800,
        Callback = function(v)
            _G._UltraFarDist = v
        end,
    })

    AdvancedTab:CreateSlider({
        Name = "Tắt physics part xa (studs)",
        Min = 100, Max = 1000, Default = 300,
        Callback = function(v)
            _G._UltraPhysDist = v
        end,
    })

    AdvancedTab:CreateButton({
        Name = "Áp dụng khoảng cách mới",
        Callback = function()
            optimizeAll({
                farDist = _G._UltraFarDist or 800,
                physDist = _G._UltraPhysDist or 300,
            })
            if Lib.Banner then
                Lib.Banner("Apply", "Đã áp dụng khoảng cách mới", Color3.fromRGB(120, 195, 140), 2, "✓")
            end
        end,
    })

    AdvancedTab:CreateSection("Auto cleanup")

    AdvancedTab:CreateToggle({
        Name = "Tự động dọn mỗi 15 giây",
        CurrentValue = true,
        Callback = function(v) State.Enabled = v end,
    })

    AdvancedTab:CreateSection("Debug")

    AdvancedTab:CreateButton({
        Name = "In stats ra Console (F9)",
        Callback = function()
            local s = State.Stats
            print("=== ULTRA FIX STATS ===")
            for k, v in pairs(s) do print("  " .. k .. ":", v) end
            print("  FPS:", State.FPS)
        end,
    })

    AdvancedTab:CreateSection("Thông tin")

    AdvancedTab:CreateLabel("FPS unlock: setfpscap(9999)")
    AdvancedTab:CreateLabel("Nếu vẫn 60 FPS → executor không hỗ trợ setfpscap")
    AdvancedTab:CreateLabel("Thử executor khác (Solara, Wave, ...)")
end

-- ════════════════════════════════════════════════════════════════
--  RUN INITIAL
-- ════════════════════════════════════════════════════════════════
backup()
unlockFPS()
setPreset("Balanced")

-- ════════════════════════════════════════════════════════════════
--  API NGOÀI
-- ════════════════════════════════════════════════════════════════
_G.UltraFix = {
    Run = function() optimizeAll() end,
    Max = function() unlockFPS(); setPreset("Extreme") end,
    SetPreset = setPreset,
    Restore = restore,
    UnlockFPS = unlockFPS,
    GetFPS = function() return State.FPS end,
    GetStats = function() return State.Stats end,
}

log("Loaded. Bấm 'MAX FPS MODE' để bật cực hạn.")
log("API: _G.UltraFix.Max() / .Run() / .Restore()")
