--[[
    Model overrides (owner 2026-10-09: hosts find their own models and
    swap ours in the Server settings page).

    Every model the suite uses from a table field is listed here as a
    setting in config module "models": key = an id, default = the path the
    code ships with. The registry writes the setting's value (Server
    settings override > host file > default) back into that field, on
    both realms, so the code that reads the field uses the new model.
    Models that already are settings of their own module (e.g. eod
    mineModel) stay there; the page shows them with these.

    Found automatically (rhylib_ classes only, own fields only):
      weapons   ViewModel, WorldModel, PropModel, CarrierVM, DualCarrierVM,
                ModeProxies[mode].model
      entities  ENT.Model (not when ENT.ModelFromConfig: a config setting
                picks the model there)
      items     def.model / def.iconModel of non-weapon items
    Addons add their own tables with hook Rhylib.ModelCatalogue(add):
      add(key, name, group, getTable, field, onApply)

    Things already in the world keep their model until they're made
    again; most need a map change. The page says so.

    Shared. Keys: "weapon.<class>.<Field>", "weapon.<class>.mode.<mode>",
    "entity.<class>", "item.<id>", "item.<id>.icon", or an addon's own.
    When: Scan at Initialize, InitPostEntity, 2 s after that, and after a
    Lua refresh. A change from the page: Rhylib.ConfigChanged("models", key)
    -> ApplyOne(key) -> hook Rhylib.ModelsChanged(key).
    M.pending["<module>\0<key>"] = true (server): changed this map, the
    page shows "map change needed".
]]

Rhylib.Models = Rhylib.Models or {}
local M = Rhylib.Models
local Config = Rhylib.Config

M.entries = M.entries or {}   -- [key] = { key, name, group, get, field, orig, onApply }
M.order = M.order or {}       -- keys in the order they were found

local function isModel(v)
    return isstring(v) and string.lower(string.sub(v, -4)) == ".mdl"
end

-- M.Field(key, name, group, get, field, onApply): register (or refresh)
-- one model field. get() returns the table that holds it (nil = not
-- available on this realm right now); table[field] must hold a .mdl path
-- the first time, which becomes the setting's default. name and group are
-- what the page shows. onApply(value, entry) (optional) runs after every
-- apply, for copies of the path kept elsewhere. Addons call it through
-- hook Rhylib.ModelCatalogue (the add argument is M.Field).
-- Example (shared file):
--   Rhylib.Hook.Add("Rhylib.ModelCatalogue", "myaddon.models", function(add)
--       add("myaddon.crate", "My crate", "Entities: My addon",
--           function() return MyAddon.MODELS end, "crate")
--   end)
function M.Field(key, name, group, get, field, onApply)
    local e = M.entries[key]
    local t = get()
    if not e then
        local orig = t and t[field]
        if not isModel(orig) then return end
        e = { key = key, orig = orig }
        M.entries[key] = e
        M.order[#M.order + 1] = key
        Config.Register("models", key, orig, name, { name = name, group = group })
    end
    e.name, e.group, e.get, e.field, e.onApply = name, group, get, field, onApply
end

-- Put the current value into the field.
-- Weapons that already exist on this client (a player who joins after a
-- change builds them before the overrides arrive): copied fields and
-- cached props are refreshed once, shortly after.
local carrierSwaps = {}
local function refreshLiveWeapons()
    for _, w in ipairs(ents.FindByClass("rhylib_*")) do
        if IsValid(w) and w:IsWeapon() then
            local tbl = w:GetTable()
            local nv = carrierSwaps[rawget(tbl, "ViewModel") or ""]
            if nv and w.rhylibCarrier then tbl.ViewModel = nv end
            if w.RhylibModelsChanged then
                local ok, err = pcall(w.RhylibModelsChanged, w)
                if not ok then ErrorNoHalt("[Rhylib] models: " .. tostring(err) .. "\n") end
            end
        end
    end
    carrierSwaps = {}
end

-- M.ApplyOne(key): write the setting's value into its field (an invalid
-- value falls back to the shipped path). M.ApplyAll(): every entry.
function M.ApplyOne(key)
    local e = M.entries[key]
    if not e then return end
    local t = e.get()
    if not t then return end
    local v = Config.Get("models", key)
    if not isModel(v) then v = e.orig end
    local old = t[e.field]
    if old ~= v then t[e.field] = v end
    if e.onApply then
        local ok, err = pcall(e.onApply, v, e)
        if not ok then ErrorNoHalt("[Rhylib] models " .. key .. ": " .. tostring(err) .. "\n") end
    end
    if CLIENT and old ~= v and string.sub(key, 1, 7) == "weapon." then
        if e.field == "CarrierVM" and isstring(old) then carrierSwaps[old] = v end
        timer.Create("Rhylib.Models.Live", 0.2, 1, refreshLiveWeapons)
    end
end

function M.ApplyAll()
    for _, key in ipairs(M.order) do M.ApplyOne(key) end
end

