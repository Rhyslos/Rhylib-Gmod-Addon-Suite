--[[
    Class mode on the server (see sh_30_class.lua).
    Data "skills" "classmode" = { on, epoch }; per player "c"..SteamID64 =
    { cls, order, epoch, picks } (only counts while its epoch is the
    current one and class mode is on). A class's skills are applied with
    K.SetSkills(ply, set, true), which doesn't save, so the player's own
    tree stays in Data "skills" "s"..sid and is simply loaded back.
    Nets: skills.classpick (class index 4 bits, order index 3 bits),
    skills.classleave, skills.classmode (bool, staff).
    Console: rhylib_classmode [0|1] (perm rhylib.skills.admin).
]]

local K = Rhylib.Skills
local Data = Rhylib.Data

Rhylib.Net.Register("skills.classpick")
Rhylib.Net.Register("skills.classleave")
Rhylib.Net.Register("skills.classmode")

local function rkey(ply) return "c" .. (ply:SteamID64() or "0") end

local function record(ply)
    if ply:IsBot() then return nil end
    local r = Data.Get("skills", rkey(ply))
    if istable(r) and r.epoch == K.ClassEpoch() and K.ClassMode() then return r end
    return nil
end

local function saveRecord(ply, r)
    if ply:IsBot() then return end
    if r then Data.Set("skills", rkey(ply), r) else Data.Delete("skills", rkey(ply)) end
end

-- Back to the player's own tree (re-read from Data).
function K.LeaveClass(ply, quiet)
    if not K.ClassOf(ply) then return end
    ply:SetNW2String("rhylib_class", "")
    ply.rhylibClassOrder = nil
    ply.rhylibSkillsLoaded = nil
    K.SetSkills(ply, K.Stored(ply), true)
    local r = record(ply)
    if r then
        r.cls, r.order = nil, nil
        saveRecord(ply, r)
    end
    if not quiet then K.Note(ply, "Back to your own skill tree") end
end

local function applyClass(ply, cls, orderId)
    -- (the command order only with the rank for it)
    if orderId and not K.RankOk(ply, "commandRank") then orderId = nil end
    ply:SetNW2String("rhylib_class", cls.id)
    ply.rhylibClassOrder = orderId
    K.SetSkills(ply, K.ClassSet(cls, orderId), true)
end

-- Picking a class (or switching to another one) uses a pick.
Rhylib.Net.Receive("skills.classpick", function(ply)
    local cls = K.CLASSES[net.ReadUInt(4)]
    local order = K.ORDERS[net.ReadUInt(3)]
    if not (cls and K.ClassMode()) then return end
    local ok, why = K.ClassAllowed(ply, cls)
    if not ok then return K.Note(ply, why, true) end
    local cur = K.ClassOf(ply)
    if cur == cls and (not cls.orders or ply.rhylibClassOrder == (order and order.skill)) then return end
    if K.ClassPicksLeft(ply) <= 0 then return K.Note(ply, "No class changes left until class mode is switched on again", true) end
    local orderId = cls.orders and order and order.skill or nil
    if cls.orders and not orderId then return K.Note(ply, "Pick a command order first", true) end
    local picks = ply:GetNW2Int("rhylib_classPicks", 0) + 1
    ply:SetNW2Int("rhylib_classPicks", picks)
    applyClass(ply, cls, orderId)
    saveRecord(ply, { cls = cls.id, order = orderId, epoch = K.ClassEpoch(), picks = picks })
    local note = "Playing " .. cls.name
    if cls.orders and orderId and not K.RankOk(ply, "commandRank") then
        note = note .. " (command orders need the rank " .. tostring(K.Cfg("commandRank")) .. ")"
    end
    K.Note(ply, note)
end, { rate = 2, burst = 3 })

Rhylib.Net.Receive("skills.classleave", function(ply)
    K.LeaveClass(ply)
end, { rate = 2, burst = 3 })

-- Switching class mode on (a fresh epoch: everyone gets their picks back)
-- or off (everyone back on their own tree).
function K.SetClassMode(on)
    on = on and true or false
    if on == K.ClassMode() then return end
    local epoch = K.ClassEpoch() + (on and 1 or 0)
    if not on then
        for _, p in ipairs(player.GetAll()) do K.LeaveClass(p, true) end
    end
    SetGlobal2Int("rhylib_classEpoch", epoch)
    SetGlobal2Bool("rhylib_classMode", on)
    Data.Set("skills", "classmode", { on = on, epoch = epoch })
    for _, p in ipairs(player.GetAll()) do
        p:SetNW2Int("rhylib_classPicks", 0)
        K.Note(p, on and "Class mode is on: pick a class on the Class page (Character), or keep your own tree"
            or "Class mode is off: you're back on your own skill tree")
    end
end

-- (permission rhylib.skills.admin is registered in sv_10_skills.lua)
local function staffToggle(ply, on)
    Rhylib.Perms.Check(ply, "rhylib.skills.admin", function(ok)
        if not ok then
            if IsValid(ply) then K.Note(ply, "You can't switch class mode", true) end
            return
        end
        K.SetClassMode(on)
    end)
end

Rhylib.Net.Receive("skills.classmode", function(ply)
    staffToggle(ply, net.ReadBool())
end, { rate = 1, burst = 2 })

concommand.Add("rhylib_classmode", function(ply, _, args)
    local on = args[1] == nil and not K.ClassMode() or args[1] == "1"
    staffToggle(IsValid(ply) and ply or nil, on)
end)

-- Saved state: class mode itself (at load and again once the map is up),
-- then each joining player's class.
local function loadMode()
    local d = Data.Get("skills", "classmode")
    if istable(d) then
        SetGlobal2Int("rhylib_classEpoch", tonumber(d.epoch) or 0)
        SetGlobal2Bool("rhylib_classMode", d.on == true)
    end
end
loadMode()
Rhylib.Hook.Add("InitPostEntity", "skills.classmode", loadMode)

-- The skills whose inventory grids a player should have (the inventory
-- loads before skills.class applies a class on joining).
function K.GridSet(ply)
    if K.ClassOf(ply) then return K.Stored(ply) end
    local r = record(ply)
    local cls = r and r.cls and K.classById[r.cls]
    if cls then return K.ClassSet(cls, r.order) end
    return K.Stored(ply)
end

Rhylib.Hook.Add("PlayerInitialSpawn", "skills.class", function(ply)
    if ply:IsBot() then return end
    local raw = Data.Get("skills", rkey(ply))
    local r = record(ply)
    if not r then
        if raw ~= nil then saveRecord(ply, nil) end   -- (from an older round of class mode)
        return
    end
    ply:SetNW2Int("rhylib_classPicks", tonumber(r.picks) or 0)
    -- (job rules aren't checked here: the job may not be set yet; medic and
    -- MP skills only work in those jobs anyway)
    local cls = r.cls and K.classById[r.cls]
    if cls then applyClass(ply, cls, r.order) end
end, 10)
