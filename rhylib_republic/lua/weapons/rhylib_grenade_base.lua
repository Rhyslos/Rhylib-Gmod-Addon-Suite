--[[
    Grenade base (not spawnable). A 1x1 inventory item that stacks; LMB
    throws hard, RMB lobs short. Each throw uses one from the inventory
    (none in rhylib_infammo test mode) and spawns rhylib_grenade.

    SWEP.ImpactMode = true: E + R switches it between timed (fuse) and
    impact; the choice is a player NW2Bool per grenade type (ImpactKey).
    An EMP in impact mode is kind "emp_impact".
    SWEP.BreachMode = true: with the Breaching charge skill (rhylib_skills)
    E + R cycles timed -> impact -> breach. In breach mode LMB / RMB stick
    it to the door or wall you look at (kind "breach": long fuse, small
    blast, forces doors open; see rhylib_grenade).
    SWEP.RequiresSkill: a skill (rhylib_skills) needed to throw it.
    SWEP.GrenadeKind: "fuse" (explodes FuseTime after the throw), "impact"
    (explodes on the first hit) or "emp" (fuse; kills Rhylib droids in
    range, harmless to everything else). Blast numbers are on the entity.
    First person: GMod's HL2 grenade hands (c_grenade, player hands) play
    draw / idle / throw; its grenade bones are shrunk away and the prop is
    drawn on the grenade bone, so it follows the throw. Third person: the
    prop in the right hand (PropWMPos/Ang, tune with rhylib_wm_editor).
    Prop offsets are from the model's centre (the thermal's origin is off
    to one side).
]]

AddCSLuaFile()

local Config = Rhylib.Config
Config.Register("weapons", "breachFuse", 6, "Breaching charge: seconds from placing to the blast")
Config.Register("weapons", "breachRadius", 130, "Breaching charge: blast radius (units, 130 = 2.5 m)")
Config.Register("weapons", "breachDamage", 70, "Breaching charge: damage at the centre")
Config.Register("weapons", "breachDoors", 130, "Breaching charge: doors this close are forced open (units)")
Config.Register("weapons", "breachHold", 300, "Breaching charge: seconds a forced door stays open")
Config.Register("weapons", "breachReach", 80, "Breaching charge: how far you can reach to place it (units)")

SWEP.Base = "weapon_base"
SWEP.PrintName = "Grenade"
SWEP.Category = "Rhylib: Grenades & charges"
SWEP.InvGroup = "grenade"   -- (armoury shelf: rhylib_inventory Items.GroupOf)
SWEP.Spawnable = false
SWEP.Slot = 4
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true

SWEP.ViewModel = "models/weapons/c_grenade.mdl"
SWEP.ViewModelFOV = 54
SWEP.WorldModel = "models/jajoff/sps/cgiweapons/tc13j/thermalgrenade.mdl"
SWEP.UseHands = true
SWEP.HoldType = "grenade"

SWEP.Primary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }

SWEP.InvW = 1
SWEP.InvH = 1
SWEP.InvStack = 3
SWEP.InvWeight = 0.4
SWEP.InvCategory = "gear"

SWEP.GrenadeKind = "fuse"
SWEP.FuseTime = 3
SWEP.ThrowForce = 1000       -- LMB
SWEP.LobForce = 450          -- RMB
SWEP.ThrowDelay = 1          -- seconds between throws
SWEP.PropColor = nil         -- tint of the grenade model

SWEP.PropModel = "models/jajoff/sps/cgiweapons/tc13j/thermalgrenade.mdl"
SWEP.PropScale = 0.75                  -- third person size
SWEP.PropVMScale = 1                   -- first person size (owner-tuned)
SWEP.PropVMPos = Vector(-10.6, -5.1, -5.6)   -- first person: from the viewmodel's grenade bone
SWEP.PropVMAng = Angle(0, 0, 0)
SWEP.PropWMPos = Vector(-5, -1, -5)    -- third person: forward, right, up from the right hand
SWEP.PropWMAng = Angle(0, 0, 0)
SWEP.RedrawTime = 0.7                  -- after a throw, the next one comes up

function SWEP:SetupDataTables()
    self:NetworkVar("Float", 0, "LastThrow")
    self:NetworkVar("Bool", 0, "NeedDraw")
end

function SWEP:Deploy()
    self:SendWeaponAnim(ACT_VM_DRAW)
    self:SetNeedDraw(false)
    return true
end

-- Each grenade type remembers its own mode (thermal: rhylib_nadeImpact).
function SWEP:ImpactKey()
    local c = self:GetClass()
    return c == "rhylib_thermal" and "rhylib_nadeImpact" or ("rhylib_nadeImpact_" .. c)
