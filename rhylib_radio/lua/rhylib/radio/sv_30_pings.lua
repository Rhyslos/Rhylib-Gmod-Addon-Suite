-- Squad pings, server side (sh_40_pings.lua has the overview).
local R = Rhylib.Radio

Rhylib.Net.Receive("radio.ping", function(ply)
    local k = net.ReadUInt(R.PING_BITS)
    local p = R.PINGS[k]
    if not p or not ply:Alive() then return end
    if (ply.rhylibPingAt or 0) > CurTime() then return end
    ply.rhylibPingAt = CurTime() + (R.Cfg("pingCooldown") or 0.6)
    local sq = R.squads[R.SquadOf(ply)]
    if not sq then R.Note(ply, "Join a squad to send pings") return end
    if ply.rhylibJammed then R.Note(ply, "Comms jammed: your ping didn't get through") return end
    local pos, ent
    if p.self then
        pos, ent = ply:GetPos(), ply
    else
        local eye = ply:EyePos()
        local tr = util.TraceLine({ start = eye, endpos = eye + ply:GetAimVector() * (R.Cfg("pingRange") or 12000), filter = ply, mask = MASK_SHOT })
        if not tr.Hit or tr.HitSky then R.Note(ply, "Aim at something to ping it") return end
        pos = tr.HitPos
        local e = tr.Entity
        if p.track and IsValid(e) and (e:IsNPC() or e:IsNextBot()) then ent = e end
    end
    local rec = {}
    for m in pairs(sq.members) do
        if IsValid(m) and not m.rhylibJammed then rec[#rec + 1] = m end
    end
    if #rec == 0 then return end
    Rhylib.Net.Start("radio.ping")
    net.WriteEntity(ply)
    net.WriteUInt(k, R.PING_BITS)
    net.WriteVector(pos)
    net.WriteEntity(ent or NULL)
    net.Send(rec)
end, { rate = 4, burst = 4 })
