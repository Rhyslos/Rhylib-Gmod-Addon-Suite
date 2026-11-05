--[[
    Medical actions (server): stabilise, revive, and treat with a kit.

    Every action is one row in Med.acts[helper] and four NW2 values on the
    helper (sh_00_config.lua), set when it starts and cleared when it ends.
    The patient gets rhylib_healBy (the helper) so their screen shows
    "being treated", and doesn't bleed while it runs (ply.rhylibTreated).
    The 0.1 s loop in sv_10_downed.lua checks them: helper and target still
    valid and close, kit still carried; at the end time the kit is used and
    the effect applied. Stabilising has no end; it pauses the target's
    bleed-out until the helper stops. Reviving pauses it too.

    Kits (worst problem first, Med.TreatWounds in sv_30_injuries.lua):
      medkit         one per use. Trooper: stops the worst bleed, heals
                     medkitHeal. Medic: stops all bleeding, ends a limp,
                     repairs medkitLimbRepair on every part, heals
                     medkitHealMedic.
      first aid kit  medics. Fixes every wound and heals what's missing.
                     Charge = health it can still heal (fill x
                     firstAidCharge); each use costs the health it heals
                     (at least firstAidMinCost). Empty kits are used up.
      revive kit     medics. One per revive.
      blood pack     medics, E menu on a downed player.
    Hardcore (Med.Hardcore()): a medkit or first aid kit click on someone
    standing (or yourself) opens their H menu instead, and the kit is
    dragged onto one body part there: A_TREAT (hcMedkitLimbTime /
    hcFirstAidLimbTime, a.kit and a.limb; Med.TreatPart in
    sv_30_injuries.lua). A first aid kit on a downed player still revives.
    Skills (Med.Skill): Steady hands (treatments) and Quick revive
    (revives) shorten the timers, Hands-on revive needs no kit, Efficient
    care spends less first aid charge, Field surgeon patches up whoever
    you treat (patchedMult damage for patchedTime s; ply.rhylibPatchedUntil,
    EntityTakeDamage "medical.patched").

    Started by the kit weapons (left click: someone else, right click:
    yourself, selfMult times longer), the E menu on a downed player
    (med.act) or, in hardcore, the H menu (med.treat in sv_30_injuries.lua).

    Patients are players or test dummies (Med.IsPatient); helpers are
    always players. A dummy gets no notes.

    Public: Med.Has, Med.Consume, Med.KitCharge, Med.SpendCharge,
    Med.Start, Med.Cancel, Med.CheckActions, Med.UseKit, Med.DragRevive,
    Med.OpenMenuFor.
    Hook fired: Rhylib.PlayerHealed(patient, helper) after a treatment of
    a player (rhylib_datapad counts it; not for test dummies).
    Nets: med.act (client -> server) kind Med.ACT_BITS (4) + target
    entity index 13 bits; med.open (server -> client) entity: open the
    injury menu on that patient (NULL = your own).
]]

local Med = Rhylib.Medical
Med.acts = Med.acts or {}

--------------------------------------------------------------------------
-- Kits: carried in the inventory (rhylib_inventory) or as plain weapons
--------------------------------------------------------------------------

local function inventory()
    return Rhylib.Inventory and Rhylib.Inventory.Count and Rhylib.Inventory or nil
end

-- Med.Has(ply, class): true if ply carries at least one of the item/kit
-- `class` (inventory item, or the plain weapon without rhylib_inventory).
function Med.Has(ply, class)
    local Inv = inventory()
    if Inv then return Inv.Count(ply, class) > 0 end
    return ply:HasWeapon(class)
end

-- Med.Consume(ply, class): uses up one of an item (medkit, revive kit,
-- blood pack). Returns false if there was none.
-- Example: if Rhylib.Medical.Consume(ply, "rhylib_bloodpack") then ... end
function Med.Consume(ply, class)
    local Inv = inventory()
    if not Inv then
        if not ply:HasWeapon(class) then return false end
        ply:StripWeapon(class)
        return true
    end
    local st = Inv.Get(ply)
    for _, o in pairs(st.byUid) do
        if o.id == class then
            Inv.Remove(ply, o.uid, 1)
            return true
        end
    end
    return false
