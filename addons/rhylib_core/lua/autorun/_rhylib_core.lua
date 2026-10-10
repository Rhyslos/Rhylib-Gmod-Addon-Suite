--[[
    Rhylib core loader (shared: runs on the server and on every client).

    The file name starts with an underscore so it sorts before other
    autorun files and runs first. Every other Rhylib addon has its own
    autorun file that calls Rhylib.LoadModule("<id>").

    Adds:
      Rhylib (global table), Rhylib.Version, Rhylib.Modules
      Rhylib.Print / Warn / Error   console output tagged with a module
      Rhylib.LoadModule(id, info)   loads lua/rhylib/<id>/*.lua
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

    info (optional): { name = "Shown name", version = "1.0.0" }.
    Returns the module record { id, name, version, files }, also kept in
    Rhylib.Modules[id]. Loading the same id twice does nothing (returns
    the first record). Fires hook Rhylib.ModuleLoaded(id, mod) when done.

    Example (lua/autorun/myaddon.lua):
        if not Rhylib then return end   -- (rhylib_core missing)
        Rhylib.LoadModule("myaddon", { name = "My addon", version = "1.0.0" })
]]
function Rhylib.LoadModule(id, info)
    if Rhylib.Modules[id] then return Rhylib.Modules[id] end

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
    }
    Rhylib.Modules[id] = mod
    Rhylib.Print("core", "Loaded module %s %s (%d files)", mod.name, mod.version, count)

    hook.Run("Rhylib.ModuleLoaded", id, mod)
    return mod
end

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

Rhylib.LoadModule("core", { name = "Core", version = Rhylib.Version })
Rhylib.LoadConfigFiles()
hook.Run("Rhylib.CoreLoaded")
