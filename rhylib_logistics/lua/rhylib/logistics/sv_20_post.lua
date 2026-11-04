--[[
    Command post (server): what its window shows (cl_20_post.lua), per
    viewer (L.Access):
      everyone      Logistics: supply crates, medical crates, ammo cabinets
                    and armouries (rhylib_armoury) within postRadius, with
                    the items left in each crate; Respawn tickets and
                    Garrison (stage 2: shown as not set up yet).
      technicians   + Sensor arrays: every beacon on the map: label, who
                    set it, power left, Jammed / Running / No power,
                    droids inside now, seconds since its last alert.
      officers      + Orders (stage 2: shown as not set up yet).

    Net logi.post (server -> that player): Entity post, UInt 2 access,
    UInt 32 length, compressed JSON { supplies = { {name, kind, left, dist} },
    beacons = { {label, owner, power, state, count, ago} } }. Sent on E
    (once a second at most) and on Refresh: net logi.postreq (client ->
    server): Entity post, within 300 units, rate 1/s.

    Command posts are saved per map when made permanent
    (Rhylib.Perma.Placements "logistics": Data "logistics_places",
    console rhylib_logistics_save, permission rhylib.logistics.admin).
]]

local L = Rhylib.Logistics

Rhylib.Net.Register("logi.post")

local UNITS_PER_M = 52.49

-- What a supply entity is, and what's left in it (nil = it never runs out).
local function supplyOf(e)
    local kind = e.ArmouryKind
    if kind == "crate" then
        local I = Rhylib.Inventory
        local st = I and I.GetStorage and I.GetStorage(e)
        local n = 0
        for _, inst in pairs(st and st.items or {}) do n = n + (tonumber(inst.count) or 1) end
        return e.CrateStock == "medCrate" and "Medical" or "Ammo", n
    elseif kind == "ammo" then
        return "Ammo", nil
    elseif kind == "armoury" then
        return "Weapons", nil
    end
end

local function build(ply, post, access)
    local data = { supplies = {}, beacons = {} }
    local r = math.max(100, L.Cfg("postRadius"))
    local pos = post:GetPos()
    for _, e in ipairs(ents.FindInSphere(pos, r)) do
        if IsValid(e) and e.ArmouryKind then
            local kind, left = supplyOf(e)
            if kind then
                data.supplies[#data.supplies + 1] = { name = e.PrintName or e:GetClass(), kind = kind, left = left or -1,
                    dist = math.floor(e:GetPos():Distance(pos) / UNITS_PER_M) }
            end
        end
    end
    table.sort(data.supplies, function(a, b) return a.dist < b.dist end)
    if access >= L.ACCESS_TECH then
        local now = CurTime()
        for e, b in pairs(L.beacons or {}) do
            if IsValid(e) then
                local power = math.max(0, e:GetPowerEnd() - now)
                data.beacons[#data.beacons + 1] = {
                    label = e:GetLabel(), owner = IsValid(b.owner) and b.owner:Nick() or "?",
                    power = math.floor(power), state = power <= 0 and "No power" or (e:GetJammed() and "Jammed" or "Running"),
                    count = b.count or 0, ago = (b.at or 0) > 0 and math.floor(now - b.at) or -1,
                    dist = math.floor(e:GetPos():Distance(pos) / UNITS_PER_M),
                }
            end
        end
        table.sort(data.beacons, function(a, b) return a.count > b.count or (a.count == b.count and a.label < b.label) end)
    end
    return data
end

local function send(ply, post)
    Rhylib.Perms.Check(ply, "rhylib.logistics.admin", function(admin)
        if not (IsValid(ply) and IsValid(post)) then return end
        local access = L.Access(ply, admin)
        local json = util.Compress(util.TableToJSON(build(ply, post, access)) or "{}") or ""
        Rhylib.Net.Start("logi.post")
        net.WriteEntity(post)
        net.WriteUInt(access, 2)
        net.WriteUInt(#json, 32)
        net.WriteData(json, #json)
        net.Send(ply)
    end)
end

function L.OpenPost(ply, post)
    if (ply.rhylibPostAt or 0) > CurTime() then return end
    ply.rhylibPostAt = CurTime() + 1
    send(ply, post)
end

Rhylib.Net.Receive("logi.postreq", function(ply)
    local post = net.ReadEntity()
    if not (IsValid(post) and post:GetClass() == "rhylib_command_post") then return end
    if ply:GetPos():DistToSqr(post:GetPos()) > 300 * 300 then return end
    send(ply, post)
end, { rate = 1, burst = 2 })

-- Command posts stay where they're placed (made permanent).
if Rhylib.Perma and Rhylib.Perma.Placements then
    L.PostPlaces = Rhylib.Perma.Placements("logistics", {
        classes = { "rhylib_command_post" },
        dataModule = "logistics_places",
        command = "rhylib_logistics_save",
        perm = "rhylib.logistics.admin",
    })
end