end

-- First aid kits: the one to use next (the emptiest), and its charge in health.
local function chargeMax() return math.max(1, Med.Cfg("firstAidCharge")) end

local function nextKit(ply)
    local Inv = inventory()
    if not Inv then return nil end
    local pick
    for _, o in pairs(Inv.Get(ply).byUid) do
        if o.id == Med.FIRST_AID then
            local f = o.data and o.data.fill or 1
            if not pick or f < (pick.data and pick.data.fill or 1) then pick = o end
        end
    end
    return pick
end

-- Med.KitCharge(ply): health the next first aid kit can still heal
-- (its fill 0-1 × firstAidCharge), 0 without a kit. Only the emptiest
-- kit counts, not the total.
function Med.KitCharge(ply)
    local Inv = inventory()
    if not Inv then
        local w = ply:GetWeapon(Med.FIRST_AID)
        return IsValid(w) and (w.rhylibCharge or chargeMax()) or 0
    end
    local o = nextKit(ply)
    return o and (o.data and o.data.fill or 1) * chargeMax() or 0
end

-- Med.SpendCharge(ply, amount): takes `amount` health worth of charge from
-- the next first aid kit (× efficientCare with Efficient care); a kit
-- left under 1 is removed. Keeps the held weapon's Charge in step.
function Med.SpendCharge(ply, amount)
    if Med.Skill(ply, "efficient_care") then amount = amount * Med.Cfg("efficientCare") end
    local max = chargeMax()
    local Inv = inventory()
    if not Inv then
        local w = ply:GetWeapon(Med.FIRST_AID)
        if not IsValid(w) then return end
        w.rhylibCharge = (w.rhylibCharge or max) - amount
        if w.SetCharge then w:SetCharge(math.max(0, w.rhylibCharge / max)) end
        if w.rhylibCharge < 1 then ply:StripWeapon(Med.FIRST_AID) end
        return
    end
    local o = nextKit(ply)
    if not o then return end
    local left = (o.data and o.data.fill or 1) * max - amount
    if left < 1 then
        Inv.Remove(ply, o.uid)
    else
        o.data = o.data or {}
        o.data.fill = left / max
        Inv.Internal.update(ply, Inv.Get(ply), o)
    end
    -- The weapon shows the kit that's next.
    local w = ply:GetWeapon(Med.FIRST_AID)
    if IsValid(w) and w.SetCharge then
        local n = nextKit(ply)
        w:SetCharge(n and (n.data and n.data.fill or 1) or 0)
    end
end

-- Health a first aid treatment heals (at most `want`), and what it costs.
local function kitHeal(ply, want)
    local have = Med.KitCharge(ply)
    local heal = math.max(0, math.min(want, have))
    return heal, math.min(have, math.max(heal, Med.Cfg("firstAidMinCost")))
end

--------------------------------------------------------------------------
-- Starting and stopping
--------------------------------------------------------------------------

-- The helper's NW2 action state (read with Med.Action). The rhylib_medDrag
-- bool is only written when it changes.
local function setAct(helper, kind, target, startT, endT, dragging)
    helper:SetNW2Int("rhylib_medAct", kind)
    if helper:GetNW2Bool("rhylib_medDrag", false) ~= (dragging or false) then helper:SetNW2Bool("rhylib_medDrag", dragging or false) end
    helper:SetNW2Entity("rhylib_medT", target or NULL)
    helper:SetNW2Float("rhylib_medS", startT or 0)
    helper:SetNW2Float("rhylib_medE", endT or 0)
end

-- The patient's side: "being treated" on their screen, no bleeding.
local function setPatient(target, helper)
    if not IsValid(target) then return end
    target.rhylibTreated = helper and true or nil
    target:SetNW2Entity("rhylib_healBy", helper or NULL)
end

