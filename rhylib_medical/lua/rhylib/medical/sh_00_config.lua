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

    Kits (left click someone, right click yourself; worst problem first):
      medkit          single use, stacks 3 (troopers) / 5 (medics). A
                      trooper's stops the worst bleed and heals medkitHeal;
                      a medic's stops all bleeding, ends a limp, takes
                      medkitLimbRepair off every part and heals
                      medkitHealMedic.
      first aid kit   medics only, doesn't stack. Fixes every wound and
                      heals what's missing from its charge
                      (firstAidCharge, shown as %); empty kits are used up.
      revive kit      medics only.
    Every treatment takes a moment; the patient sees "being treated" and
    doesn't bleed while it runs. Field surgeon (Chemist skill): someone
    you treat takes patchedMult damage for patchedTime s afterwards.
    Medicines (antiviral, antidote, antibiotics) cure illnesses, dosed
    in units (sh_50_illness.lua).
    Medics: blood pack (E menu on a downed player, more bleed-out time).
    Medical supplies are what Chemists turn into medkits, blood packs and
    the illness kit at a chemistry bench (sv_40_medbay.lua). Old splints,
    burn gel and painkillers in saved inventories and lockers load as
    medical supplies (Items.RENAMED).
    Med bay: near a bacta tank or a medical holotable.
    Skills (rhylib_skills, medic jobs): Med.Skill(ply, id).

    Hardcore (config hardcore, live; the simplified system wins over it):
    the fuller injury model in sh/sv/cl_30 with its own hc* keys:
    bleeding from smaller hits, fractures and burns instead of limps, and
    treatment one body part at a time by dragging a kit onto the part in
    the H menu (a kit's click opens that menu). Only medics set bones and
    treat burns (medkit or first aid kit); the bacta tank does too.
    Med.Hardcore() says whether it is on.

    State, all NW2 (changes only on events):
      downed player:  rhylib_down (bool), rhylib_downEnd (CurTime when the
                      timer runs out), rhylib_downLeft (seconds left while
                      paused), rhylib_stabBy, rhylib_dragBy (entities),
                      rhylib_downYaw (body yaw when going down)
      helper:         rhylib_medAct (action, see A_*), rhylib_medT (target),
                      rhylib_medS / rhylib_medE (start / end time),
                      rhylib_dragging (entity being dragged)

    This file (shared, loads first): every "medical" config key except the
    injury and illness ones (sh_30_injuries.lua, sh_50_illness.lua), the
    action and item ids, the plain medical items, and the state readers
    other addons call (Med.IsDown, Med.TimeLeft, Med.IsMedic ...).
    The rest of the addon:
      sh_10_move      downed / dragging / helper movement and the lying pose
      sv_10_downed    going down, bleeding out, reviving, dragging
      sv_20_actions   timed actions (stabilise, revive, heal, one part in hardcore)
      sh/sv/cl_30     body part injuries and the H menu
      sh/sv/cl_40     med bay: bacta tank, chemistry bench, med sofa
      sh/sv/cl_50     illness, blood tests and medicine
      cl_10_hud       downed / helper HUD, markers, E menu, wheel options
      sv_60_dummy     test dummies' damage, numbers, rhylib_dummy_* commands

    Patients are players and test dummies (lua/entities/rhylib_test_dummy.lua,
    NextBots with ENT.IsRhylibDummy: no player slot). Med.IsPatient(ent)
    says which; code that treats a patient never calls player-only API
    on a dummy, and the Rhylib.PlayerDowned / PlayerRevived / PlayerHealed /
    DelayDown hooks only fire for players. Med.dummies = the set of dummies
    (both realms; on a client only the ones it knows).
]]

Rhylib.Medical = Rhylib.Medical or {}
local Med = Rhylib.Medical
local Config = Rhylib.Config

