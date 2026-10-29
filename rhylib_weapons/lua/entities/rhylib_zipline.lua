--[[
    A zipline: a straight line from a post planted where the shooter stood
    (A) to where the grapple hook gripped (B), or to a second post when
    the Zipline rigger skill planted the far end on the floor. Rigged by
    the grapple's zipline fire mode (sv_30_grapple.lua); ridden in
    SetupMove (sh_30_grapple.lua, "Zipline mode").

    Static: no physics, no Think. The ends are network vars, so they reach
    everyone who comes near, once. E on the near post picks the hook back
    up (not while anyone is riding). The entity sits at the foot of the
    near post; its use box is the post.

    Looks: the line is a dark cable; posts are config grapple zipPostModel
    (a model you make) or, while that's empty, a plain drawn pole; the
    hook end is the same small block as a grapple rope's hook.

    Realm: shared. ENT:SetZip(a, b, postB, hookNormal) on the server;
    ENT:GetZipData() on both realms: { a, b, dir, len, deg, twoWay }.
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Zipline"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_OPAQUE

-- Only there so the engine renders the entity; never drawn.
local MARKER_MODEL = "models/hunter/blocks/cube025x025x025.mdl"
local USE_MINS, USE_MAXS = Vector(-3, -3, 0), Vector(3, 3, 88)   -- the near post (thin: it stops shots)

function ENT:SetupDataTables()
    self:NetworkVar("Vector", 0, "A")          -- top of the near post (where the line ties on)
    self:NetworkVar("Vector", 1, "B")          -- the far end (hook point, or the far post's top)
    self:NetworkVar("Bool", 0, "PostB")        -- the far end is a post (skill), not a hook
    self:NetworkVar("Angle", 0, "HookAng")     -- the hook's surface normal, as an angle
    self:NetworkVar("Bool", 1, "Ready")        -- set last: clients build the data then
    self:NetworkVarNotify("Ready", self.OnReadyChanged)
end

-- Build the data (and, on clients, the render bounds) as soon as it arrives,
-- so the cable draws before anyone looks at the near post.
function ENT:OnReadyChanged()
    self.zipData = nil
    timer.Simple(0, function()
        if IsValid(self) then self:GetZipData() end
    end)
end

function ENT:Initialize()
    self:SetModel(MARKER_MODEL)
    if SERVER then
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_BBOX)
        self:SetCollisionBounds(USE_MINS, USE_MAXS)
        self:SetCollisionGroup(COLLISION_GROUP_WEAPON)  -- nobody bumps into it
        self:SetUseType(SIMPLE_USE)
    end
    Rhylib.Weapons.Grapple.zips[self] = true
    if CLIENT then self:OnReadyChanged() end
end

-- Always sent: a line can be 40 m long and riders far from the near post
-- need it to predict their ride. Static and capped by grapple maxRopes.
function ENT:UpdateTransmitState()
    return TRANSMIT_ALWAYS
end

function ENT:OnRemove()
    Rhylib.Weapons.Grapple.zips[self] = nil
    if SERVER and IsValid(self.gripped) then
        self.gripped:RemoveCallOnRemove("rhylib_zip_" .. self:EntIndex())
    end
end

-- Server: fill in the line. a = near post top, b = far end, postB = the
-- far end is a post, hookNormal = the gripped surface's normal (hook end).
function ENT:SetZip(a, b, postB, hookNormal)
    self:SetA(a)
    self:SetB(b)
    self:SetPostB(postB and true or false)
    self:SetHookAng((hookNormal or Vector(0, 0, 1)):Angle())
    self:SetReady(true)
end

-- Server: what the hook gripped (non-world). If that goes, the line goes
-- and the hook drops at the near post.
function ENT:SetGripped(ent)
    if not IsValid(ent) then return end
    self.gripped = ent
    local zip = self
    ent:CallOnRemove("rhylib_zip_" .. self:EntIndex(), function()
        if not IsValid(zip) or zip.taken then return end
        zip.taken = true   -- (Remove is deferred: no second hook from Use this tick)
        Rhylib.Weapons.Grapple.DropHook(zip:GetPos() + Vector(0, 0, 8), zip.rhylibIssued)
        zip:Remove()
    end)
end

-- The line's data (cached: it never changes). nil until it's ready.
function ENT:GetZipData()
    if self.zipData then return self.zipData end
    if not self:GetReady() then return nil end
    local a, b = self:GetA(), self:GetB()
    local dir = b - a
    local len = dir:Length()
    if len < 1 then return nil end
    dir:Normalize()
    local deg, twoWay = Rhylib.Weapons.Grapple.ZipSlope(a, b)
    local d = { a = a, b = b, dir = dir, len = len, deg = deg, twoWay = twoWay,
        margin = Rhylib.Weapons.Grapple.ZipMargin(dir) }
    self.zipData = d
    if CLIENT then
        local mins = Vector(math.min(a.x, b.x), math.min(a.y, b.y), math.min(a.z, b.z) - 100)
        local maxs = Vector(math.max(a.x, b.x), math.max(a.y, b.y), math.max(a.z, b.z))
        self:SetRenderBoundsWS(mins - Vector(8, 8, 8), maxs + Vector(8, 8, 8))
    end
    return d
end

if SERVER then
    function ENT:Use(ply)
        if self.taken or not IsValid(ply) or not ply:IsPlayer() then return end
        local G = Rhylib.Weapons.Grapple
        if G.ZipRiders(self) > 0 then
            Rhylib.Notify(ply, "Someone is on the zipline", "bad", "Grapple")
            return
        end
        -- (an armoury hook stays issued; taken: Remove() is deferred to the tick's end)
        if Rhylib.Weapons.Pouch.Add(ply, G.ITEM, 1, false, self.rhylibIssued) then
            self.taken = true
            ply:EmitSound("physics/metal/metal_solid_impact_soft1.wav", 60)
            self:Remove()
        else
            Rhylib.Notify(ply, "No room for the grapple hook", "bad", "Grapple")
        end
    end
end

if CLIENT then
    local COL_LINE = Color(20, 20, 22)
    local COL_POST = Color(70, 72, 74)
    local COL_HOOK = Color(58, 60, 62)
    local POST_MINS, POST_MAXS = Vector(-2, -2, 0), Vector(2, 2, 0)
    local HOOK_MINS, HOOK_MAXS = Vector(-2.25, -1.5, -1.5), Vector(6.75, 1.5, 1.5)
    local ANG0 = Angle(0, 0, 0)
    local postModels = {}   -- [model path] = ClientsideModel (one shared per path)
    local modelOk = {}      -- [model path] = true / false (checked once)

    -- A post standing on the ground at foot, its top at top.
    local function drawPost(foot, top)
        local mdl = Rhylib.Config.Get("grapple", "zipPostModel")
        if isstring(mdl) and mdl ~= "" and modelOk[mdl] == nil then
            modelOk[mdl] = (util.IsValidModel(mdl) or file.Exists(mdl, "GAME")) and true or false
            if modelOk[mdl] then util.PrecacheModel(mdl) end
        end
        if isstring(mdl) and modelOk[mdl] then
            local cm = postModels[mdl]
            if not IsValid(cm) then
                cm = ClientsideModel(mdl, RENDERGROUP_OPAQUE)
                if not IsValid(cm) then return end
                cm:SetNoDraw(true)
                postModels[mdl] = cm
            end
            cm:SetPos(foot)
            cm:SetAngles(ANG0)
            cm:SetupBones()
            cm:DrawModel()
            return
        end
        render.SetColorMaterial()
        POST_MAXS.z = top.z - foot.z
        render.DrawBox(foot, ANG0, POST_MINS, POST_MAXS, COL_POST)
    end

    function ENT:Draw()
        local d = self:GetZipData()
        if not d then return end
        local G = Rhylib.Weapons.Grapple
        drawPost(self:GetPos(), d.a)
        if self:GetPostB() then
            drawPost(d.b - Vector(0, 0, G.POST_H), d.b)
        else
            render.SetColorMaterial()
            render.DrawBox(d.b, self:GetHookAng(), HOOK_MINS, HOOK_MAXS, COL_HOOK)
        end
        render.SetColorMaterial()
        render.DrawBeam(d.a, d.b, 1.6, 0, 1, COL_LINE)
    end
end
