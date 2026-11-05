--[[
    Rhy's Logistics (server): garrison tickets and call-ins (settings in
    sh_40_stock.lua).

    Garrison: !garrison [on <n> | off | add <n> | set <n>]
    (rhylib.logistics.admin). Global2 rhylib_garrison_on / rhylib_garrison.
    L.SpendGarrison(n) -> how many could be spent (all n while it's off).
    The Reinforcements skill (rhylib_skills K.CallReinforcements) asks
    L.GarrisonAllows(n) and calls L.SpendGarrison(made) while it's on.

    Call-ins: net logi.call (client -> server): Entity post, UInt 3 call
    index (L.CALLS). Officers (L.Access 3) within 300 units of a command
    post; jammed officers can't (ply.rhylibJammed, rhylib_radio). Each
    call starts its server-wide cooldown (Global2 rhylib_call_<id>) and
    arrives after callDelay s:
      squad    D.CallSquad round the officer (rhylib_droids), one garrison
               ticket per clone; only as many as there are tickets.
      supply   an armoury resupply crate next to the post.
      ammo     the callAmmoCrates crates (rhylib_armoury), filled.
      medical  a medical crate (rhylib_med_crate).
    Called crates go after callCrateLife s unless made permanent.
]]

local L = Rhylib.Logistics
L.callStamp = L.callStamp or {}   -- [call id] = the latest call's token

-- ---------------------------------------------------------------------------
-- Garrison

local function setGarrison(on, n)
    SetGlobal2Bool("rhylib_garrison_on", on and true or false)
    if n then SetGlobal2Int("rhylib_garrison", math.Clamp(math.floor(n), 0, 99999)) end
end

function L.GarrisonAllows(n)
    if not L.GarrisonOn() then return n end
    return math.min(n, L.Garrison())
end

function L.SpendGarrison(n)
    if not L.GarrisonOn() then return n end
    local have = L.Garrison()
    local spent = math.min(have, n)
    setGarrison(true, have - spent)
    if have - spent <= 0 and spent > 0 then
        Rhylib.Notify(true, "Garrison tickets are out: no more clone squads can be called", "bad", "Logistics")
    end
    return spent
end

Rhylib.Command.Add({
    name = "rhylib_garrison", chat = { "garrison" }, perm = "rhylib.logistics.admin", tag = "Logistics",
    args = "[on <n> | off | add <n> | set <n>]", help = "Garrison tickets for an event: officers spend one per clone they call in",
    fn = function(ply, args)
        local op = string.lower(args[1] or "")
        local n = tonumber(args[2] or "")
        if op == "" then
            return L.GarrisonOn() and ("Garrison tickets are on: " .. L.Garrison() .. " left") or "Garrison tickets are off: clone call-ins are free (!garrison on <n>)", "info"
        elseif op == "on" then
            setGarrison(true, n or L.Cfg("garrisonStart"))
            Rhylib.Notify(true, "Garrison tickets are on: " .. L.Garrison(), "info", "Logistics")
            return
        elseif op == "off" then
            setGarrison(false)
            Rhylib.Notify(true, "Garrison tickets are off", "info", "Logistics")
            return
        elseif op == "add" and n then
            setGarrison(L.GarrisonOn(), L.Garrison() + n)
        elseif op == "set" and n then
            setGarrison(L.GarrisonOn(), n)
        else
            return "Use !garrison on <n>, off, add <n> or set <n>", "bad"
        end
        return "Garrison tickets: " .. L.Garrison() .. (L.GarrisonOn() and "" or " (off: !garrison on to use them)"), "good"
    end,
})

-- ---------------------------------------------------------------------------
-- Call-ins


-- A free spot on the ground round the post (i-th of a few).
local function spotNear(post, i)
    local base = post:GetPos()
    local r = math.max(post:BoundingRadius() + 60, 110)
    for try = 0, 11 do
        local a = math.rad((i * 67 + try * 30) % 360)
        local p = base + Vector(math.cos(a), math.sin(a), 0) * (r + (try >= 6 and 60 or 0))
        local tr = util.TraceLine({ start = p + Vector(0, 0, 60), endpos = p - Vector(0, 0, 200), mask = MASK_SOLID_BRUSHONLY })
        if tr.Hit and tr.HitNormal.z > 0.7 then
            local hull = util.TraceHull({ start = tr.HitPos + Vector(0, 0, 4), endpos = tr.HitPos + Vector(0, 0, 4),
                mins = Vector(-28, -28, 0), maxs = Vector(28, 28, 50), mask = MASK_SOLID })
            local clear = util.TraceLine({ start = base + Vector(0, 0, 40), endpos = tr.HitPos + Vector(0, 0, 40), mask = MASK_SOLID_BRUSHONLY })
            if not hull.Hit and not clear.Hit then return tr.HitPos end
        end
    end
    return nil
end