end

-- Breach mode on (E + R, BreachMode grenades with the skill)?
function SWEP:IsBreach()
    if not self.BreachMode then return false end
    local o = self:GetOwner()
    if not (IsValid(o) and o:GetNW2Bool(self:ImpactKey() .. "_breach")) then return false end
    local K = Rhylib.Skills
    return not (K and K.Has) or K.Has(o, "breaching")
end

-- Impact mode on (E + R, for ImpactMode grenades)?
function SWEP:IsImpact()
    local o = self:GetOwner()
    return self.ImpactMode and IsValid(o) and o:GetNW2Bool(self:ImpactKey()) and not self:IsBreach() or false
end

function SWEP:CanBreach()
    if not self.BreachMode then return false end
    local K = Rhylib.Skills
    return not (K and K.Has) or K.Has(self:GetOwner(), "breaching")
end

-- May the owner throw it (SWEP.RequiresSkill)?
function SWEP:SkillOK()
    local K = Rhylib.Skills
    if not (self.RequiresSkill and K and K.Has) then return true end
    return K.Has(self:GetOwner(), self.RequiresSkill)
end

-- The next grenade comes up after a throw.
function SWEP:Think()
    -- E + R: timed / impact.
    local o = self:GetOwner()
    if SERVER and self.ImpactMode and IsValid(o) and o:KeyPressed(IN_RELOAD) and o:KeyDown(IN_USE) then
        -- timed -> impact -> (breach) -> timed
        local key, bkey = self:ImpactKey(), self:ImpactKey() .. "_breach"
        local msg
        if self:IsBreach() then
            o:SetNW2Bool(bkey, false)
            o:SetNW2Bool(key, false)
        elseif o:GetNW2Bool(key) then
            o:SetNW2Bool(key, false)
            if self:CanBreach() then o:SetNW2Bool(bkey, true) end
        else
            o:SetNW2Bool(bkey, false)
            o:SetNW2Bool(key, true)
        end
        if self:IsBreach() then
            msg = ": breaching charge (stick it on a door)"
        elseif self:IsImpact() then
            msg = ": impact"
        else
            msg = ": timed (" .. self.FuseTime .. " s)"
        end
        o:EmitSound("weapons/smg1/switch_single.wav", 60)
        o:ChatPrint(self.PrintName .. msg)
    end
    if self:GetNeedDraw() and CurTime() >= self:GetLastThrow() + self.RedrawTime then
        self:SetNeedDraw(false)
        self:SendWeaponAnim(ACT_VM_DRAW)
    end
end

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
end

function SWEP:Reload() end

function SWEP:PrimaryAttack()
    if self:IsBreach() then self:PlaceBreach() return end
    self:Throw(self.ThrowForce, 0.05)
end
function SWEP:SecondaryAttack()
    if self:IsBreach() then self:PlaceBreach() return end
    self:Throw(self.LobForce, 0.25)
end

-- Breach mode: stick a charge on the surface you look at.
function SWEP:PlaceBreach()
    local o = self:GetOwner()
    if not IsValid(o) or not o:IsPlayer() then return end
    self:SetNextPrimaryFire(CurTime() + 0.5)
    self:SetNextSecondaryFire(CurTime() + 0.5)
    local tr = util.TraceLine({
        start = o:GetShootPos(), endpos = o:GetShootPos() + o:GetAimVector() * Config.Get("weapons", "breachReach"),
        filter = o, mask = MASK_SOLID,
    })
    local e = tr.Entity
    local ok = tr.Hit and not tr.HitSky and (tr.HitWorld or (IsValid(e) and not e:IsPlayer() and not e:IsNPC() and not e:IsNextBot()))
    if not ok then
        if SERVER then o:ChatPrint("Look at a door or a wall close by to place the charge") end
        return
    end
    self:SetNextPrimaryFire(CurTime() + self.ThrowDelay)
    self:SetNextSecondaryFire(CurTime() + self.ThrowDelay)
    self:SetLastThrow(CurTime())
    self:SetNeedDraw(true)
    self:SendWeaponAnim(ACT_VM_THROW)
    o:SetAnimation(PLAYER_ATTACK1)
    if CLIENT then return end
    local g = ents.Create("rhylib_grenade")
    if not IsValid(g) then return end
    g:SetPos(tr.HitPos + tr.HitNormal * 2)
    g:SetAngles(tr.HitNormal:Angle())
    g.kind = "breach"
    g.fuse = Config.Get("weapons", "breachFuse")
    g.thrower = o
    g.training = self.Training   -- (training grenades: sim health only)
    g.stuckTo = IsValid(e) and e or nil
    g:SetOwner(o)
    g:SetColor(Color(255, 150, 60))
    g:Spawn()
    o:EmitSound("physics/metal/weapon_impact_soft" .. math.random(1, 3) .. ".wav", 65, 110)
    self:UseOne(o)
