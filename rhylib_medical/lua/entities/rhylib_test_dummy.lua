--[[
    Test dummy (admins: spawn menu Rhy's Medical, or the toolgun's Testing
    entries). A NextBot in a trooper model, not a player: it takes no
    player slot and works in single player. It stands where you placed it
    (facing you) and never shoots; droids and clone NPCs leave it alone.

    It is hurt like a player (rhylib_medical sv_60_dummy.lua): armour
    first, then health (100 / 100); body part injuries, bleeding, limps
    and recovery as players get them; at 0 HP it goes down (a ragdoll,
    the bleed-out timer, stabilise / drag / revive / blood pack); dying
    (bled out, or finished off) leaves the ragdoll for 3 s, then it stands
    back up on its spot with full health and armour. Medics treat it with
    the normal kits and the E menu / wheel, and look at its body with H.
    Hits show as damage numbers over it (net dummy.dmg, drawn here).
    The tough dummy (rhylib_test_dummy_tough) takes no damage at all: no
    injuries, never goes down; it only shows what a hit would have done
    (after armour).

    rhylib_dummy_move still|walk|run (admins): every dummy stands still,
    or walks / runs back and forth along the way it faced when placed
    (turning every 2.5 s; NextBot locomotion, no navmesh needed). Running
    while limping is a walk. Falls hurt it like a player (mp_falldamage).

    Player-like methods (both realms): Alive, Nick / Name, Armor,
    SetArmor (server), GetMaxArmor, GetPlayerColor. Fields:
    ENT.IsRhylibDummy (Rhylib.Medical.IsPatient), RhylibWheel /
    RhylibWheelHold (rhylib_menus wheel; a downed one opens at once).
    NW2 on the dummy: rhylib_dummyName (String), rhylib_dummyDead (Bool),
    rhylib_dummyHp / rhylib_dummyMax / rhylib_dummyArmor (Int: clients
    don't get a NextBot's health), plus the medical and lying ones.
    Server: ENT:DummyDie(), ENT:DummyRespawn(). Hit groups: rhylib bolts
    set rhylibHitGroup; engine bullets are noted in OnTraceAttack.

    A variant only needs ENT.Base = "rhylib_test_dummy", ENT.Type =
    "nextbot" plus DummyName and Tough (see rhylib_test_dummy_tough.lua).
    The model is ENT.Model (Server settings > Models can swap it), with a
    fallback; ENT.PreviewModel gives it to the toolgun's tile picture.
    Not saved across map changes.
]]

AddCSLuaFile()

ENT.Type = "nextbot"
ENT.Base = "base_nextbot"
ENT.PrintName = "Test dummy"
ENT.Category = "Rhy's Medical"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.IsRhylibDummy = true
ENT.RhylibWheel = true        -- (rhylib_menus: E opens the interaction wheel on it)
ENT.RhylibWheelHold = true    -- (after a hold while standing; cl_10_hud.lua clears it while down)

local MODEL = "models/ct_trp/pm_ct_trp.mdl"
local MODEL_FALLBACK = "models/aussiwozzi/cgi/base/unassigned_cpt.mdl"
ENT.Model = MODEL   -- (Server settings > Models can swap it)

local function okModel(m)
    if not isstring(m) or m == "" then return false end
    return util.IsValidModel(m) or (CLIENT and file.Exists(m, "GAME"))
end
local function dummyModel()
    local st = scripted_ents.GetStored("rhylib_test_dummy")
    local m = st and st.t and st.t.Model or MODEL
    if okModel(m) then return m end
    return okModel(MODEL) and MODEL or MODEL_FALLBACK
