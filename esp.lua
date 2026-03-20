local Tabs         = _G.ZoltTabs
local Library      = _G.ZoltLibrary
local Options      = _G.ZoltOptions
local Toggles      = _G.ZoltToggles
local RunService   = _G.ZoltRunService    or game:GetService("RunService")
local TweenService = _G.ZoltTweenService  or game:GetService("TweenService")
local Debris       = _G.ZoltDebris        or game:GetService("Debris")
local _teams       = _G.ZoltTeams         or {}
local criminalsTeam = _teams.criminals
local guardsTeam    = _teams.guards
local inmatesTeam   = _teams.inmates

-- Load Crumbleware framework (player tracking only)
local framework = loadstring(request({
    Url = "https://raw.githubusercontent.com/YellowFireFighter/Crumbleware-Rewrite/refs/heads/main/Util/framework.lua",
    Method = "Get"
}).Body)()({debug = false})


local esp = {}
esp.settings = {
    enabled   = false,
    maxdis    = 200,
    teamcheck = false,
    box       = { enabled = false, outline = false, mode = "corner", color = Color3.fromRGB(255,255,255) },
    healthbar = { enabled = false, width = 3, hptext = false, hptextcolor = Color3.fromRGB(255,255,255), hptextoutline = false },
    name      = { enabled = false, size = 13, outline = false, color = Color3.fromRGB(255,255,255) },
    distance  = { enabled = false, size = 13, outline = false, color = Color3.fromRGB(255,255,255) },
    weapon    = { enabled = false, size = 12, outline = false, color = Color3.fromRGB(255,0,0) },
}

esp.weapons_list = {
    "M9","Taser","MP5","M4A1","AK-47","FAL","Remington 870","EBR","M700","Revolver",
    "Crude Knife","Hammer","Breakfast","C4","Explosive","Dinner","Handcuffs","Key card","Lunch","Riot Shield","Pickaxe",
}
esp.localPlayer = game:GetService("Players").LocalPlayer

local _espWeaponCache = {}
local function _espUpdateWeapon(player)
    if not player or not player.Parent then _espWeaponCache[player] = "[none]"; return end
    local char = workspace:FindFirstChild(player.Name)
    if not char then _espWeaponCache[player] = "[none]"; return end
    for _, wn in ipairs(esp.weapons_list) do
        if char:FindFirstChild(wn) then _espWeaponCache[player] = "[" .. wn .. "]"; return end
        for _, item in ipairs(char:GetChildren()) do
            if string.find(item.Name:lower(), wn:lower()) then _espWeaponCache[player] = "[" .. wn .. "]"; return end
        end
    end
    _espWeaponCache[player] = "[none]"
end
local _espWeaponConns = {}
local function _espHookWeaponCache(player)
    if _espWeaponConns[player] then return end
    local char = workspace:FindFirstChild(player.Name); if not char then return end
    _espUpdateWeapon(player)
    _espWeaponConns[player] = {
        char.ChildAdded:Connect(function() _espUpdateWeapon(player) end),
        char.ChildRemoved:Connect(function() _espUpdateWeapon(player) end),
    }
end
function esp:getPlayerWeapon(player)
    if not _espWeaponCache[player] then _espUpdateWeapon(player) end
    return _espWeaponCache[player] or "[none]"
end

-- ── Drawing creation ──
-- Creates all Drawing objects for a player directly (no framework:draw wrapper)
local function _newText(color, size)
    local t = Drawing.new("Text")
    t.Color   = color
    t.Size    = size
    t.Center  = true
    t.Outline = false
    t.Visible = false
    t.Text    = ""
    return t
end
local function _newLine(color, thick)
    local l = Drawing.new("Line")
    l.Color     = color
    l.Thickness = thick or 1.5
    l.Visible   = false
    return l
end
local function _newQuad(filled, color, thick)
    local q = Drawing.new("Quad")
    q.Filled  = filled
    q.Color   = color
    if not filled then q.Thickness = thick or 1.5 end
    q.Visible = false
    return q
end

