--[[
    Jail (server). Cells and terminals are entities placed by admins and
    saved per map (rhylib_mp_save). An MP at a terminal jails a cuffed
    prisoner who is near it (or whom they're escorting):
      - their items go to evidence (issued gear goes back to the armoury)
      - they're uncuffed and put in the emptiest cell
      - the sentence counts down only while they're online, and survives
        reconnects and map changes (Data "mp_jail" / SteamID64)
      - a prisoner who leaves the cell area is put back
      - when the time is up (or an MP releases them early) they stay in
        the cell, "awaiting processing"
      - processing (an MP at the terminal, or processAuto seconds later):
        they respawn at the property locker (rhylib_property_locker) and
        their evidence waits in it for them, minus contraband
        (rhylib_inventory config contraband) and anything an MP
        withheld. No locker on the map: straight into their inventory.

    Messages (all checked: MP, near the terminal):
      mp.term     server -> MP  the terminal's lists
      mp.jail     MP -> server  terminal, prisoner, minutes, reason
      mp.release  MP -> server  terminal, prisoner (serving: end the
                                sentence; awaiting: process them)
      mp.destroy  MP -> server  terminal, prisoner, evidence index:
                                withhold it / give it back (toggle)
]]

local MP = Rhylib.MP
local Data = Rhylib.Data

MP.jailed = MP.jailed or {}   -- [ply] = record { ends, why, by, cell, awaiting, processAt,
                              --   evidence = { {id, count, data, c, withheld} } }
local jailed = MP.jailed

Rhylib.Net.Register("mp.term")
Rhylib.Perms.Register("rhylib.mp.admin", "admin", "Save jail cell and terminal placements")

local function inv() return Rhylib.Inventory and Rhylib.Inventory.Get and Rhylib.Inventory or nil end
local function sid(ply) return ply:SteamID64() or "0" end

local function save(ply)
    local rec = jailed[ply]
    if not rec then return end
    -- Stored as seconds left, so time only passes while they're online.
    Data.Set("mp_jail", sid(ply), {
        left = math.max(0, rec.ends - CurTime()), why = rec.why, by = rec.by, evidence = rec.evidence,
        awaiting = rec.awaiting or nil,
        processLeft = rec.awaiting and math.max(0, (rec.processAt or 0) - CurTime()) or nil,
    })
end

local function cells()
    return ents.FindByClass("rhylib_jail_cell")
end

-- A random cell, out of those with the fewest prisoners in them.
local function freeCell()
    local list = cells()
    if #list == 0 then return nil end
    local pick, bestN = {}, nil
    for _, c in ipairs(list) do
        local n = 0
        for _, rec in pairs(jailed) do
            if rec.cell == c then n = n + 1 end
        end
        if not bestN or n < bestN then
            pick, bestN = { c }, n
        elseif n == bestN then
            pick[#pick + 1] = c
        end
    end
    return pick[math.random(#pick)]
end

local function stripToStowed(ply)
    ply:StripWeapons()
    if weapons.GetStored("rhylib_stowed") then
        ply:Give("rhylib_stowed")
        ply:SelectWeapon("rhylib_stowed")
    end
end

local function putInCell(ply)
    local rec = jailed[ply]
    if not rec then return end
    if not IsValid(rec.cell) then rec.cell = freeCell() end
    if not IsValid(rec.cell) then return end
    ply:SetPos(rec.cell:GetPos() + Vector(0, 0, 4))
    ply:SetEyeAngles(Angle(0, rec.cell:GetAngles().y, 0))
    ply:SetVelocity(-ply:GetVelocity())
end

local function setState(ply)
    local rec = jailed[ply]
    -- (awaiting: the end is in the past, so JailLeft is 0 but IsJailed holds)
    ply:SetNW2Float("rhylib_jailEnd", rec and math.max(rec.ends, 1) or 0)
    ply:SetNW2String("rhylib_jailWhy", rec and rec.why or "")
    ply:SetNW2Bool("rhylib_jailAwait", rec and rec.awaiting or false)
end

-- Everything the prisoner carries becomes evidence; issued gear is just removed.
local function confiscate(ply)
    local I = inv()
    if not I then return {} end
    local st = I.Get(ply)
    local list = {}
    for _, o in pairs(st.byUid) do list[#list + 1] = o end
    -- Contents before what holds them (backpack, holster: worn slots).
    local worn = Rhylib.Items and Rhylib.Items.IsWorn or function(c) return c == 3 end
    table.sort(list, function(a, b) return (worn(a.c) and 1 or 0) < (worn(b.c) and 1 or 0) end)
    local evidence = {}
    for _, o in ipairs(list) do
        I.Internal.captureWeapon(ply, o)
        if not (o.data and o.data.issued) then
            evidence[#evidence + 1] = { id = o.id, count = o.count or 1, data = table.Copy(o.data or {}), c = o.c }
        end
        I.Internal.removeInst(ply, st, o.uid)
    end
    return evidence
end

--------------------------------------------------------------------------
-- Records (looked up on the datapad): Data "mp_rec"/SteamID64 = list of
-- arrests; Data "mp_idx"/"all" = { ["s" .. sid] = name } of everyone on
-- file (prefixed: JSON would turn a bare SteamID64 key into a rounded number).
--------------------------------------------------------------------------

MP.REC_MAX = 50

function MP.IndexPlayer(sid, name)
    if not sid or sid == "" or sid == "0" then return end
    local idx = Data.Get("mp_idx", "all")
    if not istable(idx) then idx = {} end
    if idx["s" .. sid] == name then return end
    idx["s" .. sid] = name
    Data.Set("mp_idx", "all", idx)
end

function MP.GetRecord(sid)
    local r = Data.Get("mp_rec", sid)
    return istable(r) and r or {}
end

local function addRecord(ply, by, minutes, why)
    local id = ply:SteamID64()
    if not id then return end
    local r = MP.GetRecord(id)
    table.insert(r, 1, { t = os.time(), by = by, min = minutes, why = why })
    while #r > MP.REC_MAX do table.remove(r) end
    Data.Set("mp_rec", id, r)
    MP.IndexPlayer(id, ply:Nick())
end

function MP.Jail(ply, by, minutes, why)
    if not IsValid(ply) or jailed[ply] then return false end
    local cell = freeCell()
    if not IsValid(cell) then return false, "No jail cells on this map" end
    minutes = math.Clamp(math.floor(minutes), 1, MP.Cfg("maxSentence"))
    local rec = {
        ends = CurTime() + minutes * 60,
        why = string.sub(why ~= "" and why or "No reason given", 1, 80),
        by = IsValid(by) and by:Nick() or "?",
        cell = cell,
        evidence = confiscate(ply),
    }
    jailed[ply] = rec
    if MP.IsCuffed(ply) then MP.Uncuff(ply) end
    stripToStowed(ply)
    putInCell(ply)
    setState(ply)
    save(ply)
    addRecord(ply, rec.by, minutes, rec.why)
    ply:ChatPrint(string.format("Jailed by %s for %d min: %s", rec.by, minutes, rec.why))
    hook.Run("Rhylib.PlayerJailed", ply, by, minutes, rec.why)
    return true
end

-- Sentence over (time up, or an MP ends it early): wait in the cell to be processed.
function MP.EndSentence(ply, by)
    local rec = jailed[ply]
    if not rec or rec.awaiting then return end
    rec.awaiting = true
    rec.ends = math.min(rec.ends, CurTime())
    rec.processAt = CurTime() + MP.Cfg("processAuto")
    setState(ply)
    save(ply)
    ply:ChatPrint((IsValid(by) and ("Released by " .. by:Nick() .. ".") or "Your sentence is over.")
        .. " Wait to be processed: an MP at the terminal, or automatically in " .. math.ceil(MP.Cfg("processAuto") / 60) .. " min.")
end

-- Evidence that goes back: not withheld by an MP, not contraband.
function MP.Returnable(e)
    local Items = Rhylib.Items
    return not e.withheld and not (Items and Items.IsContraband and Items.IsContraband(e.id))
end

-- The property locker processed prisoners walk out to (the nearest to their cell).
local function propertyLocker(rec)
    local best, bestD
    local from = IsValid(rec.cell) and rec.cell:GetPos() or vector_origin
    for _, e in ipairs(ents.FindByClass("rhylib_property_locker")) do
        local d = e:GetPos():DistToSqr(from)
        if not bestD or d < bestD then best, bestD = e, d end
    end
    return best
end

-- Processed: out of jail, at the property locker with their things in it.
function MP.Process(ply, by)
    local rec = jailed[ply]
    if not rec then return end
    jailed[ply] = nil
    local back = {}
    for _, e in ipairs(rec.evidence or {}) do
        if MP.Returnable(e) then back[#back + 1] = e end
    end
    -- Worn things (backpack, holster) before their contents, so they can hold them.
    local worn = Rhylib.Items and Rhylib.Items.IsWorn or function(c) return c == 3 end
    table.sort(back, function(a, b) return (worn(a.c) and 0 or 1) < (worn(b.c) and 0 or 1) end)
    local locker = propertyLocker(rec)
    local I = inv()
    if I then
        local over = back
        if IsValid(locker) and MP.StoreProperty then over = MP.StoreProperty(ply, back) end
        for _, e in ipairs(over) do I.AddOrDrop(ply, e.id, e.count, e.data) end
        if I.Save then I.Save(ply) end
    end
    Data.Delete("mp_jail", sid(ply))
    setState(ply)
    ply:Spawn()
    if IsValid(locker) then
        timer.Simple(0.1, function()
            if not (IsValid(ply) and IsValid(locker)) or jailed[ply] then return end
            local pos = locker:GetPos() + locker:GetForward() * 50 + Vector(0, 0, 4)
            ply:SetPos(pos)
            ply:SetEyeAngles((locker:GetPos() - pos):Angle())
        end)
    end
    local kept = #(rec.evidence or {}) - #back
    ply:ChatPrint((IsValid(by) and ("Processed by " .. by:Nick() .. ". ") or "Processed. ")
        .. (IsValid(locker) and "Your things are in the property locker" or "Your things are back")
        .. (kept > 0 and (" (" .. kept .. " kept as evidence)") or "") .. ".")
    hook.Run("Rhylib.PlayerReleased", ply, by)
end

-- One step: serving -> awaiting -> processed.
function MP.Release(ply, by)
    local rec = jailed[ply]
    if not rec then return end
    if rec.awaiting then MP.Process(ply, by) else MP.EndSentence(ply, by) end
end

-- Time up, or wandered off.
timer.Create("Rhylib.MP.Jail", 1, 0, function()
    if next(jailed) == nil then return end
    local now = CurTime()
    local r = MP.Cfg("jailRadius")
    for ply, rec in pairs(jailed) do
        if not IsValid(ply) then
            jailed[ply] = nil
        elseif rec.awaiting and now >= (rec.processAt or 0) then
            MP.Process(ply)
        else
            if not rec.awaiting and now >= rec.ends then MP.EndSentence(ply) end
            if ply:Alive() and IsValid(rec.cell) and ply:GetPos():DistToSqr(rec.cell:GetPos()) > r * r then
                putInCell(ply)
            end
        end
    end
end)

-- Respawning while jailed: back in the cell, no weapons.
Rhylib.Hook.Add("PlayerSpawn", "mp.jail", function(ply)
    if not jailed[ply] then return end
    timer.Simple(0, function()
        if IsValid(ply) and jailed[ply] then
            stripToStowed(ply)
            putInCell(ply)
        end
    end)
end, 50)

Rhylib.Hook.Add("PlayerLoadout", "mp.jail", function(ply)
    if jailed[ply] then return true end  -- no job weapons in jail
end)

-- Rejoining: pick the sentence (or the wait for processing) back up.
Rhylib.Hook.Add("PlayerInitialSpawn", "mp.jail", function(ply)
    local rec = Data.Get("mp_jail", sid(ply))
    if not istable(rec) then return end
    -- (time ran out just before they left: awaiting too, so nothing is lost)
    if rec.awaiting or ((rec.left or 0) <= 0 and istable(rec.evidence) and #rec.evidence > 0) then
        jailed[ply] = { ends = CurTime(), why = rec.why or "", by = rec.by or "?", evidence = rec.evidence or {},
            awaiting = true, processAt = CurTime() + math.min(rec.processLeft or MP.Cfg("processAuto"), MP.Cfg("processAuto")) }
        setState(ply)
    elseif (rec.left or 0) > 0 then
        jailed[ply] = { ends = CurTime() + rec.left, why = rec.why or "", by = rec.by or "?", evidence = rec.evidence or {} }
        setState(ply)
    else
        Data.Delete("mp_jail", sid(ply))
    end
end)

Rhylib.Hook.Add("PlayerDisconnected", "mp.jail", function(ply)
    if jailed[ply] then
        save(ply)
        jailed[ply] = nil
    end
end)

Rhylib.Hook.Add("ShutDown", "mp.jail", function()
    for ply in pairs(jailed) do
        if IsValid(ply) then save(ply) end
    end
end, -10)  -- before Data flushes at 0

Rhylib.Hook.Add("playerCanChangeTeam", "mp.jailjob", function(ply)
    if jailed[ply] then return false, "You can't change job in jail" end
end)

--------------------------------------------------------------------------
-- Terminal
--------------------------------------------------------------------------

local function nearTerminal(ply, term)
    return IsValid(term) and term:GetClass() == "rhylib_jail_terminal" and ply:GetPos():DistToSqr(term:GetPos()) <= MP.TERM_USE * MP.TERM_USE
end

-- Cuffed players near the terminal, or escorted by this MP.
local function candidates(mp, term)
    local out = {}
    local r = MP.Cfg("terminalRange")
    for _, p in ipairs(player.GetAll()) do
        if p ~= mp and MP.IsCuffed(p) and not jailed[p]
            and (MP.EscortedBy(p) == mp or p:GetPos():DistToSqr(term:GetPos()) <= r * r) then
            out[#out + 1] = p
        end
    end
    return out
end

function MP.OpenTerminal(mp, term)
    if not MP.IsMP(mp) then
        mp:PrintMessage(HUD_PRINTCENTER, "Military police only")
        return
    end
    local Items = Rhylib.Items
    local cand = candidates(mp, term)
    Rhylib.Net.Start("mp.term")
    net.WriteEntity(term)
    net.WriteUInt(math.min(#cand, 31), 5)
    for i = 1, math.min(#cand, 31) do net.WriteEntity(cand[i]) end
    local list = {}
    for p in pairs(jailed) do if IsValid(p) then list[#list + 1] = p end end
    net.WriteUInt(math.min(#list, 63), 6)
    for i = 1, math.min(#list, 63) do
        local p = list[i]
        local rec = jailed[p]
        net.WriteEntity(p)
        net.WriteString(rec.why)
        net.WriteBool(rec.awaiting or false)
        net.WriteFloat(rec.awaiting and (rec.processAt or 0) or 0)
        local ev = rec.evidence or {}
        net.WriteUInt(math.min(#ev, 63), 6)
        for j = 1, math.min(#ev, 63) do
            net.WriteUInt(Items and Items.NetId(ev[j].id) or 0, Items and Items.NET_BITS or 10)
            net.WriteUInt(math.Clamp(ev[j].count or 1, 0, 255), 8)
            net.WriteBool(ev[j].withheld or false)
            net.WriteBool(Items and Items.IsContraband and Items.IsContraband(ev[j].id) or false)
        end
    end
    net.Send(mp)
end

Rhylib.Net.Receive("mp.jail", function(mp)
    local term, p = net.ReadEntity(), net.ReadEntity()
    local minutes = net.ReadUInt(7)
    local why = string.Trim(net.ReadString())
    if not MP.IsMP(mp) or not nearTerminal(mp, term) or not IsValid(p) or not p:IsPlayer() then return end
    local ok = false
    for _, c in ipairs(candidates(mp, term)) do
        if c == p then ok = true break end
    end
    if not ok then
        mp:ChatPrint("They need to be cuffed and at the terminal")
        return
    end
    local done, err = MP.Jail(p, mp, minutes, why)
    if not done and err then mp:ChatPrint(err) end
    MP.OpenTerminal(mp, term)
end, { rate = 2, burst = 3 })

Rhylib.Net.Receive("mp.release", function(mp)
    local term, p = net.ReadEntity(), net.ReadEntity()
    if not MP.IsMP(mp) or not nearTerminal(mp, term) or not IsValid(p) or not jailed[p] then return end
    MP.Release(p, mp)
    MP.OpenTerminal(mp, term)
end, { rate = 2, burst = 3 })

Rhylib.Net.Receive("mp.destroy", function(mp)
    local term, p = net.ReadEntity(), net.ReadEntity()
    local i = net.ReadUInt(6)
    local netId = net.ReadUInt(Rhylib.Items and Rhylib.Items.NET_BITS or 10)
    local count = net.ReadUInt(8)
    if not MP.IsMP(mp) or not nearTerminal(mp, term) or not IsValid(p) then return end
    local rec = jailed[p]
    local e = rec and rec.evidence and rec.evidence[i]
    if not e then return end
    -- The list may have changed since the MP's window was filled.
    local Items = Rhylib.Items
    if (Items and Items.NetId(e.id) or 0) ~= netId or math.min(e.count or 1, 255) ~= count then
        MP.OpenTerminal(mp, term)
        return
    end
    e.withheld = not e.withheld or nil
    save(p)
    MP.OpenTerminal(mp, term)
end, { rate = 6, burst = 6 })

--------------------------------------------------------------------------
-- Placements
--------------------------------------------------------------------------

local CLASSES = { "rhylib_jail_cell", "rhylib_jail_terminal", "rhylib_property_locker" }
Rhylib.PLACEMENT_CLASSES = Rhylib.PLACEMENT_CLASSES or {}
for _, c in ipairs(CLASSES) do Rhylib.PLACEMENT_CLASSES[c] = true end

concommand.Add("rhylib_mp_save", function(ply)
    Rhylib.Perms.Check(ply, "rhylib.mp.admin", function(ok)
        if not ok then
            if IsValid(ply) then ply:ChatPrint("You don't have permission for rhylib_mp_save") end
            return
        end
        local list = {}
        for _, class in ipairs(CLASSES) do
            for _, e in ipairs(ents.FindByClass(class)) do
                local pos, ang = e:GetPos(), e:GetAngles()
                list[#list + 1] = { class = class, pos = { pos.x, pos.y, pos.z }, ang = { ang.p, ang.y, ang.r } }
            end
        end
        Data.Set("mp_places", game.GetMap(), list)
        local msg = "Saved " .. #list .. " jail cells, terminals and property lockers for " .. game.GetMap()
        if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
    end)
end)

local function loadPlaces()
    local list = Data.Get("mp_places", game.GetMap())
    if not istable(list) then return end
    for _, class in ipairs(CLASSES) do
        for _, e in ipairs(ents.FindByClass(class)) do e:Remove() end
    end
    for _, it in ipairs(list) do
        local e = ents.Create(it.class)
        if IsValid(e) then
            e:SetPos(Vector(it.pos[1], it.pos[2], it.pos[3]))
            e:SetAngles(Angle(it.ang[1], it.ang[2], it.ang[3]))
            e:Spawn()
            local phys = e:GetPhysicsObject()
            if IsValid(phys) then phys:EnableMotion(false) end
        end
    end
end
Rhylib.Hook.Add("InitPostEntity", "mp.places", loadPlaces)
Rhylib.Hook.Add("PostCleanupMap", "mp.places", loadPlaces)
