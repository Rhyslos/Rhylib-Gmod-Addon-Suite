--[[
    Hook bus (shared).

    Every Rhylib module registers here instead of calling hook.Add directly:
        Rhylib.Hook.Add("PlayerDeath", "medic.downed", function(ply) ... end)
        Rhylib.Hook.Add("Tick", "weapons.bolts", stepBolts, 10)   -- priority 10

    For each event, the bus puts exactly one real hook into GMod
    ("Rhylib.Bus") and calls the module handlers from a flat array.
    That gives us:
      - one engine hook per event, no matter how many modules are loaded
      - a fixed call order (lower priority number runs first)
      - per-handler timing when the profiler is on, at zero cost when off

    Like normal GMod hooks, a handler that returns a non-nil value stops
    the chain and that value is returned to the engine.

    Order: lower priority first (default 0, may be negative); same
    priority = the order they were added. Example: a damage blocker at
    -1000 runs before armour at 0, and if it returns true nothing after it
    runs. Return nothing (not false) to let the rest run: false is a value
    and stops the chain too.

    Ordering against other addons' plain hook.Add handlers isn't fixed:
    "Rhylib.Bus" is one GMod hook among theirs, and GMod calls those in
    no set order. Priorities only order Rhylib handlers among themselves.
    Up to 6 return values are passed on. Works for custom events too
    (hook.Run("Rhylib.X", ...) reaches handlers added here).
]]

Rhylib.Hook = Rhylib.Hook or {}
local Hook = Rhylib.Hook

Hook.events = Hook.events or {}  -- [event] = { entries = { ... }, order = n }

local HOOK_ID = "Rhylib.Bus"

local function rebuild(event)
    local ev = Hook.events[event]
    if not ev or #ev.entries == 0 then
        hook.Remove(event, HOOK_ID)
        Hook.events[event] = nil
        return
    end

    table.sort(ev.entries, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        return a.order < b.order
    end)

    -- (one dispatcher per event, re-made on every Add/Remove; the timed
    -- version is only used while the profiler is on)
    -- Copy into plain arrays so adding or removing a handler while the
    -- event is running never changes the array being looped over.
    local fns, keys, n = {}, {}, #ev.entries
    for i = 1, n do
        fns[i] = ev.entries[i].fn
        keys[i] = event .. "/" .. ev.entries[i].id
    end

    local dispatch
    if Rhylib.Profiler.enabled then
        local addTime, clock = Rhylib.Profiler.AddTime, SysTime
        dispatch = function(...)
            for i = 1, n do
                local t = clock()
                local a, b, c, d, e, f = fns[i](...)
                addTime(keys[i], clock() - t)
                if a ~= nil then return a, b, c, d, e, f end
            end
        end
    else
        dispatch = function(...)
            for i = 1, n do
                local a, b, c, d, e, f = fns[i](...)
                if a ~= nil then return a, b, c, d, e, f end
            end
        end
    end

    hook.Add(event, HOOK_ID, dispatch)
end

-- Hook.Add(event, id, fn, priority): add or replace (same id) a handler.
-- id: "<module>.<name>"; the part before the first "." is the module the
-- live profiler adds its time to. priority: number, default 0.
-- Example:
--   Rhylib.Hook.Add("PlayerSpawn", "myaddon.spawn", function(ply) ... end)
--   Rhylib.Hook.Add("EntityTakeDamage", "myaddon.block", function(ent, dmg)
--       if ent.myGodMode then return true end   -- stops the chain: no damage
--   end, -500)
function Hook.Add(event, id, fn, priority)
    local ev = Hook.events[event]
    if not ev then
        ev = { entries = {}, order = 0 }
        Hook.events[event] = ev
    end

    -- Replace an existing handler with the same id (safe with Lua autorefresh).
    for i, e in ipairs(ev.entries) do
        if e.id == id then
            table.remove(ev.entries, i)
            break
        end
    end

    ev.order = ev.order + 1
    ev.entries[#ev.entries + 1] = { id = id, fn = fn, priority = priority or 0, order = ev.order }
    rebuild(event)
end

-- Hook.Remove(event, id): remove a handler (nothing happens if it isn't there).
-- Example: Rhylib.Hook.Remove("PlayerSpawn", "myaddon.spawn")
function Hook.Remove(event, id)
    local ev = Hook.events[event]
    if not ev then return end
    for i, e in ipairs(ev.entries) do
        if e.id == id then
            table.remove(ev.entries, i)
            rebuild(event)
            return
        end
    end
end

-- Hook.RebuildAll(): remake every event's dispatcher (the profiler calls it).
function Hook.RebuildAll()
    for event in pairs(Hook.events) do rebuild(event) end
end

-- Rebuild once in case the profiler flag changed before this file loaded.
Hook.RebuildAll()