local _espDrawings = {} -- [player] = drawings table

local function _espInit(player)
    if not player or player == esp.localPlayer then return end
    -- Clean old drawings if any
    if _espDrawings[player] then
        for _, d in pairs(_espDrawings[player]) do
            if type(d) == "table" then
                for _, l in pairs(d) do pcall(function() l:Remove() end) end
            else
                pcall(function() d:Remove() end)
            end
        end
    end
    local d = {}
    d.name        = _newText(Color3.fromRGB(255,255,255), 13)
    d.distance    = _newText(Color3.fromRGB(255,255,255), 13)
    d.weapon      = _newText(Color3.fromRGB(255,0,0),     12)
    d.full_box    = _newQuad(false, Color3.fromRGB(255,255,255), 1.5)
    d.box_outline = _newQuad(false, Color3.fromRGB(0,0,0),       3)
    d.healthbar_b = _newQuad(true,  Color3.fromRGB(0,0,0))
    d.healthbar_f = _newQuad(true,  Color3.fromRGB(0,255,0))
    d.healthbar_t = _newText(Color3.fromRGB(255,255,255), 11)
    -- corner_box: indices 1-8 = black outline lines, 9-16 = colored lines
    d.corner_box = {}
    for i = 1, 8  do d.corner_box[i] = _newLine(Color3.fromRGB(0,0,0),     3)   end
    for i = 9, 16 do d.corner_box[i] = _newLine(Color3.fromRGB(255,255,255), 1.5) end
    _espDrawings[player] = d
end

local function _espHide(player)
    local d = _espDrawings[player]; if not d then return end
    d.name.Visible=false; d.distance.Visible=false; d.weapon.Visible=false
    d.full_box.Visible=false; d.box_outline.Visible=false
    d.healthbar_b.Visible=false; d.healthbar_f.Visible=false; d.healthbar_t.Visible=false
    for _, l in pairs(d.corner_box) do l.Visible = false end
end

local function _espClean(player)
    local d = _espDrawings[player]; if not d then return end
    for _, v in pairs(d) do
        if type(v) == "table" then for _, l in pairs(v) do pcall(function() l:Remove() end) end
        else pcall(function() v:Remove() end) end
    end
    _espDrawings[player] = nil
end

