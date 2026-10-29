--[[
    Rhy's Bounty Hunters (shared): config, item types, who counts as a
    bounty hunter, the Bounty hunter skill tree and its shared effects.

    The system in short (server: sv_10_bounty.lua):
      - A Bounty Office (entity rhylib_bounty_office, placed by staff) holds
        the board. Players post bounties on other players with their own
        money (held by the office until paid or refunded); staff
        (rhylib.bounty.gm) post free ones on players, NPCs or themselves.
      - A bounty wants its target dead, alive, or either.
      - Contracts: an open bounty hands out a contract item to every hunter
        who accepts it. A standalone bounty has one contract, made in the
        poster's inventory for them to hand over; only it can claim that
        bounty. Contracts can be looted.
      - Proof: a dead target leaves a body (bodyLife s); anyone can collect
        proof from it through the interaction wheel. Proof is an item only
        (never dropped on the ground), so it can be looted too. Turning it
        in at the office pays every open bounty on that target posted
        before the death (standalone ones only with their contract).
      - Alive: binders (rhylib_binders, needs rhylib_mp) restrain a downed
        or stunned target with an alive/either bounty; escort them to the
        office and hand them in. They are released at a spawn point.
      - The Bounty Puck (rhylib_bounty_puck) beeps faster the closer you
        are to your contract's target; no direction.
      - Wanted posters (rhylib_bounty_poster) and the datapad's Bounties
        tab show the open bounties, so targets can find out.

    Config module "bounty" (Server settings). Permission rhylib.bounty.gm
    (default admin; the gamemaster rank has it in rhylib_admin's default
    ranks).

    Adds Rhylib.Bounty (B): B.Cfg, B.IsHunter, B.MODES, B.CONTRACT,
    B.PROOF, B.PUCK, B.BINDERS, B.ContractLimit, B.Gun (gun setup for the
    weapon files).
]]

Rhylib.Bounty = Rhylib.Bounty or {}
local B = Rhylib.Bounty
local Config = Rhylib.Config
if Config.Describe then Config.Describe("bounty", { name = "Bounty hunters", category = "Units & roles" }) end   -- (Server settings page)

-- B.After(id, fn): run fn once module `id` is loaded (now if it already
-- is): rhylib_core's Rhylib.After.
function B.After(id, fn) return Rhylib.After(id, fn) end

B.CONTRACT = "rhylib_bounty_contract"
B.PROOF = "rhylib_bounty_proof"
B.PUCK = "rhylib_bounty_puck"
B.BINDERS = "rhylib_binders"

-- Bounty modes: { id, label }. Index = the wire value (2 bits).
B.MODES = { { "dead", "Dead" }, { "alive", "Alive" }, { "either", "Dead or alive" } }
B.MODE_INDEX = { dead = 1, alive = 2, either = 3 }

Rhylib.Perms.Register("rhylib.bounty.gm", "admin", "Free bounties on players, NPCs or yourself; cancel any bounty")

