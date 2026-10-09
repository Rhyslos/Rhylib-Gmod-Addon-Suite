--[[
    Test dummy (admins, spawn menu: Rhylib Medical). A bot player that
    stands where you placed it and never moves or shoots, so everything
    that works on players works on it: damage, armour, going down,
    stabilising, dragging, revives, healing, the scoreboard.

    The entity itself is an invisible marker; the bot stands on it and
    comes back there 3 seconds after dying. Removing the marker (undo,
    remover tool, cleanup) kicks the bot. Each dummy takes a player slot.

    rhylib_dummy_move still|walk|run (admins): every dummy stands still,
    or walks / runs back and forth (turning every 2.5 s), for testing
    falls and moving targets.

    Hits show as damage numbers over the dummy (net dummy.dmg to players
    within 1500 units). The tough dummy (rhylib_test_dummy_tough) takes
    no damage at all: no injuries, never goes down; it only shows what a
    hit would have done (after armour).
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Test dummy"
ENT.Category = "Rhylib: Medical"
ENT.Spawnable = true
ENT.AdminOnly = true

local MODEL = "models/ct_trp/pm_ct_trp.mdl"
local MODEL_FALLBACK = "models/aussiwozzi/cgi/base/unassigned_cpt.mdl"
ENT.Model = MODEL   -- (Server settings > Models can swap it)
local function dummyModel()
    local st = scripted_ents.GetStored("rhylib_test_dummy")
    local m = st and st.t and st.t.Model or MODEL
    if util.IsValidModel(m) then return m end
    return util.IsValidModel(MODEL) and MODEL or MODEL_FALLBACK
end
local MARKER = "models/hunter/blocks/cube025x025x025.mdl"
ENT.BotName = "Test dummy"
ENT.Tough = false

if CLIENT then
    function ENT:Draw() end  -- the marker is invisible; the bot is what you see

    -- Damage numbers: rise and fade over the dummy's head.
    local pops = {}
    Rhylib.Net.Receive("dummy.dmg", function()
        local who = net.ReadEntity()
        local amount = net.ReadUInt(12)
        local head = net.ReadBool()
        if not IsValid(who) then return end
        local jitter = Vector(math.Rand(-8, 8), math.Rand(-8, 8), 0)
        pops[#pops + 1] = { pos = who:GetPos() + Vector(0, 0, 76) + jitter, n = amount, head = head, t = RealTime() }
        if #pops > 40 then table.remove(pops, 1) end
    end)

    local COL, COL_HEAD = Color(240, 240, 235), Color(255, 120, 90)
    Rhylib.Hook.Add("HUDPaint", "dummy.dmg", function()
        if #pops == 0 then return end
        local now = RealTime()
        local i = 1
        while i <= #pops do
            local p = pops[i]
            local age = now - p.t
            if age > 1.2 then
                table.remove(pops, i)
            else
                local sp = (p.pos + Vector(0, 0, age * 30)):ToScreen()
                if sp.visible then
                    local col = p.head and COL_HEAD or COL
                    local a = 255 * math.min(1, (1.2 - age) / 0.4)
                    draw.SimpleTextOutlined(tostring(p.n), Rhylib.UI.Font(p.head and 24 or 20, 800), sp.x, sp.y,
                        Color(col.r, col.g, col.b, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, a * 0.8))
                end
                i = i + 1
            end
        end
    end)
    return
end

Rhylib.Net.Register("dummy.dmg")

local count = 0

function ENT:SpawnFunction(ply, tr, class)
    if not tr.Hit then return end
    local ent = ents.Create(class)
    ent:SetPos(tr.HitPos)
    ent:SetAngles(Angle(0, ply:EyeAngles().y + 180, 0))  -- facing you
    ent:Spawn()
    return ent
end

function ENT:Initialize()
    self:SetModel(MARKER)
    self:SetNoDraw(true)
    self:SetSolid(SOLID_NONE)
    self:SetMoveType(MOVETYPE_NONE)
    self:DrawShadow(false)

    -- Bots need a multiplayer game (a local game with 2+ player slots).
    if game.SinglePlayer() or not player.CreateNextBot then
        for _, p in ipairs(player.GetHumans()) do
            if p:IsAdmin() then p:ChatPrint("Test dummy: needs a multiplayer game. Start your local game with 2 or more player slots.") end
        end
        self:Remove()
        return
    end
    count = count + 1
    -- (pcall: the engine errors instead of returning nil in some setups)
    local ok, bot = pcall(player.CreateNextBot, self.BotName .. " " .. count)
    if not ok or not IsValid(bot) then
        local why = (not ok and string.find(tostring(bot), "singleplayer", 1, true))
            and "needs a multiplayer game. Start your local game with 2 or more player slots."
            or "no free player slot"
        for _, p in ipairs(player.GetHumans()) do
            if p:IsAdmin() then p:ChatPrint("Test dummy: " .. why) end
        end
        self:Remove()
        return
    end
    bot.rhylibDummy = self
    self.bot = bot
    -- The bot spawns on its own next tick; put it here once it has.
    timer.Simple(0.1, function()
        if IsValid(self) and IsValid(bot) then self:PlaceBot() end
    end)
end

function ENT:PlaceBot()
    local bot = self.bot
    if not IsValid(bot) then return end
    if not bot:Alive() then bot:Spawn() end
    bot:StripWeapons()
    bot:SetModel(dummyModel())
    bot:SetPos(self:GetPos())
    bot:SetEyeAngles(self:GetAngles())
    bot:SetVelocity(-bot:GetVelocity())
end

function ENT:OnRemove()
    local bot = self.bot
    if IsValid(bot) then bot:Kick("Test dummy removed") end
end

local function dummyOf(ply)
    local ent = ply.rhylibDummy
    return IsValid(ent) and ent or nil
end

DUMMY_MOVE = DUMMY_MOVE or "still"   -- still, walk, run (all dummies)

-- Stand still, or walk/run back and forth from the marker's facing.
Rhylib.Hook.Add("StartCommand", "dummy.still", function(ply, cmd)
    if not ply:IsBot() then return end
    local ent = dummyOf(ply)
    if not ent then return end
    cmd:ClearMovement()
    cmd:ClearButtons()
    if DUMMY_MOVE == "still" then return end
    local back = math.floor(CurTime() / 2.5) % 2 == 1
    cmd:SetViewAngles(Angle(0, ent:GetAngles().y + (back and 180 or 0), 0))
    cmd:SetForwardMove(10000)
    if DUMMY_MOVE == "run" then cmd:SetButtons(IN_SPEED) end
end, -200)

concommand.Add("rhylib_dummy_move", function(ply, _, args)
    if IsValid(ply) and not ply:IsAdmin() then return end
    local m = string.lower(args[1] or "")
    if m ~= "still" and m ~= "walk" and m ~= "run" then
        local msg = "rhylib_dummy_move still|walk|run (now: " .. DUMMY_MOVE .. ")"
        if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
        return
    end
    DUMMY_MOVE = m
    if IsValid(ply) then ply:ChatPrint("Test dummies: " .. m) end
end)

-- Every spawn: back on the marker, with the dummy model and no weapons.
Rhylib.Hook.Add("PlayerSpawn", "dummy.place", function(ply)
    local ent = ply:IsBot() and dummyOf(ply)
    if not ent then return end
    timer.Simple(0, function()
        if IsValid(ent) and IsValid(ply) then ent:PlaceBot() end
    end)
end, 100)

Rhylib.Hook.Add("PlayerSetModel", "dummy.model", function(ply)
    if ply:IsBot() and dummyOf(ply) then
        ply:SetModel(dummyModel())
        return true
    end
end)

-- Back up 3 seconds after dying.
Rhylib.Hook.Add("PlayerDeath", "dummy.respawn", function(ply)
    local ent = ply:IsBot() and dummyOf(ply)
    if not ent then return end
    timer.Simple(3, function()
        if IsValid(ent) and IsValid(ply) and not ply:Alive() then ent:PlaceBot() end
    end)
end)

-- The bot left (kicked, map change): remove its marker too.
Rhylib.Hook.Add("PlayerDisconnected", "dummy.cleanup", function(ply)
    local ent = ply.rhylibDummy
    if IsValid(ent) then
        ent.bot = nil
        ent:Remove()
    end
end)

-- Damage numbers to players nearby.
local function showDamage(bot, amount, head)
    local n = math.floor(amount + 0.5)
    if n <= 0 then return end
    local near = {}
    for _, p in ipairs(player.GetHumans()) do
        if p:GetPos():DistToSqr(bot:GetPos()) < 1500 * 1500 then near[#near + 1] = p end
    end
    if #near == 0 then return end
    Rhylib.Net.Start("dummy.dmg")
    net.WriteEntity(bot)
    net.WriteUInt(math.min(n, 4095), 12)
    net.WriteBool(head)
    net.Send(near)
end

local function isHead(ply)
    return (ply.rhylibHitGroup or ply:LastHitGroup()) == HITGROUP_HEAD
end

-- Tough dummy: shows the hit (after armour at 100) and takes none of it.
Rhylib.Hook.Add("EntityTakeDamage", "dummy.tough", function(ent, dmg)
    if not (ent:IsPlayer() and ent:IsBot()) then return end
    local d = dummyOf(ent)
    if not (d and d.Tough) then return end
    showDamage(ent, dmg:GetDamage(), isHead(ent))
    return true
end, 140)

Rhylib.Hook.Add("PostEntityTakeDamage", "dummy.numbers", function(ent, dmg, took)
    if not took or not (ent:IsPlayer() and ent:IsBot()) or ent.rhylibBleedTick then return end
    local d = dummyOf(ent)
    if not d or d.Tough then return end
    showDamage(ent, dmg:GetDamage(), isHead(ent))
end)
