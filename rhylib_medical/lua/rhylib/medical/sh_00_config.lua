--[[
    Medical: downed state, bleed-out, stabilise, drag, revive and heal.

    At 0 HP a player goes down instead of dying. While down:
      - a bleed-out timer runs (bleedTime); at 0 they die
      - their health becomes a small pool (downHealth); damage while down
        comes off it, and at 0 they die (they can be finished off)
      - holding Jump for giveUpTime gives up (dies at once)
      - they lie in a death pose: same entity, same place on every screen,
        hits use the lying hitboxes
    Anyone can stabilise (E menu, pauses the timer, helper is locked in
    place) or drag (hold attack with empty hands). Medics (DarkRP job with
    medic = true) revive with a revive kit or first aid kit, picked by the
    medic; reviving also pauses the timer.

    Kits:
      medkit          single use, stacks 3 (troopers) / 5 (medics). Heals
                      and stops bleeding; stronger in a medic's hands.
      first aid kit   medics only, doesn't stack. Holds a charge
                      (firstAidCharge, shown as %) spent on the health it
                      heals; empty kits are used up.
      revive kit      medics only.
    Every treatment takes a moment; the patient sees "being treated" and
    doesn't bleed while it runs.
    Medicines (antiviral, antidote, antibiotics) cure illnesses, dosed
    in units (sh_50_illness.lua).
    Field items (H menu, drag onto a part; anyone): splint (a broken bone
    holds until the med bay), burn gel, painkillers. Medics:
    blood pack (E menu on a downed player, more bleed-out time). Medical
    supplies are what Chemists turn into all of these at a chemistry
    bench (sv_40_medbay.lua).
    Med bay: near a bacta tank or a medical holotable. Only there does a
    first aid kit fully set bones and heal burns (or anywhere with the
    Field surgeon skill); elsewhere it splints them and halves burns.
    Skills (rhylib_skills, medic jobs): Med.Skill(ply, id).

    State, all NW2 (changes only on events):
      downed player:  rhylib_down (bool), rhylib_downEnd (CurTime when the
                      timer runs out), rhylib_downLeft (seconds left while
                      paused), rhylib_stabBy, rhylib_dragBy (entities),
                      rhylib_downYaw (body yaw when going down)
      helper:         rhylib_medAct (action, see A_*), rhylib_medT (target),
                      rhylib_medS / rhylib_medE (start / end time),
                      rhylib_dragging (entity being dragged)
]]

Rhylib.Medical = Rhylib.Medical or {}
local Med = Rhylib.Medical
local Config = Rhylib.Config

