--[[
    Client bolt visuals. Purely cosmetic: damage is decided on the server.

    Bolts come from two places:
      - your own shots, spawned instantly by the weapon's predicted PrimaryAttack
      - other players' shots, from the batched "wep.shot" message
    The real bolt flies from the eyes. The visual flies in a straight line
    from the muzzle to where that eye line ends (the impact, or its far
    end), so it never bends and lands exactly where the shot lands.

    Realm: client. Public: Bolts.Spawn, Bolts.FireLocal, Bolts.NearMiss,
    Bolts.COLOR_* numbers. Client convars rhylib_whizz (near-miss sounds),
    rhylib_bolt_lights (bolts light their surroundings, default on;
    Settings > Weapons "Bolt lighting"), rhylib_bolt_lights_max (how many
    of the nearest bolts are lit at once, default 6). A bolt flying through
    a smoke cloud (rhylib_republic, Rhylib.Weapons.smokes) lights the smoke
    around it with a big soft glow in its light colour.
    Receives net "wep.shot" (format in sv_10_bolts.lua).
    BoltColor styles (SWEP.BoltColor or opts.color): 1 blue, 2 red,
    3 green, 4 rocket, 5 grapple hook, 6 stun ring, 7 training yellow,
    8 training droids, 9 training rocket, 10 overcharged, 11 droids (thick red).
]]

local W = Rhylib.Weapons
W.Bolts = W.Bolts or {}
local Bolts = W.Bolts
Bolts.visual = Bolts.visual or {}

