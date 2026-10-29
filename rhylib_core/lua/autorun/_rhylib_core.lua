--[[
    Rhylib core loader (shared: runs on the server and on every client).

    The file name starts with an underscore so it sorts before other
    autorun files and runs first. Every other Rhylib addon has its own
    autorun file that calls Rhylib.LoadModule("<id>").

    Adds:
      Rhylib (global table), Rhylib.Version, Rhylib.Modules
      Rhylib.Print / Warn / Error   console output tagged with a module
      Rhylib.LoadModule(id, info)   loads lua/rhylib/<id>/*.lua (info.needs /
                                    info.wants: waits for those modules)
      Rhylib.After(id, fn)          runs fn once module id has loaded
      Rhylib.Has(id)                module id has loaded
      Rhylib.LoadConfigFiles()      loads the host's lua/rhylib_config/*.lua
    Hooks fired: Rhylib.ModuleLoaded(id, mod), Rhylib.CoreLoaded().

    Order at start-up: the core module (lua/rhylib/core/) loads, then the
    host config files, then hook Rhylib.CoreLoaded. Other addons' autorun
    files run after this one and each load their own module.
]]

Rhylib = Rhylib or {}
Rhylib.Version = "0.1.0"
Rhylib.Modules = Rhylib.Modules or {}

local COLOR_TAG = Color(120, 170, 255)
local COLOR_TEXT = Color(230, 230, 230)
local COLOR_WARN = Color(255, 190, 80)

-- Rhylib.Print(module, fmt, ...): a line in the console, "[Rhylib:<module>] "
-- then string.format(fmt, ...). Warn is the same in orange; Error uses
-- ErrorNoHalt (shows as a Lua error but doesn't stop the code).
-- Example: Rhylib.Print("myaddon", "Loaded %d things", n)
function Rhylib.Print(module, fmt, ...)
    MsgC(COLOR_TAG, "[Rhylib:" .. module .. "] ", COLOR_TEXT, string.format(fmt, ...), "\n")
end

function Rhylib.Warn(module, fmt, ...)
    MsgC(COLOR_TAG, "[Rhylib:" .. module .. "] ", COLOR_WARN, string.format(fmt, ...), "\n")
end

function Rhylib.Error(module, fmt, ...)
    ErrorNoHalt("[Rhylib:" .. module .. "] " .. string.format(fmt, ...) .. "\n")
end

-- Load one file by its realm prefix: sh_ (both), sv_ (server), cl_ (client).
local function loadFile(path, prefix)
    if prefix == "sh_" then
        if SERVER then AddCSLuaFile(path) end
        include(path)
    elseif prefix == "sv_" then
        if SERVER then include(path) end
    elseif prefix == "cl_" then
        if SERVER then
            AddCSLuaFile(path)
        else
            include(path)
        end
    end
end

--[[
    Rhylib.LoadModule(id, info): load every file in lua/rhylib/<id>/.
    Shared files load first, then server, then client. Within each group,
    files load in alphabetical order, so number them to control order
    (sh_00_first.lua, sh_10_second.lua, ...). The server also sends sh_
    and cl_ files to clients (AddCSLuaFile).

    info (optional): { name = "Shown name", version = "1.0.0",
                       needs = { "inventory", ... }, wants = { "skills", ... } }
      needs: modules this one can't do its job without. It waits until all
             of them have loaded, then loads straight after the last one.
      wants: optional modules it works better with. It waits for one only
             if that addon is installed (its autorun file exists) and hasn't
             loaded yet; cycles between wants are ignored.
    Anything still waiting when the gamemode has loaded (OnGamemodeLoaded,
    before weapons and entities register) loads anyway, with a warning
    naming what's missing, so a missing addon never stops the rest.

    Returns the module record { id, name, version, files, needs, wants }
    (also Rhylib.Modules[id]), or nil while it waits (Rhylib.pending[id]).
    Loading the same id twice does nothing. Fires hook
    Rhylib.ModuleLoaded(id, mod) when done, then runs Rhylib.After callbacks.

    Example (lua/autorun/myaddon.lua):
        if not Rhylib then return end   -- (rhylib_core missing)
        Rhylib.LoadModule("myaddon", { name = "My addon", version = "1.0.0",
            needs = { "inventory" }, wants = { "skills" } })
]]
Rhylib.pending = Rhylib.pending or {}   -- [id] = info, waiting for needs / wants
Rhylib.pendingOrder = Rhylib.pendingOrder or {}   -- ids in the order they asked (loads keep it)
Rhylib.afterFns = Rhylib.afterFns or {} -- [id] = { fn, ... }

-- Rhylib.Has(id): true once that module has loaded.
function Rhylib.Has(id) return Rhylib.Modules[id] ~= nil end

-- Installed: its autorun file exists (rhylib_<id>.lua; the core's is _rhylib_core.lua).
local installedCache = {}
local function installed(id)
    local v = installedCache[id]
    if v == nil then
        v = id == "core" or file.Exists("autorun/rhylib_" .. id .. ".lua", "LUA")
        installedCache[id] = v
    end
    return v
end

-- What id still waits for: needs not loaded, and wants installed but not
-- loaded (skipping a want that waits on id itself, directly or further on).
local function waitsOn(id, info, seen)
    local out = {}
    for _, n in ipairs(info.needs or {}) do
        -- (a need that isn't installed at all can't arrive: don't wait for
        -- it, so the module still loads during autorun, before the SWEPs and
        -- entities that read its tables; the warning is printed below)
        if not Rhylib.Modules[n] and installed(n) then out[#out + 1] = n end
    end
    for _, w in ipairs(info.wants or {}) do
        if not Rhylib.Modules[w] and installed(w) then
            local cyc = false
            local wi = Rhylib.pending[w]
            if wi then
                seen = seen or {}
                seen[id] = true
                local stack, visited = { w }, {}
                while #stack > 0 and not cyc do
                    local x = table.remove(stack)
                    if not visited[x] then
                        visited[x] = true
                        local xi = Rhylib.pending[x]
                        if xi then
                            for _, list in ipairs({ xi.needs or {}, xi.wants or {} }) do
                                for _, y in ipairs(list) do
                                    if seen[y] then cyc = true end
                                    if Rhylib.pending[y] then stack[#stack + 1] = y end
                                end
                            end
                        end
                    end
                end
            end
            if not cyc then out[#out + 1] = w end
        end
    end
    return out
end

local loadNow
-- Load whatever is waiting and now may (repeats until nothing changes).
local function flushPending(force)
    local again = true
    while again do
        again = false
        -- (in the order the modules asked to load, so hooks that share a
        -- priority keep a fixed order from one start to the next)
        for _, id in ipairs(Rhylib.pendingOrder) do
            local info = Rhylib.pending[id]
            local wait = info and waitsOn(id, info) or {}
            if not info then
                -- (already loaded or never pending)
            elseif #wait == 0 or force then
                Rhylib.pending[id] = nil
                if #wait > 0 then
                    Rhylib.Warn("core", "%s loads without %s (not installed or not loaded); some of its features may be missing",
                        info.name or id, table.concat(wait, ", "))
                end
                loadNow(id, info)
                again = true
                break   -- (the list may have changed: start again)
            end
        end
    end
end

loadNow = function(id, info)
    local dir = "rhylib/" .. id .. "/"
    local files = file.Find(dir .. "*.lua", "LUA")
    table.sort(files)

    local count = 0
    for _, prefix in ipairs({ "sh_", "sv_", "cl_" }) do
        for _, name in ipairs(files) do
            if string.sub(name, 1, 3) == prefix then
                loadFile(dir .. name, prefix)
                count = count + 1
            end
        end
    end

    local mod = {
        id = id,
        name = info and info.name or id,
        version = info and info.version or "0.0.0",
        files = count,
        needs = info and info.needs or {},
        wants = info and info.wants or {},
    }
    Rhylib.Modules[id] = mod
    Rhylib.Print("core", "Loaded module %s %s (%d files)", mod.name, mod.version, count)

    hook.Run("Rhylib.ModuleLoaded", id, mod)
    local fns = Rhylib.afterFns[id]
    Rhylib.afterFns[id] = nil
    for _, fn in ipairs(fns or {}) do
        local ok, err = pcall(fn, mod)
        if not ok then Rhylib.Error("core", "Rhylib.After(%s) callback: %s", id, tostring(err)) end
    end
    flushPending()
    return mod
end

function Rhylib.LoadModule(id, info)
    if Rhylib.Modules[id] then return Rhylib.Modules[id] end
    info = info or {}
    for _, n in ipairs(info.needs or {}) do
        if not installed(n) then
            Rhylib.Warn("core", "%s needs %s, which isn't installed; some of its features won't work", info.name or id, n)
        end
    end
    if #waitsOn(id, info) > 0 then
        Rhylib.pending[id] = info
        if not table.HasValue(Rhylib.pendingOrder, id) then Rhylib.pendingOrder[#Rhylib.pendingOrder + 1] = id end
        flushPending()   -- (this one waiting may break a cycle of wants for another)
        return Rhylib.Modules[id]
    end
    return loadNow(id, info)
end

-- Rhylib.After(id, fn): run fn(mod) now if module id has loaded, else once
-- right after it loads (refresh-safe enough: a re-run file adds its
-- callback again only while the module is still missing).
-- Example: Rhylib.After("inventory", function() registerMyItems() end)
function Rhylib.After(id, fn)
    local mod = Rhylib.Modules[id]
    if mod then return fn(mod) end
    local list = Rhylib.afterFns[id] or {}
    Rhylib.afterFns[id] = list
    list[#list + 1] = fn
end

-- Whatever still waits once the gamemode has loaded (before weapons and
-- entities register) loads anyway, with a warning.
hook.Add("OnGamemodeLoaded", "Rhylib.LoadPending", function() flushPending(true) end)

--[[
    Rhylib.LoadConfigFiles(): host overrides live in lua/rhylib_config/*.lua,
    ideally in a separate addon folder so Workshop updates never overwrite
    them (see docs/config-example.lua). Loaded on both realms, in
    alphabetical order, right after the core module. Config.Set works
    before the setting is registered, so these files may set values for
    addons that load later.
]]
function Rhylib.LoadConfigFiles()
    local files = file.Find("rhylib_config/*.lua", "LUA")
    table.sort(files)
    for _, name in ipairs(files) do
        local path = "rhylib_config/" .. name
        if SERVER then AddCSLuaFile(path) end
        include(path)
    end
end

Rhylib.LoadModule("core", { name = "Rhy's Core", version = Rhylib.Version })
Rhylib.LoadConfigFiles()
hook.Run("Rhylib.CoreLoaded")
