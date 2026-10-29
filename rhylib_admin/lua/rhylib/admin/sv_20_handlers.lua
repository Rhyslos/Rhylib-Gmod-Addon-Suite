--[[
    What each admin command does (Admin.handlers[id]), plus the powers
    behind them:
      noclip      the noclip key works for staff with "noclip" / "noclip.self"
      god         FL_GODMODE (ply:GodEnable)
      cloak       invisible: no model, weapon, shadow; NW2Bool rhylib_cloak
                  (the HUD hides the name); also no target
      notarget    FL_NOTARGET (NPCs and Rhylib droids ignore them; rhylib_medical
                  keeps it while downed, see ply.rhylibAdminNoTarget)
      spawn       spawn menu rights (props, entities, NPCs, weapons, vehicles,
                  ragdolls, effects, tools) whatever DarkRP / sandbox say
      freeze, mute (text), gag (voice): session only
    Spawned things are remembered per player (ent.rhylibSpawner) for cleanup.
    Handlers return the text to echo and log, or nil, "error for the caller".

    Server only. Other addons' commands (roster ranks, MP jail, illness,
    DarkRP money) live in those addons (Admin.AddCommand); admin only
    asks hooks for its general ones: Rhylib.AdminRevive / AdminHeal
    (target, caller), Rhylib.AdminInfo(target, sid, add(line)),
    Rhylib.KeepNoTarget(ply).
    Hooks it answers: Rhylib.CanStun / Rhylib.CanKnockDown (god mode = no),
    Rhylib.CanChat (mute), PlayerCanHearPlayersVoice (gag), the
    PlayerSpawn* hooks (spawn rights), CanTool, EntityTakeDamage (buddha).
]]

local Admin = Rhylib.Admin
local H = Admin.handlers

Admin.muted = Admin.muted or {}    -- [ply] = true
Admin.gagged = Admin.gagged or {}  -- [ply] = true
Admin.returnPos = Admin.returnPos or {}   -- [ply] = Vector

local function name(p) return IsValid(p) and p:Nick() or "Console" end
local function you(caller, t) return caller == t and "themselves" or name(t) end

--------------------------------------------------------------------------
-- Powers
--------------------------------------------------------------------------

