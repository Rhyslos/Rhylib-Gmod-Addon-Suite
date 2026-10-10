--[[
    Live profiler (server side) for the staff Profiler page
    (rhylib_menus cl_36_profiler.lua).

    While at least one viewer is subscribed (core.profsub true), the
    profiler is on and once a second the server works out what happened
    in that second and sends it to the viewers (core.profdata, compressed
    JSON): tick rate and the slowest tick, Rhylib hook time per tick, Lua
    memory, counts (players, bots, entities, droids, bolts), time per
    module and per hook handler, and net bytes out per module and per
    message (bytes x recipients, all addons' messages). When the last
    viewer leaves, the profiler goes back to how it was (rhylib_profile).

    Perm rhylib.profiler (superadmin).
    Nets:
      core.profsub   client -> server: bool (true = watch, false = stop);
                     rate 6/s, burst 12
      core.profdata  server -> viewers, every 1 s: UInt 16 length + data
                     (util.Compress of JSON: tickRate, ticks, worst (ms),
                     hookMs, perTick, bytes, mem (MB), humans, bots, ents,
                     droids, bolts, load, mods, hooks, net)
    Modules: a hook handler's module is its id before the first "."; a
    net message's is its name before the first "." when the name has a
    "." and no "_" (Rhylib style), else "other".
]]

local Profiler = Rhylib.Profiler

Rhylib.Net.Register("core.profsub")
Rhylib.Net.Register("core.profdata")
Rhylib.Perms.Register("rhylib.profiler", "superadmin", "See the live profiler page")

-- (kept on a global table so a Lua refresh doesn't lose who's watching)
Rhylib.ProfLive = Rhylib.ProfLive or { viewers = {}, pending = {}, prevHooks = {}, prevNet = {} }
local L = Rhylib.ProfLive
local viewers, pending = L.viewers, L.pending
local ticks, worstGap, lastTick = 0, 0, nil

local function anyViewers() return next(viewers) ~= nil end
local stop

-- Real time between ticks (a slow server stretches them).
local function onTick()
    local now = SysTime()
    if lastTick then
        local gap = now - lastTick
        if gap > worstGap then worstGap = gap end
    end
    lastTick = now
    ticks = ticks + 1
end

-- Totals since the last sample (resets if someone cleared the profiler).
local function deltas(cur, prev, field)
    local out = {}
    for key, e in pairs(cur) do
        local p = prev[key]
        local dv = e[field] - (p and p[field] or 0)
        local dn = e.n - (p and p.n or 0)
        if dv < 0 or dn < 0 then dv, dn = e[field], e.n end
        if dn > 0 or dv > 0 then out[key] = { v = dv, n = dn } end
    end
    return out
end

local function snapshot(tbl, field)
    local out = {}
    for key, e in pairs(tbl) do out[key] = { [field] = e[field], n = e.n } end
    return out
end

-- "Think/weapons.bolts" -> "weapons"; net "chat.msg" -> "chat"; others "other".
local function hookModule(key)
    local id = string.match(key, "/(.+)$") or key
    return string.match(id, "^([^%.]+)%.") or id
end
local function netModule(name)
    if string.find(name, ".", 1, true) and not string.find(name, "_", 1, true) then
        return string.match(name, "^([^%.]+)%.") or "other"
    end
    return "other"
end

local function top(map, n)
    local rows = {}
    for k, e in pairs(map) do rows[#rows + 1] = { k = k, v = e.v, n = e.n } end
    table.sort(rows, function(a, b) return a.v > b.v end)
    local out = {}
    for i = 1, math.min(n, #rows) do out[i] = rows[i] end
    return out
end

local function sample()
    local hooks = deltas(Profiler.hooks, L.prevHooks, "t")
    local nets = deltas(Profiler.net, L.prevNet, "bytes")
    L.prevHooks = snapshot(Profiler.hooks, "t")
    L.prevNet = snapshot(Profiler.net, "bytes")

    local mods = {}   -- [module] = { ms, calls, bytes, msgs }
    local function mod(m)
        mods[m] = mods[m] or { ms = 0, calls = 0, bytes = 0, msgs = 0 }
        return mods[m]
    end
    local hookMs = 0
    for key, e in pairs(hooks) do
        local m = mod(hookModule(key))
        m.ms = m.ms + e.v * 1000
        m.calls = m.calls + e.n
        hookMs = hookMs + e.v * 1000
    end
    local bytes = 0
    for name, e in pairs(nets) do
        local m = mod(netModule(name))
        m.bytes = m.bytes + e.v
        m.msgs = m.msgs + e.n
        bytes = bytes + e.v
    end
    local modList = {}
    for name, m in pairs(mods) do
        modList[#modList + 1] = { name, math.Round(m.ms, 3), m.calls, m.bytes, m.msgs }
    end
    table.sort(modList, function(a, b) return a[2] > b[2] end)

    local hookTop, netTop = {}, {}
    for i, r in ipairs(top(hooks, 15)) do hookTop[i] = { r.k, math.Round(r.v * 1000, 3), r.n } end
    for i, r in ipairs(top(nets, 15)) do netTop[i] = { r.k, r.v, r.n } end

    local humans, bots = 0, 0
    for _, p in ipairs(player.GetAll()) do
        if p:IsBot() then bots = bots + 1 else humans = humans + 1 end
    end
    local D = Rhylib.Droids
    local B = Rhylib.Weapons and Rhylib.Weapons.Bolts
    local data = {
        tickRate = math.Round(1 / engine.TickInterval()),
        ticks = ticks,
        worst = math.Round(worstGap * 1000, 1),
        hookMs = math.Round(hookMs, 3),
        perTick = ticks > 0 and math.Round(hookMs / ticks, 3) or 0,
        bytes = bytes,
        mem = math.Round(collectgarbage("count") / 1024, 1),
        humans = humans, bots = bots,
        ents = #ents.GetAll(),
        droids = (D and D.Count) and D.Count() or 0,
        bolts = (B and B.active) and #B.active or 0,
        load = Rhylib.LoadTest and Rhylib.LoadTest.Count and Rhylib.LoadTest.Count() or 0,
        mods = modList, hooks = hookTop, net = netTop,
    }
    ticks, worstGap = 0, 0

    local list = {}
    for p in pairs(viewers) do
        if IsValid(p) then list[#list + 1] = p else viewers[p] = nil end
    end
    if #list == 0 then return stop() end
    local raw = util.Compress(util.TableToJSON(data) or "{}") or ""
    Rhylib.Net.Start("core.profdata")
    net.WriteUInt(#raw, 16)
    net.WriteData(raw, #raw)
    net.Send(list)
end

local function start()
    Profiler.SetEnabled(true)
    L.prevHooks = snapshot(Profiler.hooks, "t")
    L.prevNet = snapshot(Profiler.net, "bytes")
    ticks, worstGap, lastTick = 0, 0, nil
    Rhylib.Hook.Add("Tick", "core.proftick", onTick, -100000)
    timer.Create("Rhylib.Profiler.Live", 1, 0, sample)
end

stop = function()
    timer.Remove("Rhylib.Profiler.Live")
    Rhylib.Hook.Remove("Tick", "core.proftick")
    -- (back to what rhylib_profile says)
    local cv = GetConVar("rhylib_profile")
    Profiler.SetEnabled(cv and cv:GetBool() or false)
end

local function setViewer(ply, on)
    local had = anyViewers()
    viewers[ply] = on or nil
    local has = anyViewers()
    if has and not had then start() elseif had and not has then stop() end
end

Rhylib.Net.Receive("core.profsub", function(ply)
    local on = net.ReadBool()
    if not on then
        pending[ply] = nil
        return setViewer(ply, false)
    end
    pending[ply] = true
    Rhylib.Perms.Check(ply, "rhylib.profiler", function(ok)
        -- (only if no unsubscribe came in meanwhile)
        if ok and IsValid(ply) and pending[ply] then setViewer(ply, true) end
        pending[ply] = nil
    end)
end, { rate = 6, burst = 12 })

Rhylib.Hook.Add("PlayerDisconnected", "core.profiler", function(ply)
    pending[ply] = nil
    if viewers[ply] then setViewer(ply, false) end
end)
