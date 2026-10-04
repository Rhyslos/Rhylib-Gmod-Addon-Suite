--[[
    Searching: an MP with the stun baton in hand (RMB on a player) sees
    that player's inventory, backpack and back slot. Taking items needs
    the player to be cuffed; taken items go to the MP's inventory.

    Hidden items: a player can hide up to 3 contraband items (rhylib_inventory,
    data.hidden). Each search rolls once per hidden item: the MP's
    U(0, 100) x searchMult (rhylib_skills Thorough search) plus a size
    bonus against the player's U(0, 100); the MP sees it only if theirs is
    higher. Rolls are kept for searchMemory seconds per MP and target, so
    searching again doesn't roll again.

    Messages:
      mp.search  client -> server  target (open), or NULL (close)
      mp.list    server -> MP      target, cuffed, then the items
      mp.take    client -> server  target, item uid
]]

local MP = Rhylib.MP
local Items = Rhylib.Items

Rhylib.Net.Register("mp.list")

MP.searching = MP.searching or {}   -- [mp] = target
MP.searchSig = MP.searchSig or {}   -- [mp] = rough checksum of the last list sent

local function inv()
    if not Items then Items = Rhylib.Items end
    return Items and Rhylib.Inventory and Rhylib.Inventory.Get and Rhylib.Inventory or nil
end

-- Reach of the search tool in hand: the baton, or another tool that answers
-- Rhylib.MPSearchTool with true (baton reach) or its own reach (the datapad).
-- (no tool: an MP can still search by hand from the interaction wheel)
local function toolRange(ply)
    local w = ply:GetActiveWeapon()
    if not IsValid(w) then return MP.Cfg("searchRange") end
    if w:GetClass() == "rhylib_stunbaton" then return MP.Cfg("searchRange") end
    local r = hook.Run("Rhylib.MPSearchTool", ply, w)
    if r == true then return MP.Cfg("searchRange") end
    return tonumber(r) or MP.Cfg("searchRange")
end