-- ── ESP Render Loop ──
game:GetService("RunService").Heartbeat:Connect(function()
    pcall(function()
        if not esp.settings.enabled then
            for player in pairs(_espDrawings) do _espHide(player) end
            return
        end

        local cam       = workspace.CurrentCamera
        local lp        = esp.localPlayer
        local localChar = lp.Character
        local localRoot = localChar and localChar:FindFirstChild("HumanoidRootPart")
        if not localRoot then
            for player in pairs(_espDrawings) do _espHide(player) end
            return
        end

        for player, d in pairs(_espDrawings) do
            -- Basic validity
            if not player or not player.Parent then _espHide(player); continue end
            if esp.settings.teamcheck and player.Team == lp.Team then _espHide(player); continue end

            local char = player.Character
            if not char then _espHide(player); continue end

            local root = char:FindFirstChild("HumanoidRootPart")
            local head = char:FindFirstChild("Head")
            local hum  = char:FindFirstChildOfClass("Humanoid")
            if not root or not head or not hum then _espHide(player); continue end

            -- Instant hide on death – no delay whatsoever
            if hum.Health <= 0 then _espHide(player); continue end

            -- Distance check
            local dist = (root.Position - localRoot.Position).Magnitude / 3
            -- Distance check: 0 = nobody, >0 = max meters
            if esp.settings.maxdis == 0 then _espHide(player); continue end
            if dist > esp.settings.maxdis then _espHide(player); continue end

            -- Weapon cache hook
            if not _espWeaponConns[player] then _espHookWeaponCache(player) end

            -- Compute screen bounding box (R6 layout)
            local minX, minY =  math.huge,  math.huge
            local maxX, maxY = -math.huge, -math.huge
            local onscreen   = false

            -- Head top
            local hSP, hON = cam:WorldToViewportPoint(head.Position + Vector3.new(0, head.Size.Y * 0.5, 0))
            if hON and hSP.Z > 0 then
                onscreen = true
                minY = hSP.Y
                minX = math.min(minX, hSP.X); maxX = math.max(maxX, hSP.X)
            end
            -- Arms (width)
            for _, n in ipairs({"Right Arm", "Left Arm"}) do
                local p = char:FindFirstChild(n)
                if p then
                    local s, on = cam:WorldToViewportPoint(p.Position)
                    if on and s.Z > 0 then
                        local sx = cam:WorldToViewportPoint(p.Position + Vector3.new(0.5, 0, 0))
                        local pad = math.abs(sx.X - s.X)
                        minX = math.min(minX, s.X - pad); maxX = math.max(maxX, s.X + pad)
                        onscreen = true
                    end
                end
            end
            -- Feet (height bottom)
            for _, n in ipairs({"Right Leg", "Left Leg"}) do
                local p = char:FindFirstChild(n)
                if p then
                    local s, on = cam:WorldToViewportPoint(p.Position - Vector3.new(0, p.Size.Y * 0.5, 0))
                    if on and s.Z > 0 then maxY = math.max(maxY, s.Y); onscreen = true end
                end
            end

            if not onscreen or minX == math.huge or maxX == -math.huge or minY == math.huge or maxY == -math.huge then
                _espHide(player); continue
            end

            local tl = Vector2.new(math.floor(minX), math.floor(minY))
            local br = Vector2.new(math.floor(maxX), math.floor(maxY))
            local tr = Vector2.new(br.X, tl.Y)
            local bl = Vector2.new(tl.X, br.Y)
            local cx = math.floor((tl.X + br.X) * 0.5)
            local bh = br.Y - tl.Y
            if bh <= 1 then _espHide(player); continue end

            -- ── Name ──
            if esp.settings.name.enabled then
                local dn = d.name
                dn.Text    = player.Name
                dn.Color   = esp.settings.name.color
                dn.Outline = esp.settings.name.outline
                dn.Size    = esp.settings.name.size
                dn.Position = Vector2.new(cx, tl.Y - dn.TextBounds.Y - 4)
                dn.Visible  = true
            else d.name.Visible = false end

            -- ── Distance ──
            if esp.settings.distance.enabled then
                local dd = d.distance
                dd.Text    = tostring(math.round(dist)) .. "m"
                dd.Color   = esp.settings.distance.color
                dd.Outline = esp.settings.distance.outline
                dd.Size    = esp.settings.distance.size
                local tb = dd.TextBounds
                dd.Position = dist >= 150
                    and Vector2.new(br.X + tb.X * 0.5 + 4, (tl.Y + br.Y) * 0.5 - tb.Y * 0.5)
                    or  Vector2.new(br.X + tb.X * 0.5 + 6, tl.Y)
                dd.Visible = true
            else d.distance.Visible = false end

            -- ── Weapon ──
            if esp.settings.weapon.enabled then
                local dw = d.weapon
                dw.Text    = esp:getPlayerWeapon(player)
                dw.Color   = esp.settings.weapon.color
                dw.Outline = esp.settings.weapon.outline
                dw.Size    = esp.settings.weapon.size
                dw.Position = Vector2.new(cx, br.Y + bh * 0.005)
                dw.Visible  = true
            else d.weapon.Visible = false end

            -- ── Health Bar ──
            if esp.settings.healthbar.enabled then
                local bw  = esp.settings.healthbar.width
                local xo  = 3
                local pct = hum.MaxHealth > 0 and math.clamp(hum.Health / hum.MaxHealth, 0, 1) or 0
                local fh  = bh * pct

                local hbb = d.healthbar_b
                hbb.PointA = Vector2.new(tl.X - xo - bw, tl.Y - 1)
                hbb.PointB = Vector2.new(tl.X - xo,      tl.Y - 1)
                hbb.PointC = Vector2.new(tl.X - xo,      br.Y + 2)
                hbb.PointD = Vector2.new(tl.X - xo - bw, br.Y + 2)
                hbb.Color  = Color3.fromRGB(0, 0, 0)
                hbb.Visible = true

                local hbf = d.healthbar_f
                hbf.PointA = Vector2.new(tl.X - xo - bw + 1, br.Y - fh)
                hbf.PointB = Vector2.new(tl.X - xo - 1,      br.Y - fh)
                hbf.PointC = Vector2.new(tl.X - xo - 1,      br.Y + 1)
                hbf.PointD = Vector2.new(tl.X - xo - bw + 1, br.Y + 1)
                -- color lerp: red→green
                hbf.Color  = Color3.new(math.clamp(1 - pct, 0, 1), math.clamp(pct, 0, 1), 0)
                hbf.Visible = true

                -- ── HP Text ──
                if esp.settings.healthbar.hptext then
                    local hbt = d.healthbar_t
                    hbt.Text    = math.floor(hum.Health)
                    hbt.Color   = esp.settings.healthbar.hptextcolor
                    hbt.Outline = esp.settings.healthbar.hptextoutline
                    hbt.Size    = 11
                    hbt.Center  = false
                    -- position: left of bar, above the top of the bar
                    hbt.Position = Vector2.new(tl.X - xo - bw - 1, tl.Y - 1)
                    hbt.Visible  = true
                else
                    d.healthbar_t.Visible = false
                end
            else
                d.healthbar_b.Visible = false
                d.healthbar_f.Visible = false
                d.healthbar_t.Visible = false
            end

            -- ── Box ──
            if esp.settings.box.enabled then
                if esp.settings.box.mode == "full" then
                    for _, l in pairs(d.corner_box) do l.Visible = false end

                    local fb = d.full_box
                    fb.PointA = tl; fb.PointB = tr; fb.PointC = br; fb.PointD = bl
                    fb.Color  = esp.settings.box.color; fb.Visible = true

                    if esp.settings.box.outline then
                        local ob = d.box_outline
                        ob.PointA = tl; ob.PointB = tr; ob.PointC = br; ob.PointD = bl
                        ob.Thickness = 3; ob.Visible = true
                    else d.box_outline.Visible = false end

                else -- corner
                    d.full_box.Visible = false; d.box_outline.Visible = false
                    local cb = d.corner_box
                    local ls = math.max(math.min((br.X - tl.X) * 0.25, bh * 0.25), 3)

                    cb[9].From  = tl;               cb[9].To  = tl + Vector2.new(ls, 0)
                    cb[10].From = tl;               cb[10].To = tl + Vector2.new(0, ls)
                    cb[11].From = tr;               cb[11].To = tr - Vector2.new(ls, 0)
                    cb[12].From = tr;               cb[12].To = tr + Vector2.new(0, ls)
                    cb[13].From = bl;               cb[13].To = bl + Vector2.new(ls, 0)
                    cb[14].From = bl;               cb[14].To = bl - Vector2.new(0, ls)
                    cb[15].From = br + Vector2.new(1,0); cb[15].To = br - Vector2.new(ls, 0)
                    cb[16].From = br + Vector2.new(0,1); cb[16].To = br - Vector2.new(0, ls)

                    for i = 9, 16 do
                        cb[i].Color   = esp.settings.box.color
                        cb[i].Visible = true
                    end

                    if esp.settings.box.outline then
                        local ot = 3
                        cb[1].From=tl-Vector2.new(1,0);  cb[1].To=tl+Vector2.new(ls+1,0);  cb[1].Thickness=ot
                        cb[2].From=tl-Vector2.new(0,1);  cb[2].To=tl+Vector2.new(0,ls+1);  cb[2].Thickness=ot
                        cb[3].From=tr+Vector2.new(1,0);  cb[3].To=tr-Vector2.new(ls+1,0);  cb[3].Thickness=ot
                        cb[4].From=tr-Vector2.new(0,1);  cb[4].To=tr+Vector2.new(0,ls+1);  cb[4].Thickness=ot
                        cb[5].From=bl-Vector2.new(1,0);  cb[5].To=bl+Vector2.new(ls+1,0);  cb[5].Thickness=ot
                        cb[6].From=bl-Vector2.new(0,1);  cb[6].To=bl-Vector2.new(0,ls+1);  cb[6].Thickness=ot
                        cb[7].From=br+Vector2.new(2,0);  cb[7].To=br-Vector2.new(ls+1,0);  cb[7].Thickness=ot
                        cb[8].From=br+Vector2.new(0,2);  cb[8].To=br-Vector2.new(0,ls+1);  cb[8].Thickness=ot
                    end
                    for i = 1, 8 do cb[i].Visible = esp.settings.box.outline end
                end
            else
                d.full_box.Visible = false; d.box_outline.Visible = false
                for _, l in pairs(d.corner_box) do l.Visible = false end
            end
        end -- for player
    end) -- pcall
end) -- Heartbeat