Config.Register("medical", "enabled", true, "Players go down at 0 HP instead of dying")
Config.Register("medical", "simplified", false, "Simplified medical system: no injuries, bleeding, limps, illness, blood packs, H menu or chemistry; health is a plain 0-100% of the job's max health. Medkit +simpleMedkit, first aid kit heals to full, revive kit revives to full. Downing, stabilising, dragging and reviving stay")
Config.Register("medical", "hardcore", false, "Hardcore medical system: bleeding from smaller hits, fractures and burns instead of limps, slow recovery, and treatment one body part at a time in the H menu (drag a kit onto the part). Only medics set bones and treat burns. The numbers are in the Hardcore section. Live: switching it on ends limps, switching it off clears fractures and burns. The simplified system wins over it")
Config.Register("medical", "simpleMedkit", 0.3, "Simplified medical system: share of max health a medkit heals (0.3 = +30%)")
Config.Register("medical", "simpleFirstAidRevive", 0.3, "Simplified medical system: health after a first aid kit revive, as a share of max health")
Config.Register("medical", "simpleFirstAidCharge", false, "Simplified medical system: first aid kits still spend their charge (off = never run out)")
Config.Register("medical", "bleedTime", 120, "Seconds a downed player lasts before bleeding out")
Config.Register("medical", "downHealth", 50, "Health while downed; damage while down comes off this")
Config.Register("medical", "downGrace", 2, "Seconds after going down when the body takes no damage (the fall plays; no instant finishing)")
Config.Register("medical", "giveUpTime", 3, "Seconds of holding Jump to give up")
Config.Register("medical", "callMedicCooldown", 30, "Downed players' \"call a medic\" key (reload): seconds between two calls")
Config.Register("medical", "range", 90, "How close a helper must be (units; ~2.3 m)")
Config.Register("medical", "reviveKitTime", 5, "Seconds to revive with a revive kit")
Config.Register("medical", "reviveKitHealth", 1, "Health after a revive kit, as a share of max health")
Config.Register("medical", "firstAidReviveTime", 15, "Seconds to revive with a first aid kit")
Config.Register("medical", "firstAidReviveHealth", 30, "Health after a first aid revive (taken from the kit's charge)")
Config.Register("medical", "firstAidCharge", 500, "Health a full first aid kit can heal before it's used up")
Config.Register("medical", "firstAidMinCost", 10, "Charge a first aid treatment always costs, even when it heals less")
Config.Register("medical", "firstAidHealTime", 5, "Seconds to treat someone who is up with a first aid kit (fixes every wound, heals as much as the charge allows)")
Config.Register("medical", "medkitHealTime", 3, "Seconds for a medkit on someone else")
Config.Register("medical", "medkitHeal", 25, "Health a medkit gives (trooper)")
Config.Register("medical", "medkitHealMedic", 50, "Health a medkit gives in a medic's hands")
Config.Register("medical", "medkitStack", 3, "Medkits per stack for troopers")
Config.Register("medical", "medkitStackMedic", 5, "Medkits per stack for medics (at most 10)")
Config.Register("medical", "medkitMedicOnly", false, "Only medics can use medkits")
Config.Register("medical", "selfMult", 2, "Treating yourself takes this many times longer")
Config.Register("medical", "dragSpeed", 100, "Top speed while dragging someone")
Config.Register("medical", "dragLeash", 45, "How far behind the dragger the body trails")
-- (a set: weapon class = true)
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
Config.Register("medical", "patchedTime", 20, "Field surgeon: seconds someone you treated takes less damage")
Config.Register("medical", "patchedMult", 0.75, "Field surgeon: damage multiplier while patched up (0.75 = 25% less)")
Config.Register("medical", "bloodPackTime", 4, "Seconds to hook up a blood pack")
Config.Register("medical", "bactaHeal", 2, "Bacta grenade mist: health per second while standing in it")
Config.Register("medical", "bactaBleedStep", 5, "Bacta grenade mist: seconds in it for bleeding to drop one step (heavy -> light -> none) on each bleeding part")
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
Config.Register("medical", "tankRepair", 8, "Bacta tank: body part damage healed per second")
Config.Register("medical", "tankSpecialist", 300, "Bacta specialist: tanks within this range of you heal twice as fast")
Config.Register("medical", "benchModel", "models/fyu/cedi/misc/v4/misc_30.mdl", "Chemistry bench model")
Config.Register("medical", "craftTime", 3, "Chemistry bench: seconds per batch")
-- (each row's place in the list is its recipe number on the wire, chem.make
-- 5 bits, so at most 31 recipes)
Config.Register("medical", "chemRecipes", {
    { "rhylib_bloodpack", 2 }, { "rhylib_medkit", 2 },
    { "rhylib_blood_kit", 1, 2 }, { "rhylib_test_strip", 1, 3 },
    { "rhylib_antiviral", 2, 10 }, { "rhylib_antibiotics", 2, 10 }, { "rhylib_antidote", 2, 10 },
}, "Chemistry bench recipes: { item, medical supplies it takes, how many it makes (default 1) }")