end

-- force: speed along the aim; lift: extra upward share of it.
function SWEP:Throw(force, lift)
    local o = self:GetOwner()
    if not IsValid(o) or not o:IsPlayer() then return end
    if not self:SkillOK() then
        self:SetNextPrimaryFire(CurTime() + 1)
        self:SetNextSecondaryFire(CurTime() + 1)
        if SERVER then o:ChatPrint("You need the " .. (self.SkillName or "right") .. " skill to throw this") end
        return
    end
    self:SetNextPrimaryFire(CurTime() + self.ThrowDelay)
    self:SetNextSecondaryFire(CurTime() + self.ThrowDelay)
    self:SetLastThrow(CurTime())
    self:SetNeedDraw(true)
    self:SendWeaponAnim(ACT_VM_THROW)
    o:SetAnimation(PLAYER_ATTACK1)
    if CLIENT then return end

    local ang = o:EyeAngles()
    local pos = o:GetShootPos() + ang:Forward() * 16 + ang:Right() * 6 - ang:Up() * 4
    -- Don't spawn it inside a wall.
    local tr = util.TraceLine({ start = o:GetShootPos(), endpos = pos, filter = o, mask = MASK_SOLID })
    if tr.Hit then pos = tr.HitPos + tr.HitNormal * 4 end

    local g = ents.Create("rhylib_grenade")
    if not IsValid(g) then return end
    g:SetPos(pos)
    g:SetAngles(ang)
    g.kind = self:IsImpact() and (self.GrenadeKind == "emp" and "emp_impact" or "impact") or self.GrenadeKind
    g.fuse = self.FuseTime
    g.thrower = o
    g.training = self.Training   -- (training grenades: sim health only)
    g:SetOwner(o)
    local tint = self:IsImpact() and (self.ImpactColor or Color(255, 190, 150)) or self.PropColor
    if tint then g:SetColor(tint) end
    g:Spawn()
    local phys = g:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetVelocity(o:GetVelocity() * 0.5 + ang:Forward() * force + Vector(0, 0, force * lift))
        phys:AddAngleVelocity(VectorRand() * 400)
    end
    o:EmitSound("weapons/slam/throw.wav", 65, 100)
    self:UseOne(o)
end

-- One fewer in the inventory (the inventory strips the weapon when the
-- last one leaves). Test ammo keeps it.
function SWEP:UseOne(o)
    if o:GetNW2Bool("rhylib_infammo") then return end
    local Inv = Rhylib.Inventory
    local class = self:GetClass()
    if Inv and Inv.Get and Inv.Remove then
        for _, inst in pairs(Inv.Get(o).byUid) do
            if inst.id == class then
                Inv.Remove(o, inst.uid, 1)
                return
            end
        end
    end
    o:StripWeapon(class)
end