-- Player tracking callbacks
table.insert(framework.connec_funcs["playeradded"], function(player)
    task.wait(0.5)
    _espInit(player)
    _espHookWeaponCache(player)
end)
table.insert(framework.connec_funcs["playerremoving"], function(player)
    _espClean(player)
    _espWeaponCache[player] = nil
    if _espWeaponConns[player] then
        for _, c in pairs(_espWeaponConns[player]) do pcall(function() c:Disconnect() end) end
        _espWeaponConns[player] = nil
    end
end)

-- Init existing players
for _, p in pairs(game:GetService("Players"):GetPlayers()) do
    if p ~= esp.localPlayer then _espInit(p) end
end

-- ══ ESP UI ══

local EspMainGroup   = Tabs.Visuals:AddLeftGroupbox("ESP",        "eye")
local EspNameGroup   = Tabs.Visuals:AddLeftGroupbox("Name",       "tag")
local EspDistGroup   = Tabs.Visuals:AddLeftGroupbox("Distance",   "ruler")
local EspBoxGroup    = Tabs.Visuals:AddRightGroupbox("Box",       "square")
local EspWeaponGroup = Tabs.Visuals:AddRightGroupbox("Weapon",    "sword")
local EspHealthGroup = Tabs.Visuals:AddRightGroupbox("Health Bar","heart")

