--[[
    Poses (shared): named body poses, made in rhylib_devtools'
    rhylib_pose_editor, saved on the server and sent to every client, and
    played on any player or NPC whose model has the same bone names (the
    ValveBiped clone models). Drawn client side through a
    BuildBonePositions callback, eased in and out.

    A pose: { mode = "add" | "set", loop = bool, length = seconds,
              keys = { { t = seconds, bones = { [boneName] = { a = { p, y, r }, v = { x, y, z } } } }, ... } }
      add  each bone is turned by a (and moved by v) in its own axes on
           top of whatever the animation does (walking, breathing and
           aiming still show)
      set  each listed bone takes the turn a relative to its parent
           (v moves it from where it sits), ignoring the animation (not
           the root bone, the pelvis: it has no parent)
      Unlisted bones follow their parent as the animation has them.
      The held gun (optional, players): anchor = "chest" | "hips" | "rhand"
      | "lhand" (what the gun moves with), each key's gun = { p, a } (the
      gun from the anchor bone), hands = { r = bool, l = bool } (that hand
      holds the gun: two-bone IK puts it on its grip; off = the hand poses
      freely), grip = { l = { p, a } } (the left grip from the gun, this
      pose only; else the weapon's Po.gear grip; else where the animation
      has the left hand on the gun), each key's elbow = { r = { x, y, z },
      l = ... } (the point that elbow bends toward, from the chest bone;
      unset = where the animation has the elbow). The right grip is the
      weapon's own hold (PropWMPos / PropWMAng). An anchor hand isn't moved
      by IK (the gun goes with it).
      Hand IK: ik = { r = { on, rel }, l = ... } (rel "chest" | "hips" |
      "gun"), each key's hand = { r = { p, a }, l = ... }: that hand goes to
      the target from that frame and the arm is solved to reach it (elbow
      toward the key's elbow point); it wins over the gun grips and spot
      locks for that hand. A right hand kept from the gun needs a pose
      moving the gun (it holds the gun otherwise). The hand bones' own
      values in a key are a fine turn / move on top of where hand IK or a
      gun grip puts the hand (Add-style in either mode). The wrist's twist
      helper bones (Ulna, Wrist) share the hand's turn round the forearm.
      loop: the keys play over length seconds and repeat (blended, eased);
      not loop: the first key is held.

    Rhylib.Poses (Po):
      Po.defs[name]                     the saved poses (both realms)
      Po.Play(ent, name, fade)          server: play a pose on ent (NW2String
                                        rhylib_pose, NW2Float rhylib_poseAt)
      Po.Stop(ent, fade)                server: stop it
      Po.SetLocal(ent, name)            client: play one on this client only,
                                        over the networked one ("" = none;
                                        nil = back to the networked one)
      Po.Sample(pose, t) -> bones       { [boneName] = { a = Angle, v = Vector } }
      Po.preview = { ent, pose, t }     client: the editor's live preview
    Po.gear[class] = { lgrip = { p, a }, sling = { bone, p, a }, spots,
      lock }: per weapon, the left-hand grip from the gun, the spot on the
      body where it shows while carried but not held (from that bone; only
      weapons given a spot show), named spots { [name] = { parent = "@gun"
      | another spot, p, a } } (a spot is where a hand goes and how it
      turns), and hand locks { r = spot, l = spot, reload, lowered }: the
      left hand stays on its spot whenever the weapon is held, in every
      animation, also with no pose playing (eased off while reloading /
      lowered or on safety unless reload / lowered are ticked). A pose can
      add spots (pose.spots) and change a lock (pose.lock: a spot, or false
      = none during this pose); with a pose moving the gun the right hand's
      lock works too.
    Po.gear[class].recoil = { gesture, pose, back, up, side, length,
      strength }: the third-person fire gesture ("ACT_..." name from
      Po.GESTURES, "none", nil = the hold type's; hook DoAnimationEvent
      "core.poses.recoil"), a saved pose added on top at each shot, and the
      gun's kick (back units, up / side degrees) easing out over length s
      after the weapon's KickTime (or Po.fakeShot[ent], the editor's fire
      loop). Po.RecoilK, Po.ApplyRecoil, Po.KickHand.
    Po.gear[class].wm = { p, a, s } / .muzzle = { x, y, z }: the weapon's
      third-person hold and muzzle point over its file's PropWMPos /
      PropWMAng / PropScale / PropMuzzle (Po.WeaponProp(w); the weapon base
      draws with them).
    Po.GunHold(w) -> pos, ang: the gun from the right hand (PropWMPos /
      PropWMAng; nothing for other weapons).
    NW2String rhylib_sling (server, each second): the player's carried
      weapons not in their hands that have a sling spot, "class,class".
    ent.rhylibPoseGun = { f = FrameNumber(), pos, ang } while a pose moves
      the gun (the weapon base draws it there); ent.rhylibPoseDbg = the
      handles for the editor ({ G, A, chest, R, L, ER, EL } matrices /
      vectors) on the preview entity.
    Weapon poses: Po.weapons[class] = { { pose = name, when = { [filter] = true } }, ... }
      a list per weapon class; someone holding that weapon (third person)
      shows the first entry whose filters fit them now, eased in and out.
      Filters, one or more ticked in each group (a group with none ticked
      never fits):
        Stance   standing, crouching
        Moving   still (shown as Idle), walking, running, air (jumping /
                 falling)
        Gun      hip, aiming, lowered (safety on or lowered to sprint)
        Doing    none, shooting (fired in the last 0.4 s), reloading
      (Gun and Doing read the Rhylib weapon base; other weapons count as
      hip / none.) Po.State(ply) -> { [filter] = true } of the four now.
      A pose from !pose or Po.SetLocal wins over the weapon's.
    Perms: rhylib.poses.edit (superadmin): save / delete poses;
    rhylib.poses.play (admin): !pose.
    Command !pose <name> (on the player / NPC you look at, else you),
    !pose stop, !pose list.
    Nets: poses.req (client: send me every pose), poses.one (server ->
    client: name, JSON or "" = deleted), poses.save (client, edit perm:
    name, JSON), poses.del (client, edit perm: name), poses.wpn (server ->
    client: UInt32 length + compressed JSON of Po.weapons, on join and
    when changed), poses.wpnset (client, edit perm: class, JSON list or
    "" = none), poses.gearset (client, edit perm: class, JSON
    Po.gear entry or "" = none), poses.give (client, edit perm: class: give it to me and
    hold it; the editor's weapon picker).
    poses.wpn carries { w = Po.weapons, g = Po.gear }.
    Saved: Data "poses" "all" = { [name] = pose }, "weapons" = Po.weapons,
    "gear" = Po.gear.
]]

Rhylib.Poses = Rhylib.Poses or {}
local Po = Rhylib.Poses
Po.defs = Po.defs or {}
Po.weapons = Po.weapons or {}
Po.gear = Po.gear or {}

Rhylib.Perms.Register("rhylib.poses.edit", "superadmin", "Save and delete body poses (rhylib_pose_editor)")
Rhylib.Perms.Register("rhylib.poses.play", "admin", "Play a body pose on yourself or an NPC (!pose)")

local MAX_KEYS, MAX_BONES, MAX_POSES = 32, 128, 200
Po.MAX_POSES = MAX_POSES

-- Po.CleanName(s): letters, digits, spaces, _ and -; trimmed, 40 long.
function Po.CleanName(n)
    return string.sub(string.Trim((string.gsub(tostring(n or ""), "[^%w _%-]", ""))), 1, 40)
end

local function three(t, lim, norm)
    if not istable(t) then return nil end
    local out = {}
    for i = 1, 3 do
        local v = math.Clamp(tonumber(t[i]) or 0, -lim, lim)
        out[i] = norm and math.NormalizeAngle(v) or v
    end
    return out
end

local cleanSpots, cleanLock   -- (below)