if CLIENT then
    local IMPACT_TINT = Color(255, 190, 150)
    local WHITE = Color(255, 255, 255)

    -- Mode under the crosshair (thermal: timed / impact; locked grenades).
    function SWEP:DrawHUD()
        local text
        if not self:SkillOK() then
            text = "Needs the " .. (self.SkillName or "right") .. " skill"
        elseif self:IsBreach() then
            text = "BREACHING CHARGE  ·  E + R"
        elseif self.ImpactMode then
            text = self:IsImpact() and "IMPACT  ·  E + R" or ("TIMED " .. self.FuseTime .. " S  ·  E + R")
        end
        if not text then return end
        local font = Rhylib.UI and Rhylib.UI.Font and Rhylib.UI.Font(13, 700) or "DermaDefaultBold"
        draw.SimpleTextOutlined(text, font, ScrW() * 0.5, ScrH() * 0.5 + ScrH() * 0.05, Color(225, 225, 225, 220),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 160))
    end

    -- Model centre in its own coordinates (the thermal's origin is off to
    -- one side), per model.
    local centres = {}
    function SWEP:PropCentre(e)
        local m = self.PropModel
        if not centres[m] then
            local mins, maxs = e:GetModelBounds()
            centres[m] = (mins + maxs) * 0.5
        end
        return centres[m]
    end

    local function place(pos, ang, off, offAng)
        local p = pos + ang:Forward() * off.x + ang:Right() * off.y + ang:Up() * off.z
        local a = Angle(ang.p, ang.y, ang.r)
        a:RotateAroundAxis(a:Up(), offAng.y)
        a:RotateAroundAxis(a:Right(), offAng.p)
        a:RotateAroundAxis(a:Forward(), offAng.r)
        return p, a
    end

    function SWEP:Prop(key, sc)
        local e = self[key]
        if not IsValid(e) then
            e = ClientsideModel(self.PropModel, RENDERGROUP_OPAQUE)
            if not IsValid(e) then return nil end
            e:SetNoDraw(true)
            self[key] = e
        end
        -- Impact mode shows as a warmer tint.
        local tint = self:IsImpact() and (self.ImpactColor or IMPACT_TINT) or self.PropColor or WHITE
        if e.rhylibTint ~= tint then e:SetColor(tint) e.rhylibTint = tint end
        sc = sc or self.PropScale or 1
        if e.rhylibScale ~= sc then e:SetModelScale(sc, 0) e.rhylibScale = sc end
        return e
    end

    -- Draws the prop with its centre at pos.
    function SWEP:DrawPropAt(e, pos, ang)
        local c = self:PropCentre(e) * (e.rhylibScale or 1)
        e:SetPos(LocalToWorld(-c, angle_zero, pos, ang))
        e:SetAngles(ang)
        e:SetupBones()
        e:DrawModel()
    end

    -- c_grenade's own grenade bones (grenade / .pin / lever): the prop is
    -- drawn on the grenade bone.
    local nadeBones = {}
    local function bonesOf(vm)
        local mdl = vm:GetModel() or ""
        if not nadeBones[mdl] then
            local body
            for i = 0, (vm:GetBoneCount() or 0) - 1 do
                local n = string.lower(vm:GetBoneName(i) or "")
                if string.find(n, "grenade", 1, true) then body = i break end
            end
            nadeBones[mdl] = { body = body }
        end
        return nadeBones[mdl]
    end

    -- c_grenade is only the HL2 grenade (the arms are the separate hands
    -- entity), so the viewmodel is drawn fully see-through (render blend 0).
    -- The blend goes back to 1 in a PostDrawViewModel hook, which runs
    -- before the hands and the prop are drawn. (Same hook id as in
    -- rhylib_base, so only one copy runs.)
    Rhylib.Hook.Add("PostDrawViewModel", "weapons.blendreset", function(vm)
        if IsValid(vm) and vm.rhylibBlendOff then
            render.SetBlend(1)
            vm.rhylibBlendOff = nil
        end
    end, -1000)
    -- (Safety: a viewmodel that wasn't drawn after all.)
    Rhylib.Hook.Add("PreDrawHUD", "weapons.blendsafety", function()
        local lp = LocalPlayer()
        local vm = IsValid(lp) and lp:GetViewModel()
        if IsValid(vm) and vm.rhylibBlendOff then
            render.SetBlend(1)
            vm.rhylibBlendOff = nil
        end
    end)

    function SWEP:PreDrawViewModel(vm)
        render.SetBlend(0)
        vm.rhylibBlendOff = true
    end

    function SWEP:PostDrawViewModel(vm)
        -- Gone from the hand once thrown, until the next one comes up.
        if self:GetNeedDraw() or CurTime() < self:GetLastThrow() + 0.1 then return end
        local b = bonesOf(vm)
        local bone = b.body or vm:LookupBone("ValveBiped.Bip01_R_Hand")
        local m = bone and vm:GetBoneMatrix(bone)
        local e = self:Prop("propVM", self.PropVMScale or 1)
        if m and e then self:DrawPropAt(e, place(m:GetTranslation(), m:GetAngles(), self.PropVMPos, self.PropVMAng)) end
    end

    function SWEP:DrawWorldModel(flags)
        local o = self:GetOwner()
        if not IsValid(o) then self:DrawModel(flags) return end
        if self:GetNeedDraw() then return end   -- just thrown
        local b = o:LookupBone("ValveBiped.Bip01_R_Hand")
        local m = b and o:GetBoneMatrix(b)
        local e = self:Prop("propWM")
        if m and e then self:DrawPropAt(e, place(m:GetTranslation(), m:GetAngles(), self.PropWMPos, self.PropWMAng)) end
    end

    function SWEP:OnRemove()
        if IsValid(self.propVM) then self.propVM:Remove() end
        if IsValid(self.propWM) then self.propWM:Remove() end
    end
end
