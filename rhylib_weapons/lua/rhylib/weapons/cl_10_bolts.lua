--[[
    Client bolt visuals. Purely cosmetic: damage is decided on the server.

    Bolts come from two places:
      - your own shots, spawned instantly by the weapon's predicted PrimaryAttack
      - other players' shots, from the batched "wep.shot" message
    The real bolt flies from the eyes. The visual flies in a straight line
    from the muzzle to where that eye line ends (the impact, or its far
    end), so it never bends and lands exactly where the shot lands.
]]

local W = Rhylib.Weapons
W.Bolts = W.Bolts or {}
local Bolts = W.Bolts
Bolts.visual = Bolts.visual or {}

-- Looks, by the weapon's BoltColor: colour, trail length, beam width,
-- glow size and how long the visual can live.
local STYLES = {
    -- (core: a thin white-hot centre line, so it reads as a bolt, not a glowing bullet)
    [1] = { color = Color(90, 150, 255), length = 90, width = 6.5, glow = 17, life = 1.2, core = true },   -- Republic blue
    [2] = { color = Color(255, 70, 60), length = 90, width = 6.5, glow = 17, life = 1.2, core = true },    -- CIS red
    [3] = { color = Color(80, 255, 120), length = 90, width = 6.5, glow = 17, life = 1.2, core = true },   -- green
    [4] = { color = Color(255, 170, 80), length = 140, width = 9, glow = 40, life = 6, rocket = true },  -- rocket
    [5] = { color = Color(14, 14, 14), length = 0, width = 1.8, glow = 0, life = 0.6, hook = true },    -- grapple hook
    [6] = { color = Color(120, 200, 255), length = 0, width = 0, glow = 22, life = 1.2, ring = 26 },     -- stun ring
    [7] = { color = Color(255, 225, 60), length = 70, width = 5, glow = 14, life = 1.2 },   -- training (yellow)
    [8] = { color = Color(255, 160, 40), length = 70, width = 5, glow = 14, life = 1.2 },   -- training droids (orange-yellow)
    [9] = { color = Color(255, 225, 60), length = 140, width = 9, glow = 40, life = 6, rocket = true },  -- training rocket
    [10] = { color = Color(150, 205, 255), length = 115, width = 9, glow = 26, life = 1.2, core = true },  -- overcharged (DC-15A)
}
-- BoltColor numbers for other addons.
Bolts.COLOR_TRAINING, Bolts.COLOR_TRAINING_ENEMY, Bolts.COLOR_TRAINING_ROCKET = 7, 8, 9
Bolts.COLOR_OVERCHARGE = 10
local COL_HOOK = Color(58, 60, 62)
local COL_CORE = Color(255, 255, 255, 220)
local HOOK_MINS, HOOK_MAXS = Vector(-6.75, -1.5, -1.5), Vector(2.25, 1.5, 1.5)

local matBeam = Material("trails/laser")
local matGlow = Material("sprites/light_glow02_add")
local matRing = Material("effects/select_ring")

local function muzzlePos(shooter, fallback, left)
    if not IsValid(shooter) then return fallback end

    local firstPerson = shooter == LocalPlayer() and not shooter:ShouldDrawLocalPlayer()
    local active = shooter.GetActiveWeapon and shooter:GetActiveWeapon()
    if IsValid(active) and active.GetPropMuzzle then
        local p = active:GetPropMuzzle(firstPerson, left)
        if p then return p end
    end

    if firstPerson then
        local vm = shooter:GetViewModel()
        local att = IsValid(vm) and vm:GetAttachment(1)
        return att and att.Pos or fallback
    end

    local wep = shooter.GetActiveWeapon and shooter:GetActiveWeapon()
    if IsValid(wep) then
        local id = wep:LookupAttachment("muzzle")
        local att = id and id > 0 and wep:GetAttachment(id)
        if att then return att.Pos end
    end
    return fallback
end

local traceResult = {}
local traceData = { mask = MASK_SHOT, output = traceResult }

