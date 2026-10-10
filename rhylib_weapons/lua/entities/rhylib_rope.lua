--[[
    A grapple rope: the hook where it gripped, plus the rope laid down the
    surface below it (see sh_30_grapple.lua and sv_30_grapple.lua).

    Static: no physics, no Think. Its points are network vars, so they
    reach every player who comes near, once. Press E on the hook to pick
    it back up (not while anyone is climbing).

    Looks: the hook is a small dark grey block sticking out
    of the surface, the rope a black line. Both are drawn directly, no
    model. The hook's use box is a bit bigger than it looks, so it's easy
    to press E on.

    Realm: shared. The server creates it (sv_30_grapple.lua onHookHit)
    and fills it with ENT:SetRope; both realms read it with
    ENT:GetRopeData (climbing is predicted, sh_30_grapple.lua).
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Grapple rope"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_OPAQUE

-- Only there so the engine renders the entity; never drawn.
local HOOK_MODEL = "models/hunter/blocks/cube025x025x025.mdl"
local USE_BOX = Vector(5, 5, 5)                 -- half size of the use/pickup box

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "Count")
    self:NetworkVar("Int", 1, "Top")
    self:NetworkVar("Int", 2, "FreeMask")     -- bit i-1 set: segment i hangs free (no wall)
    self:NetworkVar("Bool", 0, "HasLedge")
    self:NetworkVar("Vector", 0, "Ledge")     -- where a climber stands after going over the top
    self:NetworkVar("Float", 0, "Born")       -- when the rope started lowering
    for i = 1, 16 do  -- G.MAX_POINTS
        self:NetworkVar("Vector", i, "P" .. i)          -- rope points, hook first
        self:NetworkVar("Angle", i - 1, "N" .. i)       -- wall normal of segment i, as an angle
    end
    -- Client: build the rope (and its draw bounds) as soon as the points arrive.
    self:NetworkVarNotify("Count", self.OnCountChanged)
end

function ENT:OnCountChanged()
    self.ropeData = nil
    if CLIENT then self:BuildSoon() end
end

-- Notify callbacks run before the value is stored, so wait a tick.
function ENT:BuildSoon()
    timer.Simple(0, function()
        if IsValid(self) then self:GetRopeData() end
    end)
end

function ENT:Initialize()
    self:SetModel(HOOK_MODEL)
    if SERVER then
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_BBOX)
        self:SetCollisionBounds(-USE_BOX, USE_BOX)
        self:SetCollisionGroup(COLLISION_GROUP_WEAPON)  -- nobody bumps into it
        self:SetUseType(SIMPLE_USE)
    end
    Rhylib.Weapons.Grapple.ropes[self] = true
    if CLIENT then self:BuildSoon() end  -- players arriving later get the points with the entity
end

function ENT:OnRemove()
    Rhylib.Weapons.Grapple.ropes[self] = nil
    if SERVER and IsValid(self.gripped) then
        self.gripped:RemoveCallOnRemove("rhylib_rope_" .. self:EntIndex())
    end
end

-- Server: what the hook gripped (non-world). If that goes, the rope goes
-- and the hook drops where it was.
function ENT:SetGripped(ent)
    if not IsValid(ent) then return end
    self.gripped = ent
    local rope = self
    ent:CallOnRemove("rhylib_rope_" .. self:EntIndex(), function()
        if not IsValid(rope) then return end
        Rhylib.Weapons.Grapple.DropHook(rope:GetPos())
        rope:Remove()
    end)
end

