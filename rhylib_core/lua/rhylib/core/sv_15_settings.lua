--[[
    Server settings page (server side). Staff with rhylib.settings change
    any registered config value in game; the change applies at once
    (Config.Get reads it next time; a few values that a module copies at
    load only change after a map change), is saved, and is sent to every
    client so shared code agrees. "Reset" removes the override (back to
    the host file's value or the default).

    Perm rhylib.settings (superadmin).
    Saved: Data "core" "settings" = { { m, k, v }, ... }, loaded when this
    file loads (before the other addons load, so they see the overrides
    from the start).
    Nets:
      core.cfgreq      client -> server, empty: "send me the catalogue"
                       (rate 1/s, burst 3)
      core.cfglist     server -> that client: catalogue, compressed JSON in
                       parts, rows { m, k, d = default, b = base (host file
                       or default), o = override, s = desc, x = meta,
                       p = map change needed }; an empty list when denied
      core.cfgset      client -> server: module string, key string, has
                       bool, then (if has) JSON {v=value}; has false = reset
                       (rate 4/s, burst 8)
      core.cfgsync     server -> everyone: module, key, has, JSON (one change)
      core.cfgallreq   client -> server once its Lua is loaded (once per player)
      core.cfgall      server -> that client: every override, compressed
                       JSON in parts { { m, k, v } }
    Parts: UInt 8 part, UInt 8 part count, UInt 32 length, data
    (60000-byte parts).
    Checks on cfgset: the setting must exist, same type as the default,
    numbers finite and |v| <= 1e6, not negative when the default isn't,
    arrays stay arrays with the same kind of first item; model settings
    must be a models/...mdl path the server has (see badModel).
    The admin module's settings (ranks, owners, levels) aren't editable
    here: a bad value could lock everyone out or promote someone.
    Console: rhylib_settings_reset <module> [key] (no key = the whole module).
]]

local Config = Rhylib.Config
local Data = Rhylib.Data

Rhylib.Net.Register("core.cfgreq")
Rhylib.Net.Register("core.cfglist")
Rhylib.Net.Register("core.cfgset")
Rhylib.Net.Register("core.cfgsync")
Rhylib.Net.Register("core.cfgall")
Rhylib.Net.Register("core.cfgallreq")

Rhylib.Perms.Register("rhylib.settings", "superadmin", "Change server settings in the Server settings page")

-- Never editable from the page.
local PROTECTED = { admin = true }

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
Rhylib.Settings = Rhylib.Settings or {}
-- Rhylib.Settings.FixColors(value): turns {r,g,b[,a]} tables (anywhere in
-- value) back into Colors. Server copy; the client has its own.
Rhylib.Settings.FixColors = fixColors

local function saved()
    local list = {}
    for m, keys in pairs(Config.overrides) do
        for k, v in pairs(keys) do list[#list + 1] = { m = m, k = k, v = v } end
    end
    return list
end

local function save()
    local list = saved()
    if #list > 0 then Data.Set("core", "settings", list) else Data.Delete("core", "settings") end
end

-- Load the saved overrides now (before other addons read their settings).
do
    local list = Data.Get("core", "settings")
    if istable(list) then
        for _, e in ipairs(list) do
            if isstring(e.m) and isstring(e.k) and e.v ~= nil and not PROTECTED[e.m] then
                Config.overrides[e.m] = Config.overrides[e.m] or {}
                Config.overrides[e.m][e.k] = fixColors(e.v)
            end
        end
    end
end

local function wrap(v) return util.TableToJSON({ v = v }) or "{}" end

-- Sent in parts of up to 60000 bytes (the catalogue with every model
-- grew past one message): part index, part count, length, data.
local PART = 60000
local function sendCompressed(name, tbl, target)
    local data = util.Compress(util.TableToJSON(tbl) or "[]") or ""
    local parts = math.max(1, math.ceil(#data / PART))
    if parts > 255 then
        Rhylib.Warn("settings", "%s is too large to send (%d bytes)", name, #data)
        return
    end
    for i = 1, parts do
        local chunk = string.sub(data, (i - 1) * PART + 1, i * PART)
        Rhylib.Net.Start(name)
        net.WriteUInt(i, 8)
        net.WriteUInt(parts, 8)
        net.WriteUInt(#chunk, 32)
        net.WriteData(chunk, #chunk)
        net.Send(target)
    end
end

-- Everyone gets the overrides once their Lua is loaded (shared code
-- reads them). (On PlayerInitialSpawn the client can't receive yet.)
Rhylib.Net.Receive("core.cfgallreq", function(ply)
    if ply.rhylibCfgSent then return end
    ply.rhylibCfgSent = true
    local list = saved()
    if #list > 0 then sendCompressed("core.cfgall", list, ply) end
end, { rate = 1, burst = 2 })

local function allowed(ply, cb, denied)
    Rhylib.Perms.Check(ply, "rhylib.settings", function(ok)
        if ok then cb() elseif denied then denied() end
    end)
end

Rhylib.Net.Receive("core.cfgreq", function(ply)
    allowed(ply, function()
        local list = {}
        for m, keys in pairs(Config.defs) do
            if PROTECTED[m] then keys = {} end
            for k, d in pairs(keys) do
                local ov = Config.overrides[m] and Config.overrides[m][k]
                local pend = Rhylib.Models and Rhylib.Models.pending[m .. "\0" .. k] or nil
                list[#list + 1] = { m = m, k = k, d = d.default, b = Config.Base(m, k), o = ov, s = d.desc, x = d.meta, p = pend }
            end
        end
        sendCompressed("core.cfglist", list, ply)
    end, function()
        -- (an empty list: the page says there's nothing it may show)
        if IsValid(ply) then sendCompressed("core.cfglist", {}, ply) end
    end)
end, { rate = 1, burst = 3 })

local function isArray(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n == #t
end

-- Same type as the default, and roughly the same shape: no NaN, no
-- huge numbers, no negatives where the default isn't, arrays stay
-- arrays (with the same kind of first item).
local function sameKind(new, default)
    if default == nil then return type(new) ~= "function" end
    if type(new) ~= type(default) then return false end
    if isnumber(new) then
        if new ~= new or math.abs(new) > 1e6 then return false end
        if default >= 0 and new < 0 then return false end
    end
    if istable(new) and next(default) ~= nil then
        if isArray(default) ~= isArray(new) then return false end
        if isArray(default) and new[1] ~= nil and type(new[1]) ~= type(default[1]) then return false end
    end
    return true
end

-- Model paths (config module "models" and any setting whose default is a
-- .mdl path): a clean path under models/ that the server has.
local function badModel(value)
    if not isstring(value) then return "that isn't a model path" end
    if value == "" then return nil end   -- (some settings use "" for their own fallback)
    local v = string.lower(value)
    if string.sub(v, 1, 7) ~= "models/" or string.sub(v, -4) ~= ".mdl" or string.find(v, "..", 1, true)
        or string.find(v, "[:%c\\]") then
        return "a model path looks like models/folder/name.mdl"
    end
    if not util.IsValidModel(value) then
        return "the server doesn't have " .. value .. " (install the addon it comes from on the server and add it to your Workshop collection)"
    end
end

local function broadcast(m, k, value)
    Rhylib.Net.Start("core.cfgsync")
    net.WriteString(m)
    net.WriteString(k)
    net.WriteBool(value ~= nil)
    if value ~= nil then net.WriteString(wrap(value)) end
    net.Broadcast()
end

Rhylib.Net.Receive("core.cfgset", function(ply)
    local m, k = net.ReadString(), net.ReadString()
    local has = net.ReadBool()
    local raw = has and net.ReadString() or nil
    allowed(ply, function()
        local def = Config.defs[m] and Config.defs[m][k]
        if not def or PROTECTED[m] then return end
        local value
        if has then
            local t = util.JSONToTable(raw or "")
            value = istable(t) and fixColors(t.v) or nil
            if value == nil or not sameKind(value, def.default) then
                if IsValid(ply) then ply:ChatPrint("[Settings] " .. m .. "." .. k .. ": that isn't a valid value") end
                return
            end
            if m == "models" or Config.IsModelDefault(def.default) then
                if isstring(value) then value = string.Trim((string.gsub(value, "\\", "/"))) end
                if m == "models" and value == "" then value = nil end   -- (empty = back to the shipped model)
                local why = value and badModel(value)
                if why then
                    if IsValid(ply) then ply:ChatPrint("[Settings] " .. ((def.meta and def.meta.name) or (m .. "." .. k)) .. ": " .. why) end
                    return
                end
            end
        end
        if (m == "models" or Config.IsModelDefault(def.default)) and Rhylib.Models then
            Rhylib.Models.pending[m .. "\0" .. k] = true
        end
        Config.SetOverride(m, k, value)
        save()
        broadcast(m, k, value)
        Rhylib.Print("settings", "%s set %s.%s to %s", IsValid(ply) and ply:Nick() or "Console", m, k,
            value == nil and "(default)" or tostring(istable(value) and util.TableToJSON(value) or value))
    end)
end, { rate = 4, burst = 8 })

-- Undo from the console (e.g. a value that broke something):
-- rhylib_settings_reset <module> [key].
concommand.Add("rhylib_settings_reset", function(ply, _, args)
    allowed(IsValid(ply) and ply or nil, function()
        local m, k = args[1], args[2]
        local keys = m and Config.overrides[m]
        if not keys then return print("[Rhylib] rhylib_settings_reset <module> [key]: nothing changed there") end
        local list = {}
        for key in pairs(keys) do
            if k == nil or key == k then list[#list + 1] = key end
        end
        for _, key in ipairs(list) do
            Config.SetOverride(m, key, nil)
            broadcast(m, key, nil)
        end
        save()
        print("[Rhylib] reset " .. #list .. " setting(s) in " .. m)
    end)
end)
