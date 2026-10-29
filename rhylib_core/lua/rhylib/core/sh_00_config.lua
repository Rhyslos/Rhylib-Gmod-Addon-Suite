--[[
    Config registry (shared).

    Modules register their settings with defaults:
        Rhylib.Config.Register("stamina", "max", 100, "Full stamina")

    Hosts override them in lua/rhylib_config/*.lua:
        Rhylib.Config.Set("stamina", "max", 120)

    Set works before or after Register, so load order doesn't matter.
    Read with Rhylib.Config.Get(module, key). Values are plain Lua, read
    once when needed; nothing here runs per frame.

    Overrides from the in-game Server settings page (sv_15_settings.lua)
    win over both, are saved, and are copied to every client so shared
    (predicted) code reads the same numbers: Config.SetOverride.

    Which value Get returns, first match wins:
        1. Config.overrides  (Server settings page, saved in Data)
        2. Config.values     (host file: Config.Set)
        3. the registered default
    Hook fired: Rhylib.ConfigChanged(module, key, newValue) on every
    SetOverride (newValue = the value now in force).

    Register a setting in a sh_ file when client code reads it too:
    a setting registered only on the server has no default on clients.

    Also:
      Config.For(module) -> cfg(key)    a getter for one module (use it
                                        instead of a local cfg function and
                                        never add "or <default>": the
                                        registered default is the default)
      meta.section (Register)           the Server settings page section
                                        ("B1 grenades") for that setting
      Config.Describe(module, { name, category, sections? })
                                        the module's shown name and sidebar
                                        category on the Server settings page
                                        ("Combat", "Soldiers", "Units & roles",
                                        "NPCs", "Server & interface")
      Config.Sections(module, { {title, {patterns}}, ... })
                                        the module's page sections, in order
]]

Rhylib.Config = Rhylib.Config or {}
local Config = Rhylib.Config

Config.defs = Config.defs or {}      -- [module][key] = { default, desc }
Config.values = Config.values or {}  -- [module][key] = value set by the host
Config.overrides = Config.overrides or {}  -- [module][key] = value from the Server settings page

-- Config.Register(module, key, default, desc, meta): declares a setting.
-- The default's type is the setting's type: the Server settings page only
-- accepts values of the same type. desc is shown on that page.
-- meta (optional): extra facts for the Server settings page, e.g.
-- { name = "Shown name", group = "Weapons" } (model overrides use it),
-- { section = "B1 grenades" } (the section chip the setting sits under).
-- Registering again replaces the default (Lua refresh safe).
-- Example: Rhylib.Config.Register("myaddon", "range", 500, "How far it reaches (units)")
local sectionFor   -- (below: Config.Sections patterns)
function Config.Register(module, key, default, desc, meta)
    Config.defs[module] = Config.defs[module] or {}
    local d = { default = default, desc = desc or "", meta = meta }
    Config.defs[module][key] = d
    if not (meta and meta.section) then
        local sec = sectionFor(module, key)
        if sec then
            d.meta = d.meta or {}
            d.meta.section, d.meta.autoSection = sec, true
        end
    end
end

-- Config.IsModelDefault(default): true for a model path setting (a string
-- ending in .mdl). Such settings also show on the page's Models list and
-- get the model path checks there.
function Config.IsModelDefault(default)
    return isstring(default) and string.lower(string.sub(default, -4)) == ".mdl"
end

-- Config.Set(module, key, value): the host file's value (layer 2 above).
-- Works before or after Register. Doesn't fire Rhylib.ConfigChanged.
-- Example (lua/rhylib_config/settings.lua): Rhylib.Config.Set("jetpack", "fuelTime", 15)
function Config.Set(module, key, value)
    Config.values[module] = Config.values[module] or {}
    Config.values[module][key] = value
end

-- Config.SetOverride(module, key, value): set (value) or clear (nil) a
-- Server settings override on this realm only; hook
-- Rhylib.ConfigChanged(module, key, newValue) lets modules react.
-- Normally called by the settings code (sv_15/cl_15_settings.lua), which
-- also saves it and sends it to clients; calling it yourself does neither.
function Config.SetOverride(module, key, value)
    Config.overrides[module] = Config.overrides[module] or {}
    Config.overrides[module][key] = value
    -- (not Get: server-only settings have no def on clients)
    local nv = value
    if nv == nil then nv = Config.Base(module, key) end
    hook.Run("Rhylib.ConfigChanged", module, key, nv)
end

-- Config.Base(module, key): the value without the page's override (host
-- file, else default).
function Config.Base(module, key)
    local vals = Config.values[module]
    if vals and vals[key] ~= nil then return vals[key] end
    local defs = Config.defs[module]
    return defs and defs[key] and defs[key].default
end

-- Config.Get(module, key): the value in force (see the order above).
-- Unknown keys return nil and warn once in the console. Cheap: read it
-- when you need it rather than copying it into a local at file load
-- (a copy misses later changes from the Server settings page).
-- Example: local range = Rhylib.Config.Get("myaddon", "range")
function Config.Get(module, key)
    local ov = Config.overrides[module]
    if ov and ov[key] ~= nil then return ov[key] end
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

-- Config.For(module) -> cfg(key): a getter bound to one module, cached.
-- Same as Config.Get(module, key) (unknown keys warn once). Don't write
-- cfg("x") or 5: if the key may be missing, that's a missing Register.
-- Example: local cfg = Rhylib.Config.For("eod")  ...  local r = cfg("reach")
Config.getters = Config.getters or {}
function Config.For(module)
    local g = Config.getters[module]
    if g then return g end
    local Get = Config.Get
    g = function(key) return Get(module, key) end
    Config.getters[module] = g
    return g
end

-- Config.Describe(module, { name = "Droids & clones", category = "NPCs" }):
-- how the Server settings page names a module and where it puts it in the
-- side bar. Shared (register it where the client sees it). Modules that
-- never call it fall back to the page's own list, then to "Other".
Config.modules = Config.modules or {}   -- [module] = { name, category, sections, order }
function Config.Describe(module, info)
    local d = Config.modules[module] or {}
    for k, v in pairs(info or {}) do
        if k ~= "sections" then d[k] = v end
    end
    Config.modules[module] = d
    -- sections: either { {title, {patterns}}, ... } (= Config.Sections) or
    -- just the titles in order { "General", ... }.
    local secs = info and info.sections
    if istable(secs) and secs[1] ~= nil then
        if istable(secs[1]) then Config.Sections(module, secs)
        else d.order = secs end
    end
end

-- Config.Sections(module, { { title, { Lua patterns } }, ... }): the
-- Server settings page sections of a module, in this order; each key goes
-- to the first section with a pattern that matches it (string.find), and
-- meta.section on the key (Register) still wins. Applies to keys already
-- registered and to ones registered later. Shared.
-- Example: Config.Sections("droids", { { "B1 grenades", { "^b1Nade" } }, { "B1 battle droids", { "^b1" } } })
function Config.Sections(module, list)
    local d = Config.modules[module] or {}
    Config.modules[module] = d
    d.sections = list
    local order = {}
    for i, s in ipairs(list) do order[i] = s[1] end
    d.order = order
    for key, def in pairs(Config.defs[module] or {}) do
        if not (def.meta and def.meta.section) or def.meta.autoSection then
            local sec = sectionFor(module, key)
            if sec then
                def.meta = def.meta or {}
                def.meta.section, def.meta.autoSection = sec, true
            end
        end
    end
end

sectionFor = function(module, key)
    local d = Config.modules[module]
    local list = d and d.sections
    if not list then return nil end
    for _, s in ipairs(list) do
        for _, pat in ipairs(s[2] or {}) do
            if string.find(key, pat) then return s[1] end
        end
    end
end

Config.Describe("core", { name = "Core", category = "Server & interface" })
Config.Describe("models", { name = "Model overrides" })
