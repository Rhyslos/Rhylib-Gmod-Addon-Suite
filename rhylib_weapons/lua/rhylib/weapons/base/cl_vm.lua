--[[
    Weapon base, client: the viewmodel (rhylib_base includes this; it
    returns function(SWEP, env)). Aim and lowered poses
    (GetViewModelPosition, reload dip, CarrierPose), the prop drawn on a
    carrier's gun bone or floating, carriers (shrunk gun bone, CarrierBoneMods,
    invisible carriers), ExtraProps, proxy viewmodels (ModeProxies), the
    mirrored left hand (DualMirror), the dual carrier, PreDrawViewModel /
    PostDrawViewModel, AlignPropAngle / MatchFloatOffset (first idle frame
    auto-tuning), HoldReloadFrame.
    Shares with the other parts through env: offsetTransform, drawExtra,
    carrierBone (rhylib_devtools' editors), Track(self, ent) (every
    ClientsideModel the weapon makes; OnRemove in cl_wm.lua removes them).
]]

return function(SWEP, env)
    -- env.Track(wep, ent): remember a ClientsideModel for OnRemove.
    function env.Track(wep, ent)
        local list = wep.rhylibCSEnts
        if not list then
            list = {}
            wep.rhylibCSEnts = list
        end
        list[#list + 1] = ent
    end

    local ease = math.ease and math.ease.InOutSine or function(x) return x end
    -- Pistols when lowered/sprinting: where they idle, muzzles tipped up a
    -- little, just lifted from where they are when aiming.
    -- The tilt turns around the eyes, so the offset pulls them back down.
    local PISTOL_LOWER = Vector(0, -1, -3)
    local PISTOL_TILT = 12

    function SWEP:GetViewModelPosition(pos, ang)
        local ft = FrameTime()
        local pos0, ang0 = pos, ang   -- (the view's own frame: props with vmIgnoreGunPose undo what's added below)
        self.aimFrac = math.Approach(self.aimFrac or 0, (self:GetAiming() or self.rhylibAimPreview) and 1 or 0, ft * 6)
        self.safeFrac = math.Approach(self.safeFrac or 0, self:IsLowered() and 1 or 0, ft / (self.SafeBlendTime or 0.2))

        local dual = self:DualViewModelOn()
        local o = dual and self.DualVMOffset or (not dual and self.rhylibCarrier and self:CarrierPose("VMOffset"))
        if o then pos = pos + ang:Right() * o.x + ang:Forward() * o.y + ang:Up() * o.z end
        -- (mirrored dual pistols: the right hand out to the side; the left is its mirror image)
        if self.DualMirror and (self.DualSpread or 0) ~= 0 and self:GetFireModeName() == "dual" then
            pos = pos + ang:Right() * self.DualSpread
        end
        if self.rhylibCarrier and self.SafePose then self.ViewModelFOV = self:CarrierPose("CarrierFOV") end

        local f = ease(self.aimFrac)
        -- (dual pistols: aiming only tightens the spread, the guns don't slide)
        if f > 0 and not dual and self:GetFireModeName() ~= "dual" then
            local off = self.AimPos * f
            pos = pos + ang:Right() * off.x + ang:Forward() * off.y + ang:Up() * off.z
        end

        -- On safety or sprinting: a rifle lowered and turned inward; pistols
        -- (one or two) held muzzle-up instead.
        local sf = ease(self.safeFrac)
        if sf > 0 then
            ang = Angle(ang.p, ang.y, ang.r)
            if self:LoweredHoldType() == "normal" then
                -- (SWEP.PistolLowerPos: right, forward, up; SWEP.PistolLowerTilt: degrees up)
                local lp = self.PistolLowerPos or PISTOL_LOWER
                local pv = self.PistolLowerPivot   -- (forward, right, up: turn around the hand, not the eyes)
                local tilt = (self.PistolLowerTilt or PISTOL_TILT) * sf
                if pv then
                    local piv = pos + ang:Forward() * pv.x + ang:Right() * pv.y + ang:Up() * pv.z
                    ang:RotateAroundAxis(ang:Right(), tilt)
                    pos = piv - (ang:Forward() * pv.x + ang:Right() * pv.y + ang:Up() * pv.z)
                    local a = ang0
                    pos = pos + a:Right() * (lp.x * sf) + a:Forward() * (lp.y * sf) + a:Up() * (lp.z * sf)
                else
                    pos = pos + ang:Right() * (lp.x * sf) + ang:Forward() * (lp.y * sf) + ang:Up() * (lp.z * sf)
                    ang:RotateAroundAxis(ang:Right(), tilt)
                end
            else
                pos = pos - ang:Up() * (4 * sf) + ang:Right() * (1.5 * sf) - ang:Forward() * (2 * sf)
                ang:RotateAroundAxis(ang:Right(), -20 * sf)
                ang:RotateAroundAxis(ang:Up(), 18 * sf)
            end
        end
        -- (the mirrored left hand starts from here: its own reload dip and sway)
        self.rhylibVMBase = self.rhylibVMBase or {}
        self.rhylibVMBase[1], self.rhylibVMBase[2] = pos, Angle(ang.p, ang.y, ang.r)
        local k = self:ReloadDip(false)
        if k > 0 then pos, ang = self:ApplyReloadDip(pos, ang, k) end
        -- (where the view's own frame sits in the gun's: ExtraProps with
        -- vmIgnoreGunPose use it, so a shield doesn't follow the gun's aim,
        -- lowering, reload dip or VMOffset)
        local up, ua = WorldToLocal(pos0, ang0, pos, ang)
        self.rhylibVMUndo = self.rhylibVMUndo or {}
        self.rhylibVMUndo[1], self.rhylibVMUndo[2] = up, ua
        return pos, ang
    end

    -- Reload with no reload animation on the viewmodel (Battlefront models
    -- often have none): the gun dips down and tilts, then comes back. Dual
    -- mirrored pistols take turns: right in the first half, left in the second.
    -- Returns 0-1 for the right (left = true: the left hand).
    function SWEP:ReloadDip(left)
        if not self:IsReloading() then
            self.rhylibDipLen = nil
            return 0
        end
        local o = self:GetOwner()
        local vm = IsValid(o) and o:IsPlayer() and o:GetViewModel()
        if not IsValid(vm) then return 0 end
        local mdl = vm:GetModel()
        if self.rhylibDipModel ~= mdl then
            self.rhylibDipModel = mdl
            self.rhylibHasReload = vm:SelectWeightedSequence(self.ReloadAct or ACT_VM_RELOAD) >= 0
        end
        if self.rhylibHasReload and not self.DualMirror then return 0 end
        local left0 = math.max(self:GetReloadEnd() - CurTime(), 0)
        self.rhylibDipLen = self.rhylibDipLen or math.max(left0, 0.1)
        local t = math.Clamp(1 - left0 / self.rhylibDipLen, 0, 1)
        if self.DualMirror and self:GetFireModeName() == "dual" then
            t = left and math.Clamp(t * 2 - 1, 0, 1) or math.Clamp(t * 2, 0, 1)
        elseif left or self.rhylibHasReload then
            return 0
        end
        return math.sin(math.pi * t) ^ 0.7
    end

    function SWEP:ApplyReloadDip(pos, ang, k)
        pos = pos - ang:Up() * (4 * k) - ang:Forward() * (2 * k)
        ang = Angle(ang.p, ang.y, ang.r)
        ang:RotateAroundAxis(ang:Right(), -25 * k)
        ang:RotateAroundAxis(ang:Forward(), 20 * k)
        return pos, ang
    end

    -- A carrier pose value, blended towards SafePose while lowered (same
    -- easing as the lowering). key: PropBonePos, PropBoneAng, PropBoneScale,
    -- VMOffset or CarrierFOV.
    local POSE_DEFAULT = { PropBoneScale = function(w) return w.PropScale end }
    function SWEP:CarrierPose(key)
        local v = self[key]
        if v == nil and POSE_DEFAULT[key] then v = POSE_DEFAULT[key](self) end
        local safe = self.SafePose and self.SafePose[key]
        local sf = safe and ease(self.safeFrac or 0) or 0   -- (SafePose false = a fire mode without one, ApplyModeCarrier)
        if sf <= 0 or v == nil then return v end
        if sf >= 1 then return safe end
        if isangle(v) then return LerpAngle(sf, v, safe) end
        if isvector(v) then return LerpVector(sf, v, safe) end
        return Lerp(sf, v, safe)
    end


    -- Prop model helpers ------------------------------------------------

    local function offsetTransform(pos, ang, offPos, offAng)
        local p = pos + ang:Forward() * offPos.x + ang:Right() * offPos.y + ang:Up() * offPos.z
        local a = Angle(ang.p, ang.y, ang.r)
        a:RotateAroundAxis(a:Up(), offAng.y)
        a:RotateAroundAxis(a:Right(), offAng.p)
        a:RotateAroundAxis(a:Forward(), offAng.r)
        return p, a
    end

    function SWEP:GetPropEntity(key, scale)
        scale = scale or self.PropScale
        local ent = self[key]
        if IsValid(ent) and ent:GetModel() == self.PropModel then
            if ent.rhylibScale ~= scale then ent:SetModelScale(scale, 0) ent.rhylibScale = scale end
            return ent
        end
        if IsValid(ent) then ent:Remove() end
        ent = ClientsideModel(self.PropModel, RENDERGROUP_OPAQUE)
        if not IsValid(ent) then return nil end
        env.Track(self, ent)
        ent:SetNoDraw(true)
        ent:SetModelScale(scale, 0)
        ent.rhylibScale = scale
        -- (numbers only: GMod's weapon inheritance can leave a BaseClass key in sub-tables)
        for k, v in pairs(self.PropBodygroups or {}) do if isnumber(k) and isnumber(v) then ent:SetBodygroup(k, v) end end
        self[key] = ent
        return ent
    end

    -- Dual pistols: was the last shot from the left gun? Your own shots are
    -- noted when fired; others' come with the shot message (wep.shot).
    function SWEP:IsLeftShot()
        if self.rhylibLeftShot ~= nil then return self.rhylibLeftShot end
        return self:Clip1() % 2 == 1
    end

    -- Where bolts should appear to leave the gun. Used by cl_10_bolts.lua.
    function SWEP:GetPropMuzzle(firstPerson, left)
        if not self.PropModel then return nil end
        if firstPerson and self.PropFirstPerson == false then return nil end   -- (the viewmodel's attachment)
        if firstPerson and self:Scoped() then
            local o = self:GetOwner()
            if IsValid(o) then
                local a = o:EyeAngles()
                return o:EyePos() + a:Forward() * 12 - a:Up() * 3
            end
        end
        -- Dual pistols: the left one fires on odd rounds left (as the anims).
        if left == nil then left = self:GetFireModeName() == "dual" and self:IsLeftShot() end
        if left then
            local p = firstPerson and self.propMuzzleVML or self.propMuzzleWML
            if p then return p end
        end
        return firstPerson and self.propMuzzleVM or self.propMuzzleWM
    end

    -- Carrier viewmodel: its gun bone is shrunk (and moved, CarrierBoneMove)
    -- every frame while a carrier weapon is drawn (the server's bone state
    -- overwrites client changes), and restored for anything else.
    local SHRINK, ONE, ZERO = Vector(0.009, 0.009, 0.009), Vector(1, 1, 1), Vector(0, 0, 0)

    local function carrierBone(self, vm)
        local b = vm:LookupBone(self.CarrierBone or "")
        return b
    end

    local function unshrink(vm)
        local i = vm.rhylibShrunk
        if not i then return end
        if i < (vm:GetBoneCount() or 0) then
            vm:ManipulateBoneScale(i, ONE)
            vm:ManipulateBonePosition(i, ZERO)
        end
        vm.rhylibShrunk = nil
    end

    local function shrink(self, vm)
        local b = carrierBone(self, vm)
        if vm.rhylibShrunk and vm.rhylibShrunk ~= b then unshrink(vm) end
        if not b or self.CarrierInvisible then return end
        vm:ManipulateBoneScale(b, SHRINK)
        vm:ManipulateBonePosition(b, self.CarrierBoneMove or ZERO)
        vm.rhylibShrunk = b
    end

    Rhylib.Hook.Add("PreDrawViewModel", "weapons.vmreset", function(vm, ply, wep)
        if IsValid(vm) and vm.rhylibShrunk and not (IsValid(wep) and wep.UsesCarrier and wep:UsesCarrier()) then
            unshrink(vm)
        end
    end)

    -- Extra props (ExtraProps) and extra hidden carrier bones (CarrierHideBones).
    function SWEP:GetExtraEntity(e, side)
        local key = "rhylibExtra_" .. e.key .. side
        local ent = self[key]
        if IsValid(ent) then return ent end
        if not util.IsValidModel(e.model) then return nil end
        ent = ClientsideModel(e.model, RENDERGROUP_OPAQUE)
        if not IsValid(ent) then return nil end
        env.Track(self, ent)
        ent:SetNoDraw(true)
        ent:SetModelScale((side == "vm" and e.vmScale or e.wmScale) or 1, 0)
        self[key] = ent
        return ent
    end

    local function drawExtra(self, ent, matrix, pos, ang, scale)
        scale = scale or 1
        if ent.rhylibScale ~= scale then
            ent:SetModelScale(scale, 0)
            ent.rhylibScale = scale
        end
        local p, a = offsetTransform(matrix:GetTranslation(), matrix:GetAngles(), pos or Vector(), ang or Angle())
        ent:SetPos(p)
        ent:SetAngles(a)
        ent:SetupBones()
        ent:DrawModel()
    end

    local function extraShrink(self, vm, on)
        if not on then
            local n = vm:GetBoneCount() or 0
            for _, i in ipairs(vm.rhylibExtraShrunk or {}) do
                if i < n then vm:ManipulateBoneScale(i, ONE) end
            end
            vm.rhylibExtraShrunk = nil
            return
        end
        if vm.rhylibExtraShrunk then
            for _, i in ipairs(vm.rhylibExtraShrunk) do vm:ManipulateBoneScale(i, SHRINK) end
            return
        end
        local list = {}
        for _, name in ipairs(self.CarrierHideBones or {}) do
            local b = vm:LookupBone(name)
            if b then
                vm:ManipulateBoneScale(b, SHRINK)
                list[#list + 1] = b
            end
        end
        vm.rhylibExtraShrunk = list
    end

    Rhylib.Hook.Add("PreDrawViewModel", "weapons.extrareset", function(vm, ply, wep)
        if IsValid(vm) and vm.rhylibExtraShrunk and not (IsValid(wep) and wep.CarrierHideBones and wep.UsesCarrier and wep:UsesCarrier()) then
            extraShrink(nil, vm, false)
        end
    end)

    -- Hidden viewmodel (CarrierInvisible, the dual carrier): drawn with
    -- render blend 0. The hands are a separate entity drawn after the
    -- PostDrawViewModel hooks, so this hook puts the blend back before them
    -- (and before the props). Same hook id as in the grenade base.
    local function blendOff(vm)
        render.SetBlend(0)
        vm.rhylibBlendOff = true
    end

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

    -- CarrierBoneMods: applied every frame (the server overwrites client bone
    -- changes), undone for other weapons. The indices touched are kept on the vm.
    local function boneMods(self, vm, on)
        if not on then
            local n = vm:GetBoneCount() or 0
            for _, i in ipairs(vm.rhylibBoneMods or {}) do
                if i < n then
                    vm:ManipulateBonePosition(i, ZERO)
                    vm:ManipulateBoneAngles(i, angle_zero)
                end
            end
            vm.rhylibBoneMods = nil
            return
        end
        local list = {}
        for name, m in pairs(self.CarrierBoneMods or {}) do
            local b = vm:LookupBone(name)
            if b then
                vm:ManipulateBonePosition(b, m.pos or ZERO)
                vm:ManipulateBoneAngles(b, m.ang or angle_zero)
                list[#list + 1] = b
            end
        end
        vm.rhylibBoneMods = list
    end

    Rhylib.Hook.Add("PreDrawViewModel", "weapons.invisreset", function(vm, ply, wep)
        if not IsValid(vm) then return end
        local carrier = IsValid(wep) and wep.UsesCarrier and wep:UsesCarrier()
        if vm.rhylibBoneMods and not (carrier and wep.CarrierBoneMods) then boneMods(nil, vm, false) end
    end)

    -- WorldBoneMods: the holder's own bones, client side, for everyone who
    -- draws them (not while lowered); undone when they switch away.

    local function drawProp(self, pos, ang, scale)
        local ent = self:GetPropEntity("propVM", scale)
        if not ent then return end
        ent:SetPos(pos)
        ent:SetAngles(ang)
        ent:SetupBones()
        ent:DrawModel()
        self.propMuzzleVM = ent:LocalToWorld(self.PropMuzzle * (scale or self.PropScale) / self.PropScale)
    end

    -- Proxy viewmodels: a clientside copy of a viewmodel plus the player's
    -- hands, animated by us, so a gun can show other hands without swapping
    -- the real (networked) viewmodel. Used two ways:
    --   DualMirror: the left hand and pistol of dual pistols, the viewmodel
    --     drawn again mirrored (the left-handed viewmodel trick: scale -1 on
    --     the model's left axis, back faces culled the other way).
    --   ModeProxies: a fire mode held with another viewmodel (DC-15S sidearm
    --     on the DC-17's pistol hands); the real viewmodel and hands are hidden.
    -- Each proxy plays its own fire animation from its own shot time, and
    -- its gun is drawn on ITS gun bone, so it moves with its own hand.
    local MIRROR = Matrix()
    MIRROR:Scale(Vector(1, -1, 1))

    local function proxyModel(self, key, model, mirrored)
        local ent = self[key]
        if IsValid(ent) and ent:GetModel() == model and ent.rhylibMirrored == mirrored then return ent end
        if IsValid(ent) then ent:Remove() end
        ent = ClientsideModel(model, RENDERGROUP_VIEWMODEL)
        if not IsValid(ent) then return nil end
        env.Track(self, ent)
        ent:SetNoDraw(true)
        if mirrored then ent:EnableMatrix("RenderMultiply", MIRROR) end
        ent.rhylibMirrored = mirrored
        self[key] = ent
        return ent
    end

    -- A sequence to rest on: the idle activity, one named "idle", or the
    -- last one it showed at rest (Battlefront viewmodels often have no activities).
    local function restSeq(ent)
        local idle = ent:SelectWeightedSequence(ACT_VM_IDLE)
        if not idle or idle < 0 then idle = ent:LookupSequence("idle") end
        if (not idle or idle < 0) and ent.rhylibRest then idle = ent.rhylibRest end
        return idle
    end

    local function playSeq(ent, seq, cyc)
        if ent:GetSequence() ~= seq then ent:SetSequence(seq) end
        ent:SetCycle(math.Clamp(cyc, 0, 1))
    end

    -- Animate a proxy: its fire animation for a while after `shot`, else
    -- follow (seq, cyc) when given, else rest. True if it fired.
    local function animate(ent, shot, followSeq, followCyc)
        local fireSeq = ent:SelectWeightedSequence(ACT_VM_PRIMARYATTACK)
        local fireLen = (fireSeq and fireSeq >= 0) and ent:SequenceDuration(fireSeq) or 0
        if shot and fireLen > 0 and RealTime() - shot < fireLen then
            playSeq(ent, fireSeq, (RealTime() - shot) / fireLen)
            return true
        end
        if followSeq then
            playSeq(ent, followSeq, followCyc)
            -- (remembered to rest on only if it's an idle, not a draw or reload)
            if ent:GetSequenceActivity(followSeq) == ACT_VM_IDLE or string.find(string.lower(ent:GetSequenceName(followSeq) or ""), "idle", 1, true) then
                ent.rhylibRest = followSeq
            end
            return false
        end
        local idle = restSeq(ent)
        if idle and idle >= 0 then
            local len = math.max(ent:SequenceDuration(idle), 0.1)
            playSeq(ent, idle, (RealTime() % len) / len)
        end
        return false
    end

    -- The player's hands on a proxy (bonemerged), drawn now.
    local function drawProxyHands(self, key, parent, mirrored)
        local hands = LocalPlayer():GetHands()
        if not (IsValid(hands) and hands:GetModel()) then return end
        local mh = proxyModel(self, key, hands:GetModel(), mirrored)
        if not mh then return end
        if mh:GetParent() ~= parent then
            mh:SetParent(parent)
            mh:AddEffects(EF_BONEMERGE)
            mh:SetLocalPos(vector_origin)     -- (lighting is sampled at the origin)
            mh:SetLocalAngles(angle_zero)
            -- (battalion colours: the PlayerColor material proxy asks the entity)
            mh.GetPlayerColor = function()
                local p = LocalPlayer()
                return IsValid(p) and p:GetPlayerColor() or Vector(1, 1, 1)
            end
        end
        if mh:GetSkin() ~= hands:GetSkin() then mh:SetSkin(hands:GetSkin()) end
        for i = 0, (hands:GetNumBodyGroups() or 1) - 1 do
            local v = hands:GetBodygroup(i)
            if mh:GetBodygroup(i) ~= v then mh:SetBodygroup(i, v) end
        end
        mh:DrawModel()
    end

    -- Bones fresh for this frame's sequence, its gun bone hidden.
    local function proxyBones(ent, boneName, move)
        local b = ent:LookupBone(boneName or "")
        if b and ent.rhylibShrunkB ~= b then
            ent:ManipulateBoneScale(b, SHRINK)
            ent:ManipulateBonePosition(b, move or ZERO)
            ent.rhylibShrunkB = b
        end
        ent:InvalidateBoneCache()
        ent:SetupBones()
        return b
    end

    local function mirrorVec(v, right) return v - right * (2 * v:Dot(right)) end

    local function drawMirror(self, vm)
        local mv = proxyModel(self, "rhylibMirrorVM", vm:GetModel(), true)
        if not mv then return end
        local vpos, vang = vm:GetPos(), vm:GetAngles()
        -- Its own pose: the weapon's placement before the right hand's
        -- reload dip and sway (rhylibVMBase), its own reload dip, and the
        -- step/breath sway a quarter cycle off, so the hands don't move as
        -- mirror images.
        local base = self.rhylibVMBase
        if base and base[1] then vpos, vang = base[1], base[2] end
        local k = self:ReloadDip(true)
        if k > 0 then vpos, vang = self:ApplyReloadDip(vpos, vang, k) end
        local right = vang:Right()
        -- Mirrored across the middle of the view (through the eyes).
        local eye = EyePos()
        local mpos = vpos - right * (2 * (vpos - eye):Dot(right))
        local Mo = Rhylib.Lying and Rhylib.Lying.motion
        local side, dip, dp, dy, dr
        if Mo and Mo.Sway then side, dip, dp, dy, dr = Mo.Sway(self, math.pi * 0.5, 1.3) end
        if side then
            mpos = mpos - right * side + vang:Up() * dip   -- (its right is the mirror's left)
            vang = Angle(vang.p + dp, vang.y - dy, vang.r - dr)
        end
        mv:SetPos(mpos)
        mv:SetAngles(vang)
        -- Left shots kick this hand; the right gun's kick isn't copied (by
        -- its activity, or by time since its shot); draw/reload are.
        local seq = vm:GetSequence()
        local rightKick = vm:GetSequenceActivity(seq) == ACT_VM_PRIMARYATTACK
            or (self.rhylibMainShot and RealTime() - self.rhylibMainShot < 0.4)
        if rightKick then
            animate(mv, self.rhylibMirrorShot)
        else
            animate(mv, self.rhylibMirrorShot, seq, vm:GetCycle())
        end
        local b = proxyBones(mv, self.CarrierBone, self.CarrierBoneMove)
        render.CullMode(MATERIAL_CULLMODE_CW)
        mv:DrawModel()
        drawProxyHands(self, "rhylibMirrorHands", mv, true)
        render.CullMode(MATERIAL_CULLMODE_CCW)
        -- The left pistol on the mirrored hand's own gun bone: its pose is
        -- worked out unmirrored, then reflected like the model is drawn.
        local m = b and mv:GetBoneMatrix(b)
        if not m then return end
        local scale = self:CarrierPose("PropBoneScale")
        local ent = self:GetPropEntity("propVML", scale)
        if not ent then return end
        -- (RenderMultiply may already be baked into the bone matrices: a
        -- left-handed matrix is unmirrored first, so it's reflected once)
        mpos = mv:GetPos()
        local bp, ba = m:GetTranslation(), m:GetAngles()
        -- (columns read directly, so the sign of the determinant tells)
        local function col(c) return Vector(m:GetField(1, c), m:GetField(2, c), m:GetField(3, c)) end
        local bf, bl, bu = col(1), col(2), col(3)
        if bf:Cross(bl):Dot(bu) < 0 then
            bp = bp - right * (2 * (bp - mpos):Dot(right))
            bf:Normalize()
            bu:Normalize()
            ba = mirrorVec(bf, right):AngleEx(mirrorVec(bu, right))
        end
        local pos, ang = offsetTransform(bp, ba, self:CarrierPose("PropBonePos"), self:CarrierPose("PropBoneAng") or angle_zero)
        local lp = pos - right * (2 * (pos - mpos):Dot(right))
        local la = mirrorVec(ang:Forward(), right):AngleEx(mirrorVec(ang:Up(), right))
        if self.DualMirrorPos or self.DualMirrorAng then
            lp, la = offsetTransform(lp, la, self.DualMirrorPos or vector_origin, self.DualMirrorAng or angle_zero)
        end
        ent:SetPos(lp)
        ent:SetAngles(la)
        ent:SetupBones()
        ent:DrawModel()
        self.propMuzzleVML = ent:LocalToWorld(self.PropMuzzle * (scale or self.PropScale) / self.PropScale)
    end

    -- A fire mode's proxy viewmodel (ModeProxies): its hands, its fire and
    -- reload animations, the gun on its gun bone.
    local function drawProxy(self, vm, px)
        local ent = proxyModel(self, "rhylibProxyVM", px.model, false)
        if not ent then return end
        local ang = vm:GetAngles()
        local pos = vm:GetPos()
        local o = px.VMOffset
        if o then pos = pos + ang:Right() * o.x + ang:Forward() * o.y + ang:Up() * o.z end
        ent:SetPos(pos)
        ent:SetAngles(ang)
        -- Reload: its reload animation stretched over the gun's reload time.
        if self:IsReloading() then
            -- (stretched over the real reload, skills included: ReloadEnd)
            local left = math.max(self:GetReloadEnd() - CurTime(), 0)
            self.rhylibProxyReload = self.rhylibProxyReload or math.max(left, 0.1)
            local rs = ent:SelectWeightedSequence(ACT_VM_RELOAD)
            if rs and rs >= 0 then
                playSeq(ent, rs, 1 - left / self.rhylibProxyReload)
            else
                animate(ent, nil)
            end
        else
            self.rhylibProxyReload = nil
            animate(ent, self.rhylibProxyShot)
        end
        local b = proxyBones(ent, px.bone, px.boneMove)
        ent:DrawModel()
        drawProxyHands(self, "rhylibProxyHands", ent, false)
        local m = b and ent:GetBoneMatrix(b)
        if not m then return end
        local ppos, pang = offsetTransform(m:GetTranslation(), m:GetAngles(), px.PropBonePos or vector_origin, px.PropBoneAng or angle_zero)
        drawProp(self, ppos, pang, px.PropBoneScale or self.PropScale)
    end

    -- The real hands stay hidden while a proxy stands in for them.
    Rhylib.Hook.Add("PreDrawPlayerHands", "weapons.proxyhands", function(hands, vm, ply, wep)
        if IsValid(wep) and wep.ActiveProxy and wep:ActiveProxy() then return true end
    end)

    -- "dual" mode: the second gun, floating at the left of the view.
    local function drawDualVM(self, vm)
        if self.DualMirror and self:UsesCarrier() then return end   -- (mirrored instead, below)
        if not self.DualPropVMPos or self:GetFireModeName() ~= "dual" then return end
        local ent = self:GetPropEntity("propVML", self.PropBoneScale or self.PropScale)
        if not ent then return end
        local pos, ang = offsetTransform(vm:GetPos(), vm:GetAngles(), self.DualPropVMPos, self.DualPropVMAng)
        ent:SetPos(pos)
        ent:SetAngles(ang)
        ent:SetupBones()
        ent:DrawModel()
        self.propMuzzleVML = ent:LocalToWorld(self.PropMuzzle)
    end

    -- First person. Carrier: it draws (gun bone shrunk) and the prop goes
    -- on that bone in PostDrawViewModel. Otherwise the placeholder isn't
    -- drawn and the prop floats in its place. Both inside the viewmodel
    -- pass (viewmodel FOV, bob, sway, aim offset).
    -- Two-gun viewmodel: hidden whole (render blend), and a prop is drawn
    -- on its left and right gun bone. (Shrinking its gun bones also shrank
    -- the left hand, which hangs off them.)
    local function dualBones(vm, wep)
        local key = vm:GetModel()
        if vm.rhylibDualKey == key then return vm.rhylibDualBones end
        local info = {}
        for i = 0, (vm:GetBoneCount() or 0) - 1 do
            local n = string.lower(vm:GetBoneName(i) or "")
            local gunPart = string.find(n, "elite", 1, true) or string.find(n, "weapon", 1, true) and not string.find(n, "hand", 1, true)
                and not string.find(n, "arm", 1, true) and not string.find(n, "finger", 1, true) and not string.find(n, "wrist", 1, true)
                and not string.find(n, "bip", 1, true)
            if gunPart then
                -- The gun itself: the shortest name with left / right in it.
                if string.find(n, "left", 1, true) and (not info.left or #n < info.leftLen) then info.left, info.leftLen = i, #n end
                if string.find(n, "right", 1, true) and (not info.right or #n < info.rightLen) then info.right, info.rightLen = i, #n end
            end
        end
        -- Named in the weapon (SWEP.DualBoneL / DualBoneR) wins over the guess.
        if wep and wep.DualBoneL then info.left = vm:LookupBone(wep.DualBoneL) or info.left end
        if wep and wep.DualBoneR then info.right = vm:LookupBone(wep.DualBoneR) or info.right end
        vm.rhylibDualKey, vm.rhylibDualBones = key, info
        return info
    end

    -- Bone list of the current viewmodel (for tuning the dual carrier).
    function SWEP:PreDrawViewModel(vm)
        if self.ModeCarriers then self:ApplyModeCarrier() end
        if self:Scoped() then return true end   -- looking through the scope: no gun, no hands
        if self:ActiveProxy() then
            -- (another viewmodel stands in, PostDrawViewModel: this one hidden)
            if vm.rhylibShrunk then unshrink(vm) end
            blendOff(vm)
            return
        end
        if not self.PropModel or self.PropFirstPerson == false then return end
        if self:DualViewModelOn() then
            -- The two-gun model is only guns (the hands are their own
            -- entity), so all of it is hidden and props go on its gun bones.
            if vm.rhylibShrunk then unshrink(vm) end
            blendOff(vm)
            return
        end
        if self:UsesCarrier() then
            shrink(self, vm)
            if self.CarrierHideBones then extraShrink(self, vm, true) end
            if self.CarrierInvisible then blendOff(vm) end
            if self.CarrierBoneMods then boneMods(self, vm, true) end
            self:HoldReloadFrame(vm)
            return
        end
        drawProp(self, offsetTransform(vm:GetPos(), vm:GetAngles(), self.PropVMPos, self.PropVMAng))
        return true
    end

    function SWEP:PostDrawViewModel(vm)
        local px = self.PropModel and not self:Scoped() and self:ActiveProxy()
        if px then drawProxy(self, vm, px) return end
        if self.PropModel and not self:Scoped() and self:DualViewModelOn() then
            local info = dualBones(vm, self)
            for side, b in pairs({ right = info.right, left = info.left }) do
                local m = b and vm:GetBoneMatrix(b)
                if m then
                    local ent = self:GetPropEntity(side == "left" and "propVML" or "propVM", self.PropBoneScale or self.PropScale)
                    if ent then
                        local pos, ang = offsetTransform(m:GetTranslation(), m:GetAngles(), self.DualBonePos, self.DualBoneAng)
                        ent:SetPos(pos)
                        ent:SetAngles(ang)
                        ent:SetupBones()
                        ent:DrawModel()
                        if side == "right" then self.propMuzzleVM = ent:LocalToWorld(self.PropMuzzle)
                        else self.propMuzzleVML = ent:LocalToWorld(self.PropMuzzle) end
                    end
                end
            end
            return
        end
        if self.PropModel and not self:Scoped() then drawDualVM(self, vm) end
        if not self.PropModel or not self:UsesCarrier() then return end
        for _, e in ipairs(self.ExtraProps or {}) do
            local m
            if e.vmAnchor == "view" then
                -- (placed in the view itself: x ahead, y right, z up; follows view bob)
                local vp, va = vm:GetPos(), vm:GetAngles()
                local undo = e.vmIgnoreGunPose and self.rhylibVMUndo
                if undo and undo[1] then vp, va = LocalToWorld(undo[1], undo[2], vp, va) end
                if e.vmAimAnchor == "eyes" then
                    -- (while aiming the frame slides onto the camera itself, so
                    -- a sight on the prop stays on the crosshair: no bob, no AimPos)
                    local f = self:GetAimFrac()
                    f = math.ease and math.ease.InOutSine(f) or f
                    if f > 0 then
                        vp = LerpVector(f, vp, EyePos())
                        va = LerpAngle(f, va, EyeAngles())
                    end
                end
                m = Matrix()
                m:SetTranslation(vp)
                m:SetAngles(va)
            else
                local b = e.vmBone and vm:LookupBone(e.vmBone)
                m = b and vm:GetBoneMatrix(b)
            end
            local ent = m and self:GetExtraEntity(e, "vm")
            if ent then
                local pos, ang = e.vmPos, e.vmAng
                -- (vmPosAim / vmAngAim: a second pose blended in while aiming)
                if e.vmPosAim or e.vmAngAim then
                    local f = self:GetAimFrac()
                    f = math.ease and math.ease.InOutSine(f) or f
                    if f > 0 then
                        pos = LerpVector(f, pos or vector_origin, e.vmPosAim or pos or vector_origin)
                        ang = LerpAngle(f, ang or angle_zero, e.vmAngAim or ang or angle_zero)
                    end
                end
                -- (SWEP:ExtraPoseOffset(e): a moving offset on top, e.g. the shield bash shove)
                if self.ExtraPoseOffset then
                    local add = self:ExtraPoseOffset(e)
                    if add then pos = (pos or vector_origin) + add end
                end
                drawExtra(self, ent, m, pos, ang, e.vmScale)
            end
        end
        local b = carrierBone(self, vm)
        local m = b and vm:GetBoneMatrix(b)
        local pos, ang
        if m and (not self.PropBoneAng or self.rhylibRealign) then self:AlignPropAngle(vm, m:GetAngles()) end
        if m and self.PropBoneAng then
            pos, ang = offsetTransform(m:GetTranslation(), m:GetAngles(), self:CarrierPose("PropBonePos"), self:CarrierPose("PropBoneAng"))
        else
            pos, ang = offsetTransform(vm:GetPos(), vm:GetAngles(), self.PropVMPos, self.PropVMAng)
        end
        drawProp(self, pos, ang, self:CarrierPose("PropBoneScale"))
        if self.DualMirror and self:GetFireModeName() == "dual" then drawMirror(self, vm) end
        if m and (self.VMOffset == nil or self.rhylibRematch) then self:MatchFloatOffset(vm, pos) end
    end

    -- PropBoneAng that points the held prop like the floating prop
    -- (PropVMAng from the view), measured on an idle frame.
    local function idleFrame(self, vm)
        if self:IsReloading() or (self.aimFrac or 0) > 0 or (self.safeFrac or 0) > 0 then return false end
        return vm:GetSequenceActivity(vm:GetSequence()) == ACT_VM_IDLE
    end

    function SWEP:AlignPropAngle(vm, boneAng)
        if not idleFrame(self, vm) then return end
        local _, want = offsetTransform(vector_origin, vm:GetAngles(), vector_origin, self.PropVMAng)
        local _, l = WorldToLocal(vector_origin, want, vector_origin, boneAng)
        -- offsetTransform's rotation order may differ from WorldToLocal's
        -- in sign: keep the candidate that lands closest.
        local best, bestErr
        for _, c in ipairs({ l, Angle(-l.p, l.y, l.r), Angle(l.p, l.y, -l.r), Angle(-l.p, l.y, -l.r), Angle(l.p, -l.y, l.r), Angle(-l.p, -l.y, -l.r) }) do
            local _, a = offsetTransform(vector_origin, boneAng, vector_origin, c)
            local err = (1 - a:Forward():Dot(want:Forward())) + (1 - a:Up():Dot(want:Up()))
            if not bestErr or err < bestErr then best, bestErr = c, err end
        end
        best = Angle(math.Round(best.p, 2), math.Round(best.y, 2), math.Round(best.r, 2))
        self.PropBoneAng = best
        self.rhylibRealign = nil
        local st = not self.rhylibModeCarrier and weapons.GetStored(self:GetClass())   -- (not a fire mode's own values)
        if st then st.PropBoneAng = Angle(best) end
        print(string.format("[Rhylib] %s: SWEP.PropBoneAng = Angle(%g, %g, %g)", self:GetClass(), best.p, best.y, best.r))
    end

    -- VMOffset that puts the held prop where the floating prop was
    -- (PropVMPos from the view), measured on an idle frame. Stored on the
    -- weapon class for the rest of the session.
    function SWEP:MatchFloatOffset(vm, propPos)
        if not idleFrame(self, vm) then return end
        local o, a = vm:GetPos(), vm:GetAngles()
        local d = propPos - o
        local want = self.PropVMPos
        local v = Vector(want.y - d:Dot(a:Right()), want.x - d:Dot(a:Forward()), want.z - d:Dot(a:Up()))
        v = Vector(math.Round(v.x, 2), math.Round(v.y, 2), math.Round(v.z, 2))
        self.VMOffset = v
        self.rhylibRematch = nil
        local st = not self.rhylibModeCarrier and weapons.GetStored(self:GetClass())   -- (not a fire mode's own values)
        if st then st.VMOffset = Vector(v) end
        print(string.format("[Rhylib] %s: SWEP.VMOffset = Vector(%g, %g, %g)", self:GetClass(), v.x, v.y, v.z))
    end

    -- A reload longer than its animation holds the last frame instead of
    -- replaying it; FinishReload sends the idle animation.
    local HOLD = 0.96
    function SWEP:HoldReloadFrame(vm)
        local act = self.ReloadAct or ACT_VM_RELOAD
        if self:IsReloading() and vm:GetSequenceActivity(vm:GetSequence()) == act then
            if self.rhylibHold or vm:GetCycle() >= HOLD then
                self.rhylibHold = true
                vm:SetCycle(HOLD)
                vm:SetPlaybackRate(0)
            end
        elseif self.rhylibHold then
            self.rhylibHold = nil
            vm:SetPlaybackRate(1)
        end
    end

    -- The carrier's own muzzle flashes, shells and sounds stay off.
    function SWEP:FireAnimationEvent()
        if self:UsesCarrier() then return true end
    end


    env.offsetTransform = offsetTransform
    env.drawExtra = drawExtra
    env.carrierBone = carrierBone
end
