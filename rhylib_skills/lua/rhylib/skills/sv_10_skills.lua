--[[
    Skills on the server: saving, learning, resetting, and the effects
    that only the server works out (damage, Momentum, inventory grids).

    Data "skills" key "s"..SteamID64 = { n = { ids } } (sorted ids; a
    reset deletes the row). Class mode rows: sv_40_class.lua.
    Nets: skills.learn (node index, 8 bits), skills.unlearn (node index:
    right-click undo, K.CanUnlearn + K.UndoAllowed or the reset hook),
    skills.reset (empty), skills.note (server -> player: bad bool, text;
    a chat line).
    Hooks fired: Rhylib.SkillsChanged(ply) after every change,
    Rhylib.CanResetSkills(ply) (return true / false to allow or refuse a
    reset while freePoints is off; true also allows a late undo; nil = the
    built-in rule), Rhylib.SkillPoints(ply) (in K.Points).
    Free resets (built in): one every resetCooldownDays (7) days per
    player; the last one is Data "skills" key "r"..SteamID64 (os.time).
    K.ResetState(ply) -> ok, nextAt, viaCooldown; NW2Int rhylib_skillReset
    on the player = 0 (allowed now), -1 (never) or the os.time of the next
    free reset (set on join, after a reset, every 60 s), read by
    K.ResetInfo for the Reset button. Admin resets don't use it up.
    Console: rhylib_skills_reset [name] (perm rhylib.skills.admin, admin).
    While freePoints is on: a warning in the server console at start and a
    chat + console line to every superadmin who joins.
    K.SetSkills(ply, set) applies a set (NW2String, save, inventory grids).
    K.DamageMult(ply, bolt, ent, tr, group) for rhylib_weapons (Focus fire,
    Carbine sidearm, Point blank, Headhunter, Shotgun drills, crits /
    Light rounds);
    returns mult, crit.
    K.ExtraGrids(ply) for rhylib_inventory: { [cid] = { w, h } } the
    player's skills open (Ammo belt); K.BackpackMult(ply) (Load bearer
    doubles the backpack).
    On a change: items the player may no longer carry are dropped
    (droid poppers without Droid popper), Hard landings jump power,
    Reinforced max health.
    Damage taken (EntityTakeDamage 95, before armour): Hard landings,
    Blast hardened, Aerial stability, Combat drop, Juggernaut, Under fire,
    Hold the line, and the Hold fast / Press forward orders.
    Death from above: OnPlayerHitGround.
]]

local K = Rhylib.Skills
local Data = Rhylib.Data

Rhylib.Net.Register("skills.note")

local function key(ply) return "s" .. (ply:SteamID64() or "0") end

-- Renamed skills (old saves keep working): old id -> new id.
local RENAMED = { burst_fire = "rapid_fire", thruster_dodge = "combat_drop" }