--[[
    Each bolt is traced once, when it spawns, along its whole flight; after
    that it just moves along the line and stops where that trace hit. (A
    player who steps into its path later doesn't stop the visual; damage
    is the server's job anyway.) Nothing is allocated per frame.
]]
-- left: dual pistols, the shot came from the left gun (nil = ask the gun).
-- Near misses: someone else's bolt passing within WHIZZ_DIST of your head
-- whizzes past (once, when it gets there). Worked out once per bolt.
local whizzVar = CreateClientConVar("rhylib_whizz", "1", true, false, "Near-miss sounds for bolts flying past you")
local WHIZZ_DIST = 90
local nextWhizz = 0
-- lead: head start the visual catches up on (CATCHUP, see Bolts.Spawn).
local CATCHUP = 3
function Bolts.NearMiss(shooter, from, dir, len, speed, tr, lead)
    local me = LocalPlayer()
    if not IsValid(me) or shooter == me or not whizzVar:GetBool() or not me:Alive() then return end
    if tr.Entity == me then return end   -- (a hit, not a miss)
    local eye = me:EyePos()
    local t = (eye - from):Dot(dir)
    if t <= 0 or t >= len then return end
    local close = from + dir * t
    if close:DistToSqr(eye) > WHIZZ_DIST * WHIZZ_DIST then return end
    -- (CATCHUP x speed until the head start is made up, then normal speed)
    lead = lead or 0
    speed = math.max(speed, 1)
    local caught = lead * CATCHUP / (CATCHUP - 1)
    local delay = t <= caught and t / (speed * CATCHUP) or (t - lead) / speed
    timer.Simple(delay, function()
        local now = CurTime()
        if now < nextWhizz then return end
        nextWhizz = now + 0.07
        sound.Play(string.format("weapons/fx/nearmiss/bulletltor%02d.wav", math.random(3, 14)), close, 75, math.random(110, 130), 0.8)
    end)
end

-- ahead: seconds the server's bolt is ahead (its lag-compensated first
-- leg). The visual still leaves the muzzle but flies up to CATCHUP times
-- as fast until it has made that up (not hooks or stun rings).
function Bolts.Spawn(shooter, origin, dir, speed, colorIndex, left, ahead)
    local style = STYLES[colorIndex] or STYLES[1]
    local muzzle = muzzlePos(shooter, origin, left)
    local range = speed * style.life
    -- (the server's optional reach cap, boltRange; rockets, hooks and
    -- scoped guns keep their life)
    local cap = Rhylib.Weapons.BoltRange()
    local w = cap > 0 and IsValid(shooter) and shooter:IsPlayer() and shooter:GetActiveWeapon()
    if cap > 0 and not style.rocket and not style.hook and not (IsValid(w) and w.Scope) then
        range = math.min(range, cap)
    end
    traceData.start = origin
    traceData.endpos = origin + dir * range
    traceData.filter = IsValid(shooter) and shooter or nil
    util.TraceLine(traceData)
    local tr = traceResult
    local finish = Vector(tr.HitPos)
    -- Straight from the muzzle to the end of the real path.
    local path = finish - muzzle
    local len = path:Length()
    if len < 1 then
        muzzle, path, len = Vector(origin), Vector(dir), tr.Fraction * range
    else
        path:Div(len)
    end
    local lead = 0
    if ahead and ahead > 0 and not style.hook and not style.ring then lead = speed * ahead end
    if not style.hook and not style.ring then Bolts.NearMiss(shooter, muzzle, path, len, speed, tr, lead) end
    Bolts.visual[#Bolts.visual + 1] = {
        shooter = shooter,
        origin = muzzle,
        pos = Vector(muzzle),
        dir = path,
        speed = speed,
        style = style,
        born = CurTime(),
        travelled = 0,
        lead = lead,
        endDist = len,   -- (a miss ends here too: the end of the real path)
        hitDist = tr.Hit and len or nil,
        hitPos = tr.Hit and finish or nil,
        hitNormal = tr.Hit and Vector(tr.HitNormal) or nil,
        hitEnt = tr.Hit and tr.Entity or nil,
    }
end

-- Called by the weapon on the shooter's own client (first prediction only).
function Bolts.FireLocal(owner, weapon, origin, dir, opts)
    local speed = opts and opts.speed or weapon.BoltSpeed or 7000
    if not weapon.Explosive and not (opts and opts.speed) then speed = speed * (Rhylib.Config.Get("weapons", "boltSpeedMult") or 1) end
    Bolts.Spawn(owner, origin, dir, speed, opts and opts.color or weapon.BoltColor or 1)
end

