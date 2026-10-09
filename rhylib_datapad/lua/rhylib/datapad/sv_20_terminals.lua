--[[
    Battalion computers and the medical holotable (server).

      dp.term    server -> player: the computer's state and its entries
      dp.tread   entity, entry id -> dp.tbody
      dp.tup     upload your notes here
      dp.tdel    moderator: delete an entry
      dp.tban    moderator: ban the author of an entry from uploading here
      dp.tunban  moderator: lift a ban (sid)
      dp.tset    admin: set the battalion of a computer

    Placements: rhylib_datapad_save (Data "dp_places"/map, with battalion).
]]

local D = Rhylib.Datapad

Rhylib.Net.Register("dp.term")
Rhylib.Net.Register("dp.tbody")

local function sid(ply) return ply:SteamID64() or "" end
local function isMed(ent) return ent:GetClass() == "rhylib_med_holotable" end
local function keyOf(ent) return isMed(ent) and D.MED_KEY or ent:GetBattalion() end

local function near(ply, ent)
    if not IsValid(ent) or not (ent:GetClass() == "rhylib_bn_computer" or isMed(ent)) then return false end
    local r = D.Cfg("useRange")
    return ply:Alive() and ply:GetPos():DistToSqr(ent:GetPos()) <= r * r
end

-- What a player may do here. admin comes from the permission check.
-- Only members read a computer (medics the holotable). Admins too only use
-- their own, unless inspecting (rhylib_datapad_inspect).
local function access(ply, ent, admin)
    local insp = admin and ply.rhylibDpInspect or false
    local a = {}
    local own
    if isMed(ent) then
        own = D.IsMedic(ply)
        a.upload = own
        a.mod = insp or (own and (admin or D.IsCommander(ply)))
        a.admin = admin and (own or insp)
    else
        local bn = ent:GetBattalion()
        own = bn ~= "" and D.Battalion(ply) == bn
        a.upload = own
        a.mod = insp or (own and (admin or D.IsCommander(ply)))
        a.admin = admin and (own or insp or bn == "")
    end
    a.view = own or insp
    a.foreign = insp and not own   -- shown as "admin inspection"
    a.rawAdmin = admin
    return a
end

-- Run fn(admin) after the permission check (CAMI can answer later).
local function withAdmin(ply, fn)
    Rhylib.Perms.Check(ply, "rhylib.datapad.admin", function(ok)
        if IsValid(ply) then fn(ok) end
    end)
end

-- The pad notes that would go to this computer.
local function uploadable(ply, ent)
    local want = isMed(ent) and D.KIND_MED or D.KIND_LOG
    local n = 0
    for _, note in ipairs(D.Pad(ply)) do
        if (note.k or 0) == want then n = n + 1 end
    end
    return n
end