local function canSearch(mp, target)
    if not (IsValid(mp) and IsValid(target) and mp:Alive() and target:Alive()) then return false end
    if mp == target or not MP.IsMP(mp) or MP.IsCuffed(mp) or mp.rhylibDown then return false end
    local r = toolRange(mp)
    if not r then return false end
    if mp:GetPos():DistToSqr(target:GetPos()) > r * r then return false end
    local rag = Rhylib.Lying and Rhylib.Lying.Ragdoll and Rhylib.Lying.Ragdoll(target)   -- (a lying target's own body)
    local tr = util.TraceLine({ start = mp:EyePos(), endpos = target:WorldSpaceCenter(), filter = rag and { mp, target, rag } or { mp, target }, mask = MASK_SOLID })
    return not tr.Hit
end
MP.CanSearch = canSearch

MP.searchRolls = MP.searchRolls or {}   -- [mp] = { [target] = { at, found = { [uid] = bool } } }

-- Size bonus for the MP's roll: bigger things are easier to find.
local function sizeBonus(def)
    local cells = def and (def.w or 1) * (def.h or 1) or 1
    if cells >= 5 then return 20 elseif cells >= 3 then return 10 elseif cells >= 2 then return 5 end
    return 0
end

local function isHidden(target, o)
    return o.data and o.data.hidden ~= nil and o.data.hidden == target:SteamID64() and Items.IsContraband(o.id)
end

-- Does this MP see item o of target? Rolled once, then remembered.
function MP.SearchFinds(mp, target, o)
    if not isHidden(target, o) then return true end
    local byT = MP.searchRolls[mp]
    if not byT then byT = {} MP.searchRolls[mp] = byT end
    local r = byT[target]
    if not r or CurTime() - r.at > MP.Cfg("searchMemory") then
        r = { at = CurTime(), found = {} }
        byT[target] = r
    end
    local f = r.found[o.uid]
    if f == nil then
        local mult = 1
        local K = Rhylib.Skills
        if K and K.Has and K.Has(mp, "thorough_search") then mult = K.Cfg("searchMult") or 1.2 end
        local mine = math.Rand(0, 100) * mult + sizeBonus(Items.defs[o.id])
        local theirs = math.Rand(0, 100)
        f = mine > theirs
        r.found[o.uid] = f
    end
    return f
end

-- Items as rows: uid, item net id, count, fill, container.
function MP.SendList(mp, target)
    local I = inv()
    if not I then return end
    local st = I.Get(target)
    local list = {}
    local sig, n = 0, 0
    for _, o in pairs(st.byUid) do
        if MP.SearchFinds(mp, target, o) then list[#list + 1] = o end
        n = n + 1
        sig = sig + o.uid * 7 + (o.count or 1) * 13 + (o.c or 1)
    end
    MP.searchSig[mp] = sig + n + (MP.IsCuffed(target) and 1000000 or 0)
    table.sort(list, function(a, b) return (a.c or 0) * 1000 + a.uid < (b.c or 0) * 1000 + b.uid end)
    Rhylib.Net.Start("mp.list")
    net.WriteEntity(target)
    net.WriteBool(MP.IsCuffed(target))
    net.WriteUInt(math.min(#list, 255), 8)
    for i = 1, math.min(#list, 255) do
        local o = list[i]
        net.WriteUInt(o.uid, Items.UID_BITS)
        net.WriteUInt(Items.NetId(o.id), Items.NET_BITS)
        net.WriteUInt(math.Clamp(o.count or 1, 0, 255), 8)
        net.WriteUInt(math.Clamp(math.floor((o.data and o.data.fill or 1) * 100 + 0.5), 0, 100), 7)
        net.WriteUInt(o.c or 1, Items.CONT_BITS)
    end
    net.Send(mp)
end

Rhylib.Net.Receive("mp.search", function(mp)
    local target = net.ReadEntity()
    if not IsValid(target) then
        MP.searching[mp] = nil
        return
    end
    if not target:IsPlayer() or not canSearch(mp, target) or not inv() then return end
    MP.searching[mp] = target
    MP.SendList(mp, target)
    -- Tell them once per search, not on every reopen.
    if (target.rhylibSearchMsg or 0) < CurTime() then
        target.rhylibSearchMsg = CurTime() + 20
        target:ChatPrint(mp:Nick() .. " is searching you")
    end
end, { rate = 3, burst = 3 })

Rhylib.Net.Receive("mp.take", function(mp)
    local target = net.ReadEntity()
    local I = inv()
    if not I then return end
    local uid = net.ReadUInt(Items.UID_BITS)
    if MP.searching[mp] ~= target or not canSearch(mp, target) then return end
    if not MP.IsCuffed(target) then return end
    local st = I.Get(target)
    local o = st.byUid[uid]
    if not o or not MP.SearchFinds(mp, target, o) then return end
    if not Items.CanLeave(st, o) then
        mp:ChatPrint("Empty the backpack first")
        return
    end
    -- A gun keeps its current clip and cell.
    I.Internal.captureWeapon(target, o)
    local id, count, data = o.id, o.count or 1, table.Copy(o.data or {})
    data.hidden = nil
    I.Internal.removeInst(target, st, uid)
    I.AddOrDrop(mp, id, count, data)
    MP.SendList(mp, target)
    hook.Run("Rhylib.MPConfiscated", mp, target, id, count)
end, { rate = 8, burst = 8 })

local function sigOf(target)
    local I = inv()
    if not I then return 0 end
    local sig, n = 0, 0
    for _, o in pairs(I.Get(target).byUid) do
        n = n + 1
        sig = sig + o.uid * 7 + (o.count or 1) * 13 + (o.c or 1)
    end
    return sig + n + (MP.IsCuffed(target) and 1000000 or 0)
end

-- Keep an open search list fresh while it's open (and drop it when it isn't allowed any more).
timer.Create("Rhylib.MP.Search", 1, 0, function()
    if next(MP.searching) == nil then return end
    for mp, target in pairs(MP.searching) do
        if canSearch(mp, target) then
            if sigOf(target) ~= MP.searchSig[mp] then MP.SendList(mp, target) end
        else
            MP.searching[mp] = nil
            MP.searchSig[mp] = nil
            if IsValid(mp) then
                Rhylib.Net.Start("mp.list")
                net.WriteEntity(NULL)
                net.WriteBool(false)
                net.WriteUInt(0, 8)
                net.Send(mp)
            end
        end
    end
end)

Rhylib.Hook.Add("PlayerDisconnected", "mp.search", function(ply)
    MP.searching[ply] = nil
    MP.searchSig[ply] = nil
    MP.searchRolls[ply] = nil
    for _, byT in pairs(MP.searchRolls) do byT[ply] = nil end
    for m, t in pairs(MP.searching) do
        if t == ply then MP.searching[m] = nil end
    end
end)

--------------------------------------------------------------------------
-- Interaction wheel (rhylib_menus): cuff (timed), uncuff, escort
--------------------------------------------------------------------------

Rhylib.Net.Register("mp.wheelx")

local function cuffable(t)
    if not IsValid(t) or not t:Alive() or MP.IsCuffed(t) then return false end
    return MP.IsStunned(t) or t.rhylibDown and true or false
end

local function near(mp, t, slack)
    if not (IsValid(mp) and IsValid(t) and mp:Alive() and t:Alive()) then return false end
    local r = MP.Cfg("cuffRange") + (slack or 30)
    if mp:GetPos():DistToSqr(t:GetPos()) > r * r then return false end
    local rag = Rhylib.Lying and Rhylib.Lying.Ragdoll and Rhylib.Lying.Ragdoll(t)
    local tr = util.TraceLine({ start = mp:EyePos(), endpos = t:WorldSpaceCenter(), filter = rag and { mp, t, rag } or { mp, t }, mask = MASK_SOLID })
    return not tr.Hit
end

local function stopCuff(mp, tell)
    timer.Remove("Rhylib.MP.WheelCuff." .. mp:EntIndex())
    if tell and IsValid(mp) then
        Rhylib.Net.Start("mp.wheelx")
        net.Send(mp)
    end
end

-- op 0 cuff (cuffTime, stay close and still), 1 uncuff, 2 escort / let go
Rhylib.Net.Receive("mp.wheel", function(mp)
    local op, t = net.ReadUInt(2), net.ReadEntity()
    if not MP.IsMP(mp) or MP.IsCuffed(mp) or mp.rhylibDown or not IsValid(t) or not t:IsPlayer() then return end
    if op == 0 then
        if not mp:HasWeapon("rhylib_handcuffs") or not cuffable(t) or not near(mp, t) then return stopCuff(mp, true) end
        local from, ends = mp:GetPos(), CurTime() + MP.Cfg("cuffTime")
        local name = "Rhylib.MP.WheelCuff." .. mp:EntIndex()
        timer.Create(name, 0.1, 0, function()
            if not IsValid(mp) then return timer.Remove(name) end
            if not IsValid(t) or not cuffable(t) or not near(mp, t, 50) or mp:GetPos():DistToSqr(from) > 40 * 40
                or not MP.IsMP(mp) or mp.rhylibDown or MP.IsCuffed(mp) or not mp:HasWeapon("rhylib_handcuffs") then
                return stopCuff(mp, true)
            end
            if CurTime() >= ends then
                stopCuff(mp, false)
                MP.Cuff(t, mp)
            end
        end)
    elseif op == 1 then
        if MP.IsCuffed(t) and near(mp, t) then MP.Uncuff(t, mp) end
    elseif op == 2 then
        if MP.EscortedBy(t) == mp then
            MP.SetEscort(t, nil)
        elseif MP.IsCuffed(t) and near(mp, t) then
            MP.SetEscort(t, mp)
        end
    end
end, { rate = 4, burst = 4 })
