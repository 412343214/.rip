local framework = {}

framework.debug = true

framework.player = nil
framework.character = nil
framework.players = {}
framework.instances = {}
framework.connections = {}
framework.connec_funcs = {}
framework.services = {}
framework.gc = {}

local workspace = cloneref(game:GetService("Workspace"))
local players = cloneref(game:GetService("Players"))
local replicatedstorage = cloneref(game:GetService("ReplicatedStorage"))
local runservice = cloneref(game:GetService("RunService"))
local inputservice = cloneref(game:GetService("UserInputService"))
local lighting = cloneref(game:GetService("Lighting"))
local camera = workspace.CurrentCamera

framework.services.workspace = workspace
framework.services.players = players
framework.services.replicatedstorage = replicatedstorage
framework.services.runservice = runservice
framework.services.inputservice = inputservice
framework.services.camera = camera
framework.services.lighting = lighting

function framework:info(info)
    if self.debug then
        warn([[debug ->]], tostring(info))
    end
end

function framework:draw(type, props)
    local drawing = nil
    local suc, err = pcall(function()
        drawing = Drawing.new(type)
    end)

    if suc then
        for prop,val in pairs(props) do
            local suc, err = pcall(function()
                drawing[prop] = val
            end)

            if not suc then
                self:info("draw prop failed " .. err)
            end
        end

    else
        self:info("draw failed " .. err)
    end

    return drawing
end

function framework:instance(type, props)
    local instance = nil
    local suc, err = pcall(function()
        instance = Instance.new(type)
    end)

    if suc then
        for prop,val in pairs(props) do
            local suc, err = pcall(function()
                instance[prop] = val
            end)

            if not suc then
                self:info("instance prop failed " .. err)
            end
        end

        table.insert(self.instances, instance)
    else
        self:info("instance failed " .. err)
    end

    return instance
end

function framework:addplayer(player)
    if not self.players[player] then
        self.players[player] = {
            name = player.Name,
            character = nil,
            root = nil,
            spawned = false,
            client = player == self.player,
            drawings = { },
            faded = false
        }

        self.connections[player.Name .. "a"] = player.CharacterAdded:Connect(function(character)
            repeat task.wait() until character:FindFirstChild("HumanoidRootPart")
            self:updateplayer(player)

            local hum = character:FindFirstChild("Humanoid")
            if hum then
                hum.Died:Connect(function()
                    if self.players[player] then
                        self.players[player].character = nil
                        self.players[player].root = nil
                        self.players[player].spawned = false
                    end
                end)
            end
        end)

        self.connections[player.Name .. "r"] = player.CharacterRemoving:Connect(function()
            self.players[player].character = nil
            self.players[player].root = nil
            self.players[player].spawned = false
        end)

        self:info("add player " .. player.Name)

        task.spawn(function()
            repeat task.wait() until player.Character and player.Character:FindFirstChild("Humanoid") and player.Character:FindFirstChild("HumanoidRootPart")
            self:updateplayer(player)
        end)
    else
        self:info("add player failed " .. player.Name)
    end
end

function framework:_cleanupDrawings(tbl)
    local to_remove = {}

    for k, v in pairs(tbl) do
        table.insert(to_remove, { key = k, val = v })
    end

    for _, entry in ipairs(to_remove) do
        if typeof(entry.val) == "table" then
            self:_cleanupDrawings(entry.val)
        else
            pcall(function() entry.val:Remove() end)
        end
        tbl[entry.key] = nil
    end
end

function framework:removeplayer(player)
    if self.players[player] then
        pcall(function()
            if self.connections[player.Name .. "a"] then
                self.connections[player.Name .. "a"]:Disconnect()
                self.connections[player.Name .. "a"] = nil
            end

            if self.connections[player.Name .. "r"] then
                self.connections[player.Name .. "r"]:Disconnect()
                self.connections[player.Name .. "r"] = nil
            end

            self:_cleanupDrawings(self.players[player].drawings)

            self.players[player] = nil

            self:info("remove player " .. player.Name)
        end)
    else
        self:info("remove player failed " .. player.Name)
    end
end

function framework:updateplayer(player)
    if not self.players[player] then
        self:addplayer(player)
        return
    end

    if self.players[player] then
        if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            self.players[player].character = player.Character
            self.players[player].root = player.Character.HumanoidRootPart
            self.players[player].spawned = true
        else
            self.players[player].character = nil
            self.players[player].root = nil
            self.players[player].spawned = false
        end

        self:info("update player " .. player.Name)
    else
        self:info("update player failed " .. player.Name)
    end
end