end
-- (toolgun tile picture: the model the dummy wears)
ENT.PreviewModel = function() return dummyModel() end
ENT.DummyName = "Test dummy"   -- a number is added
ENT.Tough = false              -- true: blocks all damage, only shows it
ENT.MaxHp = 100
local WALK, RUN = 160, 240     -- (DarkRP's player walk / run speeds)
local SAFE_FALL, FATAL_FALL = 526.5, 922.5   -- (the engine's player fall speeds)

--------------------------------------------------------------------------
-- Player-like methods (both realms)
--------------------------------------------------------------------------

function ENT:Alive() return not self:GetNW2Bool("rhylib_dummyDead", false) end
function ENT:Nick() return self:GetNW2String("rhylib_dummyName", self.DummyName or "Test dummy") end
function ENT:Name() return self:Nick() end
function ENT:Armor() return self:GetNW2Int("rhylib_dummyArmor", 0) end
function ENT:GetMaxArmor() return 100 end
local WHITE = Vector(1, 1, 1)
function ENT:GetPlayerColor() return WHITE end

local function medical() return Rhylib.Medical end

if CLIENT then
    function ENT:Initialize()
        local Med = medical()
        if Med and Med.dummies then Med.dummies[self] = true end
    end

    function ENT:OnRemove()
        local Med = medical()
        if Med and Med.dummies then Med.dummies[self] = nil end
    end

    -- Hidden while its ragdoll lies there (down, or dead for 3 s).
    function ENT:Draw()
        if not self:Alive() or IsValid(self:GetNW2Entity(Rhylib.NW.RAG)) then return end
        self:DrawModel()
    end

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

--------------------------------------------------------------------------
-- Server
--------------------------------------------------------------------------

function ENT:SetArmor(n)
    n = math.max(0, math.floor((tonumber(n) or 0) + 0.5))
    if self:Armor() ~= n then self:SetNW2Int("rhylib_dummyArmor", n) end
end

local function spawnArmor()
    local Med = medical()
    return Med and Med.DummyArmor and Med.DummyArmor() or 0
end

function ENT:SpawnFunction(ply, tr, class)
    if not tr.Hit then return end
    local ent = ents.Create(class)
    ent:SetPos(tr.HitPos)
    ent:SetAngles(Angle(0, ply:EyeAngles().y + 180, 0))  -- facing you
    ent:Spawn()
    ent:Activate()
    return ent
end

function ENT:Initialize()
    self:SetModel(dummyModel())
    self:SetCollisionBounds(Vector(-16, -16, 0), Vector(16, 16, 72))   -- (a player's hull)
    self:SetBloodColor(BLOOD_COLOR_RED)
    self:SetMaxHealth(self.MaxHp)
    self:SetHealth(self.MaxHp)
    self:SetArmor(spawnArmor())
    local Med = medical()
    local n = 1
    if Med then
        Med.dummyCount = (Med.dummyCount or 0) + 1
        n = Med.dummyCount
        if Med.dummies then Med.dummies[self] = true end
    end
    self:SetNW2String("rhylib_dummyName", (self.DummyName or self.BotName or "Test dummy") .. " " .. n)
    self.home = self:GetPos()
    self.homeYaw = self:GetAngles().y
    local loco = self.loco
    loco:SetStepHeight(18)
    loco:SetJumpHeight(56)
    loco:SetAcceleration(1000)
    loco:SetDeceleration(1000)
    loco:SetMaxYawRate(360)
    self:CopyHealth()
end

-- Clients don't get a NextBot's health: copy it when it changes.
function ENT:CopyHealth()
    local hp, max = math.max(0, self:Health()), self:GetMaxHealth()
    if hp ~= self.sentHp then
        self.sentHp = hp
        self:SetNW2Int("rhylib_dummyHp", hp)
    end
    if max ~= self.sentMax then
        self.sentMax = max
        self:SetNW2Int("rhylib_dummyMax", max)
    end
end

function ENT:Act(act)
    if self:GetActivity() ~= act then self:StartActivity(act) end
end

-- One tick of the behaviour: health copy, fall tracking, and standing /
-- walking / running back and forth (Med.dummyMove, sv_60_dummy.lua).
function ENT:DummyTick()
    self:CopyHealth()
    local loco = self.loco
    local Med = medical()
    local down = self.rhylibDown
    if down or loco:IsOnGround() then
        if down then self.fallV = 0 end
    else
        self.fallV = math.min(self.fallV or 0, loco:GetVelocity().z)
    end
    local mode = Med and Med.dummyMove or "still"
    if not self:Alive() or down or mode == "still" then
        self:Act(ACT_HL2MP_IDLE)
        return
    end
    local back = math.floor(CurTime() / 2.5) % 2 == 1
    local dir = Angle(0, self.homeYaw + (back and 180 or 0), 0):Forward()
    local run = mode == "run" and not (Med and Med.NoSprint and Med.NoSprint(self))   -- (limping: no running)
    loco:SetDesiredSpeed(run and RUN or WALK)
    local goal = self:GetPos() + dir * 100
    loco:FaceTowards(goal)
    loco:Approach(goal, 1)
    self:Act(run and ACT_HL2MP_RUN or ACT_HL2MP_WALK)
    if loco:IsStuck() then loco:ClearStuck() end
end

function ENT:RunBehaviour()
    while true do
        self:DummyTick()
        coroutine.yield()
    end
end

-- Player models walk with the 9-way blend (move_x / move_y).
function ENT:BodyUpdate()
    local act = self:GetActivity()
    if act == ACT_HL2MP_WALK or act == ACT_HL2MP_RUN then
        self:BodyMoveXY()   -- (advances the frame itself)
        return
    end
    self:FrameAdvance()
end

-- Landing: fall damage as a player takes it (mp_falldamage 1: by speed,
-- else 10), from the world.
function ENT:OnLandOnGround()
    local speed = -(self.fallV or 0)
    self.fallV = 0
    if speed <= SAFE_FALL or not self:Alive() or self.rhylibDown then return end
    local cv = GetConVar("mp_falldamage")
    local amount = (cv and cv:GetBool()) and (speed - SAFE_FALL) * (100 / (FATAL_FALL - SAFE_FALL)) or 10
    local world = game.GetWorld()
    local d = DamageInfo()
    d:SetDamage(amount)
    d:SetDamageType(DMG_FALL)
    d:SetAttacker(world)
    d:SetInflictor(world)
    d:SetDamagePosition(self:GetPos())
    self:TakeDamageInfo(d)
end

-- Engine bullets: which hitbox they hit (rhylib_medical Med.HitGroupOf).
function ENT:OnTraceAttack(dmginfo, dir, trace)
    self.rhylibTraceGroup = trace.HitGroup
    self.rhylibTraceAt = CurTime()
end

function ENT:OnInjured() end

-- (sv_60_dummy.lua never lets the engine kill it; this is a backstop:
-- no engine ragdoll, no NPC kill hook.)
function ENT:OnKilled()
    self:DummyDie()
end

local function timerId(self) return "Rhylib.Medical.Dummy." .. self:EntIndex() end

-- Dies: the body falls (or stays, if it was down) as a ragdoll for 3 s,
-- then ENT:DummyRespawn.
function ENT:DummyDie()
    if not self:Alive() then return end
    local L = Rhylib.Lying
    -- (standing: a ragdoll from the current pose; Begin needs it alive)
    if L and L.Begin and not L.Ragdoll(self) then L.Begin(self) end
    self:SetNW2Bool("rhylib_dummyDead", true)
    local Med = medical()
    -- Not down any more; dead, so rhylib_core keeps the ragdoll as the corpse.
    if Med and Med.DummyReset then Med.DummyReset(self) end
    if L and L.active and L.active[self] then L.End(self) end   -- (one that wasn't down)
    self:SetNotSolid(true)
    self:DrawShadow(false)
    self.loco:SetVelocity(vector_origin)
    timer.Create(timerId(self), 3, 1, function()
        if IsValid(self) then self:DummyRespawn() end
    end)
end

-- Back on its spot, facing the way it was placed, full health and armour.
function ENT:DummyRespawn()
    timer.Remove(timerId(self))
    local L = Rhylib.Lying
    if L and L.ClearCorpse then L.ClearCorpse(self) end
    self:SetPos(self.home or self:GetPos())
    self:SetAngles(Angle(0, self.homeYaw or 0, 0))
    self.loco:SetVelocity(vector_origin)
    self.fallV = 0
    self:SetNW2Bool("rhylib_dummyDead", false)
    self:SetMaxHealth(self.MaxHp)
    self:SetHealth(self.MaxHp)
    self:SetArmor(spawnArmor())
    self:SetNotSolid(false)
    if L and L.ShowPlayer then L.ShowPlayer(self, true) end
    self:DrawShadow(true)
    local Med = medical()
    if Med and Med.DummyReset then Med.DummyReset(self) end
    if L and L.Unstick then L.Unstick(self) end
    self:CopyHealth()
end

-- Removed (undo, remover, cleanup): nothing is left pointing at it.
function ENT:OnRemove()
    timer.Remove(timerId(self))
    local Med = medical()
    if Med then
        if Med.DummyReset then Med.DummyReset(self) end
        if Med.ForgetPatient then Med.ForgetPatient(self) end
        if Med.ill then Med.ill[self] = nil end
        if Med.dummies then Med.dummies[self] = nil end
    end
    local L = Rhylib.Lying
    if L then
        if L.active and IsValid(L.active[self]) then L.active[self]:Remove() end
        if L.active then L.active[self] = nil end
        if L.ClearCorpse then L.ClearCorpse(self) end
    end
end