-- M.Current(key): the current model path of an entry, or nil (for previews).
function M.Current(key)
    local e = M.entries[key]
    if not e then return nil end
    local v = Config.Get("models", key)
    return isModel(v) and v or e.orig
end

local function strip(cat)
    cat = tostring(cat or "")
    return (string.gsub(cat, "^Rhylib:%s*", ""))
end

local SWEP_FIELDS = {
    { "PropModel", "gun model" },
    { "WorldModel", "world model" },
    { "ViewModel", "first-person model" },
    { "CarrierVM", "first-person arms" },
    { "DualCarrierVM", "dual pistol arms" },
}

local function scanWeapons()
    for _, w in ipairs(weapons.GetList()) do
        local class = w.ClassName
        if isstring(class) and string.sub(class, 1, 7) == "rhylib_" then
            local function stored() return weapons.GetStored(class) end
            local s = stored()
            local name = (s and s.PrintName) or class
            local group = "Weapons: " .. (strip(s and s.Category) ~= "" and strip(s.Category) or "Other")
            for _, f in ipairs(SWEP_FIELDS) do
                if s and isModel(rawget(s, f[1])) then
                    local onApply
                    if f[1] == "WorldModel" then
                        -- (the weapon's inventory item copied it when it registered)
                        -- (and copies built on it, e.g. training guns, that don't set their own)
                        onApply = function(v)
                            local Items = Rhylib.Items
                            if not (Items and Items.defs) then return end
                            for _, def in pairs(Items.defs) do
                                if def.weapon then
                                    local full = def.weapon == class or weapons.IsBasedOn(def.weapon, class)
                                    if full then
                                        local own = weapons.GetStored(def.weapon)
                                        if def.weapon == class or not (own and rawget(own, "WorldModel")) then def.model = v end
                                    end
                                end
                            end
                        end
                    end
                    M.Field("weapon." .. class .. "." .. f[1], name .. " · " .. f[2], group, stored, f[1], onApply)
                end
            end
            local px = s and rawget(s, "ModeProxies")
            if istable(px) then
                for mode, p in pairs(px) do
                    if istable(p) and isModel(p.model) then
                        M.Field("weapon." .. class .. ".mode." .. mode, name .. " · " .. mode .. " mode arms", group,
                            function() local st = stored() local t = st and rawget(st, "ModeProxies") return t and t[mode] end, "model")
                    end
                end
            end
        end
    end
end

local function scanEntities()
    for class, v in pairs(scripted_ents.GetList()) do
        if isstring(class) and string.sub(class, 1, 7) == "rhylib_" and istable(v.t) then
            local t = v.t
            local full = scripted_ents.Get(class)
            if isModel(rawget(t, "Model")) and not (full and full.ModelFromConfig) then
                M.Field("entity." .. class, (t.PrintName or class), "Entities: " .. (strip(full and full.Category) ~= "" and strip(full.Category) or "Other"),
                    function() local st = scripted_ents.GetStored(class) return st and st.t end, "Model")
            end
        end
    end
end

local function scanItems()
    local Items = Rhylib.Items
    if not (Items and Items.defs) then return end
    local ids = {}
    for id in pairs(Items.defs) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local def = Items.defs[id]
        if istable(def) and not def.weapon then
            local get = function() return Items.defs[id] end
            local group = "Items: " .. (def.category and (string.upper(string.sub(def.category, 1, 1)) .. string.sub(def.category, 2)) or "Other")
            if isModel(def.model) then M.Field("item." .. id, (def.name or id), group, get, "model") end
            if isModel(def.iconModel) then M.Field("item." .. id .. ".icon", (def.name or id) .. " · inventory picture", group, get, "iconModel") end
        end
    end
end

-- M.Scan(): find everything (again: cheap, and new things may have
-- registered), run hook Rhylib.ModelCatalogue(M.Field), then ApplyAll.
function M.Scan()
    scanWeapons()
    scanEntities()
    scanItems()
    -- (one addon's error mustn't stop the rest being applied)
    local ok, err = pcall(hook.Run, "Rhylib.ModelCatalogue", M.Field)
    if not ok then ErrorNoHalt("[Rhylib] models catalogue: " .. tostring(err) .. "\n") end
    M.ApplyAll()
    M.scanned = true
end

-- Changes made this map (server; the page shows "map change needed").
M.pending = M.pending or {}

Rhylib.Hook.Add("Initialize", "core.models", function() M.Scan() end)
Rhylib.Hook.Add("InitPostEntity", "core.models", function()
    M.Scan()
    timer.Simple(2, function() M.Scan() end)   -- (items registered late)
end)
Rhylib.Hook.Add("Rhylib.ConfigChanged", "core.models", function(m, k)
    if m ~= "models" then return end
    M.ApplyOne(k)
    hook.Run("Rhylib.ModelsChanged", k)
end)
-- (Lua refresh: tables may have been made again with the shipped paths)
Rhylib.Hook.Add("OnReloaded", "core.models", function() if M.scanned then M.Scan() end end)
if M.scanned then M.Scan() end