local function dropCrate(post, class, i)
    if not scripted_ents.GetStored(class) then return nil end
    local p = spotNear(post, i)
    if not p then return nil end
    local e = ents.Create(class)
    if not IsValid(e) then return nil end
    e:SetPos(p)
    e:SetAngles(Angle(0, math.random(0, 359), 0))
    e:Spawn()
    e:Activate()
    -- (sit on the ground)
    local mins = e:OBBMins()
    e:SetPos(p - Vector(0, 0, mins.z))
    local fx = EffectData()
    fx:SetOrigin(p)
    util.Effect("ThumperDust", fx, true, true)
    e:EmitSound("physics/metal/metal_box_impact_hard" .. math.random(1, 3) .. ".wav", 75)
    local life = L.Cfg("callCrateLife")
    if life and life > 0 then
        -- (being carried or opened right then: tried again a minute later)
        local function expire()
            if not IsValid(e) or (Rhylib.Perma and Rhylib.Perma.Is and Rhylib.Perma.Is(e)) then return end
            if e.GetCarried and e:GetCarried() then timer.Simple(60, expire) return end
            e:Remove()
        end
        timer.Simple(life, expire)
    end
    return e
end

local ARRIVE = {}

ARRIVE.supply = function(ply, post)
    return dropCrate(post, "rhylib_resupply_crate", 1) and "An armoury resupply crate is at the command post: carry it to an armoury"
end

ARRIVE.ammo = function(ply, post)
    local n = 0
    local list = L.Cfg("callAmmoCrates")
    for i, class in ipairs(istable(list) and list or {}) do
        if dropCrate(post, class, i + 1) then n = n + 1 end
    end
    return n > 0 and ("Ammo crates are at the command post (" .. n .. ")")
end

ARRIVE.medical = function(ply, post)
    return dropCrate(post, "rhylib_med_crate", 5) and "A medical crate is at the command post"
end

-- (the squad comes to the officer; checked again on arrival)
local function squadKinds()
    local kinds = L.Cfg("callSquad")
    if not istable(kinds) then return {} end
    local out = {}
    for i = 1, L.GarrisonAllows(#kinds) do out[i] = kinds[i] end
    return out
end

ARRIVE.squad = function(ply, post)
    local D = Rhylib.Droids
    if not (D and D.CallSquad and IsValid(ply) and ply:Alive()) then return nil end
    local kinds = squadKinds()
    if #kinds == 0 then return nil end
    local made = D.CallSquad(ply, kinds, L.Cfg("callSquadLife"))
    if made == 0 then return nil end
    L.SpendGarrison(made)
    return made .. " clones have arrived and fall in on you"
end

-- Why a call can't be made now (nil = it can).
local function refuse(ply, c)
    if L.CallReady(c.id) > 0 then
        local s = math.ceil(L.CallReady(c.id))
        return string.format("%s ready in %d:%02d", c.title, math.floor(s / 60), s % 60)
    end
    if ply.rhylibJammed then return "Comms are jammed here: the call can't get out" end
    if c.id == "squad" then
        local D = Rhylib.Droids
        if not (D and D.CallSquad) then return "Clone squads aren't available on this server" end
        if L.GarrisonOn() and L.Garrison() <= 0 then return "No garrison tickets left" end
        if #squadKinds() == 0 then return "No clone squad is set up (logistics callSquad)" end
    elseif c.id == "supply" then
        if not L.Cfg("stockOn") then return "Armoury stock is off: armouries never run out" end
        if not Rhylib.Has("armoury") then return "Resupply crates need Rhy's Armoury" end
    elseif not Rhylib.Has("armoury") then
        return "Crates need Rhy's Armoury"
    end
end

Rhylib.Net.Receive("logi.call", function(ply)
    local post = net.ReadEntity()
    local c = L.CALLS[net.ReadUInt(3)]
    if not (c and IsValid(post) and post.IsRhylibCommandPost) then return end
    if ply:GetPos():DistToSqr(post:GetPos()) > 300 * 300 then return end
    Rhylib.Perms.Check(ply, "rhylib.logistics.admin", function(admin)
        if not (IsValid(ply) and IsValid(post) and ply:Alive()) then return end
        if L.Access(ply, admin) < L.ACCESS_OFFICER then
            return Rhylib.Notify(ply, "Only officers can call things in", "bad", "Logistics")
        end
        local why = refuse(ply, c)
        if why then return Rhylib.Notify(ply, why, "bad", "Logistics") end
        local delay = math.max(0, L.Cfg("callDelay"))
        local stamp = {}
        L.callStamp[c.id] = stamp
        SetGlobal2Float("rhylib_call_" .. c.id, CurTime() + math.max(0, L.Cfg(c.cd)))
        -- (didn't come: the cooldown goes, unless a later call set its own)
        local function giveBack(why)
            if L.callStamp[c.id] == stamp then SetGlobal2Float("rhylib_call_" .. c.id, 0) end
            if IsValid(ply) then Rhylib.Notify(ply, c.title .. " couldn't get through (" .. why .. ")", "bad", "Logistics") end
        end
        Rhylib.Print("logistics", "%s called in: %s", ply:Nick(), c.title)
        Rhylib.Notify(ply, c.title .. " called in: arriving in " .. math.Round(delay) .. " s", "good", "Logistics")
        ply:EmitSound("npc/combine_soldier/vo/affirmative.wav", 65, 105)
        timer.Simple(delay, function()
            if not IsValid(post) then return giveBack("the command post is gone") end
            local done = ARRIVE[c.id](ply, post)
            local hear = {}
            for _, p in ipairs(player.GetAll()) do
                if p == ply or p:GetPos():DistToSqr(post:GetPos()) < 1200 * 1200 then hear[#hear + 1] = p end
            end
            if done then
                Rhylib.Notify(hear, done, "good", "Logistics")
            else
                giveBack("no room by the post, or none left")
            end
        end)
    end)
end, { rate = 1, burst = 2 })