-- Admin.SetCloak(ply, on): invisible or visible again. Also turns no
-- target on with it (off again only if !notarget wasn't on by itself).
-- Kept through respawns (PlayerSpawn below). Server only.
-- Example: Rhylib.Admin.SetCloak(ply, true)
function Admin.SetCloak(ply, on)
    ply.rhylibCloak = on or nil
    ply:SetNW2Bool(Rhylib.NW.CLOAK, on)
    -- A lying player (rhylib_core) is already hidden under their body; leave that be.
    if not ply.rhylibLieHidden then
        ply:SetNoDraw(on)
        ply:DrawShadow(not on)
        ply:DrawWorldModel(not on)
    end
    ply:SetRenderMode(on and RENDERMODE_TRANSALPHA or RENDERMODE_NORMAL)
    Admin.SetNoTarget(ply, on or ply.rhylibAdminNoTargetOwn)
    -- (the gun is its own entity: hide it on the server too, or others see
    -- it float where the hidden player is)
    local w = ply:GetActiveWeapon()
    if IsValid(w) then w:SetNoDraw(on and true or false) end
end

-- A cloaked player switching weapons: hide the new one (deploy clears it).
Rhylib.Hook.Add("PlayerSwitchWeapon", "admin.cloak", function(ply, old, new)
    if not ply.rhylibCloak then return end
    timer.Simple(0, function()
        if not (IsValid(ply) and ply.rhylibCloak) then return end
        if IsValid(old) and old ~= ply:GetActiveWeapon() then old:SetNoDraw(true) end   -- (holstered: stays hidden anyway)
        local w = ply:GetActiveWeapon()
        if IsValid(w) then w:SetNoDraw(true) end
    end)
end)

-- Admin.SetNoTarget(ply, on): FL_NOTARGET on or off (NPCs and droids
-- ignore the player). Turning it off leaves it on when hook
-- Rhylib.KeepNoTarget(ply) answers true (rhylib_medical: downed players).
-- ply.rhylibAdminNoTarget = it's on because of us (cloak or !notarget);
-- ply.rhylibAdminNoTargetOwn = !notarget itself is on.
function Admin.SetNoTarget(ply, on)
    ply.rhylibAdminNoTarget = on or nil
    if on then
        ply:AddFlags(FL_NOTARGET)
    elseif hook.Run("Rhylib.KeepNoTarget", ply) ~= true then
        ply:RemoveFlags(FL_NOTARGET)   -- (hook: rhylib_medical keeps it on downed players)
    end
end

-- Spawn menu rights for staff with "spawn" (others: sandbox / DarkRP rules).
-- Returns true (allowed) or nothing (let the other hooks decide); never
-- blocks. Priority -50 runs before DarkRP's own checks.
local function canSpawn(ply)
    if Admin.Has(ply, "spawn") then return true end
end
for _, h in ipairs({ "PlayerSpawnProp", "PlayerSpawnSENT", "PlayerSpawnNPC", "PlayerSpawnSWEP", "PlayerGiveSWEP",
    "PlayerSpawnVehicle", "PlayerSpawnRagdoll", "PlayerSpawnEffect", "PlayerSpawnObject" }) do
    Rhylib.Hook.Add(h, "admin.spawn", canSpawn, -50)
end
-- Tools on the world only; on entities prop protection decides.
Rhylib.Hook.Add("CanTool", "admin.spawn", function(ply, tr, tool)
    if IsValid(tr.Entity) then return end
    if Admin.Has(ply, "spawn") then return true end
end, -40)

-- Remember who spawned what (cleanup).
local function remember(ply, ent)
    if IsValid(ent) then ent.rhylibSpawner = ply end
end
Rhylib.Hook.Add("PlayerSpawnedProp", "admin.track", function(ply, _, ent) remember(ply, ent) end)
Rhylib.Hook.Add("PlayerSpawnedSENT", "admin.track", remember)
Rhylib.Hook.Add("PlayerSpawnedNPC", "admin.track", remember)
Rhylib.Hook.Add("PlayerSpawnedVehicle", "admin.track", remember)
Rhylib.Hook.Add("PlayerSpawnedRagdoll", "admin.track", function(ply, _, ent) remember(ply, ent) end)
Rhylib.Hook.Add("PlayerSpawnedEffect", "admin.track", function(ply, _, ent) remember(ply, ent) end)
Rhylib.Hook.Add("PlayerSpawnedSWEP", "admin.track", remember)

-- Gagged players: nobody hears their voice.
Rhylib.Hook.Add("PlayerCanHearPlayersVoice", "admin.gag", function(listener, talker)
    if Admin.gagged[talker] then return false, false end
end, -50)

-- God mode also means no stuns (EMP, stun bolts, baton, flash) and no
-- explosion knockdowns (EMP spam would still lock a god-moded admin down).
Rhylib.Hook.Add("Rhylib.CanStun", "admin.god", function(ply)
    if IsValid(ply) and ply:HasGodMode() then return false end
end)
Rhylib.Hook.Add("Rhylib.CanKnockDown", "admin.god", function(ply)
    if IsValid(ply) and ply:IsPlayer() and ply:HasGodMode() then return false end
end)

-- The Rhylib chat box asks this before sending (rhylib_chat).
-- Muted players can still reach staff: the admin
-- channel, and private messages to anyone who reads it.
Rhylib.Hook.Add("Rhylib.CanChat", "admin.mute", function(ply, chId, _, target)
    if not Admin.muted[ply] then return end
    if chId == "admin" then return end
    if chId == "pm" and IsValid(target) and target:IsPlayer() and Admin.Has(target, "rhylib.chat.admin", "admin") then return end
    return false, "You are muted (you can still use /admin or PM staff)"
end)

-- Spawning again keeps powers that should last (cloak, god, notarget).
Rhylib.Hook.Add("PlayerSpawn", "admin.powers", function(ply)
    timer.Simple(0, function()
        if not IsValid(ply) then return end
        if ply.rhylibCloak then Admin.SetCloak(ply, true) end
        if ply.rhylibGod then ply:GodEnable() end
        if ply.rhylibAdminNoTarget then ply:AddFlags(FL_NOTARGET) end
        if ply.rhylibFrozen then ply:Freeze(true) end
    end)
end)

Rhylib.Hook.Add("PlayerDisconnected", "admin.clear", function(ply)
    Admin.muted[ply], Admin.gagged[ply], Admin.returnPos[ply] = nil, nil, nil
end)

--------------------------------------------------------------------------
-- Teleport helpers
--------------------------------------------------------------------------

-- A free standing spot near pos: the spot itself, then 8 directions at 48
-- and then 90 units, each tested with a player-sized hull (times scale).
-- `who` = entities the test ignores. Falls back to pos + 8 up.
local function freeSpot(pos, who, scale)
    local sc = scale or 1
    local mins, maxs = Vector(-16, -16, 0) * sc, Vector(16, 16, 72) * sc
    local tries = { Vector(0, 0, 0) }
    for i = 0, 7 do
        local a = i * math.pi / 4
        tries[#tries + 1] = Vector(math.cos(a) * 48, math.sin(a) * 48, 0)
        tries[#tries + 1] = Vector(math.cos(a) * 90, math.sin(a) * 90, 0)
    end
    for _, off in ipairs(tries) do
        local p = pos + off + Vector(0, 0, 4)
        local tr = util.TraceHull({ start = p, endpos = p, mins = mins, maxs = maxs, filter = who, mask = MASK_PLAYERSOLID })
        if not tr.StartSolid then return p end
    end
    return pos + Vector(0, 0, 8)
end

-- Teleports a player and remembers where they were (for !return).
local function moveTo(ply, pos)
    Admin.returnPos[ply] = ply:GetPos()
    if ply:InVehicle() then ply:ExitVehicle() end
    ply:SetPos(pos)
    ply:SetLocalVelocity(Vector(0, 0, 0))
end

--------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------

H.kick = function(caller, t, a)
    local reason = a.reason ~= "" and a.reason or "Kicked by staff"
    local text = name(caller) .. " kicked " .. name(t) .. " (" .. reason .. ")"
    t:Kick(reason)
    return text
end

H.ban = function(caller, t, a, ctx)
    local minutes = a.time
    local max = Admin.Cfg("banMaxMinutes")
    if not IsValid(t) and not Admin.Has(caller, "banid") then return nil, "Banning someone who isn't online needs the banid permission" end
    if (minutes == 0 or minutes > max) and not Admin.Has(caller, "permaban") then
        return nil, "You can ban for at most " .. Admin.FormatMinutes(max)
    end
    local who = IsValid(t) and t:Nick() or ctx.sid
    Admin.Ban(ctx.sid, minutes, a.reason, caller, who)
    return name(caller) .. " banned " .. who .. " " .. Admin.FormatMinutes(minutes) .. " (" .. (a.reason ~= "" and a.reason or "no reason given") .. ")"
end

H.unban = function(caller, t, a, ctx)
    if not Admin.Unban(ctx.sid) then return nil, ctx.sid .. " isn't banned" end
    return name(caller) .. " unbanned " .. ctx.sid
end

H.warn = function(caller, t, a)
    if a.reason == "" then return nil, "Give a reason" end
    local n = Admin.Warn(t:SteamID64(), a.reason, name(caller))
    Admin.Tell(t, "Warning from " .. name(caller) .. ": " .. a.reason, true)
    return name(caller) .. " warned " .. name(t) .. " (" .. a.reason .. "); " .. n .. " warning" .. (n == 1 and "" or "s") .. " total"
end

H.mute = function(caller, t)
    Admin.muted[t] = true
    return name(caller) .. " muted " .. name(t)
end
H.unmute = function(caller, t)
    Admin.muted[t] = nil
    return name(caller) .. " unmuted " .. name(t)
end
H.gag = function(caller, t)
    Admin.gagged[t] = true
    return name(caller) .. " gagged " .. name(t)
end
H.ungag = function(caller, t)
    Admin.gagged[t] = nil
    return name(caller) .. " ungagged " .. name(t)
end

H.freeze = function(caller, t)
    t.rhylibFrozen = true
    t:Freeze(true)
    return name(caller) .. " froze " .. you(caller, t)
end
H.unfreeze = function(caller, t)
    t.rhylibFrozen = nil
    t:Freeze(false)
    return name(caller) .. " unfroze " .. you(caller, t)
end

H.slay = function(caller, t)
    if not t:Alive() then return nil, name(t) .. " is already dead" end
    t:Kill()
    return name(caller) .. " slew " .. you(caller, t)
end

H.respawn = function(caller, t)
    t:Spawn()
    return name(caller) .. " respawned " .. you(caller, t)
end

H["goto"] = function(caller, t)
    if not IsValid(caller) then return nil, "The console can't go anywhere" end
    if caller == t then return nil, "That's you" end
    moveTo(caller, freeSpot(t:GetPos() - t:GetForward() * 48, { caller, t }, caller.rhylibScale))
    return name(caller) .. " went to " .. name(t)
end

H.bring = function(caller, t)
    if not IsValid(caller) then return nil, "The console has nowhere to bring them" end
    if caller == t then return nil, "That's you" end
    moveTo(t, freeSpot(caller:GetPos() + caller:GetForward() * 64, { caller, t }, t.rhylibScale))
    return name(caller) .. " brought " .. name(t)
end

H["return"] = function(caller, t)
    local pos = Admin.returnPos[t]
    if not pos then return nil, name(t) .. " has nowhere to return to" end
    t:SetPos(pos)
    Admin.returnPos[t] = nil
    return name(caller) .. " returned " .. you(caller, t)
end

H.teleport = function(caller, t)
    if not IsValid(caller) then return nil, "The console can't aim" end
    local tr = util.TraceLine({ start = caller:EyePos(), endpos = caller:EyePos() + caller:GetAimVector() * 32768, filter = { caller, t }, mask = MASK_PLAYERSOLID })
    if not tr.Hit then return nil, "Aim at something" end
    moveTo(t, freeSpot(tr.HitPos + tr.HitNormal * 16, { caller, t }, t.rhylibScale))
    return name(caller) .. " teleported " .. you(caller, t)
end

-- Toggles: each run flips it on or off. A rank with only "<perm>.self"
-- (e.g. "noclip.self") can use them on itself.
H.noclip = function(caller, t)
    local on = t:GetMoveType() ~= MOVETYPE_NOCLIP
    t:SetMoveType(on and MOVETYPE_NOCLIP or MOVETYPE_WALK)
    return name(caller) .. (on and " gave noclip to " or " took noclip from ") .. you(caller, t)
end

H.god = function(caller, t)
    local on = not t.rhylibGod
    t.rhylibGod = on or nil
    if on then t:GodEnable() else t:GodDisable() end
    return name(caller) .. (on and " enabled" or " disabled") .. " god mode for " .. you(caller, t)
end

H.cloak = function(caller, t)
    local on = not t.rhylibCloak
    Admin.SetCloak(t, on)
    return name(caller) .. (on and " made " or " unhid ") .. you(caller, t) .. (on and " invisible" or "")
end

H.notarget = function(caller, t)
    local on = not t.rhylibAdminNoTargetOwn
    t.rhylibAdminNoTargetOwn = on or nil
    Admin.SetNoTarget(t, on or t.rhylibCloak)
    return name(caller) .. (on and " turned on" or " turned off") .. " no target for " .. you(caller, t)
end

H.hp = function(caller, t, a)
    local n = math.Clamp(math.floor(a.amount), 1, 100000)
    if not t:Alive() then return nil, name(t) .. " is dead" end
    if n > t:GetMaxHealth() then t:SetMaxHealth(n) end
    t:SetHealth(n)
    return name(caller) .. " set the health of " .. you(caller, t) .. " to " .. n
end

H.armor = function(caller, t, a)
    local n = math.Clamp(math.floor(a.amount), 0, 100000)
    if n > t:GetMaxArmor() then t:SetMaxArmor(n) end
    t:SetArmor(n)
    return name(caller) .. " set the armour of " .. you(caller, t) .. " to " .. n
end

H.give = function(caller, t, a)
    local class = string.lower(a.class or "")
    if not weapons.GetStored(class) and not list.Get("Weapon")[class] then return nil, "No weapon called " .. class end
    t:Give(class)
    return name(caller) .. " gave " .. class .. " to " .. you(caller, t)
end

-- Staff ranks: only below your own, and only on people below you.
H.rank = function(caller, t, a, ctx)
    local r = Admin.RankById(string.lower(a.rank or ""))
    if not r then
        local ids = {}
        for _, x in ipairs(Admin.Ranks()) do ids[#ids + 1] = x.id end
        return nil, "No rank " .. tostring(a.rank) .. " (" .. table.concat(ids, ", ") .. ")"
    end
    if IsValid(caller) and (r.level or 0) >= Admin.Level(caller) then return nil, "You can only give ranks below your own" end
    Admin.SetRank(ctx.sid, r.id, name(caller))
    return name(caller) .. " set the staff rank of " .. (IsValid(t) and t:Nick() or ctx.sid) .. " to " .. r.name
end

-- Server / events.
local function startMapChange(caller, m)
    if timer.Exists("rhylib_admin_map") then return nil, "A map change is already counting down (!cancelmap)" end
    Rhylib.Net.Start("admin.countdown")
    net.WriteString(m)
    net.WriteUInt(10, 6)
    net.Broadcast()
    timer.Create("rhylib_admin_map", 10, 1, function() RunConsoleCommand("changelevel", m) end)
    return name(caller) .. " is changing the map to " .. m .. " in 10 seconds"
end

-- Exact name, else the one map whose name contains it.
H.map = function(caller, t, a)
    local want = string.lower(string.Trim(a.map or ""))
    if want == "" or not string.match(want, "^[%w_%-]+$") then return nil, "No map called " .. want end
    local list = Admin.MapList()
    local found = {}
    for _, m in ipairs(list) do
        if m == want then found = { m } break end
        if string.find(m, want, 1, true) then found[#found + 1] = m end
    end
    if #found == 0 then return nil, "No map matches " .. want end
    if #found > 1 then
        local show = {}
        for k = 1, math.min(5, #found) do show[k] = found[k] end
        return nil, #found .. " maps match " .. want .. ": " .. table.concat(show, ", ") .. (#found > 5 and ", ..." or "")
    end
    return startMapChange(caller, found[1])
end

H.restartmap = function(caller)
    return startMapChange(caller, game.GetMap())
end

H.cancelmap = function(caller)
    if not timer.Exists("rhylib_admin_map") then return nil, "No map change is counting down" end
    timer.Remove("rhylib_admin_map")
    Rhylib.Net.Start("admin.countdown")
    net.WriteString("")
    net.WriteUInt(0, 6)
    net.Broadcast()
    return name(caller) .. " cancelled the map change"
end

-- Rhylib fixtures (armoury, jail, terminals...): freezeprops leaves them be.
-- Rhylib.PLACEMENT_CLASSES is a set other addons can add class names to.
local function isPlacement(e)
    if e.placeIndex then return true end
    local c = e:GetClass()
    local A = Rhylib.Armoury
    if A and A.CLASSES and A.CLASSES[c] then return true end
    if Rhylib.PLACEMENT_CLASSES and Rhylib.PLACEMENT_CLASSES[c] then return true end
    return c == "rhylib_jail_cell" or c == "rhylib_jail_terminal" or c == "rhylib_bn_computer" or c == "rhylib_med_holotable"
end

-- Permanent things stay: Rhylib's own (toolgun "Permanent" tool,
-- Rhylib.Perma) and other perma prop addons / sandbox persistence.
local function isPerma(e)
    if Rhylib.Perma.Is(e) then return true end
    return e.PermaProps or e.PermaProps_ID or e:GetNWBool("PermaProps", false) or e:GetPersistent() or e.rhylibPerma or false
end

-- What a full cleanup takes: everything spawned during play that isn't
-- permanent (placements are only kept when made permanent). Never map entities, players, held weapons, hands and
-- viewmodels, grapple ropes, lying bodies, or things attached to a player
-- or to something permanent.
local TAKE_PREFIX = { "prop_", "spawned_", "sent_", "gmod_wire_", "edit_", "rhylib_", "npc_" }
local TAKE_CLASS = { gmod_button = true, gmod_lamp = true, gmod_light = true,
    gmod_balloon = true, gmod_thruster = true, gmod_wheel = true, gmod_hoverball = true, gmod_emitter = true,
    gmod_dynamite = true, gmod_cameraprop = true, gmod_turret = true }
local KEEP_CLASS = { gmod_hands = true, gmod_gamerules = true, predicted_viewmodel = true, viewmodel = true, rhylib_rope = true, rhylib_zipline = true,
    physgun_beam = true }
local function cleanable(e)
    -- (rhylibMapish: there when the map loaded, e.g. point_template spawns)
    if e:CreatedByMap() or e.rhylibMapish or e:IsPlayer() or isPerma(e) then return false end
    local c = e:GetClass()
    if KEEP_CLASS[c] then return false end
    if e:GetNW2Bool(Rhylib.NW.LYING_RAG, false) then return false end
    if e:IsWeapon() and IsValid(e:GetOwner()) then return false end
    local parent = e:GetParent()
    if IsValid(parent) and (parent:IsPlayer() or parent:GetClass() == "predicted_viewmodel" or isPerma(parent)) then return false end
    if e.rhylibSpawner ~= nil or e.rhylibToolSpawned or e:IsNPC() or e:IsNextBot() or e:IsVehicle() or e:IsWeapon() or TAKE_CLASS[c] then return true end
    if e:IsScripted() then return true end
    for _, p in ipairs(TAKE_PREFIX) do
        if string.sub(c, 1, #p) == p then return true end
    end
    return false
end

-- No target: everything cleanable() says. With a target: only what that
-- player spawned (ent.rhylibSpawner), not weapons and not permanent things.
H.cleanup = function(caller, t)
    local only = IsValid(t) and t or nil
    local n = 0
    for _, e in ipairs(ents.GetAll()) do
        local take
        if only then
            take = e.rhylibSpawner == only and not e:IsWeapon() and not isPerma(e)
        else
            take = cleanable(e)
        end
        if take then
            e:Remove()
            n = n + 1
        end
    end
    return name(caller) .. " cleaned up " .. n .. " spawned thing" .. (n == 1 and "" or "s") .. (only and (" of " .. you(caller, only)) or "")
end

H.announce = function(caller, t, a)
    if a.text == "" then return nil, "Say something" end
    Rhylib.Net.Start("admin.announce")
    net.WriteString(name(caller))
    net.WriteString(a.text)
    net.Broadcast()
    Admin.Log(name(caller) .. " announced: " .. a.text)
    return nil   -- (the banner is the message)
end

H.warnings = function(caller, t, a, ctx)
    local list = Admin.Warnings(ctx.sid)
    local who = IsValid(t) and t:Nick() or ctx.sid
    if #list == 0 then Admin.Tell(caller, who .. " has no warnings") return end
    Admin.Tell(caller, who .. " has " .. #list .. " warning" .. (#list == 1 and "" or "s") .. ":")
    for i = math.max(1, #list - 9), #list do
        local w = list[i]
        Admin.Tell(caller, os.date("%d %b %Y", w.at or 0) .. " by " .. (w.byName or "?") .. ": " .. (w.reason or ""))
    end
end

-- DarkRP job by command (/job name) or name.
H.setjob = function(caller, t, a)
    if not RPExtraTeams then return nil, "DarkRP isn't running" end
    local want = string.lower(a.job or "")
    local idx
    for i, job in pairs(RPExtraTeams) do
        if string.lower(job.command or "") == want or string.lower(job.name or "") == want then idx = i end
    end
    if not idx then
        for i, job in pairs(RPExtraTeams) do
            if string.find(string.lower(job.name or ""), want, 1, true) then idx = i end
        end
    end
    if not idx then return nil, "No job " .. want end
    t:changeTeam(idx, true, true)
    return name(caller) .. " set the job of " .. you(caller, t) .. " to " .. team.GetName(idx)
end

-- Watching someone: back where you were after. Hidden while watching.
-- Admin.StopSpectate(ply, move): ends it; move = put them back where they
-- started (not used on respawn). The watcher's state is ply.rhylibSpec
-- { pos, ang, target, noTarget (had FL_NOTARGET before) }.
local function stopSpec(ply, move)
    local s = ply.rhylibSpec
    if not s then return end
    ply.rhylibSpec = nil
    ply:UnSpectate()
    if not ply.rhylibCloak and not ply.rhylibLieHidden then
        ply:SetNoDraw(false)
        ply:DrawShadow(true)
        ply:DrawWorldModel(true)
    end
    if not s.noTarget and not ply.rhylibAdminNoTarget then ply:RemoveFlags(FL_NOTARGET) end
    if move and ply:Alive() then
        ply:SetMoveType(MOVETYPE_WALK)
        ply:SetPos(s.pos)
        ply:SetEyeAngles(s.ang)
        ply:SetLocalVelocity(Vector(0, 0, 0))
    end
end
Admin.StopSpectate = stopSpec

H.spectate = function(caller, t)
    if not IsValid(caller) then return nil, "The console can't watch" end
    if caller == t then return nil, "That's you" end
    if caller.rhylibSpec then return H.unspectate(caller) end
    if not caller:Alive() then return nil, "You're dead" end
    caller.rhylibSpec = { pos = caller:GetPos(), ang = caller:EyeAngles(), target = t, noTarget = caller:IsFlagSet(FL_NOTARGET) }
    caller:SetNoDraw(true)
    caller:DrawShadow(false)
    caller:DrawWorldModel(false)
    caller:AddFlags(FL_NOTARGET)
    caller:Spectate(OBS_MODE_CHASE)
    caller:SpectateEntity(t)
    Admin.Tell(caller, "Watching " .. t:Nick() .. "; !unspectate to stop")
    Admin.Log(name(caller) .. " spectated " .. t:Nick())
end

H.unspectate = function(caller)
    if not (IsValid(caller) and caller.rhylibSpec) then return nil, "You aren't spectating" end
    stopSpec(caller, true)
end

-- Respawning ends it; so does the watched player leaving or dying.
Rhylib.Hook.Add("PlayerSpawn", "admin.spec", function(ply)
    if ply.rhylibSpec then stopSpec(ply, false) end
end, -60)
local function targetGone(t)
    for _, p in ipairs(player.GetHumans()) do
        if p.rhylibSpec and p.rhylibSpec.target == t then
            stopSpec(p, true)
            Admin.Tell(p, "Stopped watching " .. (IsValid(t) and t:Nick() or "them"))
        end
    end
end
Rhylib.Hook.Add("PlayerDisconnected", "admin.spec", targetGone)
Rhylib.Hook.Add("PostPlayerDeath", "admin.spec", targetGone)

H.who = function(caller)
    local any = false
    for _, p in ipairs(player.GetHumans()) do
        local r = Admin.Rank(p)
        if (r.level or 0) > 0 then
            any = true
            Admin.Tell(caller, p:Nick() .. ": " .. r.name)
        end
    end
    if not any then Admin.Tell(caller, "No staff online") end
end

--------------------------------------------------------------------------
-- More discipline
--------------------------------------------------------------------------

H.unwarn = function(caller, t, a, ctx)
    local n = #Admin.Warnings(ctx.sid)
    if n == 0 then return nil, "No warnings to clear" end
    Admin.ClearWarnings(ctx.sid)
    return name(caller) .. " cleared " .. n .. " warning" .. (n == 1 and "" or "s") .. " of " .. (IsValid(t) and t:Nick() or ctx.sid)
end

H.slap = function(caller, t)
    if not t:Alive() then return nil, name(t) .. " is dead" end
    if t:InVehicle() then t:ExitVehicle() end
    local push = VectorRand() * 260
    push.z = math.random(200, 320)
    t:SetVelocity(push)
    if t:Health() > 5 then t:SetHealth(t:Health() - 5) end
    t:EmitSound("physics/body/body_medium_impact_hard" .. math.random(1, 6) .. ".wav", 75)
    return name(caller) .. " slapped " .. you(caller, t)
end

H.ignite = function(caller, t)
    if not t:Alive() then return nil, name(t) .. " is dead" end
    t:Ignite(10)
    return name(caller) .. " set " .. you(caller, t) .. " on fire"
end

H.extinguish = function(caller, t)
    if not t:IsOnFire() then return nil, name(t) .. " isn't burning" end
    t:Extinguish()
    return name(caller) .. " put out " .. you(caller, t)
end

H.tell = function(caller, t, a)
    if a.text == "" then return nil, "Say something" end
    Admin.Tell(t, "From " .. name(caller) .. ": " .. a.text)
    Admin.Tell(caller, "To " .. t:Nick() .. ": " .. a.text)
    Admin.Log(name(caller) .. " to " .. t:Nick() .. ": " .. a.text)
end

H.info = function(caller, t, a, ctx)
    local sid = ctx.sid
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    add((IsValid(t) and t:Nick() or "Offline player") .. " · " .. util.SteamIDFrom64(sid) .. " · " .. sid)
    local r = IsValid(t) and Admin.Rank(t) or Admin.RankById(Admin.StoredRank(sid) or "user")
    add("Staff rank: " .. (r and r.name or "User"))
    if IsValid(t) then
        add("Job: " .. team.GetName(t:Team()) .. " · health " .. t:Health() .. " · armour " .. t:Armor()
            .. " · online " .. math.floor(t:TimeConnected() / 60) .. " min")
    end
    -- Other addons add their lines (rhylib_mp: jail time; rhylib_roster: character).
    hook.Run("Rhylib.AdminInfo", t, sid, add)
    local w = Admin.Warnings(sid)
    add("Warnings: " .. #w .. (#w > 0 and (" (last: " .. (w[#w].reason or "") .. ")") or ""))
    local b = Admin.GetBan(sid)
    if b then add("Banned: " .. (b.reason or "") .. " (by " .. (b.byName or "?") .. ")") end
    for _, l in ipairs(lines) do Admin.Tell(caller, l) end
end

--------------------------------------------------------------------------
-- Health
--------------------------------------------------------------------------

H.revive = function(caller, t)
    if not t:Alive() then
        local pos, ang = t:GetPos(), t:EyeAngles()
        t:Spawn()
        timer.Simple(0, function()
            if IsValid(t) then
                t:SetPos(freeSpot(pos, { t }))
                t:SetEyeAngles(Angle(0, ang.y, 0))
            end
        end)
        return name(caller) .. " revived " .. you(caller, t) .. " where they fell"
    end
    -- Downed: the addon that downs players gets them up (hook
    -- Rhylib.AdminRevive(target, caller) -> true when it did).
    if Rhylib.State and Rhylib.State.IsDown(t) and hook.Run("Rhylib.AdminRevive", t, caller) == true then
        return name(caller) .. " revived " .. you(caller, t)
    end
    return nil, name(t) .. " isn't down or dead"
end

H.heal = function(caller, t)
    if not t:Alive() then return nil, name(t) .. " is dead (use !revive)" end
    -- (hook Rhylib.AdminHeal(target, caller): rhylib_medical gets them up,
    -- clears injuries and cures illness)
    hook.Run("Rhylib.AdminHeal", t, caller)
    t:SetHealth(math.max(t:Health(), t:GetMaxHealth()))
    local A = Rhylib.Armor
    local arm = A and A.SpawnArmor and A.SpawnArmor(t) or 100
    if t:Armor() < arm then t:SetArmor(arm) end
    t:Extinguish()
    return name(caller) .. " healed " .. you(caller, t)
end

H.buddha = function(caller, t)
    local on = not t.rhylibBuddha
    t.rhylibBuddha = on or nil
    return name(caller) .. (on and " enabled" or " disabled") .. " buddha for " .. you(caller, t)
end

-- Buddha: after armour (100); rhylib_medical skips buddha players (150).
-- Runs at 140: after armour has cut the damage, before medical would down
-- the player. +1: the engine rounds fractional damage up.
Rhylib.Hook.Add("EntityTakeDamage", "admin.buddha", function(ent, dmg)
    if ent.rhylibBuddha and ent:IsPlayer() and dmg:GetDamage() + 1 >= ent:Health() then
        dmg:SetDamage(math.max(0, ent:Health() - 1))
    end
end, 140)

--------------------------------------------------------------------------
-- Events: size, speed, jump, model (until respawn)
--------------------------------------------------------------------------

local VIEW, VIEW_DUCK = Vector(0, 0, 64), Vector(0, 0, 28)

local function applyScale(t, s)
    t:SetModelScale(s, 0)
    t:SetViewOffset(VIEW * s)
    t:SetViewOffsetDucked(VIEW_DUCK * s)
    t:SetNW2Float("rhylib_scale", s)
    if not t.rhylibHullDown then Admin.ScaleHull(t) end
    t:SetStepSize(18 * math.max(s, 0.5))
    t.rhylibScale = s ~= 1 and s or nil
end

H.scale = function(caller, t, a)
    if not t:Alive() then return nil, name(t) .. " is dead" end
    local St = Rhylib.State
    if St and (St.IsDown(t) or St.Ask("lying", t)) then return nil, name(t) .. " is lying down" end
    local s = math.Clamp(math.floor(a.size * 100 + 0.5) / 100, 0.2, 5)
    applyScale(t, s)
    if s > 1 then t:SetPos(freeSpot(t:GetPos(), { t }, s)) end
    return name(caller) .. " set the size of " .. you(caller, t) .. " to " .. s
end

H.speed = function(caller, t, a)
    local m = math.Clamp(a.mult, 0.1, 10)
    local base = t.rhylibBaseSpeed
    if not base then
        base = { t:GetWalkSpeed(), t:GetRunSpeed(), t:GetSlowWalkSpeed() }
        t.rhylibBaseSpeed = base
    end
    t:SetWalkSpeed(base[1] * m)
    t:SetRunSpeed(base[2] * m)
    t:SetSlowWalkSpeed(base[3] * m)
    if m == 1 then t.rhylibBaseSpeed = nil end
    return name(caller) .. " set the speed of " .. you(caller, t) .. " to x" .. m
end

H.jump = function(caller, t, a)
    local m = math.Clamp(a.mult, 0, 10)
    t.rhylibBaseJump = t.rhylibBaseJump or t:GetJumpPower()
    t:SetJumpPower(t.rhylibBaseJump * m)
    if m == 1 then t.rhylibBaseJump = nil end
    return name(caller) .. " set the jump of " .. you(caller, t) .. " to x" .. m
end

H.model = function(caller, t, a)
    local m = string.lower(string.Trim(a.model or ""))
    if m == "reset" or m == "default" then
        hook.Run("PlayerSetModel", t)
        t:SetupHands()
        return name(caller) .. " reset the model of " .. you(caller, t)
    end
    m = string.gsub(m, "\\", "/")
    if not string.match(m, "^models/[%w_/%.%-]+%.mdl$") or string.find(m, "..", 1, true) or not util.IsValidModel(m) then
        return nil, "No model " .. m .. " (models/....mdl)"
    end
    t:SetModel(m)
    t:SetupHands()
    return name(caller) .. " set the model of " .. you(caller, t) .. " to " .. m
end

-- Respawning puts size, speed and jump back (the job sets speed and model again).
Rhylib.Hook.Add("PlayerSpawn", "admin.events", function(ply)
    if ply.rhylibScale then applyScale(ply, 1) end
    ply.rhylibBaseSpeed, ply.rhylibBaseJump = nil, nil
end)

-- Sounds and decals on every client (admin.client: 0 play, 1 stop, 2 decals).
-- net: UInt 2 kind, String sound path ("" for 1 and 2).
local function toClients(kind, text)
    Rhylib.Net.Start("admin.client")
    net.WriteUInt(kind, 2)
    net.WriteString(text or "")
    net.Broadcast()
end

H.playsound = function(caller, t, a)
    local s = string.gsub(string.lower(string.Trim(a.sound or "")), "\\", "/")
    s = string.gsub(s, "^sound/", "")
    if not string.match(s, "^[%w_/%.%-]+%.[mwo][pag][3vg]$") or string.find(s, "..", 1, true) then
        return nil, "Sound path like ambient/alarms/klaxon1.wav (.wav, .mp3 or .ogg)"
    end
    if not file.Exists("sound/" .. s, "GAME") then return nil, "No sound " .. s .. " on the server" end
    toClients(0, s)
    return name(caller) .. " played " .. s
end

H.stopsound = function(caller)
    toClients(1)
    return name(caller) .. " stopped all sounds"
end

H.cleardecals = function(caller)
    toClients(2)
    return name(caller) .. " cleared decals"
end

H.freezeprops = function(caller)
    local n = 0
    for _, e in ipairs(ents.GetAll()) do
        local c = e:GetClass()
        if string.sub(c, 1, 12) == "prop_physics" and not isPlacement(e) then
            local phys = e:GetPhysicsObject()
            if IsValid(phys) and phys:IsMotionEnabled() then
                phys:EnableMotion(false)
                n = n + 1
            end
        end
    end
    return name(caller) .. " froze " .. n .. " prop" .. (n == 1 and "" or "s")
end