Config.Register("medical", "enabled", true, "Players go down at 0 HP instead of dying")
Config.Register("medical", "simplified", false, "Simplified medical system: no injuries, bleeding, illness, field items, H menu or chemistry; health is a plain 0-100% of the job's max health. Medkit +simpleMedkit, first aid kit heals to full, revive kit revives to full. Downing, stabilising, dragging and reviving stay")
Config.Register("medical", "simpleMedkit", 0.3, "Simplified medical system: share of max health a medkit heals (0.3 = +30%)")
Config.Register("medical", "simpleFirstAidRevive", 0.3, "Simplified medical system: health after a first aid kit revive, as a share of max health")
Config.Register("medical", "simpleFirstAidCharge", false, "Simplified medical system: first aid kits still spend their charge (off = never run out)")
Config.Register("medical", "bleedTime", 120, "Seconds a downed player lasts before bleeding out")
Config.Register("medical", "downHealth", 50, "Health while downed; damage while down comes off this")
Config.Register("medical", "downGrace", 2, "Seconds after going down when the body takes no damage (the fall plays; no instant finishing)")
Config.Register("medical", "giveUpTime", 3, "Seconds of holding Jump to give up")
Config.Register("medical", "range", 90, "How close a helper must be (units; ~2.3 m)")
Config.Register("medical", "reviveKitTime", 5, "Seconds to revive with a revive kit")
Config.Register("medical", "reviveKitHealth", 1, "Health after a revive kit, as a share of max health")
Config.Register("medical", "firstAidReviveTime", 15, "Seconds to revive with a first aid kit")
Config.Register("medical", "firstAidReviveHealth", 30, "Health after a first aid revive (taken from the kit's charge)")
Config.Register("medical", "firstAidCharge", 500, "Health a full first aid kit can heal before it's used up")
Config.Register("medical", "firstAidMinCost", 10, "Charge a first aid treatment always costs, even when it heals less")
Config.Register("medical", "firstAidHealTime", 5, "Seconds to heal someone who is up with a first aid kit (as much as the charge allows)")
Config.Register("medical", "firstAidLimbTime", 4, "Seconds to treat one body part with a first aid kit")
Config.Register("medical", "medkitHealTime", 3, "Seconds for a medkit on someone else")
Config.Register("medical", "medkitLimbTime", 3, "Seconds for a medkit on one body part")
Config.Register("medical", "medkitHeal", 25, "Health a medkit gives (trooper)")
Config.Register("medical", "medkitHealMedic", 50, "Health a medkit gives in a medic's hands")
Config.Register("medical", "medkitStack", 3, "Medkits per stack for troopers")
Config.Register("medical", "medkitStackMedic", 5, "Medkits per stack for medics (at most 10)")
Config.Register("medical", "medkitMedicOnly", false, "Only medics can use medkits")
Config.Register("medical", "selfMult", 2, "Treating yourself takes this many times longer")
Config.Register("medical", "dragSpeed", 100, "Top speed while dragging someone")
Config.Register("medical", "dragLeash", 45, "How far behind the dragger the body trails")
Config.Register("medical", "dragWeapons", { rhylib_stowed = true, keys = true }, "Weapons that count as empty hands for dragging")
Config.Register("medical", "noTarget", true, "NPCs ignore downed players")
Config.Register("medical", "downSequences", { "death_04", "death_03", "death_02", "death_01", "zombie_slump_idle_02" }, "Lying poses to try, first that exists on the model wins (last frame is used)")
Config.Register("medical", "markerRange", 2500, "Downed markers show within this distance")
Config.Register("medical", "dragSpeedSkill", 180, "Field drag: top speed while dragging")
Config.Register("medical", "handReviveTime", 25, "Hands-on revive: seconds")
Config.Register("medical", "handReviveHealth", 15, "Hands-on revive: health they get up with")
Config.Register("medical", "steadyMult", 0.85, "Steady hands: treatment time multiplier (not revives)")
Config.Register("medical", "quickReviveMult", 0.8, "Quick revive: revive time multiplier")
Config.Register("medical", "deepPockets", 2, "Deep pockets: extra medkits per stack")
Config.Register("medical", "efficientCare", 0.67, "Efficient care: first aid kit charge used multiplier")
Config.Register("medical", "triageFlash", 30, "Triage: markers flash under this many seconds left")
Config.Register("medical", "medBayRange", 400, "Med bay: this close to a bacta tank or medical holotable")
Config.Register("medical", "medBayClasses", { "rhylib_bacta_tank", "rhylib_med_holotable" }, "Entities that make a med bay around them")
Config.Register("medical", "splintTime", 4, "Seconds to splint a fracture")
Config.Register("medical", "burnGelTime", 3, "Seconds to apply burn gel")
Config.Register("medical", "burnGel", 60, "Burns that burn gel removes")
Config.Register("medical", "pillTime", 1.5, "Seconds to give painkillers")
Config.Register("medical", "painkillerTime", 60, "Painkillers: seconds that hurt limbs and burns don't slow you")
Config.Register("medical", "bloodPackTime", 4, "Seconds to hook up a blood pack")
Config.Register("medical", "bloodPackAdd", 60, "Blood pack: seconds added to a downed player's bleed-out")
Config.Register("medical", "tankModel", "models/props/cydi/bactatank1.mdl", "Bacta tank model (a missing model falls back to a fridge)")
Config.Register("medical", "tankOffset", Vector(0, 0, 2), "Bacta tank: where the occupant stands, from the bottom centre of the model")
Config.Register("medical", "sofaModel", "models/reizer_props/alysseum_project/medicine_obj/med_sofa_01/med_sofa_01.mdl", "Med sofa model")
Config.Register("medical", "sofaHeight", 22, "Med sofa: height of the lying surface above the model's bottom (only if the trace onto the model misses)")
Config.Register("medical", "sofaFlip", true, "Med sofa: lay the head toward the other end")
Config.Register("medical", "sofaDrop", 1.5, "Med sofa: gap between the body's lowest point and the surface when laid down (units)")
Config.Register("medical", "sofaSettle", 1.5, "Med sofa: seconds the arms, legs and head settle before the body freezes")
Config.Register("medical", "sofaDamping", 6, "Med sofa: how heavily the arms, legs and head are slowed while settling")
Config.Register("medical", "tankHeal", 5, "Bacta tank: health per second")
Config.Register("medical", "tankRepair", 8, "Bacta tank: body part damage and burns healed per second")
Config.Register("medical", "tankSetBones", 8, "Bacta tank: seconds inside before fractures are set")
Config.Register("medical", "tankSpecialist", 300, "Bacta specialist: tanks within this range of you heal twice as fast")
Config.Register("medical", "benchModel", "models/fyu/cedi/misc/v4/misc_30.mdl", "Chemistry bench model")
Config.Register("medical", "craftTime", 3, "Chemistry bench: seconds per batch")
Config.Register("medical", "chemRecipes", {
    { "rhylib_burngel", 1 }, { "rhylib_painkiller", 1 },
    { "rhylib_splint", 1 }, { "rhylib_bloodpack", 2 }, { "rhylib_medkit", 2 },
    { "rhylib_blood_kit", 1, 2 }, { "rhylib_test_strip", 1, 3 },
    { "rhylib_antiviral", 2, 10 }, { "rhylib_antibiotics", 2, 10 }, { "rhylib_antidote", 2, 10 },
}, "Chemistry bench recipes: { item, medical supplies it takes, how many it makes (default 1) }")