-- Server only: fill in the rope. pts/nrm from sv_30_grapple.lua.
-- pts: up to 16 points, hook first. nrm[i]: wall normal of segment i
-- (nil = hangs free). top: index where climbing starts. ledge: where a
-- climber stands after going over the top, or nil.
-- Count is set last: its notify makes clients build the rope.
function ENT:SetRope(pts, nrm, top, ledge)
    local mask = 0
    for i = 1, #pts do self["SetP" .. i](self, pts[i]) end
    for i = 1, #pts - 1 do
        if nrm[i] then
            self["SetN" .. i](self, nrm[i]:Angle())
        else
            mask = bit.bor(mask, bit.lshift(1, i - 1))
        end
    end
    self:SetFreeMask(mask)
    self:SetTop(top)
    self:SetHasLedge(ledge ~= nil)
    if ledge then self:SetLedge(ledge) end
    self:SetBorn(CurTime())
    self:SetCount(#pts)
end

-- Cached rope data for the climbing maths (built once, the rope never changes).
-- Returns nil until the points have arrived, else the table described in
-- sh_30_grapple.lua ("Rope maths"). Shared.
function ENT:GetRopeData()
    if self.ropeData then return self.ropeData end
    local n = self:GetCount()
    if n < 2 then return nil end

    local top = math.Clamp(self:GetTop(), 1, n - 1)
    local mask = self:GetFreeMask()
    local pts, nrm, cum = {}, {}, {}
    for i = 1, n do pts[i] = self["GetP" .. i](self) end
    for i = 1, n - 1 do
        if bit.band(mask, bit.lshift(1, i - 1)) == 0 then
            nrm[i] = self["GetN" .. i](self):Forward()
        end
    end
    local all = { 0 }
    for i = 1, n - 1 do all[i + 1] = all[i] + pts[i]:Distance(pts[i + 1]) end
    for i = top, n do cum[i] = all[i] - all[top] end

    local d = {
        pts = pts, nrm = nrm, cum = cum, all = all, top = top, n = n,
        len = cum[n], head = all[top], total = all[n], born = self:GetBorn(),
        ledge = self:GetHasLedge() and self:GetLedge() or nil,
    }
    self.ropeData = d

    if CLIENT then
        -- The entity sits at the hook; make sure the whole rope still draws.
        local mins, maxs = Vector(pts[1]), Vector(pts[1])
        for i = 2, n do
            local p = pts[i]
            mins.x, mins.y, mins.z = math.min(mins.x, p.x), math.min(mins.y, p.y), math.min(mins.z, p.z)
            maxs.x, maxs.y, maxs.z = math.max(maxs.x, p.x), math.max(maxs.y, p.y), math.max(maxs.z, p.z)
        end
        self:SetRenderBoundsWS(mins - Vector(8, 8, 8), maxs + Vector(8, 8, 8))
    end
    return d
end

if SERVER then
    function ENT:Use(ply)
        if not IsValid(ply) or not ply:IsPlayer() then return end
        local G = Rhylib.Weapons.Grapple
        if G.Climbers(self) > 0 then
            ply:PrintMessage(HUD_PRINTCENTER, "Someone is on the rope")
            return
        end
        if Rhylib.Weapons.Pouch.Add(ply, G.ITEM, 1) then
            ply:EmitSound("physics/metal/metal_solid_impact_soft1.wav", 60)
            self:Remove()
        else
            ply:PrintMessage(HUD_PRINTCENTER, "No room for the grapple hook")
        end
    end
end

if CLIENT then
    local COL_ROPE = Color(14, 14, 14)          -- black
    local COL_HOOK = Color(58, 60, 62)          -- dark grey
    local HOOK_MINS = Vector(-2.25, -1.5, -1.5)  -- along the surface normal: 2.25 in, 6.75 out
    local HOOK_MAXS = Vector(6.75, 1.5, 1.5)    -- about 17 x 6 x 6 cm

    function ENT:Draw()
        -- No DrawModel: the hook and rope are drawn as plain shapes.
        render.SetColorMaterial()
        render.DrawBox(self:GetPos(), self:GetAngles(), HOOK_MINS, HOOK_MAXS, COL_HOOK)

        local d = self:GetRopeData()
        if not d then return end

        -- Only the part that has come down so far; the end slides down.
        local lowered = Rhylib.Weapons.Grapple.Lowered(d)
        local all, pts = d.all, d.pts
        local last = 1
        while last < d.n and all[last + 1] <= lowered do last = last + 1 end
        local tip
        if last < d.n then
            local seg = all[last + 1] - all[last]
            tip = seg > 0 and pts[last] + (pts[last + 1] - pts[last]) * ((lowered - all[last]) / seg) or pts[last]
        end

        render.StartBeam(last + (tip and 1 or 0))
        for i = 1, last do render.AddBeam(pts[i], 1.8, 0, COL_ROPE) end
        if tip then render.AddBeam(tip, 1.8, 0, COL_ROPE) end
        render.EndBeam()
    end
end
