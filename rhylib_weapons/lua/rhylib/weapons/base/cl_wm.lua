--[[
    Weapon base, client: third person (rhylib_base includes this; it
    returns function(SWEP, env)). The holder's WorldBoneMods, the prop in
    the right hand (PropWMPos / PropWMAng / PropScale), ExtraProps on a
    player bone or attachment (wmBone / wmAttach / wmAnchor "body"), the
    left-hand gun in "dual" mode, and OnRemove (every ClientsideModel the
    weapon made, from env.Track).
    No per-frame string building or matrices: bone / attachment ids are
    cached per (player model, extra entry) and two module matrices are
    reused (drawExtra reads them at once).
]]

return function(SWEP, env)
    local offsetTransform, drawExtra = env.offsetTransform, env.drawExtra

    -- WorldBoneMods: the holder's own bones, client side, for everyone who
    -- draws them (not while lowered); undone when they switch away.
    Rhylib.Hook.Add("PrePlayerDraw", "weapons.worldbonemods", function(ply)
        local w = ply:GetActiveWeapon()
        local mods = IsValid(w) and w.WorldBoneMods
        if mods and w.IsLowered and w:IsLowered() then mods = nil end
        local had = ply.rhylibWorldMods
        if not mods and not had then return end
        if had and had ~= mods then
            for b in pairs(ply.rhylibWorldModBones or {}) do ply:ManipulateBoneAngles(b, angle_zero) end
            ply.rhylibWorldMods, ply.rhylibWorldModBones = nil, nil
        end
        if not mods then return end
        local bones = {}
        for name, a in pairs(mods) do
            local b = ply:LookupBone(name)
            if b then
                ply:ManipulateBoneAngles(b, a)
                bones[b] = true
            end
        end
        ply.rhylibWorldMods, ply.rhylibWorldModBones = mods, bones
    end)

    -- Bone ids per player model (false = the model hasn't it).
    local rightHand, leftHand = {}, {}
    -- Per extra entry, per player model: { bone = id|false, att = id|false|nil }.
    local extraIds = setmetatable({}, { __mode = "k" })
    local ATT_M, BODY_M = Matrix(), Matrix()
    local BODY_A = Angle()

    local function boneId(cache, owner, mdl, name)
        local b = cache[mdl]
        if b == nil then
            b = owner:LookupBone(name) or false
            cache[mdl] = b
        end
        return b
    end

    local function idsFor(e, owner, mdl)
        local per = extraIds[e]
        if not per then
            per = {}
            extraIds[e] = per
        end
        local ids = per[mdl]
        if not ids then
            ids = { bone = e.wmBone and owner:LookupBone(e.wmBone) or false }
            if e.wmAttach then
                local ai = owner:LookupAttachment(e.wmAttach) or 0
                ids.att = ai > 0 and ai or false
            end
            per[mdl] = ids
        end
        return ids
    end

    function SWEP:DrawWorldModel(flags)
        local owner = self:GetOwner()
        -- (admin cloak: others don't see the gun float, rhylib_admin)
        if IsValid(owner) and owner ~= LocalPlayer() and owner:GetNW2Bool(Rhylib.NW.CLOAK, false) then return end
        if not self.PropModel or not IsValid(owner) then
            self:DrawModel(flags)
            return
        end

        local mdl = owner:GetModel() or ""
        local bone = boneId(rightHand, owner, mdl, "ValveBiped.Bip01_R_Hand")
        local matrix = bone and owner:GetBoneMatrix(bone)
        local ent = self:GetPropEntity("propWM")
        if not matrix or not ent then return end

        local pos, ang = offsetTransform(matrix:GetTranslation(), matrix:GetAngles(), self.PropWMPos, self.PropWMAng)
        ent:SetPos(pos)
        ent:SetAngles(ang)
        ent:SetupBones()
        ent:DrawModel()
        self.propMuzzleWM = ent:LocalToWorld(self.PropMuzzle)

        local extras = self.ExtraProps
        if extras then
            for _, e in ipairs(extras) do
                local ids = idsFor(e, owner, mdl)
                local em
                -- (wmAttach: a player model attachment, e.g. "anim_attachment_LH",
                -- so the prop is held by the hand through every animation; falls
                -- back to wmBone on models without it)
                if ids.att then
                    local at = owner:GetAttachment(ids.att)
                    if at then
                        ATT_M:SetTranslation(at.Pos)
                        ATT_M:SetAngles(at.Ang)
                        em = ATT_M
                    end
                end
                em = em or (ids.bone and owner:GetBoneMatrix(ids.bone))
                if em and not e.wmAttach and e.wmAnchor == "body" then
                    -- (at the bone, but turned with the body: x ahead, y right,
                    -- z up of where the player faces; stays upright)
                    BODY_M:SetTranslation(em:GetTranslation())
                    BODY_A:SetUnpacked(0, owner:EyeAngles().y, 0)
                    BODY_M:SetAngles(BODY_A)
                    em = BODY_M
                end
                local ee = em and self:GetExtraEntity(e, "wm")
                if ee then drawExtra(self, ee, em, e.wmPos, e.wmAng, e.wmScale) end
            end
        end

        -- "dual" mode: the second gun in the left hand.
        if self.DualPropWMPos and self:GetFireModeName() == "dual" then
            local lb = boneId(leftHand, owner, mdl, "ValveBiped.Bip01_L_Hand")
            local lm = lb and owner:GetBoneMatrix(lb)
            local le = lm and self:GetPropEntity("propWML")
            if le then
                local lp, la = offsetTransform(lm:GetTranslation(), lm:GetAngles(), self.DualPropWMPos, self.DualPropWMAng)
                le:SetPos(lp)
                le:SetAngles(la)
                le:SetupBones()
                le:DrawModel()
                self.propMuzzleWML = le:LocalToWorld(self.PropMuzzle)
            end
        end
    end

    -- Every ClientsideModel this weapon made (props, extras, proxies,
    -- mirrored hands: env.Track), in one pass.
    function SWEP:OnRemove()
        for _, x in ipairs(self.rhylibCSEnts or {}) do
            if IsValid(x) then x:Remove() end
        end
        self.rhylibCSEnts = nil
    end
end
