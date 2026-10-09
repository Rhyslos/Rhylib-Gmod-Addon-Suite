--[[
    Downed state (server).

    Lethal damage is cut to leave 1 HP (EntityTakeDamage, after armour);
    once the engine has applied it (PostEntityTakeDamage, took = true) the
    player goes down. Blocked damage (no friendly fire, god mode) never
    downs anyone. Damage to a downed player is left alone: it comes off
    the downed pool and kills normally at 0.

    A 0.1 s timer runs while anyone is down, dragging or helping: it bleeds
    out, checks stabilisers, drags and actions (sv_20_actions.lua). With
    nobody down it returns at once.
]]

local Med = Rhylib.Medical

Med.down = Med.down or {}           -- [ply] = { attacker, inflictor }
Med.acts = Med.acts or {}           -- [helper] = action (sv_20_actions.lua)
Med.downList = Med.downList or {}   -- array of downed players (for aim checks)

local function rebuildList()
    local list = {}
    for ply in pairs(Med.down) do
        if IsValid(ply) then list[#list + 1] = ply end
    end
    Med.downList = list
end

Rhylib.Net.Register("med.note")

-- A short message under the crosshair.
function Med.Note(ply, text)
    Rhylib.Net.Start("med.note")
    net.WriteString(text)
    net.Send(ply)
end

-- Within reach of a body or a standing player.
-- Nothing solid (walls, props, doors) between the helper's eyes and the
-- target's body.
local seeTr = {}
local seeData = { mask = MASK_SOLID, output = seeTr }
local function seeClear(helper, target, pos)
    seeData.start = helper:EyePos()
    seeData.endpos = pos
    -- (the target's own ragdoll body doesn't block the view of it)
    local rag = Rhylib.Lying and Rhylib.Lying.Ragdoll and Rhylib.Lying.Ragdoll(target)
    seeData.filter = rag and { helper, target, rag } or { helper, target }
    util.TraceLine(seeData)
    return not seeTr.Hit
end

function Med.CanSee(helper, target)
    if not target.rhylibDown then return seeClear(helper, target, target:WorldSpaceCenter()) end
    -- Downed: the position or the measured body is enough.
    return seeClear(helper, target, target:GetPos() + Vector(0, 0, 12)) or seeClear(helper, target, Med.BodyPos(target))
end

local function near(a, b, range)
    return math.abs(a.z - b.z) < 72 and (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 <= range * range
end

-- Downed targets: their position or the measured body, with extra room
-- (each client's ragdoll lies a little differently).
function Med.InRange(helper, target, slack)
    local a = helper:GetPos()
    local range = Med.Cfg("range") + (slack or 0)
    if not target.rhylibDown then return near(a, target:GetPos(), range) end
    return near(a, target:GetPos(), range + 40) or near(a, Med.BodyPos(target), range + 40)
end

--------------------------------------------------------------------------
-- Going down and getting up
--------------------------------------------------------------------------

function Med.Down(ply, attacker, inflictor)
    if Med.down[ply] or not ply:Alive() then return end
    Med.down[ply] = { attacker = attacker, inflictor = inflictor }
    rebuildList()
    ply.rhylibDown = true

    if ply:InVehicle() then ply:ExitVehicle() end
    -- Off a grapple rope, jetpack flames off (rhylib_weapons, rhylib_jetpack).
    local G = Rhylib.Weapons and Rhylib.Weapons.Grapple
    if G and G.Detach and G.Attached and G.Attached(ply) then G.Detach(ply) end
    local J = Rhylib.Jetpack
    if J and J.DT_THRUST and ply:GetDTBool(J.DT_THRUST) then ply:SetDTBool(J.DT_THRUST, false) end
    Med.Cancel(ply)
    Med.StopDrag(ply)
    if Med.TankExit and ply.rhylibTank then Med.TankExit(ply) end   -- (out of the bacta tank first)
    if Rhylib.Inventory and Rhylib.Inventory.Stow then Rhylib.Inventory.Stow(ply) end

    -- (simplified medical system: downHealth is a percent of max health)
    local pool = Med.Cfg("downHealth")
    if Med.Simple() then pool = math.max(1, math.ceil(ply:GetMaxHealth() * pool / 100)) end
    ply:SetHealth(pool)
    ply:SetNW2Float("rhylib_downYaw", ply:EyeAngles().y)
    ply:SetNW2Float("rhylib_downEnd", CurTime() + Med.Cfg("bleedTime"))
    ply:SetNW2Float("rhylib_downLeft", 0)
    ply:SetNW2Entity("rhylib_stabBy", NULL)
    ply:SetNW2Entity("rhylib_dragBy", NULL)
    ply:SetNW2Bool("rhylib_down", true)

    -- Lying body: low camera, small hull, hit bounds wide enough for the
    -- whole body (it reaches past the hull).
    ply.rhylibViewOff = ply.rhylibViewOff or { ply:GetViewOffset(), ply:GetViewOffsetDucked() }
    ply:SetViewOffset(Med.VIEW_DOWN)
    ply:SetViewOffsetDucked(Med.VIEW_DOWN)
    Med.ApplyHull(ply, true)
    ply:SetSurroundingBounds(Vector(-48, -48, 0), Vector(48, 48, 32))
    -- Players walk over the body instead of bumping into it; shots still hit.
    ply.rhylibCollision = ply.rhylibCollision or ply:GetCollisionGroup()
    ply:SetCollisionGroup(COLLISION_GROUP_WEAPON)
    if Med.Cfg("noTarget") then ply:AddFlags(FL_NOTARGET) end
    ply.rhylibDownGrace = CurTime() + Med.Cfg("downGrace")
    -- Body centred on the player's position (rhylib_core; clients draw a ragdoll).
    -- A ragdoll body (rhylib_core); a stunned player keeps theirs.
    if Rhylib.Lying then Rhylib.Lying.Begin(ply) end

    hook.Run("Rhylib.PlayerDowned", ply, attacker)
end

-- Clears the downed state. Used by revive, death, spawn and disconnect.
local function clear(ply)
    if not Med.down[ply] then return false end
    Med.down[ply] = nil
    rebuildList()
    ply.rhylibDown = nil
    ply.rhylibGiveUp = nil
    if not IsValid(ply) then return true end

    -- Anyone stabilising, treating or dragging this player stops.
    local stab = Med.StabilisedBy(ply)
    if stab then Med.Cancel(stab) end
    local drag = Med.DraggedBy(ply)
    if drag then Med.StopDrag(drag) end
    for helper, a in pairs(Med.acts) do
        if a.target == ply then Med.Cancel(helper) end
    end

    ply:SetNW2Bool("rhylib_down", false)
    ply:SetNW2Entity("rhylib_stabBy", NULL)
    ply:SetNW2Entity("rhylib_dragBy", NULL)

    local vo = ply.rhylibViewOff
    if vo then
        ply:SetViewOffset(vo[1])
        ply:SetViewOffsetDucked(vo[2])
        ply.rhylibViewOff = nil
    end
    Med.ApplyHull(ply, false)
    ply:SetSurroundingBoundsType(BOUNDS_HITBOXES)
    ply:SetCollisionGroup(ply.rhylibCollision or COLLISION_GROUP_PLAYER)
    ply.rhylibCollision = nil
    if not ply.rhylibAdminNoTarget then ply:RemoveFlags(FL_NOTARGET) end   -- (rhylib_admin's no target stays)
    if Rhylib.Lying then Rhylib.Lying.End(ply) end
    return true
end

-- Standing back up under something low: move to the nearest clear spot.
local NUDGES = { Vector(0, 0, 0), Vector(0, 0, 12), Vector(24, 0, 4), Vector(-24, 0, 4), Vector(0, 24, 4), Vector(0, -24, 4),
    Vector(40, 0, 8), Vector(-40, 0, 8), Vector(0, 40, 8), Vector(0, -40, 8) }
local function unstick(ply)
    local pos = ply:GetPos()
    local mins, maxs = ply:GetHull()
    for _, off in ipairs(NUDGES) do
        local p = pos + off
        local tr = util.TraceHull({ start = p, endpos = p, mins = mins, maxs = maxs, filter = ply, mask = MASK_PLAYERSOLID })
        if not tr.StartSolid then
            if off ~= NUDGES[1] then ply:SetPos(p) end
            return
        end
    end
end

function Med.Revive(ply, health, by)
    if not clear(ply) then return end
    unstick(ply)
    ply:SetHealth(math.Clamp(math.floor(health), 1, ply:GetMaxHealth()))
    hook.Run("Rhylib.PlayerRevived", ply, by)
end

-- Dies now, credited to whoever downed them.
local function finish(ply)
    local d = Med.down[ply]
    if not d or ply.rhylibDying then return end
    ply.rhylibDying = true
    local attacker = IsValid(d.attacker) and d.attacker or ply
    local dmg = DamageInfo()
    dmg:SetDamage(ply:Health() + 1000)
    dmg:SetDamageType(DMG_DIRECT)
    dmg:SetAttacker(attacker)
    dmg:SetInflictor(IsValid(d.inflictor) and d.inflictor or attacker)
    ply:TakeDamageInfo(dmg)
    if ply:Alive() then ply:Kill() end  -- blocked (friendly fire off, god mode)
    ply.rhylibDying = nil
end

function Med.GiveUp(ply)
    if Med.down[ply] then timer.Simple(0, function() if IsValid(ply) then finish(ply) end end) end
end

--------------------------------------------------------------------------
-- Damage
--------------------------------------------------------------------------

Rhylib.Hook.Add("EntityTakeDamage", "medical.down", function(ent, dmg)
    if not ent:IsPlayer() or ent.rhylibDown or not ent:Alive() then return end
    if not Med.Cfg("enabled") then return end
    if ent.rhylibBuddha then ent.rhylibGoingDown = nil return end   -- (rhylib_admin buddha keeps 1 HP)
    local hp = ent:Health()
    -- +1: the engine rounds fractional damage up, so 99.6 on 100 HP kills.
    if dmg:GetDamage() + 1 < hp then
        ent.rhylibGoingDown = nil
        return
    end
    if hp <= 1 then
        ent:SetHealth(2)
        hp = 2
    end
    dmg:SetDamage(hp - 1)
    ent.rhylibGoingDown = true
end, 150)  -- after armour (100)

-- Just went down: no damage while the fall plays (bleeding out and
-- giving up use DMG_DIRECT from finish(), which isn't blocked).
Rhylib.Hook.Add("EntityTakeDamage", "medical.grace", function(ent, dmg)
    if ent.rhylibDown and ent:IsPlayer() and CurTime() < (ent.rhylibDownGrace or 0) and not ent.rhylibDying then
        return true
    end
end, 50)

Rhylib.Hook.Add("PostEntityTakeDamage", "medical.down", function(ent, dmg, took)
    if not ent.rhylibGoingDown then return end
    ent.rhylibGoingDown = nil
    if took and ent:Alive() then Med.Down(ent, dmg:GetAttacker(), dmg:GetInflictor()) end
end)

Rhylib.Hook.Add("PlayerDeath", "medical.clear", function(ply)
    clear(ply)
    Med.Cancel(ply)
    Med.StopDrag(ply)
end)

Rhylib.Hook.Add("PlayerSpawn", "medical.clear", function(ply)
    clear(ply)
    Med.Cancel(ply)
    Med.StopDrag(ply)
end)

Rhylib.Hook.Add("PlayerDisconnected", "medical.clear", function(ply)
    clear(ply)
    Med.Cancel(ply)
    Med.StopDrag(ply)
end)

Rhylib.Hook.Add("CanPlayerEnterVehicle", "medical.novehicle", function(ply)
    if ply.rhylibDown then return false end
end)

-- No skipping the bleed-out: "kill" while down finishes it instead
-- (credited to whoever downed you), and the job can't change.
Rhylib.Hook.Add("CanPlayerSuicide", "medical.nosuicide", function(ply)
    if ply.rhylibDown then
        Med.GiveUp(ply)
        return false
    end
end)

Rhylib.Hook.Add("playerCanChangeTeam", "medical.nojob", function(ply)
    if ply.rhylibDown then return false, "You can't change job while down" end
end)

-- DarkRP's job change and some admin tools kill silently.
Rhylib.Hook.Add("PlayerSilentDeath", "medical.clear", function(ply)
    clear(ply)
    Med.Cancel(ply)
    Med.StopDrag(ply)
end)

-- Leaving while down counts as a kill for whoever downed you.
Rhylib.Hook.Add("PlayerDisconnected", "medical.credit", function(ply)
    local d = Med.down[ply]
    if d and IsValid(d.attacker) and d.attacker:IsPlayer() and d.attacker ~= ply then
        d.attacker:AddFrags(1)
    end
end, -10)  -- before the state is cleared

--------------------------------------------------------------------------
-- Dragging
--------------------------------------------------------------------------

function Med.StartDrag(ply, target)
    if not Med.down[target] or Med.DraggedBy(target) or Med.Dragging(ply) then return end
    if ply.rhylibDown or not Med.InRange(ply, target, 40) or not Med.CanSee(ply, target) then return end
    -- Can't stabilise or treat what you're pulling away.
    local stab = Med.StabilisedBy(target)
    if stab then Med.Cancel(stab) end
    target:SetNW2Entity("rhylib_dragBy", ply)
    ply:SetNW2Entity("rhylib_dragging", target)
    -- Medevac (Combat medic): the bleed-out waits while you drag them.
    if Med.Skill(ply, "medevac") and not Med.StabilisedBy(target) then
        target:SetNW2Float("rhylib_downLeft", Med.TimeLeft(target))
        target:SetNW2Entity("rhylib_stabBy", ply)
        target.rhylibDragPause = ply
    end
end

function Med.StopDrag(ply)
    local target = ply:GetNW2Entity("rhylib_dragging")
    if IsValid(target) and target:GetNW2Entity("rhylib_dragBy") == ply then
        target:SetNW2Entity("rhylib_dragBy", NULL)
    end
    -- (Medevac pause ends with the drag)
    if IsValid(target) and target.rhylibDragPause == ply then
        target.rhylibDragPause = nil
        if target.rhylibDown and target:GetNW2Entity("rhylib_stabBy") == ply then
            -- Someone reviving or stabilising them meanwhile takes the pause over.
            for h, a in pairs(Med.acts or {}) do
                if h ~= ply and a.target == target and (Med.REVIVES[a.kind] or a.kind == Med.A_STAB) then
                    target:SetNW2Entity("rhylib_stabBy", h)
                    a.paused = true
                    return
                end
            end
            target:SetNW2Float("rhylib_downEnd", CurTime() + target:GetNW2Float("rhylib_downLeft", 0))
            target:SetNW2Entity("rhylib_stabBy", NULL)
        end
    end
    if ply:GetNW2Entity("rhylib_dragging") ~= NULL then ply:SetNW2Entity("rhylib_dragging", NULL) end
end

--------------------------------------------------------------------------
-- The check loop
--------------------------------------------------------------------------

timer.Create("Rhylib.Medical", 0.1, 0, function()
    if not next(Med.down) and not next(Med.acts) then return end
    local now = CurTime()

    -- Actions first, so a stabiliser who just left resumes the timer
    -- before it's checked.
    Med.CheckActions(now)

    for ply in pairs(Med.down) do
        if not IsValid(ply) then
            Med.down[ply] = nil
            rebuildList()
        elseif not Med.StabilisedBy(ply) and now >= ply:GetNW2Float("rhylib_downEnd", 0) then
            finish(ply)
        else
            local drag = Med.DraggedBy(ply)
            if drag and (not drag:Alive() or drag.rhylibDown or not Med.InRange(drag, ply, 80) or not Med.CanSee(drag, ply)) then
                Med.StopDrag(drag)
            end
        end
    end
end)