EspMainGroup:AddToggle("EnableESP",{Text="Enable ESP",Default=false,
    Callback=function(v) esp.settings.enabled=v end})
EspMainGroup:AddToggle("ESPTeamCheck",{Text="Team Check",Default=false,
    Callback=function(v) esp.settings.teamcheck=v end})
EspMainGroup:AddDivider()
EspMainGroup:AddSlider("MaxDistance",{Text="Max Distance",Default=200,Min=0,Max=1000,Rounding=0,Suffix=" m",
    Callback=function(v) esp.settings.maxdis=v end})

local NameToggle=EspNameGroup:AddToggle("NameEnabled",{Text="Name",Default=false,
    Callback=function(v) esp.settings.name.enabled=v end})
NameToggle:AddColorPicker("NameColor",{Default=Color3.fromRGB(255,255,255),Title="Name Color",
    Callback=function(v) esp.settings.name.color=v end})
EspNameGroup:AddToggle("NameOutline",{Text="Outline",Default=false,
    Callback=function(v) esp.settings.name.outline=v end})

local DistToggle=EspDistGroup:AddToggle("DistanceEnabled",{Text="Distance",Default=false,
    Callback=function(v) esp.settings.distance.enabled=v end})
DistToggle:AddColorPicker("DistanceColor",{Default=Color3.fromRGB(255,255,255),Title="Distance Color",
    Callback=function(v) esp.settings.distance.color=v end})
EspDistGroup:AddToggle("DistOutline",{Text="Outline",Default=false,
    Callback=function(v) esp.settings.distance.outline=v end})

local BoxToggle=EspBoxGroup:AddToggle("BoxEnabled",{Text="Box",Default=false,
    Callback=function(v) esp.settings.box.enabled=v end})