function D.SendTerminal(ply, ent)
    withAdmin(ply, function(admin)
        if not near(ply, ent) then return end
        local key = keyOf(ent)
        local a = access(ply, ent, admin)
        local book = key ~= "" and D.Book(key) or { list = {} }
        Rhylib.Net.Start("dp.term")
        net.WriteEntity(ent)
        net.WriteString(isMed(ent) and "" or ent:GetBattalion())
        net.WriteBool(a.view)
        net.WriteBool(a.mod)
        net.WriteBool(admin)
        net.WriteBool(a.foreign)
        net.WriteBool(key ~= "" and D.Banned(key, sid(ply)))
        net.WriteUInt(a.upload and math.min(uploadable(ply, ent), 255) or 0, 8)
        local list = a.view and book.list or {}
        local n = math.min(#list, 255)
        net.WriteUInt(n, 8)
        for i = 1, n do
            local e = list[i]
            net.WriteUInt(e.id, 20)
            net.WriteString(e.a or "?")
            net.WriteString(e.ti or "")
            net.WriteString(e.pn or "")
            net.WriteUInt(e.t or 0, 32)
            net.WriteBool(e.mp or false)
        end
        -- Ban list for moderators.
        local bans = {}
        if a.mod and key ~= "" then
            for k, name in pairs(D.Load("dp_ban", key, {})) do
                if isstring(k) and string.sub(k, 1, 1) == "s" then bans[#bans + 1] = { string.sub(k, 2), name } end
            end
        end
        net.WriteUInt(math.min(#bans, 255), 8)
        for i = 1, math.min(#bans, 255) do
            net.WriteString(bans[i][1])
            net.WriteString(tostring(bans[i][2]))
        end
        net.Send(ply)
    end)
end

function D.UseTerminal(ent, ply)
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end
    D.SendTerminal(ply, ent)
end

-- Every terminal message: near the computer, then h.run(ply, ent, access, arg).
-- h.read reads the rest of the message now (the permission check can answer later).
local function recv(name, h, limits)
    Rhylib.Net.Receive(name, function(ply)
        local ent = net.ReadEntity()
        local arg = h.read and h.read() or nil
        if not near(ply, ent) then return end
        withAdmin(ply, function(admin)
            if not near(ply, ent) then return end
            h.run(ply, ent, access(ply, ent, admin), arg)
        end)
    end, limits or { rate = 4, burst = 6 })
end

-- For the board, search and stats files.
D.TermRecv, D.TermAccess, D.TermNear, D.IsMedTerm, D.TermKey = recv, access, near, isMed, keyOf

local function findEntry(book, id)
    for i, e in ipairs(book.list) do
        if e.id == id then return e, i end
    end
end

recv("dp.tread", {
    read = function() return net.ReadUInt(20) end,
    run = function(ply, ent, a, id)
        local key = keyOf(ent)
        if not a.view or key == "" then return end
        local e = findEntry(D.Book(key), id)
        if not e then return end
        Rhylib.Net.Start("dp.tbody")
        net.WriteUInt(e.id, 20)
        net.WriteString(e.b or "")
        net.Send(ply)
    end,
})

recv("dp.tup", {
    run = function(ply, ent, a)
        local key = keyOf(ent)
        if key == "" then
            ply:ChatPrint("This computer has no battalion yet (an admin sets it)")
            return
        end
        if not a.upload then
            ply:ChatPrint(isMed(ent) and "Only medics upload here" or "This isn't your battalion's computer")
            return
        end
        if D.Banned(key, sid(ply)) then
            ply:ChatPrint("You're banned from uploading here")
            return
        end
        local want = isMed(ent) and D.KIND_MED or D.KIND_LOG
        local pad, keep, book = D.Pad(ply), {}, D.Book(key)
        local mp, n = D.IsMP(ply), 0
        for _, note in ipairs(pad) do
            if (note.k or 0) == want then
                table.insert(book.list, 1, {
                    id = book.next, s = sid(ply), a = ply:Nick(), ti = note.ti, b = note.b,
                    t = note.t or os.time(), mp = mp or nil, p = note.p, pn = note.pn,
                })
                book.next = book.next + 1
                n = n + 1
            else
                keep[#keep + 1] = note
            end
        end
        if n == 0 then return end
        local cap = isMed(ent) and D.Cfg("medCap") or D.Cfg("logCap")
        while #book.list > cap do table.remove(book.list) end
        D.Store("dp_log", key, book)
        D.Store("dp_pad", sid(ply), keep)
        if not isMed(ent) and not D.HasBattalion(key) then
            local idx = D.Battalions()
            idx[#idx + 1] = key
            D.Store("dp_log", "__index", idx)
        end
        if Rhylib.MP and Rhylib.MP.IndexPlayer then Rhylib.MP.IndexPlayer(sid(ply), ply:Nick()) end
        ply:ChatPrint("Uploaded " .. n .. " note" .. (n == 1 and "" or "s"))
        D.SendTerminal(ply, ent)
        if D.Holding(ply) then D.SendState(ply) end  -- an open datapad sees the change
    end,
}, { rate = 2, burst = 3 })

recv("dp.tdel", {
    read = function() return net.ReadUInt(20) end,
    run = function(ply, ent, a, id)
        local key = keyOf(ent)
        if not a.mod or key == "" then return end
        local book = D.Book(key)
        local _, i = findEntry(book, id)
        if not i then return end
        table.remove(book.list, i)
        D.Store("dp_log", key, book)
        D.SendTerminal(ply, ent)
    end,
})

recv("dp.tban", {
    read = function() return net.ReadUInt(20) end,
    run = function(ply, ent, a, id)
        local key = keyOf(ent)
        if not a.mod or key == "" then return end
        local e = findEntry(D.Book(key), id)
        if not e or not e.s or e.s == "" or e.s == sid(ply) then return end
        local bans = D.Load("dp_ban", key, {})
        bans["s" .. e.s] = e.a or "?"
        D.Store("dp_ban", key, bans)
        ply:ChatPrint((e.a or "?") .. " can no longer upload here")
        D.SendTerminal(ply, ent)
    end,
})

recv("dp.tunban", {
    read = function() return net.ReadString() end,
    run = function(ply, ent, a, id)
        local key = keyOf(ent)
        if not a.mod or key == "" then return end
        local bans = D.Load("dp_ban", key, {})
        if bans["s" .. id] == nil then return end
        bans["s" .. id] = nil
        D.Store("dp_ban", key, bans)
        D.SendTerminal(ply, ent)
    end,
})

recv("dp.tset", {
    read = function() return D.Clip(net.ReadString(), 64) end,
    run = function(ply, ent, a, bn)
        -- The window's button only sets a new computer; changing one is a command.
        if not a.rawAdmin or isMed(ent) or ent:GetBattalion() ~= "" then return end
        if string.sub(bn, 1, 2) == "__" then return end  -- reserved Data keys
        ent:SetBattalion(bn)
        D.SavePlacements(true)
        if Rhylib.Perma and not Rhylib.Perma.Is(ent) then
            ply:ChatPrint("Battalion set. Make the computer permanent (toolgun Permanent tool) to keep it after a map change")
        end
        D.SendTerminal(ply, ent)
    end,
}, { rate = 2, burst = 3 })

--------------------------------------------------------------------------
-- Admin commands
--------------------------------------------------------------------------

-- rhylib_datapad_inspect: toggle reading any battalion computer / the holotable.
concommand.Add("rhylib_datapad_inspect", function(ply)
    if not IsValid(ply) then return end
    withAdmin(ply, function(admin)
        if not admin then ply:ChatPrint("Admins only") return end
        ply.rhylibDpInspect = not ply.rhylibDpInspect or nil
        ply:ChatPrint(ply.rhylibDpInspect and "Inspecting: you can read and moderate every computer (run again to stop)"
            or "Inspection off: only your own battalion's computer")
    end)
end)

-- rhylib_datapad_setbattalion <name>: change (or with no name, clear) the
-- battalion of the computer you're looking at.
concommand.Add("rhylib_datapad_setbattalion", function(ply, _, args, argStr)
    if not IsValid(ply) then return end
    withAdmin(ply, function(admin)
        if not admin then ply:ChatPrint("Admins only") return end
        local tr = ply:GetEyeTrace()
        local ent = tr.Entity
        if not IsValid(ent) or ent:GetClass() ~= "rhylib_bn_computer" or tr.HitPos:DistToSqr(ply:EyePos()) > 400 * 400 then
            ply:ChatPrint("Look at a battalion computer")
            return
        end
        local bn = D.Clip(string.Trim(argStr or ""), 64)
        if string.sub(bn, 1, 2) == "__" then return end
        ent:SetBattalion(bn)
        D.SavePlacements(true)
        ply:ChatPrint(bn ~= "" and ("Computer set to the " .. bn) or "Computer cleared (set it again from its window)")
    end)
end)

--------------------------------------------------------------------------
-- Placements
--------------------------------------------------------------------------

local CLASSES = { "rhylib_bn_computer", "rhylib_med_holotable" }

-- quiet: only re-save a map that was saved before (keeps a battalion change).
function D.SavePlacements(quiet)
    if quiet and not istable(Rhylib.Data.Get("dp_places", game.GetMap())) then return 0 end
    local rows = {}
    for _, class in ipairs(CLASSES) do
        for _, e in ipairs(ents.FindByClass(class)) do
            if (not Rhylib.Perma or Rhylib.Perma.Is(e)) then   -- (only permanent ones, 2026-10-09u)
                local p, an = e:GetPos(), e:GetAngles()
                rows[#rows + 1] = { class = class, pos = { p.x, p.y, p.z }, ang = { an.p, an.y, an.r },
                    bn = e.GetBattalion and e:GetBattalion() or "" }
            end
        end
    end
    Rhylib.Data.Set("dp_places", game.GetMap(), rows)
    return #rows
end

local function loadPlaces()
    local rows = Rhylib.Data.Get("dp_places", game.GetMap())
    if not istable(rows) then return end
    for _, class in ipairs(CLASSES) do
        for _, e in ipairs(ents.FindByClass(class)) do e:Remove() end
    end
    for _, r in ipairs(rows) do
        local e = ents.Create(r.class)
        if IsValid(e) then
            e:SetPos(Vector(r.pos[1], r.pos[2], r.pos[3]))
            e:SetAngles(Angle(r.ang[1], r.ang[2], r.ang[3]))
            e:Spawn()
            if e.SetBattalion then e:SetBattalion(r.bn or "") end
            if Rhylib.Perma then Rhylib.Perma.Mark(e, true) end
        end
    end
end
if Rhylib.Perma and Rhylib.Perma.Register then Rhylib.Perma.Register(CLASSES, function() return D.SavePlacements() end) end
Rhylib.Hook.Add("InitPostEntity", "datapad.places", function() timer.Simple(1, loadPlaces) end)
Rhylib.Hook.Add("PostCleanupMap", "datapad.places", loadPlaces)

concommand.Add("rhylib_datapad_save", function(ply)
    Rhylib.Perms.Check(ply, "rhylib.datapad.admin", function(ok)
        local function reply(m) if IsValid(ply) then ply:ChatPrint(m) else print(m) end end
        if not ok then reply("You don't have permission for rhylib_datapad_save") return end
        reply("Saved " .. D.SavePlacements() .. " datapad computers for " .. game.GetMap())
    end)
end)