-- Looks, by the weapon's BoltColor: colour, trail length, beam width,
-- glow size and how long the visual can live.
local STYLES = {
    -- (core: a thin white-hot centre line, so it reads as a bolt, not a glowing bullet)
    [1] = { color = Color(90, 150, 255), length = 90, width = 7.5, glow = 19, life = 1.2, core = true },   -- Republic blue
    [2] = { color = Color(255, 70, 60), length = 90, width = 6.5, glow = 17, life = 1.2, core = true },    -- CIS red
    [3] = { color = Color(80, 255, 120), length = 90, width = 6.5, glow = 17, life = 1.2, core = true },   -- green
    [4] = { color = Color(255, 170, 80), length = 140, width = 9, glow = 40, life = 6, rocket = true },  -- rocket
    [5] = { color = Color(14, 14, 14), length = 0, width = 1.8, glow = 0, life = 0.6, hook = true },    -- grapple hook
    [6] = { color = Color(120, 200, 255), length = 0, width = 0, glow = 22, life = 1.2, ring = 26 },     -- stun ring
    [7] = { color = Color(255, 225, 60), length = 70, width = 5, glow = 14, life = 1.2 },   -- training (yellow)
    [8] = { color = Color(255, 160, 40), length = 70, width = 5, glow = 14, life = 1.2 },   -- training droids (orange-yellow)
    [9] = { color = Color(255, 225, 60), length = 140, width = 9, glow = 40, life = 6, rocket = true },  -- training rocket
    [10] = { color = Color(150, 205, 255), length = 115, width = 9, glow = 26, life = 1.2, core = true },  -- overcharged (DC-15A)
    [11] = { color = Color(255, 30, 25), length = 100, width = 10, glow = 26, life = 1.2, core = true },   -- droids (rhylib_droids): thicker red, easy to see
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
-- Bolts.NearMiss(shooter, from, dir, len, speed, tr, lead): plays the
-- whizz if this visual bolt passes close to your head (called by Spawn).
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

-- Same rule as the server's trace (sv_10_bolts passes): players' and
-- clones' bolts fly through clone NPCs, clones' through players (and
-- their lying ragdolls), soft-knocked players for everyone.
local function visualPasses(e, owner)
    if e:IsPlayer() then
        if e:GetNW2Bool(Rhylib.NW.KNOCK_SOFT, false) then return true end
        return owner ~= nil and owner.IsRhylibClone == true
    end
    if e.IsRhylibClone == true then return owner ~= nil and (owner:IsPlayer() or owner.IsRhylibClone == true) end
    local L = Rhylib.Lying
    return owner ~= nil and owner.IsRhylibClone == true and L and L.Owner and IsValid(L.Owner(e)) or false
end

-- ahead: seconds the server's bolt is ahead (its lag-compensated first
-- leg). The visual still leaves the muzzle but flies up to CATCHUP times
-- as fast until it has made that up (not hooks or stun rings).
-- Bolts.Spawn(shooter, origin, dir, speed, colorIndex, left, ahead): adds
-- one visual bolt. origin/dir: the real (eye) line; the visual starts at
-- the shooter's muzzle (SWEP:GetPropMuzzle). Returns nothing.
-- Example: Rhylib.Weapons.Bolts.Spawn(ply, ply:GetShootPos(), ply:GetAimVector(), 7000, 1)
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
    local owner = IsValid(shooter) and shooter or nil
    traceData.filter = owner
    util.TraceLine(traceData)
    -- (friendlies: the server's bolt flies through them, so the visual does too)
    local skip
    for _ = 1, 4 do
        if not (IsValid(traceResult.Entity) and visualPasses(traceResult.Entity, owner)) then break end
        skip = skip or { owner }
        skip[#skip + 1] = traceResult.Entity
        traceData.filter = skip
        util.TraceLine(traceData)
    end
    traceData.filter = nil
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

-- Bolts.FireLocal(owner, weapon, origin, dir, opts): called by the weapon
-- on the shooter's own client (first prediction only), so your own bolts
-- show at once. Same speed rules as the server's Bolts.Speed.
function Bolts.FireLocal(owner, weapon, origin, dir, opts)
    local speed = opts and opts.speed or weapon.BoltSpeed or 7000
    if not weapon.Explosive and not (opts and opts.speed) then speed = speed * (Rhylib.Config.Get("weapons", "boltSpeedMult")) end
    Bolts.Spawn(owner, origin, dir, speed, opts and opts.color or weapon.BoltColor or 1)
end

Rhylib.Net.ReceiveBatch("wep.shot", function()
    return {
        shooter = net.ReadUInt(13),
        origin = Vector(net.ReadInt(16), net.ReadInt(16), net.ReadInt(16)),   -- (whole units, see sv_10_bolts writeShot)
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

-- Bolt hit sounds (Star Wars shared resources pack: effects/sw_impact,
-- 24 variants): only within IMPACT_RANGE, at most one
-- every IMPACT_GAP s, so a big fight doesn't stack hundreds of them.
local IMPACT_RANGE2, IMPACT_GAP = 1800 * 1800, 0.03
local nextImpactSound = 0
local function impactSound(pos)
    local now = RealTime()
    if now < nextImpactSound then return end
    if EyePos():DistToSqr(pos) > IMPACT_RANGE2 then return end
    nextImpactSound = now + IMPACT_GAP
    sound.Play(string.format("effects/sw_impact/sw752_hit_%02d.ogg", math.random(1, 24)), pos, 72, math.random(95, 105), 0.8)
end

-- Bolt light (client convars rhylib_bolt_lights, rhylib_bolt_lights_max):
-- the nearest bolts in flight light up the walls and people around them
-- in their colour, and a hit flashes briefly. Engine dynamic lights,
-- reused by slot every frame (nothing piles up); light never reaches
-- through walls.
local lightsVar = CreateClientConVar("rhylib_bolt_lights", "1", true, false, "Blaster bolts light up their surroundings (dynamic lights; off for more FPS)")
local lightsMaxVar = CreateClientConVar("rhylib_bolt_lights_max", "6", true, false, "Most bolts lit at once (nearest first, 1-16)")
local LIGHT_BASE = 61000   -- (dynamic light indices: flying bolts, then hit flashes)
local LIGHT_RANGE2 = 3000 * 3000
local flashSlot = 0

-- The light's colour: the bolt's colour made deeper (the palest channel
-- pulled down, the brightest up to full), so a bright light still reads
-- as blue / red on walls instead of washing out to white. Cached per style.
local function lightColor(style)
    local lc = style.lightColor
    if lc then return lc end
    local c = style.color
    local lo = math.min(c.r, c.g, c.b) * 0.75
    local r, g, b = c.r - lo, c.g - lo, c.b - lo
    local hi = math.max(r, g, b, 1)
    lc = Color(r / hi * 255, g / hi * 255, b / hi * 255)
    style.lightColor = lc
    return lc
end

local function hitFlash(b)
    if not lightsVar:GetBool() or b.style.hook then return end
    if EyePos():DistToSqr(b.hitPos) > LIGHT_RANGE2 then return end
    flashSlot = flashSlot % 8 + 1
    local dl = DynamicLight(LIGHT_BASE + 32 + flashSlot)
    if not dl then return end
    local c = lightColor(b.style)
    dl.pos = b.hitPos + b.hitNormal * 6
    dl.r, dl.g, dl.b = c.r, c.g, c.b
    dl.brightness = 4
    dl.size = 240
    dl.decay = 1600
    dl.dietime = CurTime() + 0.15
end

local near, nearD = {}, {}
local function boltLights(list)
    local max = math.Clamp(lightsMaxVar:GetInt(), 1, 16)
    local eye = EyePos()
    local n = 0
    for i = 1, #list do
        local b = list[i]
        if b.style and not b.style.hook and b.pos then
            local d = b.pos:DistToSqr(eye)
            if d < LIGHT_RANGE2 then
                -- (keep the max nearest: insertion into a short sorted list)
                if n < max or d < nearD[n] then
                    local j = math.min(n + 1, max)
                    while j > 1 and nearD[j - 1] > d do
                        near[j], nearD[j] = near[j - 1], nearD[j - 1]
                        j = j - 1
                    end
                    near[j], nearD[j] = b, d
                    if n < max then n = n + 1 end
                end
            end
        end
    end
    local now = CurTime()
    for i = 1, n do
        local b = near[i]
        local dl = DynamicLight(LIGHT_BASE + i)
        if dl then
            local c = lightColor(b.style)
            dl.pos = b.pos
            dl.r, dl.g, dl.b = c.r, c.g, c.b
            dl.brightness = b.style.rocket and 4 or 3
            dl.size = b.style.rocket and 300 or 210
            dl.decay = 0
            dl.dietime = now + 0.06
        end
        near[i] = nil
    end
end

local function impact(b)
    local style = b.style
    if style.rocket or style.hook then return end  -- the server handles these
    hitFlash(b)
    local ed = EffectData()
    if style.ring then
        -- Stun: a blue spark, no scorch mark.
        ed:SetOrigin(b.hitPos)
        ed:SetNormal(b.hitNormal)
        util.Effect("StunstickImpact", ed)
        if EyePos():DistToSqr(b.hitPos) < IMPACT_RANGE2 then sound.Play("weapons/1misc_guns/sw_stun.ogg", b.hitPos, 68, 120, 0.6) end
        return
    end
    ed:SetOrigin(b.hitPos)
    ed:SetNormal(b.hitNormal)
    util.Effect("AR2Impact", ed)
    impactSound(b.hitPos)

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
    if lightsVar:GetBool() and #list > 0 then boltLights(list) end
end)

Rhylib.Hook.Add("InitPostEntity", "weapons.boltlights.setting", function()
    local Menus = Rhylib.Menus
    if not (Menus and Menus.AddSetting) then return end
    Menus.AddSetting("Weapons", { id = "wep.boltlights", order = 30, title = "Bolt lighting",
        desc = "Blaster bolts light up walls and people as they fly (turn off for more FPS)", kind = "toggle", convar = "rhylib_bolt_lights" })
end)

local head, tail = Vector(), Vector()

-- How far inside a smoke cloud (rhylib_republic, W.smokes) a point is:
-- 0 outside, up to 1 deep in a thick one.
local SMOKE_GLOW = Color(255, 255, 255, 0)
local SMOKE_UP = Vector(0, 0, 45)
local function smokeAt(smokes, pos)
    local best = 0
    for c in pairs(smokes) do
        if IsValid(c) and c.Strength then
            local s = c:Strength()
            if s > 0 then
                local r = c:CurRadius()
                local d = pos:Distance(c:GetPos() + SMOKE_UP)
                if d < r then best = math.max(best, s * math.Clamp((r - d) / (r * 0.4), 0, 1)) end
            end
        end
    end
    return best
end

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
    -- (smoke clouds about: a bolt inside one lights it up around itself)
    local smokes = W.smokes and next(W.smokes) ~= nil and W.smokes or nil
    for i = 1, #list do
        local b = list[i]
        local st = b.style
        if st and not st.hook and st.glow > 0 then
            render.DrawSprite(b.pos, st.glow, st.glow, st.color)
            if smokes then
                local inside = smokeAt(smokes, b.pos)
                if inside > 0 then
                    local c = lightColor(st)
                    SMOKE_GLOW.r, SMOKE_GLOW.g, SMOKE_GLOW.b, SMOKE_GLOW.a = c.r, c.g, c.b, 90 * inside
                    render.DrawSprite(b.pos, 260, 260, SMOKE_GLOW)
                end
            end
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