function framework:validatecache()
    for _, player in pairs(players:GetChildren()) do
        if player == self.player then continue end

        if not self.players[player] then
            warn("[cache miss] player not in cache:", player.Name)
            self:addplayer(player)
        else
            local data = self.players[player]
            local char = player.Character

            if char and char:FindFirstChild("HumanoidRootPart") and char:FindFirstChild("Humanoid") then
                local hum = char.Humanoid
                local alive = hum.Health > 0

                if alive and not data.spawned then
                    warn("[cache miss] player alive but marked dead:", player.Name)
                    self:updateplayer(player)
                elseif alive and data.character ~= char then
                    warn("[cache miss] player character mismatch:", player.Name)
                    self:updateplayer(player)
                elseif alive and data.root ~= char.HumanoidRootPart then
                    warn("[cache miss] player root mismatch:", player.Name)
                    self:updateplayer(player)
                elseif not alive and data.spawned then
                    warn("[cache miss] player dead but marked alive:", player.Name)
                    data.character = nil
                    data.root = nil
                    data.spawned = false
                end
            elseif not char and data.spawned then
                warn("[cache miss] player has no character but marked spawned:", player.Name)
                data.character = nil
                data.root = nil
                data.spawned = false
            end
        end
    end

    for player, _ in pairs(self.players) do
        if not players:FindFirstChild(player.Name) then
            warn("[cache miss] stale player in cache:", player.Name)
            self:removeplayer(player)
        end
    end
end

function framework:gcfinder(type, data)
    for i,v in pairs(getgc(true)) do
        if typeof(v) == type then
            if type == "function" then
                local func_name = debug.info(v, "n")

                if func_name == data then
                    framework.gc[func_name] = v
                    return framework.gc[func_name]
                end
            elseif type == "table" then
                local raw = rawget(v, data)

                if raw then
                    framework.gc[data] = v
                    return framework.gc[data]
                end
            end
        end
    end
end

function framework:init()
    for _,player in pairs(players:GetChildren()) do
        self:addplayer(player)
    end

    task.spawn(function()
        while true do
            task.wait(10)
            self:validatecache()
        end
    end)
end

function framework:unload()
    for index,connection in pairs(self.connections) do
        connection:Disconnect()
        self.connections[index] = nil
    end

    for index,instance in pairs(self.instances) do
        local suc, err = pcall(function()
            instance:Destroy()
        end)

        if not suc then
            self:info("failed remove instance " .. tostring(instance))
        end
    end

    self:info("unloaded framework")
end

framework.player = players.LocalPlayer

if framework.player.Character then
    framework.character = framework.player.Character
    local root = framework.character:FindFirstChild("HumanoidRootPart")
    
    if not root then
        framework.character = false
    end

    task.spawn(function()
        repeat task.wait() until framework.character == nil or framework.character == false or not framework.character:FindFirstChild("HumanoidRootPart")
        framework.character = false
    end)
else
    framework.character = false
end

framework.connec_funcs["localcharacteradded"] = { }
framework.connections["localcharacteradded"] = framework.player.CharacterAdded:Connect(function(character)
    for index,func in pairs(framework.connec_funcs["localcharacteradded"]) do
        if typeof(func) == "function" then
            func(character)
        end
    end

    repeat task.wait() until character:FindFirstChild("Humanoid")
    repeat task.wait() until character:FindFirstChild("HumanoidRootPart")

    framework.character = character

    repeat task.wait() until character == nil or not character:FindFirstChild("HumanoidRootPart")
    framework.character = false
end)

framework.connec_funcs["localcharacterremoving"] = { }
framework.connections["localcharacterremoving"] = framework.player.CharacterRemoving:Connect(function()
    framework.character = false

    for index,func in pairs(framework.connec_funcs["localcharacterremoving"]) do
        if typeof(func) == "function" then
            func()
        end
    end
end)

framework.connec_funcs["playeradded"] = { }
framework.connections["playeradded"] = players.PlayerAdded:Connect(function(player)
    framework:addplayer(player)

    for index,func in pairs(framework.connec_funcs["playeradded"]) do
        if typeof(func) == "function" then
            func(player)
        end
    end
end)

framework.connec_funcs["playerremoving"] = { }
framework.connections["playerremoving"] = players.PlayerRemoving:Connect(function(player)
    framework:removeplayer(player)

    for index,func in pairs(framework.connec_funcs["playerremoving"]) do
        if typeof(func) == "function" then
            func(player)
        end
    end
end)

return function(options)
    options = options or {}
    
    for key, value in pairs(options) do
        if framework[key] ~= nil then
            framework[key] = value
        end
    end
    
    if options.auto_init ~= false then
        framework:init()
    end
    
    return framework
end