-- The kit each action uses up (A_TREAT carries its own in a.kit).
local KIT = {
    [Med.A_REVIVE] = Med.REVIVE_KIT,
    [Med.A_FA_REVIVE] = Med.FIRST_AID,
    [Med.A_FA_HEAL] = Med.FIRST_AID,
    [Med.A_MEDKIT] = Med.MEDKIT,
    [Med.A_BLOOD] = Med.BLOOD_PACK,
}

local function kitOf(a) return a.kit or KIT[a.kind] end

local function baseDuration(kind, self, kit)
    local mult = self and math.max(1, tonumber(Med.Cfg("selfMult")) or 2) or 1
    if kind == Med.A_REVIVE then return Med.Cfg("reviveKitTime") end
    if kind == Med.A_FA_REVIVE then return Med.Cfg("firstAidReviveTime") end
    if kind == Med.A_HAND_REVIVE then return Med.Cfg("handReviveTime") end
    if kind == Med.A_BLOOD then return Med.Cfg("bloodPackTime") end
    if kind == Med.A_FA_HEAL then return Med.Cfg("firstAidHealTime") * mult end
    if kind == Med.A_MEDKIT then return Med.Cfg("medkitHealTime") * mult end
    if kind == Med.A_TREAT then
        return Med.Cfg(kit == Med.FIRST_AID and "hcFirstAidLimbTime" or "hcMedkitLimbTime") * mult
    end
    return 0
end

local function duration(helper, kind, self, kit)
    local d = baseDuration(kind, self, kit)
    if not Med.REVIVES[kind] and Med.Skill(helper, "steady_hands") then d = d * Med.Cfg("steadyMult") end
    if Med.REVIVES[kind] and Med.Skill(helper, "quick_revive") then d = d * Med.Cfg("quickReviveMult") end
    return d
end

local function itemName(id)
    local def = Rhylib.Items and Rhylib.Items.Get(id)
    return def and def.name or "kit"
end

