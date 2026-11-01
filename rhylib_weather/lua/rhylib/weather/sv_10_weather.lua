--[[
    Weather on the server: lightning strikes and comms disruption (the
    look of the weather is all client side).

    Lightning (storm, heavystorm; setting lightning): every few seconds
    (W.KINDS[kind].lightning, closer together when stronger) a strike
    lands near a random player who is outdoors (800-4000 units away, on
    the ground under open sky). Net weather.bolt (server -> everyone):
    Vector ground, Vector top of the bolt, UInt 16 seed (the bolt's shape,
    the same on every screen). In a heavy storm (disrupt kinds, from
    disruptFrom) players outdoors within strikeJamRadius lose comms for
    1.5 s. Nothing starts until clients have faded the new weather in.

    Disruption (heavystorm, blizzard, sandstorm from disruptFrom; setting
    disrupt): about every disruptEvery seconds / intensity, a burst of 3-7
    s cuts comms and the compass radar for everyone outdoors.

    W.JamFor(ply) -> true while the weather cuts this player's comms.
    rhylib_radio's jam timer asks it twice a second (and then marks the
    player NW2Bool rhylib_jamWx so the messages say it's the weather);
    the radio's usual reconnect time follows.
]]

local W = Rhylib.Weather

Rhylib.Net.Register("weather.bolt")

W.burstUntil = W.burstUntil or 0
local nextBurst, nextBolt = 0, 0

local tr = {}
local trIn = { mask = MASK_SOLID_BRUSHONLY, output = tr }
local function outdoors(p)
    local e = p:EyePos()
    trIn.start, trIn.endpos, trIn.mask = e, e + Vector(0, 0, 4000), MASK_SOLID_BRUSHONLY
    util.TraceLine(trIn)
    return tr.HitSky or not tr.Hit
end

-- (outdoors, checked at most once a second per player)
local function outdoorsCached(p)
    local now = CurTime()
    if (p.rhylibWxOutAt or 0) > now then return p.rhylibWxOut end
    p.rhylibWxOutAt = now + 1
    p.rhylibWxOut = outdoors(p)
    return p.rhylibWxOut
end

function W.JamFor(p)
    if not (IsValid(p) and p:Alive()) then return false end
    local now = CurTime()
    if (p.rhylibWxJamUntil or 0) > now then return true end
    if W.burstUntil > now and outdoorsCached(p) then return true end
    return false
end

-- A strike near a random outdoor player.
local function strike()
    local cands = {}
    for _, p in ipairs(player.GetAll()) do
        if p:Alive() and outdoorsCached(p) then cands[#cands + 1] = p end
    end
    if #cands == 0 then return end
    local p = cands[math.random(#cands)]
    for _ = 1, 6 do
        local a, r = math.Rand(0, math.pi * 2), math.Rand(800, 4000)
        local from = p:EyePos() + Vector(math.cos(a) * r, math.sin(a) * r, 0)
        -- (the sky above that spot, then down to the ground)
        trIn.start, trIn.endpos, trIn.mask = from, from + Vector(0, 0, 16000), MASK_SOLID_BRUSHONLY
        util.TraceLine(trIn)
        if not tr.StartSolid and (tr.HitSky or not tr.Hit) then
            local top = tr.HitPos - Vector(0, 0, 8)
            trIn.start, trIn.endpos, trIn.mask = top, top - Vector(0, 0, 20000), MASK_SOLID
            util.TraceLine(trIn)
            trIn.mask = MASK_SOLID_BRUSHONLY
            if tr.Hit and not tr.StartSolid then
                local ground = Vector(tr.HitPos)
                Rhylib.Net.Start("weather.bolt")
                net.WriteVector(ground)
                net.WriteVector(top)
                net.WriteUInt(math.random(0, 65535), 16)
                net.Broadcast()
                -- (only the heavy weathers' strikes cut comms)
                local k = W.KINDS[W.Kind()]
                if W.Cfg("disrupt") and k.disrupt and W.Intensity() >= W.Cfg("disruptFrom") then
                    local r2 = W.Cfg("strikeJamRadius") ^ 2
                    local until_ = CurTime() + 1.5
                    for _, q in ipairs(player.GetAll()) do
                        if q:Alive() and q:GetPos():DistToSqr(ground) < r2 and outdoorsCached(q) then
                            q.rhylibWxJamUntil = math.max(q.rhylibWxJamUntil or 0, until_)
                        end
                    end
                end
                return
            end
        end
        trIn.mask = MASK_SOLID_BRUSHONLY
    end
end

-- (clients fade a new weather in over fadeTime: no strikes or bursts
-- under a sky that hasn't changed yet)
local lastKind, settledAt = nil, 0
timer.Create("Rhylib.Weather.Server", 0.5, 0, function()
    local kind = W.Kind()
    local k = W.KINDS[kind]
    local amt = W.Intensity()
    local now = CurTime()
    if kind ~= lastKind then
        settledAt = lastKind and now + (tonumber(W.Cfg("fadeTime")) or 12) * (lastKind == "clear" and 1 or 2) or now
        lastKind = kind
        nextBurst, nextBolt = 0, 0
    end
    if now < settledAt then return end
    -- Comms bursts.
    if k.disrupt and W.Cfg("disrupt") and amt >= W.Cfg("disruptFrom") then
        if nextBurst == 0 then
            nextBurst = now + math.Rand(0.5, 1) * W.Cfg("disruptEvery") / amt
        elseif now >= nextBurst then
            W.burstUntil = now + math.Rand(3, 7)
            nextBurst = now + math.Rand(0.6, 1.4) * W.Cfg("disruptEvery") / amt
        end
    else
        nextBurst = 0
    end
    -- Lightning.
    if k.lightning and W.Cfg("lightning") and #player.GetAll() > 0 then
        if nextBolt == 0 then
            nextBolt = now + math.Rand(k.lightning[1], k.lightning[2]) / amt
        elseif now >= nextBolt then
            strike()
            nextBolt = now + math.Rand(k.lightning[1], k.lightning[2]) / amt
        end
    else
        nextBolt = 0
    end
end)