local function setString(set)
    local ids = {}
    for _, n in ipairs(K.NODES) do
        if set[n.id] then ids[#ids + 1] = n.id end
    end
    return #ids > 0 and ("," .. table.concat(ids, ",") .. ",") or ""
end

-- K.Stored(ply): the player's skill set as the server holds it, read from
-- Data on first use (the inventory may ask before PlayerInitialSpawn) and
-- cleaned of old/renamed/impossible skills. In class mode this is the
-- class's set (K.SetSkills keeps it in ply.rhylibSkills). Server only.
function K.Stored(ply)
    if ply.rhylibSkillsLoaded then return ply.rhylibSkills end
    local set = {}
    if not ply:IsBot() then
        local d = Data.Get("skills", key(ply))
        if istable(d) and istable(d.n) then
            for _, id in ipairs(d.n) do
                id = RENAMED[id] or id
                if K.byId[id] then set[id] = true end
            end
        end
    end
    -- The officer split: a save with officer skills from both
    -- specs (old saves had Adaptable in the pistol tree) keeps the spec
    -- with more skills; losing Adaptable also drops what it borrowed.
    local count = { pistol = 0, commander = 0 }
    for id in pairs(set) do
        local n = K.byId[id]
        if n and n.cat == "officer" and count[n.spec] then count[n.spec] = count[n.spec] + 1 end
    end
    -- (Adaptable may borrow from the other side: fine while it fits its slot)
    local legit = false
    if set.adapt_1 and count.pistol > 0 and count.commander > 0 then
        local tiers = {}
        for id in pairs(set) do
            if K.Borrowed(set, id) then tiers[#tiers + 1] = K.byId[id].tier end
        end
        legit = K.FitsSlots(tiers, K.AdaptSlots(set))
    end
    if count.pistol > 0 and count.commander > 0 and not legit then
        local drop = count.pistol >= count.commander and "commander" or "pistol"
        local hadAdapt = set.adapt_1
        for id in pairs(set) do
            local n = K.byId[id]
            if n and n.cat == "officer" and n.spec == drop then set[id] = nil end
        end
        if hadAdapt and not set.adapt_1 then
            for id in pairs(set) do
                if K.byId[id].cat ~= "officer" then set[id] = nil end
            end
        end
        if not ply:IsBot() then
            local ids = {}
            for id in pairs(set) do ids[#ids + 1] = id end
            table.sort(ids)
            Data.Set("skills", key(ply), { n = ids })
        end
    end
    -- Skills another one made pointless (Full auto with Combat veteran) go.
    local dropped = false
    for id in pairs(set) do
        if K.Redundant(set, K.byId[id]) then set[id] = nil dropped = true end
    end
    if dropped and not ply:IsBot() then
        local ids = {}
        for id in pairs(set) do ids[#ids + 1] = id end
        table.sort(ids)
        Data.Set("skills", key(ply), { n = ids })
    end
    ply.rhylibSkills = set
    ply.rhylibSkillsLoaded = true
    return set
end

-- K.Note(ply, text, bad): a "[Skills]" chat line for one player (bad =
-- red, with an error sound). Server only.
-- Example: Rhylib.Skills.Note(ply, "Reinforcements inbound", false)
function K.Note(ply, text, bad)
    Rhylib.Net.Start("skills.note")
    net.WriteBool(bad and true or false)
    net.WriteString(text)
    net.Send(ply)
end

-- K.ExtraGrids(ply): extra inventory grids the player's skills open:
-- { [containerId] = { w, h } } (Ammo belt: Items.BELT). rhylib_inventory
-- calls it when it builds a state. (The old Load bearer cell rack,
-- Items.RACK, is never opened now; what was in it moves on join.)
function K.ExtraGrids(ply)
    local out = {}
    local Items = Rhylib.Items
    local set = K.GridSet and K.GridSet(ply) or K.Stored(ply)   -- (class mode: the class's)
    if Items and Items.BELT and set.ammo_belt then
        local b = K.Cfg("ammoBelt") or { 5, 1 }
        out[Items.BELT] = { b[1], b[2] }
    end
    return out
end

-- K.BackpackMult(ply): how many times the backpack grid's rows the
-- player gets (Load bearer: loadBearerPack, else 1). rhylib_inventory.
function K.BackpackMult(ply)
    local set = K.GridSet and K.GridSet(ply) or K.Stored(ply)   -- (class mode: the class's)
    return set.load_bearer and (K.Cfg("loadBearerPack") or 2) or 1
end

local function syncGrids(ply)
    local Inv, Items = Rhylib.Inventory, Rhylib.Items
    if not (Inv and Inv.SetGrid and Items and Items.RACK) then return end
    local want = K.ExtraGrids(ply)
    for _, cid in ipairs({ Items.RACK, Items.BELT }) do
        local g = want[cid]
        Inv.SetGrid(ply, cid, g and g[1] or 0, g and g[2] or 0)
    end
    -- Load bearer doubles the backpack (K.BackpackMult).
    if Inv.RefreshWornGrids then Inv.RefreshWornGrids(ply) end
    if Inv.MarkChanged then Inv.MarkChanged(ply) end   -- carry limit
end

-- Items the player may no longer carry (def.carrySkill, or over the
-- carry limit) are dropped.
local function dropForbidden(ply)
    local Inv = Rhylib.Inventory
    if not (Inv and Inv.Get and Inv.MayHold and Inv.Drop) or not ply:Alive() then return end
    local out, seen = {}, {}
    local list = {}
    for _, o in pairs(Inv.Get(ply).byUid) do list[#list + 1] = o end
    -- (hotbar copies first, so the extra that goes is the one off the hotbar)
    table.sort(list, function(a, b) return (a.hb and 0 or 1) < (b.hb and 0 or 1) end)
    for _, o in ipairs(list) do
        if not Inv.MayHold(ply, o.id) then
            out[#out + 1] = o.uid
        elseif Inv.Limit then
            -- More of a gun than allowed now (a second DC-17 after losing Dual DC-17).
            seen[o.id] = (seen[o.id] or 0) + 1
            if seen[o.id] > Inv.Limit(ply, o.id) then out[#out + 1] = o.uid end
        end
    end
    for _, uid in ipairs(out) do Inv.Drop(ply, uid) end
end

-- Reinforced: max health on top of the job's. Health itself only goes
-- up with it at spawn (relearning mid-fight doesn't heal).
local function applyHealth(ply, spawned)
    local want = K.Has(ply, "reinforced") and K.Cfg("reinforcedHealth") or 0
    local have = ply.rhylibReinforced or 0
    if want == have then return end
    ply.rhylibReinforced = want
    ply:SetMaxHealth(math.max(1, ply:GetMaxHealth() - have + want))
    if ply:Alive() and not Rhylib.State.IsDown(ply) then
        local hp = ply:Health()
        if spawned then hp = hp + math.max(0, want - have) end
        ply:SetHealth(math.Clamp(hp, 1, ply:GetMaxHealth()))
    end
end

-- Hard landings / ARC conditioning: jump power, applied on top of
-- whatever the job set (the base is kept while any of them is learned).
local function applyJump(ply)
    local m = 1
    if K.Has(ply, "hard_landings") then m = m * K.Cfg("springJump") end
    if K.Has(ply, "arc_conditioning") then m = m * K.Cfg("arcJump") end
    if m ~= 1 then
        ply.rhylibSpringBase = ply.rhylibSpringBase or ply:GetJumpPower()
        ply:SetJumpPower(ply.rhylibSpringBase * m)
    elseif ply.rhylibSpringBase then
        ply:SetJumpPower(ply.rhylibSpringBase)
        ply.rhylibSpringBase = nil
    end
end

-- K.SetSkills(ply, set, noSave): give the player exactly this set
-- ({ [id] = true }): NW2String, save, inventory grids, items they may no
-- longer hold dropped, jump power, max health, fire modes fixed, then hook
-- Rhylib.SkillsChanged(ply). No rule checks here (K.CanLearn is the
-- caller's job). noSave: a class preset (class mode); the player's own
-- tree stays in Data. Server only.
-- Example: Rhylib.Skills.SetSkills(ply, { quick_hands = true, run_gun = true })
function K.SetSkills(ply, set, noSave)
    ply.rhylibSkills = set
    ply.rhylibSkillsLoaded = true
    ply:SetNW2String("rhylib_skills", setString(set))
    if not ply:IsBot() and not noSave then
        local ids = {}
        for id in pairs(set) do ids[#ids + 1] = id end
        table.sort(ids)
        if #ids > 0 then Data.Set("skills", key(ply), { n = ids }) else Data.Delete("skills", key(ply)) end
    end
    syncGrids(ply)
    dropForbidden(ply)
    applyJump(ply)
    applyHealth(ply)
    -- A gun on a mode its owner lost goes back to its first mode.
    for _, w in ipairs(ply:GetWeapons()) do
        if w.IsRhylib and w.FixFireMode then w:FixFireMode() end
    end
    hook.Run("Rhylib.SkillsChanged", ply)
end

Rhylib.Hook.Add("PlayerInitialSpawn", "skills.load", function(ply)
    local set = K.Stored(ply)
    ply:SetNW2String("rhylib_skills", setString(set))
end)

-- The spawn sets the job's jump power; ours goes on top a moment later.
Rhylib.Hook.Add("PlayerSpawn", "skills.spawn", function(ply)
    ply.rhylibSpringBase = nil
    -- Take Reinforced off now (this runs before the gamemode's spawn, which
    -- may or may not set max health again); it goes back on just after.
    if (ply.rhylibReinforced or 0) ~= 0 then
        ply:SetMaxHealth(math.max(1, ply:GetMaxHealth() - ply.rhylibReinforced))
        ply.rhylibReinforced = 0
    end
    timer.Simple(0, function()
        if not IsValid(ply) then return end
        applyJump(ply)
        applyHealth(ply, true)
        dropForbidden(ply)
    end)
end)

Rhylib.Hook.Add("PlayerDisconnected", "skills.clear", function(ply)
    ply.rhylibSkills, ply.rhylibSkillsLoaded = nil, nil
end)

-- Learn: rules checked again here (K.CanLearn), the client only asks.
Rhylib.Net.Receive("skills.learn", function(ply)
    local n = K.NODES[net.ReadUInt(8)]
    if not n then return end
    local set = table.Copy(K.Stored(ply))
    local ok, why = K.CanLearn(ply, set, n.id)
    if not ok then return K.Note(ply, why, true) end
    set[n.id] = true
    K.SetSkills(ply, set)
    ply.rhylibLearnedAt = ply.rhylibLearnedAt or {}
    ply.rhylibLearnedAt[n.id] = CurTime()
    K.Note(ply, "Learned " .. n.name)
end, { rate = 4, burst = 8 })

-- Right-click undo (misclicks): only a skill nothing else needs.
Rhylib.Net.Receive("skills.unlearn", function(ply)
    local n = K.NODES[net.ReadUInt(8)]
    if not n then return end
    local set = table.Copy(K.Stored(ply))
    local ok, why = K.CanUnlearn(ply, set, n.id)
    if not ok then return K.Note(ply, why, true) end
    if not K.UndoAllowed(ply.rhylibLearnedAt, n.id) and hook.Run("Rhylib.CanResetSkills", ply) ~= true then
        return K.Note(ply, "Only a skill learned in the last " .. math.Round(K.Cfg("undoWindow") / 60, 1) .. " minutes can be undone", true)
    end
    set[n.id] = nil
    if ply.rhylibLearnedAt then ply.rhylibLearnedAt[n.id] = nil end
    K.SetSkills(ply, set)
    K.Note(ply, "Undid " .. n.name)
end, { rate = 4, burst = 8 })

-- K.ResetState(ply): may they reset their skills now? Returns ok, nextAt
-- (0 = now, -1 = never, else os.time of the next free reset), viaCooldown
-- (true when the free reset is what allows it, so it gets used up).
-- freePoints = always; then the hook Rhylib.CanResetSkills (a true / false
-- answer wins); then one free reset every resetCooldownDays days. Server.
local function resetKey(ply) return "r" .. (ply:SteamID64() or "0") end
function K.ResetState(ply)
    if K.Cfg("freePoints") then return true, 0, false end
    local r = hook.Run("Rhylib.CanResetSkills", ply)
    if r == true then return true, 0, false end
    if r == false then return false, -1, false end
    local days = tonumber(K.Cfg("resetCooldownDays")) or 0
    if days <= 0 or ply:IsBot() then return false, -1, false end
    local last = tonumber(Data.Get("skills", resetKey(ply))) or 0
    local nextAt = last + math.floor(days * 86400)
    if os.time() >= nextAt then return true, 0, true end
    return false, nextAt, false
end

-- NW2Int rhylib_skillReset for the client's Reset button (K.ResetInfo).
local function publishReset(ply)
    if not IsValid(ply) then return end
    local _, nextAt = K.ResetState(ply)
    ply:SetNW2Int("rhylib_skillReset", math.Clamp(nextAt, -1, 2147483647))
end
K.PublishReset = publishReset
Rhylib.Hook.Add("PlayerInitialSpawn", "skills.resetinfo", function(ply)
    timer.Simple(1, function() publishReset(ply) end)
end)
timer.Create("Rhylib.Skills.ResetInfo", 60, 0, function()
    for _, p in ipairs(player.GetHumans()) do publishReset(p) end
end)

local function daysText(secs)
    if secs >= 86400 then
        local d = math.ceil(secs / 86400)
        return d .. " day" .. (d == 1 and "" or "s")
    end
    local h = math.max(1, math.ceil(secs / 3600))
    return h .. " hour" .. (h == 1 and "" or "s")
end

Rhylib.Net.Receive("skills.reset", function(ply)
    if K.ClassOf(ply) then return K.Note(ply, "You're playing a class: leave it on the Class page first", true) end
    if next(K.Stored(ply)) == nil then return end
    local ok, nextAt, viaCooldown = K.ResetState(ply)
    if not ok then
        if nextAt > 0 then
            return K.Note(ply, "Your next free reset is in " .. daysText(nextAt - os.time()), true)
        end
        return K.Note(ply, "Skill resets are off on this server", true)
    end
    K.SetSkills(ply, {})
    ply.rhylibLearnedAt = nil
    if viaCooldown then Data.Set("skills", resetKey(ply), os.time()) end
    publishReset(ply)
    local days = tonumber(K.Cfg("resetCooldownDays")) or 0
    K.Note(ply, viaCooldown and ("Skills reset. Your next free reset is in " .. daysText(days * 86400)) or "Skills reset")
end, { rate = 1, burst = 2 })

-- freePoints is a testing switch: warn the server console once at start
-- and superadmins once per join while it's on.
local FREE_WARN = "Skills are free (freePoints is on): switch it off in Server settings before going live"
Rhylib.Hook.Add("InitPostEntity", "skills.freewarn", function()
    if K.Cfg("freePoints") then Rhylib.Warn("skills", "%s", FREE_WARN) end
end)
Rhylib.Hook.Add("PlayerInitialSpawn", "skills.freewarn", function(ply)
    timer.Simple(8, function()
        if IsValid(ply) and ply:IsSuperAdmin() and K.Cfg("freePoints") then
            K.Note(ply, FREE_WARN, true)
            ply:PrintMessage(HUD_PRINTCONSOLE, "[Skills] " .. FREE_WARN .. "\n")
        end
    end)
end)

-- Admins: rhylib_skills_reset [name] (yourself without a name; also
-- !skillsreset). Rhylib.Command, perm rhylib.skills.admin.
Rhylib.Perms.Register("rhylib.skills.admin", "admin", "Reset other players' skills")
Rhylib.Command.Add({
    name = "rhylib_skills_reset", chat = { "skillsreset" }, perm = "rhylib.skills.admin",
    help = "Reset a player's skills (yourself without a name)", args = "[name]", tag = "Skills",
    fn = function(ply, args)
        local target = IsValid(ply) and ply or nil
        if args[1] then
            target = nil
            for _, p in ipairs(player.GetAll()) do
                if string.find(string.lower(p:Nick()), string.lower(args[1]), 1, true) then target = p end
            end
        end
        if not IsValid(target) then return "No such player", "bad" end
        if K.ClassOf(target) and K.LeaveClass then K.LeaveClass(target, true) end
        K.SetSkills(target, {})
        return "Reset the skills of " .. target:Nick(), "good"
    end,
})

--------------------------------------------------------------------------
-- Damage (called by rhylib_weapons for each bolt hit)
--------------------------------------------------------------------------

-- Is this gun loaded with a small magazine (training copies count)?
local function smallMag(wep)
    if not (IsValid(wep) and wep.GetMag) then return false end
    local mag = wep:GetMag()
    local W = Rhylib.Weapons
    return mag ~= nil and (W and W.BaseMag and W.BaseMag(mag.id) or mag.id) == "mag_small"
end

-- Hits in a row on one target: the streak under ply[key] grows by one
-- step per hit within the window (the first hit adds nothing), up to max.
local function streak(ply, key, ent, windowCfg, maxCfg, stepCfg)
    local now, r = CurTime(), ply[key]
    if r and r.ent == ent and now - r.t <= K.Cfg(windowCfg) then
        r.n = math.min(r.n + 1, K.Cfg(maxCfg))
    else
        r = { ent = ent, n = 0 }
        ply[key] = r
    end
    r.t = now
    return 1 + K.Cfg(stepCfg) * r.n
end

-- K.DamageMult(ply, bolt, ent, tr, group): damage multiplier for one bolt
-- hit (rhylib_weapons sv_10_bolts). bolt = the bolt record (bolt.weapon,
-- bolt.start), ent = what was hit, tr = the trace, group = hit group.
-- Returns mult, crit (crit = true shows a crit marker). Also places Called
-- shot marks and counts Precision rhythm / Sustained fire streaks, so call
-- it once per hit. Server only.
function K.DamageMult(ply, bolt, ent, tr, group)
    if not IsValid(ply) or not ply:IsPlayer() then return 1, false end
    local m, crit = 1, false
    if K.OrderIs(ply, "focus") then m = m * K.Cfg("focusDamage") end   -- (command order)
    if ply:GetNW2Float("rhylib_rush", 0) > CurTime() then m = m * K.Cfg("rushDamage") end   -- (Battle rush)
    local set = K.Set(ply)
    if K.LockMult then m = m * K.LockMult(ply, ent, set) end   -- (a squad mate's locked mark)
    if next(set) == nil then return m, false end
    local wep = bolt.weapon
    if set.combat_veteran and K.IsCarbine(wep) then m = m * K.Cfg("vetCarbineDamage") end   -- (Combat veteran)
    if set.arc_training and IsValid(wep) and K.GunClass(wep) == K.WESTAR then m = m * K.Cfg("arcWestarDamage") end   -- (ARC training)
    if set.carbine_sidearm and IsValid(wep) and wep.GetFireModeName and wep:GetFireModeName() == "sidearm" then
        m = m * K.Cfg("sidearmDamage")
    end
    if set.point_blank and bolt.start then
        local d = bolt.start:Distance(tr.HitPos)
        local near, far = K.Cfg("pointBlankNear"), K.Cfg("pointBlankFar")
        local f = d <= near and 1 or (d >= far and 0 or 1 - (d - near) / math.max(far - near, 1))
        m = m * (1 + (K.Cfg("pointBlankMult") - 1) * f)
    end
    if set.headhunter and group == HITGROUP_HEAD then m = m * K.Cfg("headhunterMult") end
    -- Marksman: Priority target, Precision rhythm (DC-15S hits in a row), Called shot.
    if set.priority_target and IsValid(ent) and K.PriorityTarget and K.PriorityTarget(ent) then
        m = m * K.Cfg("priorityMult")
    end
    local living = IsValid(ent) and (ent:IsNPC() or ent:IsNextBot() or ent:IsPlayer())
    local class = IsValid(wep) and K.GunClass(wep)
    -- Precision rhythm: aimed DC-15S hits in a row on one target.
    if set.precision_rhythm and living and class == K.DC15S and wep.GetAiming and wep:GetAiming() then
        m = m * streak(ply, "rhylibRhythm", ent, "rhythmWindow", "rhythmMax", "rhythmStep")
    end
    -- Sustained fire: DC-15A full-auto hits in a row on one target.
    if set.sustained_fire and living and class == K.DC15A and wep.AutoModes and wep.AutoModes[wep:GetFireModeName()] then
        m = m * streak(ply, "rhylibSustain", ent, "sustainWindow", "sustainMax", "sustainStep")
    end
    if set.called_shot and group == HITGROUP_HEAD and IsValid(ent) and K.CalledShot then K.CalledShot(ply, ent) end
    if set.shotgun_drills and IsValid(bolt.weapon) and K.GunClass(bolt.weapon) == K.DP24 then
        m = m * K.Cfg("shotgunDamage")
    end
    -- Critical hits / Light rounds: one roll at the better chance (no stacking).
    local chance = set.crits and K.Cfg("critChance") or 0
    if set.light_rounds and smallMag(wep) then chance = math.max(chance, K.Cfg("lightRoundsChance")) end
    if chance > 0 and math.random() < chance then
        m = m * K.Cfg("critMult")
        crit = true
    end
    return m, crit
end

--------------------------------------------------------------------------
-- Momentum: a kill (or downing someone) frees sprinting for a while
--------------------------------------------------------------------------

local function onKill(attacker)
    if not (IsValid(attacker) and attacker:IsPlayer() and K.Has(attacker, "momentum")) then return end
    local untilT = CurTime() + K.Cfg("momentumTime")
    attacker:SetNW2Float("rhylib_momentum", untilT)
    attacker.rhylibMomentumReload = untilT + 6   -- the next reload in the next few seconds
end
-- K.OnKill(attacker): start Momentum for a killer (also used by the hooks below).
K.OnKill = onKill

Rhylib.Hook.Add("OnNPCKilled", "skills.momentum", function(_, attacker) onKill(attacker) end)
Rhylib.Hook.Add("PlayerDeath", "skills.momentum", function(victim, _, attacker)
    if attacker ~= victim then onKill(attacker) end
end)
Rhylib.Hook.Add("Rhylib.PlayerDowned", "skills.momentum", function(_, attacker) onKill(attacker) end)

--------------------------------------------------------------------------
-- Damage taken: Airborne and Combat medic (before armour at 100)
--------------------------------------------------------------------------

-- No push from a hit. The engine shoves a walking player away from the
-- inflictor by the damage amount (CBaseCombatCharacter::OnTakeDamage_Alive),
-- not by the damage force, so zeroing the force alone did nothing;
-- DMG_NO_PHYSICS_FORCE is the flag that skips that shove.
local function noPush(dmg)
    dmg:SetDamageForce(vector_origin)
    dmg:SetDamageType(bit.bor(dmg:GetDamageType(), DMG_NO_PHYSICS_FORCE))
end

-- Damage taken, priority 95 (before rhylib_weapons' armour at 100, so
-- armour soaks the reduced amount). Multipliers stack by multiplying.
-- DMG_DIRECT (bleeding, bleed-out) and downed players are left alone.
Rhylib.Hook.Add("EntityTakeDamage", "skills.resist", function(ent, dmg)
    -- (uncached: the downed state can change inside this tick)
    if not ent:IsPlayer() or ent.rhylibDown or ent:GetNW2Bool(Rhylib.NW.DOWN, false) then return end
    if bit.band(dmg:GetDamageType(), DMG_DIRECT) ~= 0 then return end   -- (bleeding, bleed-out)
    local m = 1
    local set = K.Set(ent)
    if next(set) ~= nil then
        local t = dmg:GetDamageType()
        if set.hard_landings and bit.band(t, DMG_FALL) ~= 0 then m = m * K.Cfg("fallMult") end
        if set.arc_conditioning and bit.band(t, DMG_FALL) ~= 0 then m = m * K.Cfg("arcFall") end
        if set.blast_hardened and bit.band(t, DMG_BLAST) ~= 0 then m = m * K.Cfg("blastMult") end
        if set.eod_blast and bit.band(t, DMG_BLAST) ~= 0 then m = m * K.Cfg("eodBlastMult") end
        if set.aerial_stability and bit.band(t, DMG_FALL) == 0 and not ent:OnGround()
            and ent:GetMoveType() == MOVETYPE_WALK then
            m = m * K.Cfg("airMult")
        end
        if set.combat_drop and (ent.rhylibDropUntil or 0) > CurTime() then m = m * K.Cfg("combatDropMult") end
        if set.juggernaut then m = m * K.Cfg("juggernautMult") end
        if set.combat_veteran then
            local aw = ent:GetActiveWeapon()
            if IsValid(aw) and K.GunClass(aw) == K.Z6 then m = m * K.Cfg("vetZ6Resist") end
        end
        if set.under_fire then
            local Med = Rhylib.Medical
            local a = Med and Med.acts and Med.acts[ent]
            if a and a.kind ~= Med.A_STAB then m = m * K.Cfg("underFireMult") end
        end
        if set.hold_line and K.HoldingLine(ent) then m = m * K.Cfg("holdLineMult") end
        -- Battle rush: the first hit (not a fall) after the cooldown fires you up.
        if set.battle_rush and bit.band(t, DMG_FALL) == 0 and dmg:GetDamage() > 0
            and (ent.rhylibRushReady or 0) <= CurTime() then
            ent.rhylibRushReady = CurTime() + K.Cfg("rushCooldown")
            ent:SetNW2Float("rhylib_rush", CurTime() + K.Cfg("rushTime"))
            ent:EmitSound("npc/combine_soldier/vo/on2.wav", 60, 120)
            K.Note(ent, "Battle rush: " .. math.Round((K.Cfg("rushDamage") - 1) * 100) .. "% more damage for " .. K.Cfg("rushTime") .. " s")
        end
        -- Shock Assault: no push from hits.
        if set.shock_assault then noPush(dmg) end
    end
    -- Command orders (Hold fast blocks everything earlier, skills.holdfast).
    if K.OrderIs(ent, "press") then noPush(dmg) end
    if m ~= 1 then dmg:ScaleDamage(m) end
end, 95)

-- EOD Blast hardened: explosions never knock you down (rhylib_weapons).
Rhylib.Hook.Add("Rhylib.CanKnockDown", "skills.eodblast", function(p)
    if IsValid(p) and p:IsPlayer() and K.Has(p, "eod_blast") then return false end
end)

-- EOD Anti-armour: a player's explosions hit B2s, heavy and commander
-- droids harder (before the droid takes it).
Rhylib.Hook.Add("EntityTakeDamage", "skills.antiarmour", function(ent, dmg)
    if not (ent.IsRhylibDroid and ent.Kind) or bit.band(dmg:GetDamageType(), DMG_BLAST) == 0 then return end
    local att = dmg:GetAttacker()
    if not (IsValid(att) and att:IsPlayer() and K.Has(att, "eod_antiarmor")) then return end
    local k = ent:Kind()
    if k and (k.big or k.commander or ent.DroidKind == "b1_heavy") then dmg:ScaleDamage(K.Cfg("eodAntiArmour")) end
end, 90)

-- Hold fast: no damage at all while it lasts (before lying, medical, armour).
Rhylib.Hook.Add("EntityTakeDamage", "skills.holdfast", function(ent, dmg)
    if ent:IsPlayer() and K.OrderIs(ent, "hold") then return true end
end, -1200)

-- Suppression: a Z-6 hit on a droid rattles the droids around it.
Rhylib.Hook.Add("EntityTakeDamage", "skills.suppress", function(ent, dmg)
    if not ent.IsRhylibDroid then return end
    local att, inf = dmg:GetAttacker(), dmg:GetInflictor()
    if not (IsValid(att) and att:IsPlayer() and IsValid(inf) and inf:IsWeapon() and K.GunClass(inf) == K.Z6 and K.Has(att, "suppression")) then return end
    local D = Rhylib.Droids
    if not (D and D.Suppress and D.active) then return end
    local now = CurTime()
    if (ent.rhylibSuppressCheck or 0) > now then return end   -- (once per 0.25 s per droid hit)
    ent.rhylibSuppressCheck = now + 0.25
    local pos, r2 = ent:GetPos(), K.Cfg("suppressRadius") ^ 2
    for d in pairs(D.active) do
        if IsValid(d) and d:GetPos():DistToSqr(pos) <= r2 then D.Suppress(d, K.Cfg("suppressTime"), K.Cfg("suppressMult")) end
    end
end)

-- K.HoldingLine(ply): Hold the line is active: the CG riot shield up and
-- another MP within holdLineRange. Server only.
function K.HoldingLine(ply)
    local W, MP = Rhylib.Weapons, Rhylib.MP
    -- (the CG shield only: the Republic shield gets no Shock Trooper bonuses)
    local up = W and (W.ShieldProficient or W.ShieldUp)
    if not (up and up(ply) and MP and MP.IsMP) then return false end
    -- Another MP nearby: checked at most every 0.25 s per player (hits come in bursts).
    local now = CurTime()
    if (ply.rhylibHoldLineAt or 0) > now then return ply.rhylibHoldLine == true end
    ply.rhylibHoldLineAt = now + 0.25
    local r2 = K.Cfg("holdLineRange") ^ 2
    local pos = ply:GetPos()
    local near = false
    for _, o in ipairs(player.GetAll()) do
        if o ~= ply and o:Alive() and MP.IsMP(o) and o:GetPos():DistToSqr(pos) <= r2 then near = true break end
    end
    ply.rhylibHoldLine = near
    return near
end

-- Combat drop: landing after combatDropAir seconds of jetpack flight (in
-- the air the whole time, thrusting at some point) gives combatDropTime
-- seconds of less damage. Only players with the skill are tracked.
Rhylib.Hook.Add("PlayerTick", "skills.combatdrop", function(ply)
    if not K.Has(ply, "combat_drop") then
        ply.rhylibAirFrom = nil
        return
    end
    local J = Rhylib.Jetpack
    if ply:OnGround() or ply:GetMoveType() ~= MOVETYPE_WALK or ply:WaterLevel() >= 2 or not (J and J.Has and J.Has(ply))
        or IsValid(ply:GetDTEntity(Rhylib.DT and Rhylib.DT.Slot("Entity", "grapple.rope") or 31))   -- (on a grapple rope)
        or IsValid(ply:GetDTEntity(Rhylib.DT and Rhylib.DT.Slot("Entity", "grapple.zip") or 30))   -- (on a zipline)
        or ply:GetDTInt(Rhylib.DT and Rhylib.DT.Slot("Int", "grapple.phook") or 31) ~= 0 then   -- (personal grappling hook)
        ply.rhylibAirFrom, ply.rhylibAirJet = nil, nil
        return
    end
    if not ply.rhylibAirFrom then ply.rhylibAirFrom = CurTime() end
    if ply:GetDTBool(J.DT_THRUST) then ply.rhylibAirJet = true end
end)

Rhylib.Hook.Add("OnPlayerHitGround", "skills.combatdrop", function(ply, inWater)
    local from, jet = ply.rhylibAirFrom, ply.rhylibAirJet
    ply.rhylibAirFrom, ply.rhylibAirJet = nil, nil
    if inWater or not from or not jet or not K.Has(ply, "combat_drop") then return end
    if CurTime() - from < K.Cfg("combatDropAir") then return end
    local t = K.Cfg("combatDropTime")
    ply.rhylibDropUntil = CurTime() + t
    ply:EmitSound("npc/roller/mine/rmine_blades_in2.wav", 70, 90)
    K.Note(ply, "Combat drop: " .. math.Round((1 - K.Cfg("combatDropMult")) * 100) .. "% less damage for " .. t .. " s")
end)

-- Death from above: a hard landing slams droids (NPCs and NextBots) nearby.
Rhylib.Hook.Add("OnPlayerHitGround", "skills.slam", function(ply, inWater, _, speed)
    if inWater or speed < K.Cfg("slamSpeed") or not K.Has(ply, "death_from_above") then return end
    local pos = ply:GetPos()
    local r = K.Cfg("slamRadius")
    local base = K.Cfg("slamDamage") * math.min(2, speed / K.Cfg("slamSpeed"))
    for _, e in ipairs(ents.FindInSphere(pos, r)) do
        if IsValid(e) and e ~= ply and (e:IsNPC() or e:IsNextBot()) and not e.IsRhylibClone and e:Health() > 0
            and not util.TraceLine({ start = pos + Vector(0, 0, 16), endpos = e:WorldSpaceCenter(), mask = MASK_SOLID_BRUSHONLY }).Hit then
            local to = e:WorldSpaceCenter() - pos
            local f = 1 - math.Clamp(to:Length() / r, 0, 1) * 0.6
            local d = DamageInfo()
            d:SetDamage(base * f)
            d:SetDamageType(DMG_CLUB)
            d:SetAttacker(ply)
            d:SetInflictor(ply)
            d:SetDamagePosition(e:WorldSpaceCenter())
            to.z = 0
            d:SetDamageForce(to:GetNormalized() * 12000 + Vector(0, 0, 6000))
            e:TakeDamageInfo(d)
        end
    end
    local fx = EffectData()
    fx:SetOrigin(pos)
    fx:SetScale(r)
    util.Effect("ThumperDust", fx, true, true)
    ply:EmitSound("physics/concrete/boulder_impact_hard" .. math.random(1, 4) .. ".wav", 80)
    util.ScreenShake(pos, 6, 20, 0.6, r * 2)
end)

-- A gun with a skill-gated "dual" mode (DC-17: Dual DC-17): carry two.
-- Answers rhylib_inventory's Rhylib.CarryLimit(ply, itemId, def) hook.
Rhylib.Hook.Add("Rhylib.CarryLimit", "skills.dual", function(ply, id, def)
    -- (training copies inherit SkillModes from the real gun)
    local swep = def and def.weapon and weapons.GetStored(K.ItemGun(def.weapon))
    local need = swep and swep.SkillModes and swep.SkillModes.dual
    if not need then return end
    -- (a bounty hunter skill only counts while hunting: rhylib_bounty B.Has)
    local B = Rhylib.Bounty
    if swep.BountyWeapon and B and B.Has then
        if B.Has(ply, need) then return 2 end
        return
    end
    if K.Has(ply, need) then return 2 end
end)