-- Med.Cfg(key): a "medical" config value (in-game override > host file >
-- default). Read it when needed rather than copying it at load, so
-- Server settings changes apply at once.
-- Example: local secs = Rhylib.Medical.Cfg("bleedTime")
function Med.Cfg(key)
    return Config.Get("medical", key)
end

-- Med.Simple(): true when the simplified medical system is on (Server
-- settings, live): afflictions off, health as a share of the job's max
-- health, kits heal by share. Shared.
-- Example: if Rhylib.Medical.Simple() then return end   -- skip injury work
function Med.Simple()
    return Config.Get("medical", "simplified") == true
end

-- Med.Hardcore(): true when the hardcore medical system is on (Server
-- settings, live) and the simplified one is off. Shared.
-- Example: if Rhylib.Medical.Hardcore() then ... fractures ... end
function Med.Hardcore()
    return Config.Get("medical", "hardcore") == true and not Med.Simple()
end

-- Med.HealthPct(ply): health as a whole percent of max health, 0-100
-- (HUDs in the simplified system).
function Med.HealthPct(ply)
    -- (rounded down, so 100% only at full health; 1% while any is left)
    local hp = math.max(ply:Health(), 0)
    if hp <= 0 then return 0 end
    return math.Clamp(math.floor(hp / math.max(ply:GetMaxHealth(), 1) * 100), 1, 100)
end

-- Actions a helper can be doing (NW2Int rhylib_medAct, and the kind sent
-- in med.act, Med.ACT_BITS = 4 bits, so at most 15).
Med.A_NONE = 0
Med.A_STAB = 1      -- stabilising (open-ended)
Med.A_REVIVE = 2    -- reviving with a revive kit
Med.A_FA_REVIVE = 3 -- reviving with a first aid kit
Med.A_FA_HEAL = 4   -- heal with a first aid kit
Med.A_MEDKIT = 5    -- one medkit
Med.A_TREAT = 6     -- one body part from the H menu (hardcore; kit in the action)
Med.A_BLOOD = 7     -- blood pack on a downed player
Med.A_HAND_REVIVE = 8 -- revive with no kit (skill Hands-on revive)
Med.ACT_BITS = 4

-- Revives (pause the bleed-out, need a downed target).
Med.REVIVES = { [Med.A_REVIVE] = true, [Med.A_FA_REVIVE] = true, [Med.A_HAND_REVIVE] = true }

-- HUD names of the actions, by A_* number.
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
Med.BLOOD_PACK = "rhylib_bloodpack"
-- Hardcore H menu treatments: kind (Med.TREAT_BITS on the wire) <-> kit.
Med.TREAT_ITEMS = { [0] = Med.FIRST_AID, [1] = Med.MEDKIT }
Med.TREAT_KIND = { [Med.FIRST_AID] = 0, [Med.MEDKIT] = 1 }
Med.TREAT_BITS = 2
-- Anyone may use these (first aid kits and blood packs are for medics).
Med.ANYONE = { [Med.MEDKIT] = true }

