--[[
    Server settings overrides on the client (see sv_15_settings.lua): kept
    in Config.overrides so shared code reads the same values as the server.
    Rhylib.Settings.list is the catalogue the staff page asked for.
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

local function readCompressed()
    local n = net.ReadUInt(32)
    local json = util.Decompress(net.ReadData(n) or "") or "[]"
    return util.JSONToTable(json) or {}
end

Rhylib.Net.Receive("core.cfgall", function()
    for _, e in ipairs(readCompressed()) do
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
        if e.m == m and e.k == k then e.o = v end
    end
    if S.onChanged then S.onChanged(m, k) end
end)

Rhylib.Net.Receive("core.cfglist", function()
    S.list = readCompressed()
    table.sort(S.list, function(a, b)
        if a.m ~= b.m then return a.m < b.m end
        return a.k < b.k
    end)
    if S.onList then S.onList() end
end)

function S.Request()
    Rhylib.Net.Start("core.cfgreq")
    net.SendToServer()
end

-- Ask for a change (value nil = back to the default / host file).
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