Rhylib.Net.ReceiveBatch("wep.shot", function()
    return {
        shooter = net.ReadUInt(13),
        origin = net.ReadVector(),
        dir = net.ReadNormal(),
        speed = net.ReadUInt(15),
        color = net.ReadUInt(4),
        left = net.ReadBool(),
        ahead = net.ReadUInt(6) / 100,
    }
end, function(s)
    local shooter = Entity(s.shooter)
    -- Your own shots were already drawn by prediction (except in singleplayer).
    if shooter == LocalPlayer() and not game.SinglePlayer() then return end
    Bolts.Spawn(shooter, s.origin, s.dir, s.speed, s.color, s.left, s.ahead)
end)

local function impact(b)
    local style = b.style
    if style.rocket or style.hook then return end  -- the server handles these
    local ed = EffectData()
    if style.ring then
        -- Stun: a blue spark, no scorch mark.
        ed:SetOrigin(b.hitPos)
        ed:SetNormal(b.hitNormal)
        util.Effect("StunstickImpact", ed)
        return
    end
    ed:SetOrigin(b.hitPos)
    ed:SetNormal(b.hitNormal)
    util.Effect("AR2Impact", ed)

    local ent = b.hitEnt
    if not (IsValid(ent) and (ent:IsPlayer() or ent:IsNPC())) then
        util.Decal("FadingScorch", b.hitPos + b.hitNormal, b.hitPos - b.hitNormal)
    end
end

Rhylib.Hook.Add("Think", "weapons.bolts", function()
    local list = Bolts.visual
    if #list == 0 then return end

    local dt = FrameTime()
    local now = CurTime()
    local i = 1
    while i <= #list do
        local b = list[i]
        local remove = not b.style or not b.origin or now - b.born > b.style.life  -- (no style/origin: from before an autorefresh)

        if not remove then
            local step = b.speed * dt
            local lead = b.lead
            if lead and lead > 0 then
                local extra = math.min(lead, step * (CATCHUP - 1))
                b.lead = lead - extra
                step = step + extra
            end
            local t = b.travelled + step
            if b.hitDist and t >= b.hitDist then
                impact(b)
                remove = true
            elseif b.endDist and t >= b.endDist then
                remove = true
            else
                b.travelled = t
                local o, d = b.origin, b.dir
                b.pos:SetUnpacked(o.x + d.x * t, o.y + d.y * t, o.z + d.z * t)
            end
        end

        if remove then
            list[i] = list[#list]
            list[#list] = nil
        else
            i = i + 1
        end
    end
end)

local head, tail = Vector(), Vector()

Rhylib.Hook.Add("PostDrawTranslucentRenderables", "weapons.bolts", function(depth, skybox)
    if depth or skybox then return end
    local list = Bolts.visual
    if #list == 0 then return end

    local now = CurTime()
    -- Pass 1: hooks and beams. Pass 2: glows. So each material is set
    -- once per frame instead of twice per bolt.
    render.SetMaterial(matBeam)
    for i = 1, #list do
        local b = list[i]
        local st = b.style
        if st and st.hook then
            -- The hook flying out, trailing its line back to the gun.
            local from = muzzlePos(b.shooter, b.pos)
            render.SetColorMaterial()
            render.DrawBeam(from, b.pos, st.width, 0, 1, st.color)
            render.DrawBox(b.pos, b.dir:Angle(), HOOK_MINS, HOOK_MAXS, COL_HOOK)
            render.SetMaterial(matBeam)
        elseif st and st.length > 0 then
            local p, d = b.pos, b.dir
            head:Set(p)
            local len = math.min(st.length, b.travelled + 1)
            tail:SetUnpacked(head.x - d.x * len, head.y - d.y * len, head.z - d.z * len)
            render.DrawBeam(tail, head, st.width, 0, 1, st.color)
            if st.core then render.DrawBeam(tail, head, st.width * 0.3, 0, 1, COL_CORE) end
        end
    end
    render.SetMaterial(matGlow)
    for i = 1, #list do
        local b = list[i]
        local st = b.style
        if st and not st.hook and st.glow > 0 then
            render.DrawSprite(b.pos, st.glow, st.glow, st.color)
        end
    end
    -- Stun rings: a circle facing the camera, pulsing a little.
    render.SetMaterial(matRing)
    for i = 1, #list do
        local b = list[i]
        local st = b.style
        if st and st.ring then
            local r = st.ring * (1 + 0.15 * math.sin(now * 30))
            render.DrawSprite(b.pos, r, r, st.color)
        end
    end
end)