-- Plain items registered with rhylib_inventory:
-- { id, name, description, stack size, weight, model }.
Med.ITEMS = {
    { Med.SUPPLIES, "Medical supplies", "Chemists turn these into medicine at a chemistry bench", 10, 0.2, "models/items/healthkit.mdl" },
    { Med.BLOOD_PACK, "Blood pack", "Medics: buys a downed player another minute (E menu)", 3, 0.4, "models/healthvial.mdl" },
}
-- Old field items, no longer made: saved ones load as medical supplies
-- (rhylib_inventory Items.RENAMED).
Med.OLD_ITEMS = { "rhylib_splint", "rhylib_burngel", "rhylib_painkiller" }

-- Medicines for illnesses: { id, name, description }. Given in units with
-- "Give medicine" on the interaction wheel (sv_50_illness.lua); the stack
-- size is raised to 20 in sh_50_illness.lua. The order matters: the dose
-- message sends the medicine as its place in this list (2 bits).
Med.MEDICINES = {
    { "rhylib_antiviral", "Antiviral", "Viral infections (blue strip). In units: the analyser gives the dose" },
    { "rhylib_antidote", "Antidote", "Poisoning (purple strip). In units: the analyser gives the dose" },
    { "rhylib_antibiotics", "Antibiotics", "Bacterial infections (green strip). In units: the analyser gives the dose" },
}

-- Registers Med.ITEMS and Med.MEDICINES with rhylib_inventory (skipped
-- without it, and for ids another addon already registered).
local function registerMedicines()
    local Items = Rhylib.Items
    if not Items or not Items.Register then return end
    if Items.RENAMED then
        for _, id in ipairs(Med.OLD_ITEMS) do Items.RENAMED[id] = Items.RENAMED[id] or Med.SUPPLIES end
    end
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
-- leave them out, the bench is closed).
-- Hook Rhylib.ItemDisabled(id) (asked by rhylib_armoury): true = leave
-- this item out.
Med.HARDCORE_ITEMS = {
    [Med.SUPPLIES] = true, [Med.BLOOD_PACK] = true,
    rhylib_antiviral = true, rhylib_antidote = true, rhylib_antibiotics = true,
    rhylib_blood_kit = true, rhylib_test_strip = true, rhylib_blood_sample = true, rhylib_test_cassette = true,
}
Rhylib.Hook.Add("Rhylib.ItemDisabled", "medical.simple", function(id)
    if Med.HARDCORE_ITEMS[id] and Med.Simple() then return true end
end)

-- Medkits stack medkitStack for troopers and medkitStackMedic for medics,
-- + deepPockets with the Deep pockets skill (hook Rhylib.ItemStack(def,
-- ply), asked by rhylib_inventory; return a number to set the stack size).
Rhylib.Hook.Add("Rhylib.ItemStack", "medical.stack", function(def, ply)
    if def.id == "rhylib_medkit" and IsValid(ply) then
        local n = Med.IsMedic(ply) and Med.Cfg("medkitStackMedic") or Med.Cfg("medkitStack")
        if Med.Skill(ply, "deep_pockets") then n = n + Med.Cfg("deepPockets") end
        return n
    end
end)

-- Med.Skill(ply, id): true if ply has the rhylib_skills skill `id` and is
-- a medic right now (medic skills only count in a medic job). False
-- without rhylib_skills. Shared.
-- Example: if Rhylib.Medical.Skill(ply, "triage") then ... end
function Med.Skill(ply, id)
    local K = Rhylib.Skills
    if not (K and K.Has and IsValid(ply) and ply:IsPlayer()) then return false end
    return K.Has(ply, id) and Med.IsMedic(ply)
end

-- Med.DragSpeed(ply): top speed while dragging (dragSpeed, or
-- dragSpeedSkill with Field drag).
function Med.DragSpeed(ply)
    return Med.Skill(ply, "field_drag") and Med.Cfg("dragSpeedSkill") or Med.Cfg("dragSpeed")
end