-- (the fire gestures a weapon's recoil may pick)
Po.GESTURES = { "ACT_HL2MP_GESTURE_RANGE_ATTACK_AR2", "ACT_HL2MP_GESTURE_RANGE_ATTACK_SMG1", "ACT_HL2MP_GESTURE_RANGE_ATTACK_PISTOL",
    "ACT_HL2MP_GESTURE_RANGE_ATTACK_REVOLVER", "ACT_HL2MP_GESTURE_RANGE_ATTACK_SHOTGUN", "ACT_HL2MP_GESTURE_RANGE_ATTACK_RPG",
    "ACT_HL2MP_GESTURE_RANGE_ATTACK_CROSSBOW", "ACT_HL2MP_GESTURE_RANGE_ATTACK_DUEL", "ACT_HL2MP_GESTURE_RANGE_ATTACK_PHYSGUN",
    "ACT_HL2MP_GESTURE_RANGE_ATTACK_CAMERA", "ACT_HL2MP_GESTURE_RANGE_ATTACK_SLAM", "ACT_HL2MP_GESTURE_RANGE_ATTACK_GRENADE",
    "ACT_HL2MP_GESTURE_RANGE_ATTACK_MELEE2", "ACT_HL2MP_GESTURE_RANGE_ATTACK_KNIFE" }
local GEST_OK = {}
for _, g in ipairs(Po.GESTURES) do GEST_OK[g] = true end
function Po.GestureOK(g) return GEST_OK[g] == true end

-- Po.Clean(pose) -> a checked copy (numbers clamped, names kept short), or nil.
function Po.Clean(p)
    if not istable(p) or not istable(p.keys) then return nil end
    local out = { mode = p.mode == "set" and "set" or "add", loop = p.loop == true,
        length = math.Clamp(tonumber(p.length) or 2, 0.1, 60), keys = {} }
    local ANCH = { chest = true, hips = true, rhand = true, lhand = true }
    if ANCH[p.anchor] then out.anchor = p.anchor end
    if istable(p.hands) then out.hands = { r = p.hands.r ~= false, l = p.hands.l ~= false } end
    out.spots, out.lock = cleanSpots(p.spots), cleanLock(p.lock)
    if istable(p.ik) then
        local REL = { chest = true, hips = true, gun = true }
        local function side(t) return istable(t) and t.on and { on = true, rel = REL[t.rel] and t.rel or "chest" } or nil end
        local r, l = side(p.ik.r), side(p.ik.l)
        if r or l then out.ik = { r = r, l = l } end
    end
    if istable(p.grip) and istable(p.grip.l) then
        out.grip = { l = { p = three(p.grip.l.p, 100) or { 0, 0, 0 }, a = three(p.grip.l.a, 360, true) or { 0, 0, 0 } } }
    end
    for i, k in ipairs(p.keys) do
        if i > MAX_KEYS then break end
        if istable(k) and istable(k.bones) then
            local key = { t = math.Clamp(tonumber(k.t) or 0, 0, out.length), bones = {} }
            if out.anchor and istable(k.gun) then
                key.gun = { p = three(k.gun.p, 150) or { 0, 0, 0 }, a = three(k.gun.a, 360, true) or { 0, 0, 0 } }
            end
            if istable(k.elbow) then
                local r, l = three(k.elbow.r, 150), three(k.elbow.l, 150)
                if r or l then key.elbow = { r = r, l = l } end
            end
            if istable(k.hand) then
                local function h(t) return istable(t) and { p = three(t.p, 150) or { 0, 0, 0 }, a = three(t.a, 360, true) or { 0, 0, 0 } } or nil end
                local r, l = h(k.hand.r), h(k.hand.l)
                if r or l then key.hand = { r = r, l = l } end
            end
            local n = 0
            for name, b in pairs(k.bones) do
                n = n + 1
                if n > MAX_BONES then break end
                if isstring(name) and #name < 64 and istable(b) then
                    key.bones[name] = { a = three(b.a, 360, true), v = three(b.v, 50) }
                end
            end
            out.keys[#out.keys + 1] = key
        end
    end
    if #out.keys == 0 then return nil end
    table.sort(out.keys, function(x, y) return x.t < y.t end)
    return out
end

-- Po.SlerpAngle(a, b, t): the turn t of the way from a to b, the short
-- way round (through quaternions, so no Euler wobble).
local function toQ(a)
    local p, y, r = math.rad(a.p) * 0.5, math.rad(a.y) * 0.5, math.rad(a.r) * 0.5
    local sp, cp, sy, cy, sr, cr = math.sin(p), math.cos(p), math.sin(y), math.cos(y), math.sin(r), math.cos(r)
    return sr * cp * cy - cr * sp * sy, cr * sp * cy + sr * cp * sy, cr * cp * sy - sr * sp * cy, cr * cp * cy + sr * sp * sy
end
function Po.SlerpAngle(a, b, t)
    if t <= 0 then return Angle(a) end
    if t >= 1 then return Angle(b) end
    local ax, ay, az, aw = toQ(a)
    local bx, by, bz, bw = toQ(b)
    local d = ax * bx + ay * by + az * bz + aw * bw
    if d < 0 then bx, by, bz, bw, d = -bx, -by, -bz, -bw, -d end
    local ka, kb
    if d > 0.9995 then
        ka, kb = 1 - t, t
    else
        local th = math.acos(d)
        local s = math.sin(th)
        ka, kb = math.sin((1 - t) * th) / s, math.sin(t * th) / s
    end
    local x, y, z, w = ax * ka + bx * kb, ay * ka + by * kb, az * ka + bz * kb, aw * ka + bw * kb
    local n = math.sqrt(x * x + y * y + z * z + w * w)
    if n < 1e-6 then return Angle(b) end
    x, y, z, w = x / n, y / n, z / n, w / n
    local fwd = Vector(1 - 2 * (y * y + z * z), 2 * (x * y + w * z), 2 * (x * z - w * y))
    local up = Vector(2 * (x * z + w * y), 2 * (y * z - w * x), 1 - 2 * (x * x + y * y))
    return fwd:AngleEx(up)
end
local slerp = Po.SlerpAngle

-- (smooth start and stop between keys)
local function ease(x) return x * x * (3 - 2 * x) end

local function angOf(b) return b and b.a and Angle(b.a[1], b.a[2], b.a[3]) or Angle() end
local function vecOf(b) return b and b.v and Vector(b.v[1], b.v[2], b.v[3]) or Vector() end

local function v3(t) return t and Vector(t[1], t[2], t[3]) or nil end
local function a3(t) return t and Angle(t[1], t[2], t[3]) or nil end
-- (the gun and elbows of one key, or blended between two)
local function extrasOf(k)
    local x = {}
    if k.gun then x.gun = { p = v3(k.gun.p), a = a3(k.gun.a) } end
    if k.elbow then x.er, x.el = v3(k.elbow.r), v3(k.elbow.l) end
    if k.hand then
        if k.hand.r then x.hr = { p = v3(k.hand.r.p), a = a3(k.hand.r.a) } end
        if k.hand.l then x.hl = { p = v3(k.hand.l.p), a = a3(k.hand.l.a) } end
    end
    return x
end
local function blendExtras(A, B, k)
    local a, b = extrasOf(A), extrasOf(B)
    local x = {}
    if a.gun and b.gun then
        x.gun = { p = LerpVector(k, a.gun.p, b.gun.p), a = slerp(a.gun.a, b.gun.a, k) }
    else
        x.gun = a.gun or b.gun
    end
    x.er = (a.er and b.er) and LerpVector(k, a.er, b.er) or a.er or b.er
    x.el = (a.el and b.el) and LerpVector(k, a.el, b.el) or a.el or b.el
    for _, h in ipairs({ "hr", "hl" }) do
        if a[h] and b[h] then
            x[h] = { p = LerpVector(k, a[h].p, b[h].p), a = slerp(a[h].a, b[h].a, k) }
        else
            x[h] = a[h] or b[h]
        end
    end
    return x
end

-- Po.Sample(pose, t) -> bones, extras: the bones at time t (looping
-- poses wrap round); extras = { gun = { p, a }, er, el, hr, hl }
-- (Vectors / Angles; hr / hl = { p, a } the hand IK targets).
function Po.Sample(p, t)
    local keys = p.keys
    if not keys or #keys == 0 then return {}, {} end
    local out = {}
    if not p.loop or #keys == 1 then
        for name, b in pairs(keys[1].bones) do out[name] = { a = angOf(b), v = vecOf(b) } end
        return out, extrasOf(keys[1])
    end
    local len = math.max(0.1, p.length or 2)
    t = (t or 0) % len
    -- the keys either side (the last one blends back into the first)
    local ia, ib = #keys, 1
    for i = 1, #keys do
        if keys[i].t <= t then ia = i end
    end
    ib = ia % #keys + 1
    local ta, tb = keys[ia].t, keys[ib].t
    if tb <= ta then tb = tb + len end
    local tt = t
    if tt < ta then tt = tt + len end
    local k = tb > ta and ease(math.Clamp((tt - ta) / (tb - ta), 0, 1)) or 0
    local A, B = keys[ia].bones, keys[ib].bones
    local names = {}
    for n in pairs(A) do names[n] = true end
    for n in pairs(B) do names[n] = true end
    for n in pairs(names) do
        local ba, bb = A[n], B[n]
        out[n] = { a = slerp(angOf(ba), angOf(bb), k), v = LerpVector(k, vecOf(ba), vecOf(bb)) }
    end
    return out, blendExtras(keys[ia], keys[ib], k)
end

-- Spots: { [name] = { parent = "@gun" | another spot's name, p, a } }
-- (at most 16); a lock: { r = spot | false, l = spot | false, reload,
-- lowered } (false: no lock; reload / lowered: keep it then too).
cleanSpots = function(t)
    if not istable(t) then return nil end
    local out, n = {}, 0
    for name, sp in pairs(t) do
        local nm = Po.CleanName(name)
        if nm ~= "" and istable(sp) and n < 16 then
            n = n + 1
            local par = isstring(sp.parent) and (sp.parent == "@gun" and "@gun" or Po.CleanName(sp.parent)) or "@gun"
            out[nm] = { parent = par ~= "" and par or "@gun", p = three(sp.p, 100) or { 0, 0, 0 }, a = three(sp.a, 360, true) or { 0, 0, 0 } }
        end
    end
    return next(out) and out or nil
end
cleanLock = function(t)
    if not istable(t) then return nil end
    local function side(v) if v == false then return false end return isstring(v) and Po.CleanName(v) ~= "" and Po.CleanName(v) or nil end
    local out = { r = side(t.r), l = side(t.l), reload = t.reload == true or nil, lowered = t.lowered == true or nil }
    return (out.r ~= nil or out.l ~= nil or out.reload or out.lowered) and out or nil
end
Po.CleanSpots, Po.CleanLock = cleanSpots, cleanLock

-- Po.CleanGear(g) -> a checked Po.gear entry, or nil.
function Po.CleanGear(g)
    if not istable(g) then return nil end
    local out = { spots = cleanSpots(g.spots), lock = cleanLock(g.lock) }
    if istable(g.wm) then
        out.wm = { p = three(g.wm.p, 100) or { 0, 0, 0 }, a = three(g.wm.a, 360, true) or { 0, 0, 0 }, s = math.Clamp(tonumber(g.wm.s) or 1, 0.05, 5) }
    end
    if istable(g.muzzle) then out.muzzle = three(g.muzzle, 200) end
    if istable(g.recoil) then
        local r = g.recoil
        local gest = isstring(r.gesture) and (r.gesture == "none" or Po.GestureOK(r.gesture)) and r.gesture or nil
        local num = function(v, lo, hi, d) return math.Clamp(tonumber(v) or d, lo, hi) end
        local pn = isstring(r.pose) and Po.CleanName(r.pose) or ""
        out.recoil = { gesture = gest, pose = pn ~= "" and pn or nil,
            back = num(r.back, 0, 20, 0), up = num(r.up, -30, 30, 0), side = num(r.side, -30, 30, 0),
            length = num(r.length, 0.05, 1, 0.2), strength = num(r.strength, 0, 2, 1) }
    end
    if istable(g.lgrip) then out.lgrip = { p = three(g.lgrip.p, 100) or { 0, 0, 0 }, a = three(g.lgrip.a, 360, true) or { 0, 0, 0 } } end
    if istable(g.sling) and isstring(g.sling.bone) and #g.sling.bone < 64 then
        out.sling = { bone = g.sling.bone, p = three(g.sling.p, 100) or { 0, 0, 0 }, a = three(g.sling.a, 360, true) or { 0, 0, 0 } }
    end
    return next(out) and out or nil
end

-- Po.GunHold(w) -> pos, ang: where the gun sits from the right hand (the
-- weapon base's PropWMPos / PropWMAng, turned the same way it draws them).
-- Po.WeaponProp(w) -> pos, ang, scale, muzzle: the weapon's third-person
-- hold (PropWMPos / PropWMAng / PropScale) and muzzle point (PropMuzzle),
-- with Po.gear[class].wm / .muzzle (the pose editor's Gun model tab) over
-- them. The weapon base draws with these.
function Po.WeaponProp(w)
    local g = w and w.GetClass and Po.gear[w:GetClass()]
    local ov, mz = g and g.wm, g and g.muzzle
    local pos = ov and Vector(ov.p[1], ov.p[2], ov.p[3]) or (w and w.PropWMPos) or Vector()
    local ang = ov and Angle(ov.a[1], ov.a[2], ov.a[3]) or (w and w.PropWMAng) or Angle()
    local scale = ov and ov.s or (w and w.PropScale) or 1
    local muzzle = mz and Vector(mz[1], mz[2], mz[3]) or (w and w.PropMuzzle) or Vector()
    return pos, ang, scale, muzzle
end

function Po.GunHold(w)
    if not (w and w.PropModel and w.PropWMPos) then return Vector(), Angle() end
    local op, oa = Po.WeaponProp(w)
    oa = oa or angle_zero
    local a = Angle()
    a:RotateAroundAxis(a:Up(), oa.y)
    a:RotateAroundAxis(a:Right(), oa.p)
    a:RotateAroundAxis(a:Forward(), oa.r)
    return Vector(op.x, -op.y, op.z), a
end

-- (both realms, so clients can list it; only the server runs fn)
Rhylib.Command.Add({
    name = "rhylib_pose", chat = { "pose" }, perm = "rhylib.poses.play", tag = "Poses",
    args = "<name> | stop | list", help = "Play a saved body pose on the player / NPC you look at (or yourself)",
    fn = function(ply, args, argStr)
        if not Po.Load then return end
        Po.Load()
        local name = string.Trim(argStr or table.concat(args, " "))
        if name == "" or name == "list" then
            local names = {}
            for n in pairs(Po.defs) do names[#names + 1] = n end
            table.sort(names)
            return #names > 0 and ("Poses: " .. table.concat(names, ", ")) or "No poses saved yet (rhylib_pose_editor)", "info"
        end
        local target = ply
        if IsValid(ply) then
            local e = ply:GetEyeTrace().Entity
            if IsValid(e) and (e:IsPlayer() or e:IsNPC() or e:IsNextBot()) and e:GetPos():DistToSqr(ply:GetPos()) < 1500 * 1500 then target = e end
        end
        if not IsValid(target) then return "Look at someone (or run it in game)", "bad" end
        if name == "stop" then
            Po.Stop(target)
            return "Pose stopped", "good"
        end
        if not Po.defs[name] then return "No pose called \"" .. name .. "\" (!pose list)", "bad" end
        Po.Play(target, name)
        return "Playing \"" .. name .. "\" on " .. (target:IsPlayer() and target:Nick() or target:GetClass()), "good"
    end,
})

--------------------------------------------------------------------------
-- Weapon poses: filters
--------------------------------------------------------------------------

Po.FILTERS = {
    { id = "stance", name = "Stance", opts = { { "standing", "Standing" }, { "crouching", "Crouching" } } },
    { id = "moving", name = "Moving", opts = { { "still", "Idle" }, { "walking", "Walking" }, { "running", "Running" }, { "air", "In the air" } } },
    { id = "gun", name = "Gun", opts = { { "hip", "Hip" }, { "aiming", "Aiming" }, { "lowered", "Lowered / safety" } } },
    { id = "doing", name = "Doing", opts = { { "none", "Nothing" }, { "shooting", "Shooting" }, { "reloading", "Reloading" } } },
}
Po.DEFAULT_WHEN = { standing = true, still = true, hip = true, none = true }
local KNOWN = {}
for _, g in ipairs(Po.FILTERS) do for _, o in ipairs(g.opts) do KNOWN[o[1]] = true end end

-- Po.CleanWeapon(list) -> a checked copy of one weapon's list (at most 16).
function Po.CleanWeapon(list)
    if not istable(list) then return nil end
    local out = {}
    for _, e in ipairs(list) do
        if #out >= 16 then break end
        if istable(e) and isstring(e.pose) then
            local when = {}
            if istable(e.when) then
                for k, v in pairs(e.when) do if KNOWN[k] and v then when[k] = true end end
            end
            out[#out + 1] = { pose = Po.CleanName(e.pose), when = when }
        end
    end
    return #out > 0 and out or nil
end

function Po.State(ply)
    -- (once a frame per player: bones can be built several times a frame)
    local fn = FrameNumber and FrameNumber() or CurTime()
    if ply.rhylibPoseStF == fn and ply.rhylibPoseStV then return ply.rhylibPoseStV end
    local st = {}
    st[ply:Crouching() and "crouching" or "standing"] = true
    local speed = ply:GetVelocity():Length2D()
    if not ply:OnGround() and ply:GetMoveType() ~= MOVETYPE_LADDER then
        st.air = true
    elseif speed < 15 then
        st.still = true
    elseif speed > (ply:GetWalkSpeed() + ply:GetRunSpeed()) * 0.5 then
        st.running = true
    else
        st.walking = true
    end
    local w = ply:GetActiveWeapon()
    local gun, doing = "hip", "none"
    if IsValid(w) then
        if (w.GetSafety and w:GetSafety()) or (w.GetLowered and w:GetLowered()) then
            gun = "lowered"
        elseif w.GetAiming and w:GetAiming() then
            gun = "aiming"
        end
        local now = CurTime()
        if w.IsReloading and w:IsReloading() then
            doing = "reloading"
        elseif w.GetKickTime and (tonumber(w:GetKickTime()) or 0) > now - 0.4 then
            doing = "shooting"
        end
    end
    st[gun], st[doing] = true, true
    ply.rhylibPoseStF, ply.rhylibPoseStV = fn, st
    return st
end

-- Po.WeaponPose(ply) -> the pose name for what they hold and do now, or nil.
function Po.WeaponPose(ply)
    if not ply:IsPlayer() or not ply:Alive() then return nil end
    local w = ply:GetActiveWeapon()
    local list = IsValid(w) and Po.weapons[w:GetClass()]
    if not list then return nil end
    local st = Po.State(ply)
    for _, e in ipairs(list) do
        local fits = true
        for _, g in ipairs(Po.FILTERS) do
            local any = false
            for _, o in ipairs(g.opts) do
                if e.when[o[1]] and st[o[1]] then any = true break end
            end
            if not any then fits = false break end
        end
        if fits and Po.defs[e.pose] then return e.pose end
    end
    return nil
end

-- The fire gesture a weapon's recoil picks (both realms).
Po.shotAt = Po.shotAt or setmetatable({}, { __mode = "k" })
Rhylib.Hook.Add("DoAnimationEvent", "core.poses.recoil", function(ply, event)
    if event ~= PLAYERANIMEVENT_ATTACK_PRIMARY then return end
    -- (the shot's time for the kick on clients: the networked KickTime
    -- arrives a round trip late for other players)
    if CLIENT and IsFirstTimePredicted() then Po.shotAt[ply] = CurTime() end
    local w = ply:GetActiveWeapon()
    local g = IsValid(w) and Po.gear[w:GetClass()]
    local gest = g and g.recoil and g.recoil.gesture
    if not gest then return end
    -- (a fire mode with its own gesture keeps it, e.g. dual pistols)
    if w.ModeFireGestures and w.GetFireModeName and w.ModeFireGestures[w:GetFireModeName()] then return end
    if gest ~= "none" then
        if not Po.GestureOK(gest) then return end
        local act = _G[gest]
        if not isnumber(act) then return end
        ply:AnimRestartGesture(GESTURE_SLOT_ATTACK_AND_RELOAD, act, true)
    end
    return ACT_VM_PRIMARYATTACK
end)


--------------------------------------------------------------------------
-- Server: saving, sending, playing
--------------------------------------------------------------------------

if SERVER then
    Rhylib.Net.Register("poses.one")
    Rhylib.Net.Register("poses.wpn")

    local function sendWeapons(target)
        local data = util.Compress(util.TableToJSON({ w = Po.weapons, g = Po.gear }) or "{}") or ""
        Rhylib.Net.Start("poses.wpn")
        net.WriteUInt(#data, 32)
        net.WriteData(data, #data)
        if target then net.Send(target) else net.Broadcast() end
    end

    local loaded = false
    local function load()
        if loaded then return end
        loaded = true
        local all = Rhylib.Data and Rhylib.Data.Get("poses", "all")
        if istable(all) then
            for name, p in pairs(all) do
                local c = Po.Clean(p)
                -- (JSON turns a name like "212" into a number)
                if c then Po.defs[tostring(name)] = c end
            end
        end
        local gl = Rhylib.Data and Rhylib.Data.Get("poses", "gear")
        if istable(gl) then
            for class, g in pairs(gl) do
                local c = Po.CleanGear(g)
                if c then Po.gear[tostring(class)] = c end
            end
        end
        local wl = Rhylib.Data and Rhylib.Data.Get("poses", "weapons")
        if istable(wl) then
            for class, list in pairs(wl) do
                local c = Po.CleanWeapon(list)
                if c then Po.weapons[tostring(class)] = c end
            end
        end
    end
    timer.Simple(0, load)
    Po.Load = load

    local function save()
        if Rhylib.Data then Rhylib.Data.Set("poses", "all", Po.defs) end
    end

    local function sendOne(name, target)
        local p = Po.defs[name]
        Rhylib.Net.Start("poses.one")
        net.WriteString(name)
        net.WriteString(p and (util.TableToJSON(p) or "") or "")
        if target then net.Send(target) else net.Broadcast() end
    end

    Rhylib.Net.Receive("poses.req", function(ply)
        load()
        if ply.rhylibPosesSent then return end
        ply.rhylibPosesSent = true
        sendWeapons(ply)
        -- (one a tick, so a joiner's channel never overflows)
        local names = table.GetKeys(Po.defs)
        if #names == 0 then return end   -- (0 repeats would be forever)
        local i = 0
        local id = "Rhylib.PosesSend." .. ply:EntIndex()
        timer.Create(id, 0.05, #names, function()
            i = i + 1
            if IsValid(ply) and names[i] and Po.defs[names[i]] then sendOne(names[i], ply) end
        end)
    end, { rate = 1, burst = 2 })

    local cleanName = Po.CleanName

    Rhylib.Net.Receive("poses.save", function(ply)
        local name = cleanName(net.ReadString())
        local js = net.ReadString() or ""
        if name == "" then return end
        -- (the permission first: nothing is read for someone who can't save)
        Rhylib.Perms.Check(ply, "rhylib.poses.edit", function(ok)
            if not ok then return Rhylib.Notify(ply, "You can't save poses", "bad", "Poses") end
            local p = Po.Clean(util.JSONToTable(js))
            if not p then return Rhylib.Notify(ply, "That pose couldn't be read", "bad", "Poses") end
            load()
            if not Po.defs[name] and table.Count(Po.defs) >= MAX_POSES then
                return Rhylib.Notify(ply, "Too many poses saved (" .. MAX_POSES .. "): delete some first", "bad", "Poses")
            end
            Po.defs[name] = p
            save()
            sendOne(name)
            Rhylib.Notify(ply, "Pose \"" .. name .. "\" saved", "good", "Poses")
        end)
    end, { rate = 4, burst = 6 })

    Rhylib.Net.Receive("poses.del", function(ply)
        local name = cleanName(net.ReadString())
        Rhylib.Perms.Check(ply, "rhylib.poses.edit", function(ok)
            if not ok or not Po.defs[name] then return end
            Po.defs[name] = nil
            save()
            sendOne(name)
            Rhylib.Notify(ply, "Pose \"" .. name .. "\" deleted", "info", "Poses")
        end)
    end, { rate = 4, burst = 4 })

    Rhylib.Net.Receive("poses.wpnset", function(ply)
        local class = string.sub(net.ReadString(), 1, 64)
        local js = net.ReadString() or ""
        Rhylib.Perms.Check(ply, "rhylib.poses.edit", function(ok)
            if not ok then
                Rhylib.Notify(ply, "You can't change weapon poses", "bad", "Poses")
                return sendWeapons(ply)
            end
            if not weapons.GetStored(class) then
                Rhylib.Notify(ply, "\"" .. class .. "\" isn't a weapon class", "bad", "Poses")
                return sendWeapons(ply)
            end
            load()
            Po.weapons[class] = js ~= "" and Po.CleanWeapon(util.JSONToTable(js)) or nil
            if Rhylib.Data then Rhylib.Data.Set("poses", "weapons", Po.weapons) end
            sendWeapons()
        end)
    end, { rate = 6, burst = 8 })

    Rhylib.Net.Receive("poses.gearset", function(ply)
        local class = string.sub(net.ReadString(), 1, 64)
        local js = net.ReadString() or ""
        Rhylib.Perms.Check(ply, "rhylib.poses.edit", function(ok)
            if not ok or not weapons.GetStored(class) then return sendWeapons(ply) end
            load()
            Po.gear[class] = js ~= "" and Po.CleanGear(util.JSONToTable(js)) or nil
            if Rhylib.Data then Rhylib.Data.Set("poses", "gear", Po.gear) end
            sendWeapons()
        end)
    end, { rate = 6, burst = 8 })

    Rhylib.Net.Receive("poses.give", function(ply)
        local class = string.sub(net.ReadString(), 1, 64)
        Rhylib.Perms.Check(ply, "rhylib.poses.edit", function(ok)
            if not ok or not IsValid(ply) or not ply:Alive() or not weapons.GetStored(class) or string.find(class, "_base", 1, true) then return end
            if not ply:HasWeapon(class) then ply:Give(class) end
            ply:SelectWeapon(class)
        end)
    end, { rate = 2, burst = 3 })

    -- Sling spots: each player's carried-not-held weapons that have one,
    -- for every client to draw (NW2String rhylib_sling "class,class").
    timer.Create("Rhylib.Poses.Sling", 1, 0, function()
        local any = false
        for _, g in pairs(Po.gear) do if g.sling then any = true break end end
        for _, p in ipairs(player.GetAll()) do
            local list = ""
            if any and p:Alive() then
                local held = p:GetActiveWeapon()
                local out = {}
                for _, w in ipairs(p:GetWeapons()) do
                    local g = Po.gear[w:GetClass()]
                    if w ~= held and g and g.sling then out[#out + 1] = w:GetClass() end
                end
                table.sort(out)
                list = table.concat(out, ",")
            end
            if p:GetNW2String("rhylib_sling", "") ~= list then p:SetNW2String("rhylib_sling", list) end
        end
    end)

    function Po.Play(ent, name, fade)
        if not IsValid(ent) then return end
        ent:SetNW2String("rhylib_pose", name or "")
        ent:SetNW2Float("rhylib_poseAt", CurTime())
        ent:SetNW2Float("rhylib_poseFade", tonumber(fade) or 0.25)
    end
    function Po.Stop(ent, fade) Po.Play(ent, "", fade) end

    return
end

--------------------------------------------------------------------------
-- Client: receiving, drawing
--------------------------------------------------------------------------

Rhylib.Net.Receive("poses.one", function()
    local name, js = net.ReadString(), net.ReadString()
    Po.defs[name] = js ~= "" and Po.Clean(util.JSONToTable(js)) or nil
    if Po.onChanged then Po.onChanged(name) end
end)
Rhylib.Net.Receive("poses.wpn", function()
    local len = net.ReadUInt(32)
    local t = util.JSONToTable(util.Decompress(net.ReadData(len) or "") or "") or {}
    -- (Po.gearHold: the pose editor is sending this weapon's gear: keep ours)
    local hold = Po.gearHold
    local keep = hold and Po.gear[hold]
    Po.weapons, Po.gear = {}, {}
    for class, list in pairs(istable(t.w) and t.w or {}) do
        local c = Po.CleanWeapon(list)
        if c then Po.weapons[tostring(class)] = c end
    end
    for class, g in pairs(istable(t.g) and t.g or {}) do
        local c = Po.CleanGear(g)
        if c then Po.gear[tostring(class)] = c end
    end
    if hold then Po.gear[hold] = keep end
    if Po.onWeaponsChanged then Po.onWeaponsChanged() end
end)
Rhylib.Hook.Add("InitPostEntity", "core.poses", function()
    Rhylib.Net.Start("poses.req")
    net.SendToServer()
end)

-- Per model: bone ids by name, parents, and the order parents-first.
local models = {}
function Po.ModelInfo(ent)
    local mdl = ent:GetModel()
    if not mdl then return nil end
    local info = models[mdl]
    if info then return info end
    info = { ids = {}, names = {}, parent = {}, order = {} }
    local n = ent:GetBoneCount() or 0
    if n <= 0 then return nil end   -- (not loaded yet: ask again later)
    local depth = {}
    for i = 0, n - 1 do
        local name = ent:GetBoneName(i)
        info.ids[name] = i
        info.names[i] = name
        info.parent[i] = ent:GetBoneParent(i)
    end
    for i = 0, n - 1 do
        local d, p = 0, info.parent[i]
        while p and p >= 0 and d < 64 do d = d + 1 p = info.parent[p] end
        depth[i] = d
        info.order[#info.order + 1] = i
    end
    table.sort(info.order, function(a, b) return depth[a] < depth[b] end)
    models[mdl] = info
    return info
end

-- What pose (and weight) an entity shows now.
local local_ = setmetatable({}, { __mode = "k" })   -- [ent] = { name, at }
function Po.SetLocal(ent, name)
    if not IsValid(ent) then return end
    local_[ent] = name and { name = name, at = CurTime() } or nil   -- ("" shows none)
    Po.Hook(ent)
end

local function current(ent)
    local pv = Po.preview
    if pv and pv.ent == ent and pv.pose then return pv.pose, pv.t or 0, 1 end
    local l = local_[ent]
    local name, at = l and l.name, l and l.at
    if not name then
        name = ent:GetNW2String("rhylib_pose", "")
        at = ent:GetNW2Float("rhylib_poseAt", 0)
    end
    -- (nothing else on: the held weapon's pose for what they do now)
    if not l and name == "" and next(Po.weapons) then
        local wn = Po.WeaponPose(ent)
        local ws = ent.rhylibWpnPose
        local now0 = CurTime()
        -- (a pose that stops fitting is kept 0.3 s, so a slow gun's shots
        -- or a stop-start walk don't make it blink)
        if wn and ws and ws.name == wn then
            ws.lost = nil
        elseif ws and (not ws.lost or now0 - ws.lost < 0.3) and Po.defs[ws.name] then
            ws.lost = ws.lost or now0
            wn = ws.name
        elseif wn then
            -- (the same pose coming back while it fades out keeps its time)
            local st0 = ent.rhylibPoseSt
            ws = { name = wn, at = (st0 and st0.name == wn and st0.w > 0 and st0.at) or now0 }
            ent.rhylibWpnPose = ws
        else
            ent.rhylibWpnPose = nil
        end
        if wn then name, at = wn, ent.rhylibWpnPose.at end
    end
    -- (fading: the last pose eases out, a new one eases in)
    local now = CurTime()
    local st = ent.rhylibPoseSt
    if not st then st = { w = 0 } ent.rhylibPoseSt = st end
    local fade = math.max(0.05, ent:GetNW2Float("rhylib_poseFade", 0.25))
    -- (by real time passed: bones can be built more than once a frame)
    local dt = math.Clamp(now - (st.last or now), 0, 0.2)
    st.last = now
    if name ~= "" and Po.defs[name] then
        if st.name ~= name and st.w > 0 and st.name and Po.defs[st.name] then
            -- (another pose: the old one eases out first, then the new one in)
            st.w = math.Approach(st.w, 0, dt / fade)
        else
            if st.name ~= name then st.w = 0 end
            st.name, st.at = name, at
            st.w = math.Approach(st.w, 1, dt / fade)
        end
    else
        st.w = math.Approach(st.w, 0, dt / fade)
    end
    if st.w <= 0 or not st.name or not Po.defs[st.name] then return nil end
    return Po.defs[st.name], now - (st.at or now), st.w
end

local function apply(ent)
    local pv0 = Po.preview
    if pv0 and pv0.ent == ent then ent.rhylibPoseDbg = nil end   -- (only this frame's handles)
    ent.rhylibPoseGun = nil   -- (set again below if a pose moves the gun this build)
    local pose, t, w = current(ent)
    local info = Po.ModelInfo(ent)
    if not info then return end
    local extras
    if pose then
        local bones
        bones, extras = Po.Sample(pose, t)
        local byId = {}
        local any = false
        for name, b in pairs(bones) do
            local id = info.ids[name]
            if id then byId[id] = b any = true end
        end
        if any then Po.ApplyBones(ent, info, byId, pose.mode == "set", w) end
        -- (the hand bones' own numbers: a fine turn / move on top of where
        -- IK or a grip puts the hand)
        extras.hbR, extras.hbL = bones["ValveBiped.Bip01_R_Hand"], bones["ValveBiped.Bip01_L_Hand"]
    end
    -- (the weapon's recoil: its recoil pose on top, and the gun's kick)
    local kick = Po.ApplyRecoil(ent, info)
    extras = extras or {}
    extras.kick = kick
    -- (hand IK kept from the body first: an anchor hand moved by it carries
    -- the gun; then the gun; then hand IK kept from the gun)
    local ik = pose and pose.ik
    if ik then Po.ApplyHandIK(ent, info, pose, extras, w, "body") end
    if pose and pose.anchor and extras.gun then
        Po.ApplyGun(ent, info, pose, extras, w)
    else
        -- (no pose moving the gun: the kick turns the right hand, then the
        -- weapon's own hand locks, if any)
        if kick then
            local wep = ent.GetActiveWeapon and ent:GetActiveWeapon()
            local gl = IsValid(wep) and Po.gear[wep:GetClass()]
            local lk = gl and Po.LockFor(gl, pose)
            Po.KickHand(ent, info, kick, (lk and lk.l) or (pose and pose.ik and pose.ik.l))
        end
        Po.ApplyLock(ent, info, pose)
    end
    if ik then Po.ApplyHandIK(ent, info, pose, extras, w, "gun") end
end

function Po.ApplyBones(ent, info, byId, set, w)
    local orig, newM, delta = {}, {}, {}
    for _, i in ipairs(info.order) do
        local old = ent:GetBoneMatrix(i)
        if old then
            orig[i] = old
            local p = info.parent[i]
            local m, changed = old, false
            if p and p >= 0 and delta[p] then m = delta[p] * old changed = true end
            local b = byId[i]
            if b then
                if set then
                    -- (the turn relative to the parent, blended from the animation's)
                    local po, pn = p and p >= 0 and orig[p], p and p >= 0 and (newM[p] or orig[p])
                    if po and pn then
                        local loc = po:GetInverse() * old
                        local nl = Matrix()
                        nl:SetTranslation(loc:GetTranslation() + b.v * w)
                        nl:SetAngles(slerp(loc:GetAngles(), b.a, w))
                        m = pn * nl
                        changed = true
                    end
                else
                    m = Matrix(m)
                    m:Rotate(w >= 1 and b.a or slerp(angle_zero, b.a, w))
                    m:Translate(b.v * w)
                    changed = true
                end
            end
            if changed then
                ent:SetBoneMatrix(i, m)
                newM[i] = m
                delta[i] = m * old:GetInverse()
            end
        end
    end
end
Po.Apply = apply

--------------------------------------------------------------------------
-- The held gun and the hands on it
--------------------------------------------------------------------------

local function mat(pos, ang) local m = Matrix() m:SetTranslation(pos) m:SetAngles(ang) return m end
local function rigid(m) return mat(m:GetTranslation(), m:GetAngles()) end
local function bone(info, name) return info.ids["ValveBiped.Bip01_" .. name] end
local ANCHOR = { chest = "Spine4", hips = "Pelvis", rhand = "R_Hand", lhand = "L_Hand" }

-- Every bone under id (cached per model).
local function under(info, id)
    info.under = info.under or {}
    local set = info.under[id]
    if set then return set end
    set = {}
    for _, i in ipairs(info.order) do
        local p = info.parent[i]
        if p == id or (p and set[p]) then set[i] = true end
    end
    info.under[id] = set
    return set
end

-- m turned about its own origin so direction from points along to.
local function swing(m, from, to)
    local a, b = from:GetNormalized(), to:GetNormalized()
    local axis = a:Cross(b)
    local sn = axis:Length()
    if sn < 1e-5 then
        if a:Dot(b) > 0 then return rigid(m) end
        -- (straight back: half a turn about any axis across it)
        axis = a:Cross(math.abs(a.z) < 0.9 and Vector(0, 0, 1) or Vector(1, 0, 0))
        sn = axis:Length()
    end
    axis:Mul(1 / sn)
    local deg = math.deg(math.atan2(sn, a:Dot(b)))
    local ang = m:GetAngles()
    ang:RotateAroundAxis(axis, deg)
    return mat(m:GetTranslation(), ang)
end

-- Two-bone IK: the arm (side "R" / "L") reaches target (a matrix: where the
-- hand goes and how it turns), elbow bending toward pole; every bone under
-- the upper arm follows.
local function reach(ent, info, side, target, pole)
    local iu, iff, ih = bone(info, side .. "_UpperArm"), bone(info, side .. "_Forearm"), bone(info, side .. "_Hand")
    if not (iu and iff and ih) then return nil end
    local U, F, H = ent:GetBoneMatrix(iu), ent:GetBoneMatrix(iff), ent:GetBoneMatrix(ih)
    if not (U and F and H) then return nil end
    local S, E, W = U:GetTranslation(), F:GetTranslation(), H:GetTranslation()
    local a, b = S:Distance(E), E:Distance(W)
    local T = target:GetTranslation()
    local toT = T - S
    if toT:LengthSqr() < 1e-4 then return nil end
    local d = math.Clamp(toT:Length(), math.abs(a - b) + 0.01, a + b - 0.01)
    local n = toT:GetNormalized()
    local pv = (pole or E) - S
    pv = pv - n * pv:Dot(n)
    if pv:LengthSqr() < 1e-4 then pv = (E - S) - n * (E - S):Dot(n) end
    if pv:LengthSqr() < 1e-4 then pv = Vector(0, 0, -1) end
    pv:Normalize()
    local ca = math.Clamp((a * a + d * d - b * b) / (2 * a * d), -1, 1)
    local E2 = S + n * (a * ca) + pv * (a * math.sqrt(1 - ca * ca))
    local W2 = S + n * d
    -- (the new upper arm, forearm and hand, then the bones under them)
    local nU = swing(U, E - S, E2 - S)
    local dU = nU * rigid(U):GetInverseTR()
    local F1 = dU * rigid(F)
    local W1 = (dU * rigid(H)):GetTranslation()
    local nF = swing(F1, W1 - E2, W2 - E2)
    nF:SetTranslation(E2)
    local nH = mat(W2, target:GetAngles())
    local fixed = { [iu] = nU, [iff] = nF, [ih] = nH }
    local old = {}
    local set = under(info, iu)
    for i in pairs(set) do old[i] = ent:GetBoneMatrix(i) end
    old[iu] = U
    local news = {}
    for i, m in pairs(fixed) do
        local sc = old[i] and old[i]:GetScale() or Vector(1, 1, 1)
        if sc.x ~= 1 or sc.y ~= 1 or sc.z ~= 1 then m:Scale(sc) end
        ent:SetBoneMatrix(i, m)
        news[i] = m
    end
    -- (the wrist's twist helpers share the hand's turn round the forearm,
    -- so the skin there doesn't wring: Ulna half, Wrist most of it)
    local axis = (W2 - E2):GetNormalized()
    local Hc = nF * rigid(F):GetInverseTR() * rigid(H)
    local function flat(v) v = v - axis * v:Dot(axis) return v:GetNormalized() end
    local u1, u2 = flat(Hc:GetUp()), flat(nH:GetUp())
    local twist = math.deg(math.atan2(axis:Dot(u1:Cross(u2)), u1:Dot(u2)))
    local share = {}
    for i in pairs(set) do
        if info.parent[i] == iff then
            local n = string.lower(info.names[i] or "")
            if string.find(n, "ulna", 1, true) then share[i] = 0.5 elseif string.find(n, "wrist", 1, true) then share[i] = 0.9 end
        end
    end
    for _, i in ipairs(info.order) do
        if set[i] and not fixed[i] and old[i] then
            local p = info.parent[i]
            local np, op = news[p], old[p]
            if np and op then
                local m = np * op:GetInverse() * old[i]
                if share[i] and math.abs(twist) > 0.01 then
                    local a = m:GetAngles()
                    a:RotateAroundAxis(axis, twist * share[i])
                    m:SetAngles(a)
                end
                ent:SetBoneMatrix(i, m)
                news[i] = m
            end
        end
    end
    return E2, nH
end
Po.Reach = reach

-- handTweak(T, b, w): T turned / moved by the pose's own hand bone values
-- (as an Add-mode offset, whatever the pose's mode), eased by w.
local function handTweak(T, b, w)
    if not b then return T end
    local m = Matrix(T)
    m:Rotate(w >= 1 and b.a or slerp(angle_zero, b.a, w))
    m:Translate(b.v * w)
    return m
end
Po.HandTweak = handTweak

-- Recoil: Po.gear[class].recoil = { gesture, pose, back, up, side,
-- length, strength }: the third-person fire gesture ("ACT_..." name,
-- "none", nil = the hold type's), a saved pose added on top for each shot
-- (Add-style, eased by the kick), and the gun's kick (back in units, up /
-- side in degrees) over length seconds, from the last shot (the weapon's
-- KickTime; Po.fakeShot[ent] for the editor's fire loop).
Po.fakeShot = Po.fakeShot or setmetatable({}, { __mode = "k" })
-- (full at the shot, easing out; a new shot starts it full again, so
-- automatic fire stays kicked instead of snapping back each round)
local function recoilK(ent, wep, rc)
    local kt = wep.GetKickTime and (tonumber(wep:GetKickTime()) or 0) or 0
    local last = Po.fakeShot[ent] or 0
    -- (other players: the gesture's shot clock; yourself / no gesture: KickTime)
    local sa = Po.shotAt and Po.shotAt[ent]
    if CLIENT and ent ~= LocalPlayer() and sa and wep.PlayerFireAnim ~= false then last = math.max(last, sa) else last = math.max(last, kt) end
    if last <= 0 then return 0 end
    local dt = math.max(0, CurTime() - last)
    local len = rc.length or 0.2
    if dt > len then return 0 end
    local f = dt / len
    return (1 - f) * (1 - f)
end
Po.RecoilK = recoilK

function Po.ApplyRecoil(ent, info)
    local wep = ent.GetActiveWeapon and ent:GetActiveWeapon()
    if not IsValid(wep) then return nil end
    local g = Po.gear[wep:GetClass()]
    local rc = g and g.recoil
    if not rc then return nil end
    local k = recoilK(ent, wep, rc) * (rc.strength or 1)
    if k <= 0 then return nil end
    local rp = rc.pose and Po.defs[rc.pose]
    if rp then
        local bones = Po.Sample(rp, 0)
        local byId = {}
        local any = false
        for name, b in pairs(bones) do
            local id = info.ids[name]
            if id then byId[id] = b any = true end
        end
        if any then Po.ApplyBones(ent, info, byId, false, math.min(1, k)) end
    end
    if (rc.back or 0) == 0 and (rc.up or 0) == 0 and (rc.side or 0) == 0 then return nil end
    return { back = (rc.back or 0) * k, up = (rc.up or 0) * k, side = (rc.side or 0) * k }
end

-- Po.KickMatrix(kick, Hold): the kick in the gun's own axes, turning about
-- the right-hand grip (not the model's origin): back along the barrel,
-- muzzle up, and sideways (positive = muzzle left).
function Po.KickMatrix(kp, Hold)
    local p = Hold:GetInverseTR():GetTranslation()
    local m = Matrix()
    m:Translate(Vector(-kp.back, 0, 0))
    m:Translate(p)
    m:Rotate(Angle(-kp.up, kp.side, 0))
    m:Translate(-p)
    return m
end

-- The kick with no pose moving the gun: the right hand turns so the gun
-- it holds kicks (the arm follows).
function Po.KickHand(ent, info, kp, leftPlaced)
    local wep = ent.GetActiveWeapon and ent:GetActiveWeapon()
    local irh = bone(info, "R_Hand")
    local RH = irh and ent:GetBoneMatrix(irh)
    if not (IsValid(wep) and RH) or (wep.GetFireModeName and wep:GetFireModeName() == "dual") then return end
    local hp, ha = Po.GunHold(wep)
    local Hold = mat(hp, ha)
    local K = Po.KickMatrix(kp, Hold)
    local G0 = rigid(RH) * Hold
    local M = G0 * K * G0:GetInverseTR()
    -- (the left hand goes with the gun unless a lock puts it on a spot)
    local ilh = bone(info, "L_Hand")
    local LH = ilh and ent:GetBoneMatrix(ilh)
    reach(ent, info, "R", M * rigid(RH), nil)
    if LH and not leftPlaced then reach(ent, info, "L", M * rigid(LH), nil) end
end

local function dual(wep) return wep.GetFireModeName and wep:GetFireModeName() == "dual" end

-- Po.SpotWorld(spots, name, G) -> the spot's world matrix (G = the gun's),
-- following parent spots (at most 8 deep), or nil.
function Po.SpotWorld(spots, name, G, depth)
    local sp = spots and spots[name]
    if not sp or (depth or 0) > 8 then return nil end
    local P = sp.parent == "@gun" and G or Po.SpotWorld(spots, sp.parent, G, (depth or 0) + 1)
    if not P then return nil end
    return P * mat(v3(sp.p), a3(sp.a))
end

-- Po.LockFor(gear, pose) -> { spots, r, l, reload, lowered }: the weapon's
-- spots and locks, with the pose's spots added and its locks over them.
function Po.LockFor(gear, pose)
    local spots = {}
    for n, sp in pairs(gear.spots or {}) do spots[n] = sp end
    for n, sp in pairs(pose and pose.spots or {}) do spots[n] = sp end
    local gl, pl = gear.lock or {}, pose and pose.lock or {}
    local function pick(side)
        local v = pl[side]
        if v == nil then v = gl[side] end
        return v or nil
    end
    return { spots = spots, r = pick("r"), l = pick("l"), reload = gl.reload, lowered = gl.lowered }
end

-- The weapon's hand locks with no pose moving the gun: the gun stays in
-- the right hand as the animation has it; a locked hand goes onto its spot
-- (the right one only to a spot that isn't on the gun it holds: skipped).
-- Eased off while reloading / lowered unless the lock keeps them.
-- How much a hand lock holds now (0-1, eased; off while reloading /
-- lowered unless the lock keeps them). Called once a bone build.
local function lockWeight(ent, wep, lk)
    local on = lk.l ~= nil
    if not lk.reload and wep.IsReloading and wep:IsReloading() then on = false end
    if not lk.lowered and ((wep.GetSafety and wep:GetSafety()) or (wep.GetLowered and wep:GetLowered())) then on = false end
    if ent.IsPlayer and ent:IsPlayer() and not ent:Alive() then on = false end
    local now = CurTime()
    local st = ent.rhylibLockSt or { w = 0 }
    ent.rhylibLockSt = st
    local dt = math.Clamp(now - (st.last or now), 0, 0.2)
    st.last = now
    st.w = math.Approach(st.w, on and 1 or 0, dt / 0.2)
    return st.w
end
local function blendM(a, b, k)
    if k >= 1 then return b end
    if k <= 0 then return a end
    return mat(LerpVector(k, a:GetTranslation(), b:GetTranslation()), slerp(a:GetAngles(), b:GetAngles(), k))
end

function Po.ApplyLock(ent, info, pose)
    if pose and pose.ik and pose.ik.l then return end   -- (hand IK wins)
    local wep = ent.GetActiveWeapon and ent:GetActiveWeapon()
    if not IsValid(wep) or dual(wep) then return end
    local gear = Po.gear[wep:GetClass()] or {}
    if not (gear.lock or (pose and pose.lock)) then return end
    local lk = Po.LockFor(gear, pose)
    local lw = lockWeight(ent, wep, lk)
    if not lk.l or lw <= 0 then return end
    local st = ent.rhylibLockSt
    local irh, ilh = bone(info, "R_Hand"), bone(info, "L_Hand")
    local RH, LH = irh and ent:GetBoneMatrix(irh), ilh and ent:GetBoneMatrix(ilh)
    if not (RH and LH) then return end
    local hp, ha = Po.GunHold(wep)
    local G = rigid(RH) * mat(hp, ha)
    local Lt = Po.SpotWorld(lk.spots, lk.l, G)
    if not Lt then return end
    reach(ent, info, "L", blendM(rigid(LH), Lt, st.w), nil)
end

function Po.ApplyGun(ent, info, pose, x, w)
    local wep = ent.GetActiveWeapon and ent:GetActiveWeapon()
    if not IsValid(wep) or dual(wep) then return end
    local ia = bone(info, ANCHOR[pose.anchor] or "Spine4")
    local ic, irh, ilh = bone(info, "Spine4"), bone(info, "R_Hand"), bone(info, "L_Hand")
    local A = ia and ent:GetBoneMatrix(ia)
    local C = ic and ent:GetBoneMatrix(ic)
    local RH, LH = irh and ent:GetBoneMatrix(irh), ilh and ent:GetBoneMatrix(ilh)
    if not (A and C and RH and LH) then return end
    local hp, ha = Po.GunHold(wep)
    local Hold = mat(hp, ha)
    -- (the gun as the animation holds it, and as the pose puts it)
    local Ganim = rigid(RH) * Hold
    local Gp = rigid(A) * mat(x.gun.p, x.gun.a)
    local G = Gp
    if w < 1 then G = mat(LerpVector(w, Ganim:GetTranslation(), Gp:GetTranslation()), slerp(Ganim:GetAngles(), Gp:GetAngles(), w)) end
    -- (the kick; not with a hand anchor: the gun goes with that hand)
    if x.kick and pose.anchor ~= "rhand" and pose.anchor ~= "lhand" then G = G * Po.KickMatrix(x.kick, Hold) end
    -- the left grip: this pose's, else the weapon's, else the animation's
    local g = pose.grip and pose.grip.l or (Po.gear[wep:GetClass()] or {}).lgrip
    local Lgrip = g and mat(v3(g.p), a3(g.a)) or (Ganim:GetInverseTR() * rigid(LH))
    local hands = pose.hands or {}
    local gear = Po.gear[wep:GetClass()] or {}
    local lk = Po.LockFor(gear, pose)
    local Rt = G * Hold:GetInverseTR()
    -- (a hand locked to a spot goes there instead)
    local rSpot = lk.r and Po.SpotWorld(lk.spots, lk.r, G)
    if rSpot then Rt = rSpot end
    local Cr = rigid(C)
    -- (the elbow points ease in with the pose too, from where the animation has them)
    local function pole(side, loc)
        if not loc then return nil end
        local P = (Cr * mat(loc, angle_zero)):GetTranslation()
        if w >= 1 then return P end
        local fb = bone(info, side .. "_Forearm")
        local F = fb and ent:GetBoneMatrix(fb)
        return F and LerpVector(w, F:GetTranslation(), P) or P
    end
    local ER, EL = pole("R", x.er), pole("L", x.el)
    local er, el, nH
    local ikr, ikl = pose.ik and pose.ik.r, pose.ik and pose.ik.l
    if hands.r ~= false and pose.anchor ~= "rhand" and not ikr then
        er, nH = reach(ent, info, "R", handTweak(Rt, x.hbR, w), ER)
        -- (out of reach: the gun stays in the hand where it got to)
        -- (the tweak is undone first: the gun follows the hand's grip, not the tweak)
        if nH and not rSpot then
            local tw = handTweak(Matrix(), x.hbR, w)
            G = rigid(nH) * tw:GetInverseTR() * Hold
        end
    end
    -- (the left hand's lock eases off for reloads / lowering here too; the
    -- pose eases in from where the hand is without it: on the weapon's own
    -- lock spot if it has one, else the animation's)
    local lw = lockWeight(ent, wep, lk)
    local Lt = G * Lgrip
    local lSpot = lk.l and Po.SpotWorld(lk.spots, lk.l, G)
    if lSpot then Lt = blendM(Lt, lSpot, lw) end
    if w < 1 then
        local from = rigid(LH)
        local wl = Po.LockFor(gear, nil)
        local ws = wl.l and Po.SpotWorld(wl.spots, wl.l, Ganim)
        if ws then from = blendM(from, ws, lw) end
        Lt = blendM(from, Lt, w)
    end
    if hands.l ~= false and pose.anchor ~= "lhand" and not ikl then el = reach(ent, info, "L", handTweak(Lt, x.hbL, w), EL) end
    ent.rhylibPoseGun = { f = FrameNumber(), pos = G:GetTranslation(), ang = G:GetAngles() }
    local pv = Po.preview
    if pv and pv.ent == ent then
        local d = ent.rhylibPoseDbg or {}
        d.G, d.A, d.chest, d.R, d.L, d.hold = G, rigid(A), Cr, Rt, Lt, Hold
        d.ER, d.EL = d.ER or er or ER, d.EL or el or EL
        ent.rhylibPoseDbg = d
    end
end

-- The gun's world matrix for hand IK kept from it: where the pose puts it
-- this frame, else in the right hand as held (nil = no gun).
local function gunWorldOf(ent, info)
    local pg = ent.rhylibPoseGun
    if pg and pg.f == FrameNumber() then return mat(pg.pos, pg.ang), true end
    local wep = ent.GetActiveWeapon and ent:GetActiveWeapon()
    if not IsValid(wep) or dual(wep) or not info then return nil end
    local irh = bone(info, "R_Hand")
    local RH = irh and ent:GetBoneMatrix(irh)
    if not RH then return nil end
    local hp, ha = Po.GunHold(wep)
    return rigid(RH) * mat(hp, ha), false
end
Po.GunWorldOf = gunWorldOf


-- Hand IK: a hand with pose.ik[side] on goes to that key's target (from
-- the chest, the hips or the gun), the arm solved to reach it, the elbow
-- bending toward the key's elbow point. pass "body": the chest / hips
-- ones; "gun": the gun ones (the right hand only when a pose moves the
-- gun: it holds it otherwise).
local IK_FRAME = { chest = "Spine4", hips = "Pelvis" }
function Po.ApplyHandIK(ent, info, pose, x, w, pass)
    local ic = bone(info, "Spine4")
    local C = ic and ent:GetBoneMatrix(ic)
    if not C then return end
    local Cr = rigid(C)
    local pv = Po.preview
    local dbgOn = pv and pv.ent == ent
    for _, sd in ipairs({ { "r", "R", x.hr, x.er }, { "l", "L", x.hl, x.el } }) do
        local cfg = pose.ik[sd[1]]
        local tgt = sd[3]
        local rel = cfg and cfg.rel
        if cfg and tgt and ((pass == "gun") == (rel == "gun")) then
            local F
            if rel == "gun" then
                local G, moved = gunWorldOf(ent, info)
                if G and (sd[1] == "l" or moved) then F = G end
            else
                local fb = bone(info, IK_FRAME[rel] or "Spine4")
                local M = fb and ent:GetBoneMatrix(fb)
                F = M and rigid(M)
            end
            local hb = bone(info, sd[2] .. "_Hand")
            local H = hb and ent:GetBoneMatrix(hb)
            if F and H then
                local T = handTweak(F * mat(tgt.p, tgt.a), sd[2] == "R" and x.hbR or x.hbL, 1)
                if w < 1 then T = blendM(rigid(H), T, w) end
                local pole
                if sd[4] then
                    pole = (Cr * mat(sd[4], angle_zero)):GetTranslation()
                    if w < 1 then
                        local fb = bone(info, sd[2] .. "_Forearm")
                        local Fm = fb and ent:GetBoneMatrix(fb)
                        if Fm then pole = LerpVector(w, Fm:GetTranslation(), pole) end
                    end
                end
                local e2 = reach(ent, info, sd[2], T, pole)
                if dbgOn then
                    local d = ent.rhylibPoseDbg or {}
                    d.chest = d.chest or Cr
                    d["H" .. sd[2]], d["F" .. sd[2]] = T, F
                    d["E" .. sd[2]] = e2 or pole or d["E" .. sd[2]]
                    ent.rhylibPoseDbg = d
                end
            end
        end
    end
end

-- Po.Hook(ent): make sure ent draws poses (once per entity).
function Po.Hook(ent)
    if not IsValid(ent) or ent.rhylibPoseCb then return end
    ent.rhylibPoseCb = true
    ent:AddCallback("BuildBonePositions", function(e) Po.Apply(e) end)
end

-- Anything given a pose (NW2) gets the callback when it shows up.
local nextScan = 0
Rhylib.Hook.Add("Think", "core.poses", function()
    local now = CurTime()
    if now < nextScan then return end
    nextScan = now + 0.5
    local pv = Po.preview
    if pv and IsValid(pv.ent) then Po.Hook(pv.ent) end
    if not next(Po.defs) and not next(Po.gear) then return end
    for _, p in ipairs(player.GetAll()) do
        local w = p:GetActiveWeapon()
        if p:GetNW2String("rhylib_pose", "") ~= "" or (IsValid(w) and (Po.weapons[w:GetClass()] or Po.gear[w:GetClass()])) then Po.Hook(p) end
    end
    -- (NPCs and nextbots, the droids and clones too, that came into view
    -- with a pose already on)
    for _, e in ents.Iterator() do
        if not e.rhylibPoseCb and (e:IsNPC() or e:IsNextBot()) and e:GetNW2String("rhylib_pose", "") ~= "" then Po.Hook(e) end
    end
end)
Rhylib.Hook.Add("EntityNetworkedVarChanged", "core.poses", function(ent, name, _, new)
    if name == "rhylib_pose" and new ~= "" then Po.Hook(ent) end
end)

--------------------------------------------------------------------------
-- Sling spots: weapons carried but not held, on the body
--------------------------------------------------------------------------

local slung = {}   -- [ply] = { [class] = ClientsideModel } (cleaned by the timer below)
local function slingModel(ply, w, class)
    local per = slung[ply]
    if not per then per = {} slung[ply] = per end
    local mdl = w.PropModel or w.WorldModel
    if not mdl or mdl == "" then return nil end
    local cm = per[class]
    if IsValid(cm) and cm:GetModel() == mdl then return cm end
    if IsValid(cm) then cm:Remove() end
    cm = ClientsideModel(mdl, RENDERGROUP_OPAQUE)
    if not IsValid(cm) then return nil end
    cm:SetNoDraw(true)
    cm:SetModelScale(w.PropScale or 1, 0)
    per[class] = cm
    return cm
end
Po.SlingModel = slingModel

-- Po.SlingSpot(ply, class) -> pos, ang (nil = none, or that bone missing).
function Po.SlingSpot(ply, class, sling)
    sling = sling or (Po.gear[class] or {}).sling
    if not sling then return nil end
    local b = ply:LookupBone(sling.bone)
    local m = b and ply:GetBoneMatrix(b)
    if not m then return nil end
    return LocalToWorld(v3(sling.p), a3(sling.a), m:GetTranslation(), m:GetAngles())
end

-- (a weapon's fields with its base's, once per class)
local sweps = {}
local function swepOf(class)
    local w = sweps[class]
    if w == nil then w = weapons.Get(class) or false sweps[class] = w end
    return w or nil
end
-- (which weapons each player has on a spot comes from the server, NW2
-- String rhylib_sling "class,class": other players' weapons not in their
-- hands aren't always sent to clients)
Rhylib.Hook.Add("PostPlayerDraw", "core.poses.sling", function(ply)
    if not next(Po.gear) or not ply:Alive() then return end
    if Rhylib.NW and Rhylib.NW.CLOAK and ply ~= LocalPlayer() and ply:GetNW2Bool(Rhylib.NW.CLOAK, false) then return end
    local list = ply:GetNW2String("rhylib_sling", "")
    if list == "" then return end
    local held = ply:GetActiveWeapon()
    local heldClass = IsValid(held) and held:GetClass()
    for class in string.gmatch(list, "[^,]+") do
        local w = class ~= heldClass and swepOf(class)
        local g = Po.gear[class]
        if w and g and g.sling then
            local pos, ang = Po.SlingSpot(ply, class, g.sling)
            local cm = pos and slingModel(ply, w, class)
            if cm then
                cm:SetPos(pos)
                cm:SetAngles(ang)
                cm:SetupBones()
                cm:DrawModel()
            end
        end
    end
end)
-- (models of players who left, or weapons no longer carried)
timer.Create("Rhylib.Poses.SlingClean", 10, 0, function()
    sweps = {}   -- (picks up model changes)
    for ply, per in pairs(slung) do
        for class, cm in pairs(per) do
            if not IsValid(ply) or not string.find("," .. ply:GetNW2String("rhylib_sling", "") .. ",", "," .. class .. ",", 1, true) then
                if IsValid(cm) then cm:Remove() end
                per[class] = nil
            end
        end
        if not IsValid(ply) then slung[ply] = nil end
    end
end)
