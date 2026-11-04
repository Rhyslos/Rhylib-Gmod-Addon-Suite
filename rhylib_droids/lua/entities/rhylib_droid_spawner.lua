--[[
    Droid spawner (admins; spawn menu "Rhy's Droids", or the toolgun's
    spawn window). Keeps sending out droids in preset squads until it is
    destroyed or has sent them all.

    Every `interval` seconds, when a whole squad fits under `cap` alive
    (a cap smaller than one squad counts as one squad) and it still has
    droids `left`, it spawns one preset squad
    (D.SpawnPreset, droid presets only) just in front of it, facing the
    way it faces. Squads on Patrol or Roam are cut into patrol / roam
    groups (D.WanderGroups, patrols centred where they come out); Attack
    hunts the nearest players; Guard holds in front of it. The latest
    droid markers apply as for any placed droid. The last squad only
    spawns as many as are left (front rows first). It waits while the map
    is at maxActive droids. Settings that make no sense (a clone preset, a
    typo) fall back to droid_small / patrol.

    It has droids spawnerHealth health and breaks (with a bang) when it
    runs out; its droids carry on. Admins press E on it for its settings
    (rhylib/droids/cl_50_spawner.lua, sv_50_spawner.lua): preset, how many
    in all, how many alive at once, seconds between squads, mode, on/off.
    Admins see a label over it (left / alive / next squad).

    Networked: DT Int Left, Int Alive, Bool Running, Float NextAt, String
    Preset (the label). Settings on the server: self.cfg = { preset,
    total, cap, interval, mode }. Spawners and their droids aren't saved.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Droid spawner"
ENT.Category = "Rhy's Droids"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_BOTH

local MODEL = "models/props_combine/combine_dispenser.mdl"
ENT.Model = MODEL

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "Left")
    self:NetworkVar("Int", 1, "Alive")
    self:NetworkVar("Bool", 0, "Running")
    self:NetworkVar("Float", 0, "NextAt")
    self:NetworkVar("String", 0, "Preset")
end

local function D() return Rhylib.Droids end

-- Settings made safe: a droid preset, a known mode, numbers in range.
local MODES = { patrol = true, roam = true, attack = true, guard = true }
local function clean(c)
    local Dr = D()
    local pr = Dr and Dr.PRESETS and Dr.PRESETS[c.preset]
    if not pr or pr.side == 1 then c.preset = "droid_small" end
    if not MODES[c.mode] then c.mode = "patrol" end
    c.total = math.Clamp(math.floor(tonumber(c.total) or 60), 1, 1000)
    c.cap = math.Clamp(math.floor(tonumber(c.cap) or 20), 1, 100)
    c.interval = math.Clamp(math.floor(tonumber(c.interval) or 30), 5, 600)
    return c
end

-- How many NPCs a preset has.
local function presetSize(name)
    local Dr = D()
    local pr = Dr and Dr.PRESETS and Dr.PRESETS[name]
    local n = 0
    for _, row in ipairs(pr and pr.rows or {}) do n = n + #row end
    return n
end

if SERVER then
    function ENT:Initialize()
        if not (D() and D().Cfg) then self:Remove() return end   -- (rhylib_droids didn't load)
        local m = D().Cfg("spawnerModel")
        if not (isstring(m) and util.IsValidModel(m)) then m = MODEL end
        self:SetModel(m)
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
        local cfg = D().Cfg
        self.cfg = clean({ preset = cfg("spawnerPreset"), total = cfg("spawnerTotal"), cap = cfg("spawnerCap"),
            interval = cfg("spawnerInterval"), mode = cfg("spawnerMode") })
        self.hp = math.max(1, tonumber(cfg("spawnerHealth")) or 1)
        self.mine = {}
        self:SetLeft(self.cfg.total)
        self:SetPreset(self.cfg.preset)
        self:SetRunning(true)
        self:SetNextAt(CurTime() + 3)
        self:NextThink(CurTime() + 1)
    end

    -- ENT:ApplyConfig(cfg): new settings (checked by sv_50_spawner).
    -- A new total, or any Apply on an empty spawner, starts the count again.
    function ENT:ApplyConfig(cfg, running)
        local old = self.cfg.total
        cfg = clean(cfg)
        self.cfg = cfg
        if cfg.total ~= old or self:GetLeft() <= 0 then self:SetLeft(cfg.total) end
        self:SetPreset(cfg.preset)
        self:SetRunning(running and true or false)
        self:SetNextAt(math.min(self:GetNextAt(), CurTime() + cfg.interval))
    end

    -- Live droids it sent out (dead or removed ones dropped).
    function ENT:CountAlive()
        local n = 0
        for e in pairs(self.mine) do
            if IsValid(e) and e:Health() > 0 then n = n + 1 else self.mine[e] = nil end
        end
        return n
    end

    function ENT:SpawnSquad()
        local Dr = D()
        if not (Dr and Dr.SpawnPreset and Dr.PRESETS) then return end
        local pr = Dr.PRESETS[self.cfg.preset]
        if not pr or pr.side == 1 then return end
        local yaw = self:GetAngles().y
        local fwd = Angle(0, yaw, 0):Forward()
        -- (SpawnPreset puts the front row at `at` facing yaw, the other rows
        -- 85 units each behind it: the last row just clear of the spawner)
        local at = self:GetPos() + fwd * (self:BoundingRadius() + 90 + 85 * (#pr.rows - 1))
        if Dr.SnapNav then at = Dr.SnapNav(at) end
        local left = self:GetLeft()
        -- (the last squad: only as many as are left, front rows first)
        local list = Dr.SpawnPreset(self.cfg.preset, at, yaw, self.cfg.mode, left)
        for _, e in ipairs(list) do
            self.mine[e] = true
            e.rhylibSpawner = self
        end
        local made = #list
        self:SetLeft(math.max(0, left - made))
        if made > 0 then
            local keep = list
            if (self.cfg.mode == "patrol" or self.cfg.mode == "roam") and Dr.WanderGroups then
                Dr.WanderGroups(keep, self.cfg.mode)
            elseif #keep > 1 and Dr.MakeSquads then
                Dr.MakeSquads(keep, { face = yaw })
            end
            self:EmitSound("doors/door_metal_large_open1.wav", 75, 90)
        end
    end

    function ENT:Think()
        local now = CurTime()
        local Dr = D()
        local alive = self:CountAlive()
        if alive ~= self:GetAlive() then self:SetAlive(alive) end
        if self:GetRunning() and self:GetLeft() > 0 and Dr and now >= self:GetNextAt() then
            local size = math.min(presetSize(self.cfg.preset), self:GetLeft())
            -- (room for a whole squad under its cap, at least one squad's worth, and the map's)
            local room = alive + size <= math.max(self.cfg.cap, size)
            local mapRoom = not Dr.Count or Dr.Count() < Dr.Cfg("maxActive")
            if room and mapRoom then
                self:SpawnSquad()
                self:SetNextAt(now + self.cfg.interval)
            else
                self:SetNextAt(now + 2)   -- (check again soon)
            end
        end
        self:NextThink(now + 1)
        return true
    end

    function ENT:OnTakeDamage(dmg)
        if self.broken then return end
        self.hp = self.hp - dmg:GetDamage()
        if self.hp <= 0 then
            self.broken = true
            local ed = EffectData()
            ed:SetOrigin(self:WorldSpaceCenter())
            util.Effect("Explosion", ed, true, true)
            self:Remove()
        end
    end

    function ENT:Use(ply)
        if not (IsValid(ply) and ply:IsPlayer()) then return end
        local SP = D() and D().Spawner
        if SP and SP.Open then SP.Open(ply, self) end
    end
    return
end

-- Client: the label over it, for admins.
function ENT:Draw()
    self:DrawModel()
end

local function isAdmin(me)
    local A = Rhylib.Admin
    if A and A.Has then return A.Has(me, "rhylib.toolgun", "admin") end
    return me:IsAdmin()
end

function ENT:DrawTranslucent()
    local me = LocalPlayer()
    if not (IsValid(me) and isAdmin(me)) then return end
    if me:GetPos():DistToSqr(self:GetPos()) > 900 * 900 then return end
    local pos = self:GetPos() + Vector(0, 0, self:OBBMaxs().z + 16)
    local ang = Angle(0, (me:EyePos() - pos):Angle().y + 90, 90)
    local wait = math.max(0, self:GetNextAt() - CurTime())
    local line2 = string.format("%d left · %d alive", self:GetLeft(), self:GetAlive())
    local line3 = not self:GetRunning() and "Stopped (E: settings)" or (self:GetLeft() <= 0 and "Empty" or string.format("Next squad in %d s", math.ceil(wait)))
    cam.Start3D2D(pos, ang, 0.12)
        local f = Rhylib.UI and Rhylib.UI.Font and Rhylib.UI.Font(26, 700) or "DermaLarge"
        draw.SimpleTextOutlined("Droid spawner · " .. self:GetPreset(), f, 0, 0, Color(255, 120, 90), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, Color(0, 0, 0, 200))
        draw.SimpleTextOutlined(line2, f, 0, 30, Color(235, 238, 240), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, Color(0, 0, 0, 200))
        draw.SimpleTextOutlined(line3, f, 0, 60, Color(200, 205, 210), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, Color(0, 0, 0, 200))
    cam.End3D2D()
end