-- Med.InMedBay(ply): true if ply is within medBayRange of an entity of a
-- medBayClasses class (bacta tank, medical holotable). The list of those
-- entities is refreshed at most every 3 s. Shared.
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
-- State readers (shared): read the NW2 values, so they work on both realms.
--------------------------------------------------------------------------

-- Med.IsDown(ply): true while ply is downed. (On the server,
-- ply.rhylibDown is the same thing without a NW2 read.)
-- Example: if Rhylib.Medical and Rhylib.Medical.IsDown(ply) then return end
function Med.IsDown(ply)
    return ply:GetNW2Bool(Rhylib.NW.DOWN, false)
end

-- Med.StabilisedBy(ply): the player whose action pauses ply's bleed-out
-- (stabilising, reviving, or a Medevac drag), or nil.
function Med.StabilisedBy(ply)
    local e = ply:GetNW2Entity(Rhylib.NW.STAB_BY)
    return IsValid(e) and e or nil
end

-- Med.DraggedBy(ply): who is dragging the downed ply, or nil.
function Med.DraggedBy(ply)
    local e = ply:GetNW2Entity(Rhylib.NW.DRAG_BY)
    return IsValid(e) and e or nil
end

-- Med.Dragging(ply): the downed player ply is dragging, or nil.
function Med.Dragging(ply)
    local e = ply:GetNW2Entity("rhylib_dragging")
    return IsValid(e) and e or nil
end

-- Med.TimeLeft(ply): seconds of bleed-out left. While paused (stabilised)
-- this is the frozen rhylib_downLeft; otherwise rhylib_downEnd - now.
function Med.TimeLeft(ply)
    if Med.StabilisedBy(ply) then return ply:GetNW2Float(Rhylib.NW.DOWN_LEFT, 0) end
    return math.max(0, ply:GetNW2Float(Rhylib.NW.DOWN_END, 0) - CurTime())
end

-- Med.Action(ply): what ply is doing as a helper. Returns 0 when nothing,
-- else action (A_*), target, start time, end time (end 0 = open-ended,
-- stabilising).
-- Example: local a, target = Rhylib.Medical.Action(ply)
--          if a == Rhylib.Medical.A_STAB then ... end
function Med.Action(ply)
    local a = ply:GetNW2Int("rhylib_medAct", 0)
    if a == 0 then return 0 end
    return a, ply:GetNW2Entity("rhylib_medT"), ply:GetNW2Float("rhylib_medS", 0), ply:GetNW2Float("rhylib_medE", 0)
end

-- Med.IsMedic(ply): true if ply's DarkRP job has medic = true. Hook
-- Rhylib.IsMedic(ply) is asked first: return true/false to decide
-- yourself (other gamemodes, special jobs); nil = use the job flag.
-- Example (your addon): hook.Add("Rhylib.IsMedic", "myaddon", function(ply)
--     if ply:GetNWBool("isDoctor") then return true end end)
function Med.IsMedic(ply)
    if not ply:IsPlayer() then return false end   -- (test dummies)
    local r = hook.Run("Rhylib.IsMedic", ply)
    if r ~= nil then return r end
    local job = RPExtraTeams and RPExtraTeams[ply:Team()]
    return job and job.medic == true or false
end

-- Med.HoldingHands(ply): true if ply holds nothing, the rhylib_inventory
-- Stowed weapon, or a class in dragWeapons (empty hands, can drag).
function Med.HoldingHands(ply)
    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) then return true end
    local list = Med.Cfg("dragWeapons")
    return wep.IsRhylibStowed or (istable(list) and list[wep:GetClass()]) or false
end

-- Med.BodyPos(ply): centre of a lying body, a Vector (for aiming and range
-- checks).
function Med.BodyPos(ply)
    -- rhylib_core measures where the lying pose really puts the body.
    if Rhylib.Lying and Rhylib.Lying.BodyPos then return Rhylib.Lying.BodyPos(ply) end
    return ply:GetPos() + Vector(0, 0, 10)
end