Config.Register("bounty", "hunterOnly", true, "Only bounty hunter jobs (job bountyHunter = true) may accept contracts and buy hunter gear")
Config.Register("bounty", "postMin", 500, "Smallest bounty a player can post")
Config.Register("bounty", "postMax", 100000, "Largest bounty a player can post")
Config.Register("bounty", "fee", 0.1, "Share of the reward kept by the office when a bounty expires or is cancelled")
Config.Register("bounty", "life", 7200, "Seconds (real time) before an unclaimed bounty expires and is refunded")
Config.Register("bounty", "maxPerPoster", 3, "Open bounties one player may have posted at once")
Config.Register("bounty", "aliveBonus", 1.25, "Dead-or-alive office (staff) bounties pay this much more when the target is brought in alive (players' bounties pay what was put up)")
Config.Register("bounty", "collectTime", 5, "Seconds to collect proof from a body")
Config.Register("bounty", "bindAutoRelease", 600, "Seconds someone bound with binders and left alone (not escorted, no hunter within bindNearRange) waits before slipping free (0 = never)")
Config.Register("bounty", "bindNearRange", 1500, "A bounty hunter this close (units) counts as holding a bound prisoner")
Config.Register("bounty", "notifyTarget", true, "Tell a player in chat when a bounty is posted on them")
Config.Register("bounty", "notifyAmount", true, "Say the reward in that message (off: only that there is one)")
Config.Register("bounty", "bodyLife", 150, "Seconds a bounty target's body stays (proof can be taken until then)")
Config.Register("bounty", "contracts", 1, "Contracts a hunter can hold at once (Guild licence: contractsSkill)")
Config.Register("bounty", "contractsSkill", 2, "Contracts a hunter with Guild licence can hold")
Config.Register("bounty", "puckFar", 6000, "Puck: further than this the puck beeps every 5 s")
Config.Register("bounty", "puckMid", 2500, "Puck: from here in it beeps every 3 s, then faster and higher closer in")
Config.Register("bounty", "puckClose", 300, "Puck: within this it beeps rapidly")
Config.Register("bounty", "puckLevel", 62, "Puck beep loudness (dB); others nearby hear it too")
Config.Register("bounty", "shop", {
    { "rhylib_bh_m35sniper", 9000 }, { "rhylib_bh_longrifle", 11000 }, { "rhylib_bh_rifle", 7000 },
    { "rhylib_bh_m35commando", 5500 }, { "rhylib_bh_e7", 4500 }, { "rhylib_bh_dlt16s", 6000 },
    { "rhylib_bh_dr18", 3500 }, { "rhylib_bh_b10", 2600 }, { "rhylib_bh_m35pistol", 3000 },
    { "rhylib_bounty_puck", 1500 }, { "rhylib_binders", 600 },
    { "mag_small", 60 }, { "mag_medium", 100 }, { "mag_large", 250 }, { "cell", 150 },
    { "rhylib_thermal", 400 }, { "rhylib_thermal_impact", 450 }, { "rhylib_droidpopper", 400 },
    { "rhylib_flashcharge", 500 }, { "rhylib_he_charge", 1200 },
}, "The Gear tab at the Bounty Office: { item id, price }. Items that aren't installed are left out")
Config.Register("bounty", "skillMults", {
    quickDraw = 0.6, scopeSpread = 0.7, scopeRecoil = 0.7, binders = 0.5, fieldKit = 0.5, finisherCollect = 0.5,
    puckRange = 1.5, bring = 1.25, marked = 1.15, deadShot = 1.25,
}, "Bounty hunter skill numbers (see the skill descriptions)")

-- B.Cfg(key): a "bounty" config value.
function B.Cfg(k) return Config.Get("bounty", k) end
function B.Mult(k) local t = B.Cfg("skillMults") return istable(t) and tonumber(t[k]) or 1 end