function Med.Cfg(key)
    return Config.Get("medical", key)
end

-- Simplified medical system (Server settings, live): afflictions off,
-- health as a share of the job's max health, kits heal by share.
function Med.Simple()
    return Config.Get("medical", "simplified") == true
end

-- Health as a whole percent of max health (HUDs in the simplified system).
function Med.HealthPct(ply)
    -- (rounded down, so 100% only at full health; 1% while any is left)
    local hp = math.max(ply:Health(), 0)
    if hp <= 0 then return 0 end
    return math.Clamp(math.floor(hp / math.max(ply:GetMaxHealth(), 1) * 100), 1, 100)
end

-- Actions a helper can be doing.
Med.A_NONE = 0
Med.A_STAB = 1      -- stabilising (open-ended)
Med.A_REVIVE = 2    -- reviving with a revive kit
Med.A_FA_REVIVE = 3 -- reviving with a first aid kit
Med.A_FA_HEAL = 4   -- heal with a first aid kit
Med.A_MEDKIT = 5    -- one medkit
Med.A_TREAT = 6     -- one body part, from the H menu (kit in the action)
Med.A_BLOOD = 7     -- blood pack on a downed player
Med.A_HAND_REVIVE = 8 -- revive with no kit (skill Hands-on revive)
Med.ACT_BITS = 4

-- Revives (pause the bleed-out, need a downed target).
Med.REVIVES = { [Med.A_REVIVE] = true, [Med.A_FA_REVIVE] = true, [Med.A_HAND_REVIVE] = true }

Med.ActName = {
    [1] = "Stabilising",
    [2] = "Reviving",
    [3] = "Reviving (first aid)",
    [4] = "Treating",
    [5] = "Healing",
    [6] = "Treating",
    [7] = "Giving blood",
    [8] = "Reviving (hands-on)",
}

-- Kit weapon classes.
Med.REVIVE_KIT = "rhylib_revivekit"
Med.FIRST_AID = "rhylib_firstaid"
Med.MEDKIT = "rhylib_medkit"

-- Plain medical items.
Med.SUPPLIES = "rhylib_med_supplies"
Med.SPLINT = "rhylib_splint"
Med.BURN_GEL = "rhylib_burngel"
Med.PAINKILLER = "rhylib_painkiller"
Med.BLOOD_PACK = "rhylib_bloodpack"

-- H menu treatments: kind (3 bits on the wire) <-> item.
Med.TREAT_FIRSTAID, Med.TREAT_MEDKIT = 0, 1
Med.TREAT_ITEMS = { [0] = Med.FIRST_AID, [1] = Med.MEDKIT, [2] = Med.SPLINT, [3] = Med.BURN_GEL, [4] = Med.PAINKILLER }
Med.TREAT_KIND = {}
for k, v in pairs(Med.TREAT_ITEMS) do Med.TREAT_KIND[v] = k end
-- Anyone may use these (first aid kits and blood packs are for medics).
Med.ANYONE = { [Med.MEDKIT] = true, [Med.SPLINT] = true, [Med.BURN_GEL] = true, [Med.PAINKILLER] = true }