-- Test dummies (NextBots, lua/entities/rhylib_test_dummy.lua): the set of
-- them, filled by the entity itself.
Med.dummies = Med.dummies or {}

-- Med.IsDummy(ent): true for a test dummy. Shared.
function Med.IsDummy(ent)
    return IsValid(ent) and ent.IsRhylibDummy == true
end

-- Med.IsPatient(ent): true for anyone the medical system treats: a player
-- or a test dummy. Shared.
-- Example: if not Rhylib.Medical.IsPatient(tr.Entity) then return end
function Med.IsPatient(ent)
    return IsValid(ent) and (ent:IsPlayer() or ent.IsRhylibDummy == true)
end

-- Med.HealthOf(ent): health, max health of a patient. On clients a test
-- dummy's come from its NW2 copy (rhylib_dummyHp / rhylib_dummyMax).
function Med.HealthOf(ent)
    if CLIENT and ent.IsRhylibDummy then
        return ent:GetNW2Int("rhylib_dummyHp", 0), ent:GetNW2Int("rhylib_dummyMax", 100)
    end
    return ent:Health(), ent:GetMaxHealth()
end

--[[
    The downed player `ply` is aiming at, within range. Lying bodies are
    small, so this checks aim direction against every downed player
    instead of tracing for hitboxes. The list is short.
    Med.FindDowned(ply, list): list = players to check (server:
    Med.downList, client: Med.clientDown; both hold test dummies too; nil =
    every player). Returns the downed patient most in line with the aim, with no wall between, or nil.
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
                -- A body about 30 units around, plus some slack: the aim
                -- must be within atan(30 / dist) + 0.1 rad of the body
                -- (at most 1.2 rad close up).
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

-- Med.FindStanding(ply): the living, not downed patient (player or test
-- dummy) ply aims at within range + 20 (a small hull trace), or nil.
function Med.FindStanding(ply)
    local tr = util.TraceHull({
        start = ply:EyePos(),
        endpos = ply:EyePos() + ply:GetAimVector() * (Med.Cfg("range") + 20),
        filter = ply,
        mins = Vector(-4, -4, -4), maxs = Vector(4, 4, 4),
        mask = MASK_SHOT_HULL,
    })
    local e = tr.Entity
    if Med.IsPatient(e) and e:Alive() and not Med.IsDown(e) then return e end
end

-- Server settings page: this module's name, sidebar category and sections
-- (Config.Sections: patterns over the keys, the first match wins; core
-- applies them to every key of the module, registered before or after).
local SECTIONS = {
    { "General", { "^enabled$", "^range$", "^selfMult$", "^noTarget$", "^markerRange$", "^viewRange$" } },
    { "Simplified system", { "^simpl" } },
    { "Hardcore", { "^hardcore$", "^hc" } },
    { "Downed & bleeding out", { "^bleedTime$", "^downHealth$", "^downGrace$", "^giveUpTime$", "^downSequences$", "^callMedic" } },
    { "Revives", { "^reviveKit", "^firstAidRevive", "^handRevive", "^bloodPack" } },
    { "Kits & field items", { "^firstAid", "^medkit", "^bacta" } },
    { "Dragging", { "^drag" } },
    { "Medic skills", { "^steadyMult$", "^quickReviveMult$", "^deepPockets$", "^efficientCare$", "^triageFlash$", "^regen", "^patched" } },
    { "Injuries", { "^injuries$", "Bleed", "^limp", "^recover$", "^armNoAim", "^armSpread$", "^torso" } },
    { "Med bay, bacta tank & sofa", { "^medBay", "^tank", "^sofa" } },
    { "Chemistry bench", { "^bench", "^craftTime$", "^chemRecipes$" } },
    { "Illness", { "^loadRate$", "^illDrain$", "^poisonAfterDown$", "^drawTime$", "^scan", "^dose", "^strip", "^sampleLife$" } },
}
Config.Describe("medical", { name = "Medical", category = "Soldiers" })
Config.Sections("medical", SECTIONS)   -- (core: applies to keys registered before and after)