-- B.IsHunter(ply): a bounty hunter (hook Rhylib.IsBountyHunter(ply) wins
-- when it answers, else the job's bountyHunter = true). Both realms.
function B.IsHunter(ply)
    if not (IsValid(ply) and ply:IsPlayer()) then return false end
    local r = hook.Run("Rhylib.IsBountyHunter", ply)
    if r ~= nil then return r and true or false end
    local job = RPExtraTeams and RPExtraTeams[ply:Team()]
    return job ~= nil and job.bountyHunter == true
end

-- B.MayHunt(ply): may accept contracts and buy gear (hunterOnly off = anyone).
function B.MayHunt(ply)
    return not B.Cfg("hunterOnly") or B.IsHunter(ply)
end

-- B.Has(ply, skill): a Bounty hunter skill (false without rhylib_skills),
-- and only while they may hunt (B.MayHunt): learned skills sleep in other jobs.
function B.Has(ply, id)
    local K = Rhylib.Skills
    return K ~= nil and K.Has ~= nil and K.Has(ply, id) and B.MayHunt(ply) or false
end

-- B.ContractLimit(ply): contracts the player may hold at once.
function B.ContractLimit(ply)
    return B.Has(ply, "bh_licence") and B.Cfg("contractsSkill") or B.Cfg("contracts")
end

-- Contract / proof notes start with "#<bounty id> " (contracts) so the
-- client can tell which bounty a contract is for (item data stays on the
-- server; only the note is sent). B.NoteBid(note) -> id or nil.
function B.NoteBid(note)
    return tonumber(string.match(note or "", "^#(%d+) "))
end

--------------------------------------------------------------------------
-- Items (rhylib_inventory loads after us: B.After)
--------------------------------------------------------------------------

local function registerItems()
    local Items = Rhylib.Items
    if not (Items and Items.Register) then return end
    if not Items.Get(B.CONTRACT) then
        Items.Register(B.CONTRACT, {
            name = "Bounty contract", w = 1, h = 1, weight = 0.05, stack = 1, category = "misc",
            desc = "A bounty hunter's contract. A Bounty Puck tracks its target. Standalone contracts are needed to claim their bounty.",
            model = "models/props_lab/clipboard.mdl", note = true,
        })
    end
    if not Items.Get(B.PROOF) then
        Items.Register(B.PROOF, {
            name = "Bounty proof", w = 1, h = 1, weight = 0.2, stack = 1, category = "misc",
            desc = "Proof of a kill. Turn it in at a Bounty Office for the reward, whoever collected it.",
            model = "models/props_lab/box01a.mdl", note = true,
        })
    end
end
B.After("inventory", registerItems)

-- Turn the DarkRP money setting (rhylib_roster) on by default: bounties pay
-- in DarkRP money. A value saved in Server settings still wins.
local function moneyDefault()
    if not Rhylib.Roster then return end
    local host = Config.values and Config.values.roster
    if host and host.money ~= nil then return end   -- (a host config file chose already)
    Config.Set("roster", "money", true)
    if SERVER and not Rhylib.Bounty.moneyTold then
        Rhylib.Bounty.moneyTold = true
        Rhylib.Print("bounty", "DarkRP money is ON for the whole server (paydays, /give, doors), because Rhy's Bounty Hunters is installed. Set roster money in a host config file to choose yourself.")
    end
end
B.After("roster", moneyDefault)

-- Grenades that need a trooper skill (droid popper, flash charge) are
-- allowed for bounty hunters (they can't learn the trooper trees).
B.GRANTED = { droid_popper = true, flash_charge = true }
Rhylib.Hook.Add("Rhylib.SkillGranted", "bounty.grenades", function(ply, skill)
    if B.GRANTED[skill] and B.IsHunter(ply) then return true end
end)

--------------------------------------------------------------------------
-- Skill tree (rhylib_skills K.AddTree; it loads after us)
--------------------------------------------------------------------------

B.TREE = {
    id = "hunter", name = "Bounty hunter", desc = "Bounty hunter jobs only: tracking, capture and the kill",
    rule = "Bounty hunter jobs only.", noBorrow = true,
    allowed = function(ply) return B.IsHunter(ply), "Bounty hunters only" end,
    specs = {
        { id = "bh_tracker", name = "Tracker", desc = "Find them and bring them in alive" },
        { id = "bh_gunslinger", name = "Gunslinger", desc = "Find them and finish it" },
    },
}
B.NODES = {
    { id = "bh_licence", cat = "hunter", tier = 1, cost = 2, name = "Guild licence", icon = "star",
      desc = "Hold two bounty contracts at once instead of one." },
    { id = "bh_kit", cat = "hunter", tier = 2, cost = 2, name = "Field kit", icon = "pocket",
      desc = "Collect proof from a body twice as fast.", needs = { "bh_licence" } },
    -- Tracker
    { id = "bh_puck", cat = "hunter", spec = "bh_tracker", tier = 3, cost = 3, name = "Tuned puck", icon = "eye",
      desc = "Your Bounty Puck's faster beeps start half again as far out. Still no direction.", needs = { "bh_kit" } },
    { id = "bh_stun", cat = "hunter", spec = "bh_tracker", tier = 3, cost = 3, name = "Stun rounds", icon = "bolt",
      desc = "Bounty hunter pistols and carbines get a stun fire mode (E + R): a stunned target can be bound.", needs = { "bh_kit" } },
    { id = "bh_binders", cat = "hunter", spec = "bh_tracker", tier = 4, cost = 3, name = "Quick binders", icon = "cuffs",
      desc = "Binding a target takes half the time.", needs = { "bh_stun" } },
    { id = "bh_quiet", cat = "hunter", spec = "bh_tracker", tier = 4, cost = 3, name = "Quiet steps", icon = "feather",
      desc = "No footsteps while you slow-walk (walk key) or crouch.", needs = { "bh_puck" } },
    { id = "bh_bring", cat = "hunter", spec = "bh_tracker", tier = 5, cost = 4, name = "Bring them in", icon = "drag",
      desc = "Escorting a prisoner doesn't slow you, and office (staff) bounties pay 25% more when you bring the target in alive.", needs = { "bh_binders" } },
    { id = "bh_relentless", cat = "hunter", spec = "bh_tracker", tier = 6, cost = 4, name = "Relentless", icon = "anchor",
      desc = "Your Bounty Puck keeps working inside comms jammers, yours or the target's.", needs = { "bh_quiet", "bh_bring" } },
    -- Gunslinger
    { id = "bh_draw", cat = "hunter", spec = "bh_gunslinger", tier = 3, cost = 3, name = "Quick draw", icon = "pistol",
      desc = "Bounty hunter pistols come out faster.", needs = { "bh_kit" } },
    { id = "bh_scope", cat = "hunter", spec = "bh_gunslinger", tier = 3, cost = 3, name = "Steady scope", icon = "crosshair",
      desc = "The Westar-M35 sniper and the Long rifle are steadier and kick less while aimed.", needs = { "bh_kit" } },
    { id = "bh_twin", cat = "hunter", spec = "bh_gunslinger", tier = 4, cost = 3, name = "Twin revolvers", icon = "dual",
      desc = "Carry two B-10 revolvers and fire them both (dual mode, E + R).", needs = { "bh_draw" } },
    { id = "bh_marked", cat = "hunter", spec = "bh_gunslinger", tier = 4, cost = 3, name = "Marked man", icon = "target",
      desc = "15% more damage to the target of a contract you carry.", needs = { "bh_scope" } },
    { id = "bh_deadshot", cat = "hunter", spec = "bh_gunslinger", tier = 5, cost = 4, name = "Dead shot", icon = "aim",
      desc = "25% more headshot damage with bounty hunter weapons.", needs = { "bh_marked" } },
    { id = "bh_finisher", cat = "hunter", spec = "bh_gunslinger", tier = 6, cost = 4, name = "Finisher", icon = "burst",
      desc = "Your shots finish a downed bounty target at once, and you collect proof twice as fast (on top of Field kit).",
      needs = { "bh_twin", "bh_deadshot" } },
}

local function addTree()
    local K = Rhylib.Skills
    if not (K and K.AddTree) then return end
    K.AddTree(B.TREE, B.NODES)
    B.WrapSkills()
end

-- Shared skill effects, by wrapping rhylib_skills' multipliers (once).
function B.WrapSkills()
    local K = Rhylib.Skills
    if not K or K.bountyWrapped then return end
    K.bountyWrapped = true
    local draw, spread, recoil = K.DrawMult, K.SpreadMult, K.RecoilMult
    if draw then
        K.DrawMult = function(ply, wep)
            local m = draw(ply, wep)
            if IsValid(wep) and wep.BountyPistol and B.Has(ply, "bh_draw") then m = math.min(m, B.Mult("quickDraw")) end
            return m
        end
    end
    local function scoped(ply, wep)
        return IsValid(wep) and wep.BountySniper and wep.GetAiming and wep:GetAiming() and B.Has(ply, "bh_scope")
    end
    if spread then
        K.SpreadMult = function(ply, wep)
            local m = spread(ply, wep)
            if scoped(ply, wep) then m = m * B.Mult("scopeSpread") end
            return m
        end
    end
    if recoil then
        K.RecoilMult = function(ply, wep)
            local m = recoil(ply, wep)
            if scoped(ply, wep) then m = m * B.Mult("scopeRecoil") end
            return m
        end
    end
    if SERVER and B.WrapServerSkills then B.WrapServerSkills() end
end
B.After("skills", addTree)

-- Quiet steps: no footsteps while walking or crouching (both realms, so
-- the player's own prediction stays quiet too).
Rhylib.Hook.Add("PlayerFootstep", "bounty.quiet", function(ply)
    if (ply:Crouching() or ply:KeyDown(IN_WALK)) and B.Has(ply, "bh_quiet") then return true end
end)

--------------------------------------------------------------------------
-- Weapons: B.Gun(SWEP, opts) at the end of each bounty gun file
--------------------------------------------------------------------------

-- Sets what every bounty hunter gun shares: category, not in the
-- Republic armouries, stun mode for Stun rounds (not the MP rule), no
-- Republic skill modes. opts: pistol / sniper (skill flags), dual (the
-- dual mode's skill), modes (FireModes), color (bolt colour, default 2
-- red), autoModes.
function B.Gun(SWEP, opts)
    opts = opts or {}
    SWEP.Category = "Rhy's Bounty hunters"
    SWEP.Spawnable = true
    SWEP.AdminOnly = true
    SWEP.BountyWeapon = true
    SWEP.BountyPistol = opts.pistol or nil
    SWEP.BountySniper = opts.sniper or nil
    SWEP.NoArmoury = true
    SWEP.Training = false
    SWEP.TrainingOf = nil
    SWEP.Grapple = true
    SWEP.FireModes = opts.modes or { "semi", "stun" }
    SWEP.SkillModes = { stun = "bh_stun", dual = opts.dual }
    SWEP.ModeReplaces = {}
    SWEP.ModeProxies = {}
    SWEP.ModeHoldTypes = {}
    SWEP.ModeFireGestures = {}
    SWEP.MagSkills = {}
    SWEP.AutoModes = opts.autoModes or { auto = true }
    SWEP.ScopeSkill = false
    SWEP.CarrySkill = false
    SWEP.BoltColor = opts.color or 2   -- (red unless the gun says: 3 green, 7 yellow)
    -- Stun: Stun rounds (not military police); everything else as usual.
    function SWEP:ModeAllowedBase(i)
        local name = self.FireModes[i]
        if name == "stun" then
            local o = self:GetOwner()
            return IsValid(o) and o:IsPlayer() and B.Has(o, "bh_stun") or false
        end
        if name == "dual" and self:CarriedCount() < 2 then return false end
        if name == "dual" and opts.dual then   -- (hunter skill: only while hunting, B.Has)
            local o = self:GetOwner()
            return IsValid(o) and o:IsPlayer() and B.Has(o, opts.dual) or false
        end
        local K = Rhylib.Skills
        if not (K and K.ModeAllowed) then return true end
        return K.ModeAllowed(self:GetOwner(), self, name)
    end
end

--------------------------------------------------------------------------
-- Models and the toolgun
--------------------------------------------------------------------------

Config.Register("bounty", "officeModel", "models/Humans/Group02/male_02.mdl", "The Bounty Office agent's model", { name = "Bounty Office agent", group = "Bounty hunters" })
Config.Register("bounty", "posterModel", "models/hunter/plates/plate1x1.mdl", "The wanted poster's board (a thin plate; the poster is drawn on its face)", { name = "Wanted poster board", group = "Bounty hunters" })

-- Toolgun (rhylib_toolgun) entries, category "Bounty" (gamemasters with
-- rhylib.bounty.gm may place them). The poster is put flat on the wall you
-- aim at.
Rhylib.Hook.Add("Rhylib.ToolEntries", "bounty.tool", function(list)
    if scripted_ents.GetStored("rhylib_bounty_office") then
        list[#list + 1] = { id = "bounty_office", name = "Bounty Office", cat = "Bounty", class = "rhylib_bounty_office", perm = "rhylib.bounty.gm" }
    end
    if scripted_ents.GetStored("rhylib_bounty_poster") then
        list[#list + 1] = { id = "bounty_poster", name = "Wanted poster (aim at a wall)", cat = "Bounty", class = "rhylib_bounty_poster", perm = "rhylib.bounty.gm",
            place = function(ply, tr)
                local e = ents.Create("rhylib_bounty_poster")
                if not IsValid(e) then return {} end
                local stored = scripted_ents.GetStored("rhylib_bounty_poster").t
                e:SetAngles(stored.FaceAngles(tr.HitNormal))
                e:SetPos(tr.HitPos + tr.HitNormal * 2)
                e:Spawn()
                return { e }
            end }
    end
end)