Med.ITEMS = {
    { Med.SUPPLIES, "Medical supplies", "Chemists turn these into medicine at a chemistry bench", 10, 0.2, "models/items/healthkit.mdl" },
    { Med.SPLINT, "Splint", "Holds a broken bone until the med bay (drag onto the part)", 3, 0.3, "models/props_debris/wood_board04a.mdl" },
    { Med.BURN_GEL, "Burn gel", "Takes most of the burns off a part", 3, 0.2, "models/healthvial.mdl" },
    { Med.PAINKILLER, "Painkillers", "Hurt limbs and burns don't slow you for a minute", 5, 0.1, "models/healthvial.mdl" },
    { Med.BLOOD_PACK, "Blood pack", "Medics: buys a downed player another minute (E menu)", 3, 0.4, "models/healthvial.mdl" },
}

-- Medicines: items with no effect yet (ideas for later treatments).
Med.MEDICINES = {
    { "rhylib_antiviral", "Antiviral", "Viral infections (blue strip). In units: the analyser gives the dose" },
    { "rhylib_antidote", "Antidote", "Poisoning (purple strip). In units: the analyser gives the dose" },
    { "rhylib_antibiotics", "Antibiotics", "Bacterial infections (green strip). In units: the analyser gives the dose" },
}

local function registerMedicines()
    local Items = Rhylib.Items
    if not Items or not Items.Register then return end
    for _, m in ipairs(Med.ITEMS) do
        if not Items.Get(m[1]) then
            Items.Register(m[1], {
                name = m[2], desc = m[3], w = 1, h = 1, stack = m[4], weight = m[5],
                category = "medical", model = m[6], usable = true,
            })
        end
    end
    for _, m in ipairs(Med.MEDICINES) do
        if not Items.Get(m[1]) then
            Items.Register(m[1], {
                name = m[2], desc = m[3], w = 1, h = 1, stack = 5, weight = 0.1,
                category = "medical", model = "models/healthvial.mdl",
            })
        end
    end
end
registerMedicines()

