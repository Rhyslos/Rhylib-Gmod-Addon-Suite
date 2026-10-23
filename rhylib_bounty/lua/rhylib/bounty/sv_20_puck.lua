--[[
    Bounty Puck (server). A player with a puck in their inventory switches
    it on or off (LMB with it in hand, or right-click the item); it keeps
    beeping while holstered. It tracks the target of one of their
    contracts (R with the puck in hand picks the next one).

    Beeps play from the player (EmitSound, config puckLevel), so people
    nearby hear them too. Rhythm by distance to the target (config
    puckFar / puckMid / puckClose, ×skillMults.puckRange with Tuned puck):
      further than puckFar   every 5 s, low
      puckMid .. puckFar     every 3 s
      puckClose .. puckMid   3 s down to 0.6 s, pitch rising
      within puckClose       every 0.3 s, highest
    No target (offline, dead, gone, bounty closed): a low double blip every
    5 s. In a comms jammer (rhylib_radio), the holder's or the target's:
    static every 3 s, unless the holder has Relentless.
    Nothing but the beeps reaches the client: no position, no direction.

    State: player NW2Bool rhylib_puckOn, NW2Int rhylib_puckBid (the bounty
    tracked; 0 = the first contract carried).
    Message: bounty.puck  client -> server: op (UInt 2: 0 on/off, 1 next
    target). Rate 4/s.
]]

local B = Rhylib.Bounty
local Net = Rhylib.Net

B.pucks = B.pucks or {}   -- [ply] = next beep time (players with it on)

-- The contracts (instances) a player carries whose bounty is still open.
local function contracts(ply)
    local out = {}
    for _, inst in ipairs(B.Carried(ply, B.CONTRACT)) do
        local bid = istable(inst.data) and inst.data.bid
        if bid and B.list[bid] then out[#out + 1] = B.list[bid] end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

-- B.PuckTarget(ply): the bounty the player's puck tracks, or nil.
function B.PuckTarget(ply)
    local list = contracts(ply)
    local want = ply:GetNW2Int("rhylib_puckBid", 0)
    for _, b in ipairs(list) do if b.id == want then return b end end
    return list[1]
end

-- B.SetPuck(ply, on)
function B.SetPuck(ply, on)
    ply:SetNW2Bool("rhylib_puckOn", on and true or false)
    B.pucks[ply] = on and CurTime() + 0.2 or nil
    ply:EmitSound(on and "buttons/button17.wav" or "buttons/button16.wav", 55, on and 110 or 90, 0.5)
end

local function hasPuck(ply)
    local I = Rhylib.Inventory
    if I and I.Has then return I.Has(ply, B.PUCK) end
    return ply:HasWeapon(B.PUCK)
end

Net.Receive("bounty.puck", function(ply)
    local op = net.ReadUInt(2)
    if not hasPuck(ply) then return end
    if op == 0 then
        B.SetPuck(ply, not ply:GetNW2Bool("rhylib_puckOn", false))
    elseif op == 1 then
        local list = contracts(ply)
        if #list == 0 then return B.Msg(ply, false, "Puck: no contract to track") end
        local cur = B.PuckTarget(ply)
        local i = 1
        for n, b in ipairs(list) do if cur and b.id == cur.id then i = n % #list + 1 end end
        ply:SetNW2Int("rhylib_puckBid", list[i].id)
        B.Msg(ply, true, "Puck tracking " .. list[i].name)
    end
end, { rate = 4, burst = 4 })

-- Where the target is now, or nil (offline, dead, gone).
local function targetPos(b)
    if b.kind == "npc" then
        return IsValid(b.ent) and b.ent:Health() > 0 and b.ent:GetPos() or nil, b.ent
    end
    local p = player.GetBySteamID64(b.sid)
    if IsValid(p) and p:Alive() then return p:GetPos(), p end
    return nil
end

local function jammed(ply)
    return ply.rhylibJammed == true
end

local function beep(ply, pitch, snd, vol)
    ply:EmitSound(snd or "buttons/blip1.wav", tonumber(B.Cfg("puckLevel")) or 62, pitch, vol or 0.6, CHAN_ITEM)
end

timer.Create("Rhylib.Bounty.Puck", 0.1, 0, function()
    local now = CurTime()
    for ply, nextAt in pairs(B.pucks) do
        if not IsValid(ply) then
            B.pucks[ply] = nil
        elseif not hasPuck(ply) then
            B.SetPuck(ply, false)
        elseif now >= nextAt and ply:Alive() then
            local b = B.PuckTarget(ply)
            local pos, tent = nil, nil
            if b then pos, tent = targetPos(b) end
            local relentless = B.Has(ply, "bh_relentless")
            if not relentless and (jammed(ply) or (IsValid(tent) and tent:IsPlayer() and jammed(tent))) then
                beep(ply, 100, "ambient/levels/prison/radio_random" .. math.random(1, 9) .. ".wav", 0.3)
                B.pucks[ply] = now + 3
            elseif not pos then
                beep(ply, 70)
                timer.Simple(0.15, function() if IsValid(ply) then beep(ply, 65) end end)
                B.pucks[ply] = now + 5
            else
                local m = B.Has(ply, "bh_puck") and B.Mult("puckRange") or 1
                local far = (tonumber(B.Cfg("puckFar")) or 6000) * m
                local mid = (tonumber(B.Cfg("puckMid")) or 2500) * m
                local close = (tonumber(B.Cfg("puckClose")) or 300) * m
                local d = ply:GetPos():Distance(pos)
                local gap, pitch
                if d > far then gap, pitch = 5, 90
                elseif d > mid then gap, pitch = 3, 100
                elseif d > close then
                    local f = (d - close) / math.max(1, mid - close)   -- 1 at mid, 0 at close
                    gap, pitch = Lerp(f, 0.6, 3), Lerp(f, 122, 100)
                else gap, pitch = 0.3, 132 end
                beep(ply, math.floor(pitch))
                B.pucks[ply] = now + gap
            end
        end
    end
end)

Rhylib.Hook.Add("PlayerDisconnected", "bounty.puck", function(ply) B.pucks[ply] = nil end)