-- First aid kits spend charge (always, unless the simplified medical
-- system says they don't: simpleFirstAidCharge).
local function usesCharge()
    return not Med.Simple() or Med.Cfg("simpleFirstAidCharge") == true
end

-- Share of max health, rounded up (simplified medical system).
local function share(t, frac)
    return math.ceil(t:GetMaxHealth() * math.Clamp(tonumber(frac) or 0, 0, 1))
end

-- Something for this kit to do besides health? A trooper's medkit only
-- stops bleeding; a medic's kits also end a limp and repair part damage.
local function hasWounds(helper, target, kind)
    if not Med.HasWounds or Med.Simple() then return false end
    local full = kind == Med.A_FA_HEAL or Med.IsMedic(helper)
    return Med.HasWounds(target, full)
end

-- Why this can't start, or nil if it can. opts: { kit, limb } for A_TREAT.
-- "" = refused without a message (nonsense requests).
local function refuse(helper, kind, target, opts)
    if not helper:Alive() or helper.rhylibDown then return "" end
    if Med.acts[helper] then return "" end
    if not (Med.IsPatient(target) and target:Alive()) then return "" end
    local self = target == helper
    local down = target.rhylibDown
    local medic = Med.IsMedic(helper)

    if kind == Med.A_STAB or Med.REVIVES[kind] or kind == Med.A_BLOOD then
        if self or not down then return "" end
        if kind == Med.A_BLOOD and Med.Simple() then return "Blood packs aren't used in the simplified medical system" end
    elseif kind == Med.A_FA_HEAL or kind == Med.A_MEDKIT or kind == Med.A_TREAT then
        if down then return "Revive them first" end
        -- (A_TREAT: hardcore only; med.treat already checked the part)
        if kind == Med.A_TREAT then
            if not Med.Hardcore() or not (opts and Med.TREAT_KIND[opts.kit] and opts.limb) then return "" end
        elseif target:Health() >= target:GetMaxHealth() and not hasWounds(helper, target, kind) then
            return (self and "You're" or target:Nick() .. " is") .. " in good shape"
        end
    else
        return ""
    end

    if not self and not Med.InRange(helper, target, 30) then return "Too far away" end
    if not self and not Med.CanSee(helper, target) then return "Can't reach them from here" end

    if kind == Med.A_STAB then
        if Med.StabilisedBy(target) then return "Already being stabilised" end
        return nil
    end
    -- One revive or treatment per patient at a time (no wasted kits).
    for h, a in pairs(Med.acts) do
        if a.target == target and a.kind ~= Med.A_STAB and h ~= helper then
            return (h:Nick() or "Someone") .. " is already treating them"
        end
    end
    if kind == Med.A_HAND_REVIVE then
        if not Med.Skill(helper, "hands_on") then return "You need the Hands-on revive skill" end
        return nil
    end
    local kit = kind == Med.A_TREAT and opts.kit or KIT[kind]
    if not kit then return "" end
    if kit == Med.MEDKIT then
        if Med.Cfg("medkitMedicOnly") and not medic then return "Only medics can use medkits" end
    elseif not medic and not Med.ANYONE[kit] then
        return kit == Med.FIRST_AID and "Only medics can use a first aid kit" or "Only medics can do that"
    end
    if not Med.Has(helper, kit) then
        if kit == Med.REVIVE_KIT then return "You have no revive kit" end
        if kit == Med.FIRST_AID then return "You have no first aid kit" end
        if kit == Med.MEDKIT then return "You have no medkit" end
        return "You have no " .. string.lower(itemName(kit))
    end
    if kit == Med.FIRST_AID and usesCharge() and Med.KitCharge(helper) < 1 then return "Your first aid kit is empty" end
end

-- Med.Start(helper, kind, target, opts): starts a timed action (A_* kind)
-- after checking it's allowed; tells the helper why not (Med.Note).
-- opts: { kit = kit class, limb = part } for A_TREAT, { dragging = true }
-- for a revive on the move. Returns true if it started. The effect
-- happens when the timer ends (finishAct). Server only.
-- Example: Rhylib.Medical.Start(medic, Rhylib.Medical.A_STAB, downedPly)
function Med.Start(helper, kind, target, opts)
    local why = refuse(helper, kind, target, opts)
    if why then
        if why ~= "" then Med.Note(helper, why) end
        return false
    end
    local dragging = opts and opts.dragging and Med.Dragging(helper) == target or false
    if not dragging then Med.StopDrag(helper) end

    local now = CurTime()
    if kind == Med.A_STAB then
        target:SetNW2Float(Rhylib.NW.DOWN_LEFT, Med.TimeLeft(target))
        target:SetNW2Entity(Rhylib.NW.STAB_BY, helper)
        Med.acts[helper] = { kind = kind, target = target }
        setAct(helper, kind, target, now, 0)
        return true
    end

    local a = { kind = kind, target = target, started = now, dragging = dragging or nil }
    if kind == Med.A_TREAT then a.kit, a.limb = opts.kit, opts.limb end
    a.endTime = now + duration(helper, kind, target == helper, a.kit)
    -- Reviving pauses the bleed-out (unless someone already stabilises).
    if Med.REVIVES[kind] and not Med.StabilisedBy(target) then
        target:SetNW2Float(Rhylib.NW.DOWN_LEFT, Med.TimeLeft(target))
        target:SetNW2Entity(Rhylib.NW.STAB_BY, helper)
        a.paused = true
    end
    Med.acts[helper] = a
    setAct(helper, kind, target, now, a.endTime, dragging)
    setPatient(target, helper)
    return true
end

-- Resume a downed player's bleed-out (or hand the pause to another helper).
-- Only if `helper` is the one holding the pause (rhylib_stabBy). The timer
-- restarts from the frozen time left: downEnd = now + downLeft.
local function resume(t, helper)
    if not IsValid(t) or t:GetNW2Entity(Rhylib.NW.STAB_BY) ~= helper then return end
    for h, o in pairs(Med.acts) do
        if h ~= helper and o.target == t and (Med.REVIVES[o.kind] or o.kind == Med.A_STAB) then
            t:SetNW2Entity(Rhylib.NW.STAB_BY, h)
            o.paused = true
            return
        end
    end
    t:SetNW2Float(Rhylib.NW.DOWN_END, CurTime() + t:GetNW2Float(Rhylib.NW.DOWN_LEFT, 0))
    t:SetNW2Entity(Rhylib.NW.STAB_BY, NULL)
end

-- Med.Cancel(helper): stops helper's action without its effect (safe to
-- call when idle). The patient's bleed-out resumes if this helper paused
-- it. Server only.
function Med.Cancel(helper)
    local a = Med.acts[helper]
    if not a then return end
    Med.acts[helper] = nil
    local t = a.target
    if a.kind == Med.A_STAB or a.paused then resume(t, helper) end
    if a.kind ~= Med.A_STAB and IsValid(t) and t:GetNW2Entity("rhylib_healBy") == helper then
        setPatient(t, nil)
        -- Stopped early: the bleeding that was held off still happens
        -- (so starting and stopping a treatment can't stop bleeding).
        if a.started and Med.BleedRate and not t.rhylibDown then
            t.rhylibBleedAcc = (t.rhylibBleedAcc or 0) + Med.BleedRate(t) * (CurTime() - a.started)
        end
    end
    if IsValid(helper) then setAct(helper, Med.A_NONE) end
end

--------------------------------------------------------------------------
-- Effects
--------------------------------------------------------------------------

local function heal(t, amount)
    t:SetHealth(math.min(t:GetMaxHealth(), t:Health() + math.floor(amount + 0.5)))
end

-- Field surgeon's patch on someone just treated.
local function patchUp(helper, t)
    if Med.Skill(helper, "field_surgeon") and not Med.Simple() then
        t.rhylibPatchedUntil = CurTime() + Med.Cfg("patchedTime")
        if t ~= helper then
            Med.Note(t, "Patched up by " .. helper:Nick() .. ": less damage for " .. Med.Cfg("patchedTime") .. " s")
        end
    end
end

-- The wounds part of a treatment (Med.TreatWounds), and the note to the
-- helper: what was fixed, and Field surgeon's patch.
local function treatWounds(helper, t, how)
    local did = Med.TreatWounds and not Med.Simple() and Med.TreatWounds(t, how) or ""
    patchUp(helper, t)
    local what = did ~= "" and ("fixed " .. did) or "healed"
    Med.Note(helper, t == helper and (string.upper(what:sub(1, 1)) .. what:sub(2)) or (t:Nick() .. ": " .. what))
end

local function revive(helper, t, hp)
    Med.Revive(t, hp, helper)
end

-- The action's timer ran out: use the kit and apply the effect. A kit
-- that is gone by now means no effect (revives resume the bleed-out).
local function finishAct(helper, a)
    Med.acts[helper] = nil
    setAct(helper, Med.A_NONE)
    local t = a.target
    setPatient(t, nil)
    local medic = Med.IsMedic(helper)
    local kit = kitOf(a)

    local simple = Med.Simple()
    if a.kind == Med.A_REVIVE then
        if not Med.Consume(helper, kit) then resume(t, helper) return end
        -- (simplified: always back to full)
        revive(helper, t, simple and t:GetMaxHealth() or t:GetMaxHealth() * Med.Cfg("reviveKitHealth"))
    elseif a.kind == Med.A_FA_REVIVE then
        local want = simple and share(t, Med.Cfg("simpleFirstAidRevive")) or Med.Cfg("firstAidReviveHealth")
        if not usesCharge() then
            revive(helper, t, want)
        else
            local hp, cost = kitHeal(helper, want)
            if hp < 1 then
                Med.Note(helper, "Your first aid kit is empty")
                resume(t, helper)
                return
            end
            Med.SpendCharge(helper, cost)
            revive(helper, t, hp)
        end
    elseif a.kind == Med.A_HAND_REVIVE then
        -- (simplified: handReviveHealth read as a percent of max health)
        revive(helper, t, simple and share(t, Med.Cfg("handReviveHealth") / 100) or Med.Cfg("handReviveHealth"))
    elseif a.kind == Med.A_BLOOD then
        if not Med.Consume(helper, kit) then return end
        local add = Med.Cfg("bloodPackAdd")
        if Med.StabilisedBy(t) then
            t:SetNW2Float(Rhylib.NW.DOWN_LEFT, t:GetNW2Float(Rhylib.NW.DOWN_LEFT, 0) + add)
        else
            t:SetNW2Float(Rhylib.NW.DOWN_END, t:GetNW2Float(Rhylib.NW.DOWN_END, 0) + add)
        end
        Med.Note(helper, "Blood pack in: +" .. add .. " s")
    elseif a.kind == Med.A_FA_HEAL then
        -- Fixes every wound; as much health as is missing (and the kit holds).
        if t:Health() >= t:GetMaxHealth() and not hasWounds(helper, t, a.kind) then return end   -- (nothing left to do)
        if usesCharge() then
            local hp, cost = kitHeal(helper, t:GetMaxHealth() - t:Health())
            Med.SpendCharge(helper, cost)
            heal(t, hp)
        else
            heal(t, t:GetMaxHealth())   -- (simplified: to full, no charge)
        end
        treatWounds(helper, t, "full")
        -- Hook Rhylib.PlayerHealed(patient, helper): a heal went in (players only).
        if t:IsPlayer() then hook.Run("Rhylib.PlayerHealed", t, helper) end
    elseif a.kind == Med.A_MEDKIT then
        if t:Health() >= t:GetMaxHealth() and not hasWounds(helper, t, a.kind) then return end   -- (nothing left to do)
        if not Med.Consume(helper, kit) then return end
        if simple then
            heal(t, share(t, Med.Cfg("simpleMedkit")))   -- (simplified: a share of max health, medic or not)
        else
            heal(t, medic and Med.Cfg("medkitHealMedic") or Med.Cfg("medkitHeal"))
        end
        treatWounds(helper, t, medic and "medkit" or "worst")
        if t:IsPlayer() then hook.Run("Rhylib.PlayerHealed", t, helper) end
    elseif a.kind == Med.A_TREAT then
        -- (hardcore: one part; it notes the helper itself)
        if not (Med.TreatPart and Med.TreatPart(helper, t, a.limb, a.kit)) then return end
        patchUp(helper, t)
        if t:IsPlayer() then hook.Run("Rhylib.PlayerHealed", t, helper) end
    end
    if IsValid(t) and not Med.REVIVES[a.kind] then t:EmitSound("weapons/2misc_non_guns/use_bacta.ogg", 65) end
end

-- Med.CheckActions(now): run by the 0.1 s loop in sv_10_downed.lua.
-- Cancels actions whose helper/target died, moved apart, lost the kit or
-- changed state (e.g. the patient got up), and finishes those whose time
-- is up.
function Med.CheckActions(now)
    for helper, a in pairs(Med.acts) do
        local t = a.target
        local ok = IsValid(helper) and helper:Alive() and not helper.rhylibDown
            and IsValid(t) and t:Alive()
        if ok then
            local needDown = a.kind == Med.A_STAB or Med.REVIVES[a.kind] or a.kind == Med.A_BLOOD
            local kit = kitOf(a)
            ok = (t.rhylibDown and true or false) == needDown
                and (t == helper or Med.InRange(helper, t, 50))
                and (not kit or Med.Has(helper, kit))
                -- (a dragged body can't be treated, unless it's this helper's own revive on the move)
                and not (needDown and Med.DraggedBy(t) and not (a.dragging and Med.DraggedBy(t) == helper))
                and not (a.dragging and Med.Dragging(helper) ~= t)
        end
        if not ok then
            Med.Cancel(helper)
        elseif a.endTime and now >= a.endTime then
            finishAct(helper, a)
        end
    end
end

--------------------------------------------------------------------------
-- Requests
--------------------------------------------------------------------------

-- Med.UseKit(ply, class, self): a kit weapon's click (rhylib_med_base).
-- class = kit weapon class, self = right click (treat yourself).
-- Aimed at a downed player: revive (revive kit / first aid kit).
-- Medkits and first aid kits on someone standing (or yourself) treat
-- them: worst problem first, then health. Hardcore: they open that
-- patient's injury menu instead (drag the kit onto a part).
function Med.UseKit(ply, class, self)
    if Med.acts[ply] then return end
    local menuKit = (class == Med.MEDKIT or class == Med.FIRST_AID) and Med.Hardcore()
    if self then
        if menuKit then Med.OpenMenuFor(ply, nil) return end
        if class == Med.FIRST_AID then Med.Start(ply, Med.A_FA_HEAL, ply)
        elseif class == Med.MEDKIT then Med.Start(ply, Med.A_MEDKIT, ply) end
        return
    end

    local downed = Med.FindDowned(ply, Med.downList)
    if downed then
        if class == Med.REVIVE_KIT then Med.Start(ply, Med.A_REVIVE, downed)
        elseif class == Med.FIRST_AID then Med.Start(ply, Med.A_FA_REVIVE, downed)
        else Med.Note(ply, "Medkits can't revive") end
        return
    end
    if class == Med.REVIVE_KIT then
        Med.Note(ply, "Aim at a downed player")
        return
    end
    ply:LagCompensation(true)
    local t = Med.FindStanding(ply)
    ply:LagCompensation(false)
    if not t then
        Med.Note(ply, "Aim at a wounded player, or right click to treat yourself")
        return
    end
    if menuKit then
        Med.OpenMenuFor(ply, t)
        return
    end
    Med.Start(ply, class == Med.FIRST_AID and Med.A_FA_HEAL or Med.A_MEDKIT, t)
end

-- Med.DragRevive(ply, target): Revive on the move (Combat medic skill
-- drag_revive): right click while dragging starts a revive kit revive that
-- runs as you walk; letting go stops it. Called from sh_10_move.lua.
function Med.DragRevive(ply, target)
    if not Med.Skill(ply, "drag_revive") then return end
    if Med.acts[ply] or not (IsValid(target) and Med.Dragging(ply) == target) then return end
    Med.Start(ply, Med.A_REVIVE, target, { dragging = true })
end

-- Med.OpenMenuFor(ply, patient): opens the injury (H) menu on ply's screen
-- for patient, or ply's own body with nil (net med.open: one entity).
Rhylib.Net.Register("med.open")
function Med.OpenMenuFor(ply, patient)
    Rhylib.Net.Start("med.open")
    net.WriteEntity(patient or NULL)
    net.Send(ply)
end

-- From the E menu on a downed player: stabilise or revive with a chosen kit.
local MENU_KINDS = { [Med.A_STAB] = true, [Med.A_REVIVE] = true, [Med.A_FA_REVIVE] = true,
    [Med.A_HAND_REVIVE] = true, [Med.A_BLOOD] = true }

-- med.act (client -> server, cl_10_hud.lua): kind Med.ACT_BITS bits, target
-- entity index 13 bits (a player or a test dummy). Only the MENU_KINDS;
-- Med.Start does every other check.
Rhylib.Net.Receive("med.act", function(ply)
    local kind = net.ReadUInt(Med.ACT_BITS)
    local target = Entity(net.ReadUInt(13))
    if not MENU_KINDS[kind] or not Med.IsPatient(target) then return end
    Med.Start(ply, kind, target)
end, { rate = 4, burst = 4 })

-- Anything still pointing at a player who leaves.
Rhylib.Hook.Add("PlayerDisconnected", "medical.acts", function(ply)
    for h, a in pairs(Med.acts) do
        if h == ply or a.target == ply then Med.Cancel(h) end
    end
end)

-- Field surgeon: a patient you treated takes patchedMult damage until
-- ply.rhylibPatchedUntil. Priority 95 (with the skill resistances, before
-- armour). Bleeding (DMG_DIRECT) and downed players are left alone.
Rhylib.Hook.Add("EntityTakeDamage", "medical.patched", function(ent, dmg)
    if not Med.IsPatient(ent) or (ent.rhylibPatchedUntil or 0) <= CurTime() or ent.rhylibDown then return end
    if bit.band(dmg:GetDamageType(), DMG_DIRECT) ~= 0 then return end
    dmg:ScaleDamage(Med.Cfg("patchedMult"))
end, 95)
Rhylib.Hook.Add("PlayerSpawn", "medical.patched", function(ply) ply.rhylibPatchedUntil = nil end)
