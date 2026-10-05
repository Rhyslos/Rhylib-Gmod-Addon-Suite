--[[
    Config registry.

    Modules register their settings with defaults:
        Rhylib.Config.Register("stamina", "maxStamina", 100, "Base stamina for every player")

    Hosts override them in lua/rhylib_config/*.lua:
        Rhylib.Config.Set("stamina", "maxStamina", 120)

    Set works before or after Register, so load order doesn't matter.
    Read with Rhylib.Config.Get(module, key). Values are plain Lua, read
    once when needed; nothing here runs per frame.
]]

Rhylib.Config = Rhylib.Config or {}
local Config = Rhylib.Config

Config.defs = Config.defs or {}      -- [module][key] = { default, desc }
Config.values = Config.values or {}  -- [module][key] = value set by the host

function Config.Register(module, key, default, desc)
    Config.defs[module] = Config.defs[module] or {}
    Config.defs[module][key] = { default = default, desc = desc or "" }
end

function Config.Set(module, key, value)
    Config.values[module] = Config.values[module] or {}
    Config.values[module][key] = value
end

function Config.Get(module, key)
    local vals = Config.values[module]
    if vals and vals[key] ~= nil then return vals[key] end

    local defs = Config.defs[module]
    if defs and defs[key] then return defs[key].default end

    -- Warn once per unknown key (this can be called every tick).
    local id = tostring(module) .. "." .. tostring(key)
    Config.warned = Config.warned or {}
    if not Config.warned[id] then
        Config.warned[id] = true
        Rhylib.Warn("config", "Unknown setting %s", id)
    end
    return nil
end