BoxToggle:AddColorPicker("BoxColor",{Default=Color3.fromRGB(255,255,255),Title="Box Color",
    Callback=function(v) esp.settings.box.color=v end})
EspBoxGroup:AddToggle("BoxOutline",{Text="Outline",Default=false,
    Callback=function(v) esp.settings.box.outline=v end})
EspBoxGroup:AddDropdown("BoxMode",{Values={"corner","full"},Default="corner",Text="Box Mode",
    Callback=function(v) esp.settings.box.mode=v end})

local WeaponToggle=EspWeaponGroup:AddToggle("WeaponEnabled",{Text="Weapon",Default=false,
    Callback=function(v) esp.settings.weapon.enabled=v end})
WeaponToggle:AddColorPicker("WeaponColor",{Default=Color3.fromRGB(255,0,0),Title="Weapon Color",
    Callback=function(v) esp.settings.weapon.color=v end})
EspWeaponGroup:AddToggle("WeaponOutline",{Text="Outline",Default=false,
    Callback=function(v) esp.settings.weapon.outline=v end})

local HpToggle=EspHealthGroup:AddToggle("HealthbarEnabled",{Text="Health bar",Default=false,
    Callback=function(v) esp.settings.healthbar.enabled=v end})
EspHealthGroup:AddSlider("HealthbarWidth",{Text="Bar Width",Default=3,Min=1,Max=10,Rounding=1,
    Callback=function(v) esp.settings.healthbar.width=v end})
EspHealthGroup:AddDivider()
EspHealthGroup:AddToggle("HealthTextEnabled",{Text="HP Text",Default=false,
    Callback=function(v) esp.settings.healthbar.hptext=v end})
EspHealthGroup:AddLabel("HP Text Color"):AddColorPicker("HealthTextColor",{
    Default=Color3.fromRGB(255,255,255),Title="HP Text Color",
    Callback=function(v) esp.settings.healthbar.hptextcolor=v end})
EspHealthGroup:AddToggle("HealthTextOutline",{Text="HP Text Outline",Default=false,
    Callback=function(v) esp.settings.healthbar.hptextoutline=v end})

-- ── Chams (Highlight) ──
local _chamsEnabled   = false
local _teamChamsOn    = false
local _chamsFill      = Color3.fromRGB(255, 0, 0)
local _chamsOutline   = Color3.fromRGB(255, 255, 255)
local _chamsCriminals = Color3.fromRGB(255, 60, 60)
local _chamsGuards    = Color3.fromRGB(60, 120, 255)
local _chamsInmates   = Color3.fromRGB(255, 165, 0)

local function _chamsGetColor(player)
    if not _teamChamsOn then return _chamsFill end
    local tm = player.Team
    if tm == criminalsTeam then return _chamsCriminals end
    if tm == guardsTeam    then return _chamsGuards    end
    if tm == inmatesTeam   then return _chamsInmates   end
    return _chamsFill
end

local function _chamsSkip(player)
    if esp.settings.teamcheck and player.Team == game.Players.LocalPlayer.Team then return true end
    return false
end

local function _chamsAddHighlight(char, fillColor)
    if char:FindFirstChild("ChamsHighlight") then return end
    local h = Instance.new("Highlight")
    h.Name                 = "ChamsHighlight"
    h.FillColor            = fillColor
    h.OutlineColor         = _chamsOutline
    h.FillTransparency     = 0.5
    h.OutlineTransparency  = 0
    h.DepthMode            = Enum.HighlightDepthMode.AlwaysOnTop
    h.Parent               = char
end

local function _chamsRemoveHighlight(char)
    if not char then return end
    local h = char:FindFirstChild("ChamsHighlight")
    if h then h:Destroy() end
end

local function _chamsCleanAll()
    for _, plr in pairs(game.Players:GetPlayers()) do
        if plr.Character then _chamsRemoveHighlight(plr.Character) end
    end
end

