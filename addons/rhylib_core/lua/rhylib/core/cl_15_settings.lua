--[[
    Server settings overrides on the client (see sv_15_settings.lua): kept
    in Config.overrides so shared code reads the same values as the server.
    Rhylib.Settings.list is the catalogue the staff page asked for.

    The overrides arrive after this client's Lua has loaded (it asks at
    InitPostEntity), so client code that copied a Config value at file
    load keeps the base value. Read Config.Get when needed, or listen to
    hook Rhylib.ConfigChanged (fires here for every override received).

    The page (rhylib_menus) sets S.onList() (catalogue arrived) and
    S.onChanged(m, k) (one setting changed) to redraw itself.
]]

local Config = Rhylib.Config
Rhylib.Settings = Rhylib.Settings or {}
local S = Rhylib.Settings

-- JSON turns Colors into plain {r,g,b,a}; give them their metatable back.
local function fixColors(v)
    if not istable(v) then return v end
    if isnumber(v.r) and isnumber(v.g) and isnumber(v.b) then
        local n = 0
        for _ in pairs(v) do n = n + 1 end
        if n <= 4 then return Color(v.r, v.g, v.b, tonumber(v.a) or 255) end
    end
    for k, x in pairs(v) do v[k] = fixColors(x) end
    return v
end

-- Messages come in parts (see sv_15_settings.lua): nil until the last
-- part of that message has arrived.
local parts = {}
local function readCompressed(name)
    local i, count = net.ReadUInt(8), net.ReadUInt(8)
    local n = net.ReadUInt(32)
    local chunk = net.ReadData(n) or ""
    if i == 1 then parts[name] = {} end
    local buf = parts[name]
    if not buf then return nil end
    buf[i] = chunk
    if i < count then return nil end
    parts[name] = nil
    local json = util.Decompress(table.concat(buf)) or "[]"
    return util.JSONToTable(json) or {}
end

Rhylib.Net.Receive("core.cfgall", function()
    local list = readCompressed("cfgall")
    if not list then return end
    for _, e in ipairs(list) do
        if isstring(e.m) and isstring(e.k) then Config.SetOverride(e.m, e.k, fixColors(e.v)) end
    end
end)

Rhylib.Net.Receive("core.cfgsync", function()
    local m, k = net.ReadString(), net.ReadString()
    local v
    if net.ReadBool() then
        local t = util.JSONToTable(net.ReadString()) or {}
        v = fixColors(t.v)
    end
    Config.SetOverride(m, k, v)
    -- (keep the staff page's catalogue in step)
    for _, e in ipairs(S.list or {}) do
        if e.m == m and e.k == k then
            e.o = v
            -- (a model change: things already placed need a map change)
            if m == "models" or Config.IsModelDefault(e.d) then e.p = true end
        end
    end
    if S.onChanged then S.onChanged(m, k) end
end)

Rhylib.Net.Receive("core.cfglist", function()
    local list = readCompressed("cfglist")
    if not list then return end
    S.list = list
    table.sort(S.list, function(a, b)
        if a.m ~= b.m then return a.m < b.m end
        return a.k < b.k
    end)
    if S.onList then S.onList() end
end)

-- S.Request(): ask the server for the catalogue (answer: S.list, then S.onList()).
function S.Request()
    Rhylib.Net.Start("core.cfgreq")
    net.SendToServer()
end

-- S.Set(m, k, value): ask for a change (value nil = back to the default /
-- host file). The server checks the permission and the value; a refused
-- value gets a chat line saying why.
-- Example: Rhylib.Settings.Set("jetpack", "fuelTime", 12)
function S.Set(m, k, value)
    Rhylib.Net.Start("core.cfgset")
    net.WriteString(m)
    net.WriteString(k)
    net.WriteBool(value ~= nil)
    if value ~= nil then net.WriteString(util.TableToJSON({ v = value }) or "{}") end
    net.SendToServer()
end

-- Ask for the overrides once this client's Lua is loaded.
Rhylib.Hook.Add("InitPostEntity", "core.settings", function()
    Rhylib.Net.Start("core.cfgallreq")
    net.SendToServer()
end)