-- Items the simplified medical system takes out (armouries and crates
-- leave them out, H menu items can't be used, the bench is closed).
Med.HARDCORE_ITEMS = {
    [Med.SUPPLIES] = true, [Med.SPLINT] = true, [Med.BURN_GEL] = true, [Med.PAINKILLER] = true, [Med.BLOOD_PACK] = true,
    rhylib_antiviral = true, rhylib_antidote = true, rhylib_antibiotics = true,
    rhylib_blood_kit = true, rhylib_test_strip = true, rhylib_blood_sample = true, rhylib_test_cassette = true,
}
Rhylib.Hook.Add("Rhylib.ItemDisabled", "medical.simple", function(id)
    if Med.HARDCORE_ITEMS[id] and Med.Simple() then return true end
end)

-- Medkits stack 3 for troopers and 5 for medics, +3 with Deep pockets
-- (rhylib_inventory asks this).
Rhylib.Hook.Add("Rhylib.ItemStack", "medical.stack", function(def, ply)
    if def.id == "rhylib_medkit" and IsValid(ply) then
        local n = Med.IsMedic(ply) and Med.Cfg("medkitStackMedic") or Med.Cfg("medkitStack")
        if Med.Skill(ply, "deep_pockets") then n = n + Med.Cfg("deepPockets") end
        return n
    end
end)

-- A medic skill (rhylib_skills); only counts while the player is a medic.
function Med.Skill(ply, id)
    local K = Rhylib.Skills
    if not (K and K.Has and IsValid(ply) and ply:IsPlayer()) then return false end
    return K.Has(ply, id) and Med.IsMedic(ply)
end

function Med.DragSpeed(ply)
    return Med.Skill(ply, "field_drag") and Med.Cfg("dragSpeedSkill") or Med.Cfg("dragSpeed")
end

-- Is ply in a med bay (near a bacta tank or medical holotable)? The
-- anchor list is refreshed every few seconds.
local anchors, anchorsAt = {}, 0
function Med.InMedBay(ply)
    local now = CurTime()
    if now - anchorsAt > 3 then
        anchorsAt = now
        anchors = {}
        local list = Med.Cfg("medBayClasses")
        for _, c in ipairs(istable(list) and list or {}) do
            for _, e in ipairs(ents.FindByClass(c)) do anchors[#anchors + 1] = e end
        end
    end
    local r = Med.Cfg("medBayRange")
    local pos = ply:GetPos()
    for _, e in ipairs(anchors) do
        if IsValid(e) and e:GetPos():DistToSqr(pos) <= r * r then return true end
    end
    return false
end

--------------------------------------------------------------------------
-- State readers (shared)
--------------------------------------------------------------------------

function Med.IsDown(ply)
    return ply:GetNW2Bool("rhylib_down", false)
end

function Med.StabilisedBy(ply)
    local e = ply:GetNW2Entity("rhylib_stabBy")
    return IsValid(e) and e or nil
end

function Med.DraggedBy(ply)
    local e = ply:GetNW2Entity("rhylib_dragBy")
    return IsValid(e) and e or nil
end

function Med.Dragging(ply)
    local e = ply:GetNW2Entity("rhylib_dragging")
    return IsValid(e) and e or nil
end

-- Seconds of bleed-out left.
function Med.TimeLeft(ply)
    if Med.StabilisedBy(ply) then return ply:GetNW2Float("rhylib_downLeft", 0) end
    return math.max(0, ply:GetNW2Float("rhylib_downEnd", 0) - CurTime())
end

-- action, target, start, end
function Med.Action(ply)
    local a = ply:GetNW2Int("rhylib_medAct", 0)
    if a == 0 then return 0 end
    return a, ply:GetNW2Entity("rhylib_medT"), ply:GetNW2Float("rhylib_medS", 0), ply:GetNW2Float("rhylib_medE", 0)
end

-- DarkRP job flag (medic = true). Other gamemodes can answer the
-- Rhylib.IsMedic hook.
function Med.IsMedic(ply)
    local r = hook.Run("Rhylib.IsMedic", ply)
    if r ~= nil then return r end
    local job = RPExtraTeams and RPExtraTeams[ply:Team()]
    return job and job.medic == true or false
end

function Med.HoldingHands(ply)
    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) then return true end
    local list = Med.Cfg("dragWeapons")
    return wep.IsRhylibStowed or (istable(list) and list[wep:GetClass()]) or false
end

-- Centre of a lying body (for aiming and range checks).
function Med.BodyPos(ply)
    -- rhylib_core measures where the lying pose really puts the body.
    if Rhylib.Lying and Rhylib.Lying.BodyPos then return Rhylib.Lying.BodyPos(ply) end
    return ply:GetPos() + Vector(0, 0, 10)
end

--[[
    The downed player `ply` is aiming at, within range. Lying bodies are
    small, so this checks aim direction against every downed player
    instead of tracing for hitboxes. The list is short.
]]
function Med.FindDowned(ply, list)
    local eye = ply:EyePos()
    local dir = ply:GetAimVector()
    local range = Med.Cfg("range") + 40  -- eyes are well above the body
    local best, bestDot
    for _, t in ipairs(list or player.GetAll()) do
        if t ~= ply and IsValid(t) and t:Alive() and Med.IsDown(t) then
            local to = Med.BodyPos(t) - eye
            local dist = to:Length()
            if dist > 1 and dist <= range then
                local dot = dir:Dot(to / dist)
                -- A body about 30 units around, plus some slack.
                local need = math.cos(math.min(math.atan(30 / dist) + 0.1, 1.2))
                if dot >= need and (not best or dot > bestDot) then
                    local tr = util.TraceLine({ start = eye, endpos = Med.BodyPos(t), filter = { ply, t }, mask = MASK_SOLID_BRUSHONLY })
                    if not tr.Hit then best, bestDot = t, dot end
                end
            end
        end
    end
    return best
end

-- A standing player in front of `ply`, within range.
function Med.FindStanding(ply)
    local tr = util.TraceHull({
        start = ply:EyePos(),
        endpos = ply:EyePos() + ply:GetAimVector() * (Med.Cfg("range") + 20),
        filter = ply,
        mins = Vector(-4, -4, -4), maxs = Vector(4, 4, 4),
        mask = MASK_SHOT_HULL,
    })
    local e = tr.Entity
    if IsValid(e) and e:IsPlayer() and e:Alive() and not Med.IsDown(e) then return e end
end