local _chamsCharConns = {}
local function _chamsHookPlayer(plr)
    if _chamsCharConns[plr] then return end
    if plr.Character then
        if _chamsEnabled and not _chamsSkip(plr) then
            _chamsAddHighlight(plr.Character, _chamsGetColor(plr))
        end
    end
    _chamsCharConns[plr] = plr.CharacterAdded:Connect(function(char)
        pcall(function()
            if not _chamsEnabled or _chamsSkip(plr) then return end
            _chamsAddHighlight(char, _chamsGetColor(plr))
        end)
    end)
end

for _, plr in pairs(game.Players:GetPlayers()) do
    if plr ~= game.Players.LocalPlayer then
        pcall(function() _chamsHookPlayer(plr) end)
    end
end
game.Players.PlayerAdded:Connect(function(plr)
    if plr ~= game.Players.LocalPlayer then
        pcall(function() _chamsHookPlayer(plr) end)
    end
end)
game.Players.PlayerRemoving:Connect(function(plr)
    if _chamsCharConns[plr] then
        _chamsCharConns[plr]:Disconnect()
        _chamsCharConns[plr] = nil
    end
end)

game:GetService("RunService").Heartbeat:Connect(function()
    pcall(function()
        local lp        = game.Players.LocalPlayer
        local localChar = lp.Character
        local localRoot = localChar and localChar:FindFirstChild("HumanoidRootPart")

        for _, plr in pairs(game.Players:GetPlayers()) do
            if plr == lp then continue end
            local char = plr.Character
            if not char then continue end

            -- Distance check — same logic as ESP (0 = nobody)
            local withinRange = false
            if _chamsEnabled and localRoot then
                local root = char:FindFirstChild("HumanoidRootPart")
                if root then
                    local dist = (root.Position - localRoot.Position).Magnitude / 3
                    if esp.settings.maxdis > 0 and dist <= esp.settings.maxdis then
                        withinRange = true
                    end
                end
            end

            if not _chamsEnabled or _chamsSkip(plr) or not withinRange then
                local h = char:FindFirstChild("ChamsHighlight")
                if h then h:Destroy() end
            else
                local h   = char:FindFirstChild("ChamsHighlight")
                local col = _chamsGetColor(plr)
                if not h then
                    _chamsAddHighlight(char, col)
                else
                    if h.FillColor ~= col then h.FillColor = col end
                    if h.OutlineColor ~= _chamsOutline then h.OutlineColor = _chamsOutline end
                end
            end
        end
    end)
end)

local ChamsGroup = Tabs.Visuals:AddLeftGroupbox("Chams", "layers")

ChamsGroup:AddToggle("ChamsEnabled", {
    Text = "Enable Chams", Default = false,
    Callback = function(v)
        _chamsEnabled = v
        if not v then _chamsCleanAll() end
    end,
})
ChamsGroup:AddLabel("Fill Color"):AddColorPicker("ChamsFillColor", {
    Default = Color3.fromRGB(255,0,0), Title = "Fill Color",
    Callback = function(v) _chamsFill = v end,
})
ChamsGroup:AddLabel("Outline Color"):AddColorPicker("ChamsOutlineColor", {
    Default = Color3.fromRGB(255,255,255), Title = "Outline Color",
    Callback = function(v) _chamsOutline = v end,
})
ChamsGroup:AddDivider()
ChamsGroup:AddToggle("TeamChamsEnabled", {
    Text = "Team Chams", Default = false,
    Callback = function(v) _teamChamsOn = v end,
})
ChamsGroup:AddLabel("Criminals"):AddColorPicker("ChamsCriminals", {
    Default = Color3.fromRGB(255,60,60), Title = "Criminals",
    Callback = function(v) _chamsCriminals = v end,
})
ChamsGroup:AddLabel("Guards"):AddColorPicker("ChamsGuards", {
    Default = Color3.fromRGB(60,120,255), Title = "Guards",
    Callback = function(v) _chamsGuards = v end,
})
ChamsGroup:AddLabel("Inmates"):AddColorPicker("ChamsInmates", {
    Default = Color3.fromRGB(255,165,0), Title = "Inmates",
    Callback = function(v) _chamsInmates = v end,
})
