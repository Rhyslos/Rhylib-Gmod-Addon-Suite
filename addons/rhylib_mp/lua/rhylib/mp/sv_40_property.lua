--[[
    Property lockers (rhylib_property_locker): where processed prisoners
    collect what was taken from them. Each player sees only their own
    things (Data "mp_prop"/SteamID64) and can only take them out.

        MP.StoreProperty(ply, list)   list of { id, count, data } into
                                      ply's property; returns what didn't fit
        MP.OpenProperty(ply, ent)     E on a locker

    How it works: the locker is a rhylib_inventory grid storage with a
    `variant` function, so each player who opens it gets their own
    sub-storage (propertyW x propertyH cells, noDeposit: take out only),
    loaded from and saved to Data "mp_prop"/SteamID64 (row deleted when
    empty). Needs rhylib_inventory.
]]

local MP = Rhylib.MP
local Data = Rhylib.Data
local Config = Rhylib.Config

Config.Register("mp", "propertyW", 10, "Property locker width in cells")
Config.Register("mp", "propertyH", 8, "Property locker height in cells")

local function Inv() return Rhylib.Inventory and Rhylib.Inventory.NewStorage and Rhylib.Inventory or nil end

local function saveSub(sub)
    local I = Inv()
    if not (I and sub.propSid) then return end
    if next(sub.items) == nil then
        Data.Delete("mp_prop", sub.propSid)
    else
        Data.Set("mp_prop", sub.propSid, I.StorageSerialize(sub))
    end
end

local function newSub(ent, sid, title)
    local I = Inv()
    local sub = I.NewStorage(ent, {
        kind = "grid", title = title,
        w = math.Clamp(Config.Get("mp", "propertyW"), 1, 31), h = math.Clamp(Config.Get("mp", "propertyH"), 1, 31),
        noDeposit = true,
        onChanged = function(s) saveSub(s) end,
    })
    sub.propSid = sid
    I.StorageLoad(sub, Data.Get("mp_prop", sid))
    return sub
end

-- One sub-storage per player, made when they open it.
local function variant(storage, ply)
    local sid = ply:SteamID64() or "0"
    local sub = storage.subs[sid]
    -- (reloaded whenever nobody has it open, so two lockers never hold two copies)
    if sub and next(sub.viewers) == nil then
        storage.subs[sid] = nil
        sub = nil
    end
    if not sub then
        sub = newSub(storage.ent, sid, "Property: " .. ply:Nick())
        storage.subs[sid] = sub
    end
    return sub
end

local function setup(ent)
    local I = Inv()
    if not I then return nil end
    return I.GetStorage(ent) or I.CreateStorage(ent, { kind = "grid", w = 1, h = 1, title = "Property locker", variant = variant })
end

-- MP.StoreProperty(ply, list) -> leftover list. Adds { id, count, data }
-- entries to ply's saved property and closes any open copy so it reloads.
-- Returns what didn't fit (same shape). Server only.
function MP.StoreProperty(ply, list)
    local I = Inv()
    if not I then return list end
    local sid = ply:SteamID64() or "0"
    -- Into the saved rows (any open copy is dropped, so it reloads).
    local tmp = newSub(NULL, sid, "")
    local over = {}
    for _, e in ipairs(list) do
        local left = I.StorageAdd(tmp, e.id, e.count or 1, e.data)
        if left > 0 then over[#over + 1] = { id = e.id, count = left, data = e.data } end
    end
    saveSub(tmp)
    for _, ent in ipairs(ents.FindByClass("rhylib_property_locker")) do
        local st = I.GetStorage(ent)
        local sub = st and st.subs[sid]
        if sub then
            for v in pairs(sub.viewers) do if IsValid(v) then I.CloseStorage(v) end end
            st.subs[sid] = nil
        end
    end
    return over
end

-- MP.OpenProperty(ply, ent): opens ply's own property at locker ent, if
-- they have any and aren't jailed. Server only.
function MP.OpenProperty(ply, ent)

    if not setup(ent) then
        ply:PrintMessage(HUD_PRINTCENTER, "Needs rhylib_inventory")
        return
    end
    if MP.IsJailed(ply) then
        ply:PrintMessage(HUD_PRINTCENTER, "Not while you're in jail")
        return
    end
    local data = Data.Get("mp_prop", ply:SteamID64() or "0")
    if not (istable(data) and #data > 0) then
        ply:PrintMessage(HUD_PRINTCENTER, "Nothing of yours is in here")
        return
    end
    Inv().OpenStorage(ply, ent)
end
