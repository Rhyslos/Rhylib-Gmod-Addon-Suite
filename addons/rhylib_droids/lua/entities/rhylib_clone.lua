--[[
    Clone trooper NPC (2026-10-06az, owner: Cody needs reinforcements): the
    droid NextBot (rhylib_b1) on the Republic side. Same brain: moves and
    fires together, takes cover, aims with the same rules. Differences
    (all in rhylib_b1.lua / sv_10_droids.lua, keyed on IsRhylibClone):
      - targets droids (not training droids); droids target clones too
      - players and clones never hurt each other, and bolts fly through
        friendlies (rhylib_weapons)
      - troopers throw droid poppers (no stun on players)
      - medics heal players and clones near them; a clone commander
        boosts clones like a B1 commander boosts droids, and so does a
        player with the Reinforcements skill
      - "follow" mode: reinforcements stay with the officer who called them
    Kinds ct_trooper / ct_rifleman / ct_heavy / ct_medic / ct_commander
    (rhylib_droids sh_00_config.lua). Base class only: spawn the subclasses.
    A new clone kind: a D.KINDS row with side = "republic", a D.CLASSES
    entry, and a one-line file with ENT.Base = "rhylib_clone".
    Shared entity; this file only adds the medic ring (client).
]]


AddCSLuaFile()

ENT.Base = "rhylib_b1"
ENT.Type = "nextbot"
ENT.PrintName = "Clone trooper"
ENT.Category = "Rhylib: Clone troopers"
ENT.Spawnable = false
ENT.AdminOnly = true
ENT.IsRhylibDroid = false
ENT.IsRhylibClone = true
ENT.DroidKind = "ct_trooper"
ENT.RenderGroup = RENDERGROUP_BOTH

if CLIENT then
    local RING = Material("effects/select_ring")
    local GREEN = Color(90, 230, 120)

    -- Medics: a faint green ring showing where they heal.
    function ENT:DrawTranslucent()
        if not self:Kind().medic or self:Health() <= 0 then return end
        local pos = self:GetPos()
        if pos:DistToSqr(EyePos()) > 1500 * 1500 then return end
        local D = Rhylib.Droids
        local r = (D and D.Cfg("ctMedicRadius")) or 300
        local a = 18 + 10 * math.sin(CurTime() * 2)
        render.SetMaterial(RING)
        render.DrawQuadEasy(pos + Vector(0, 0, 3), Vector(0, 0, 1), r * 2, r * 2, ColorAlpha(GREEN, a), 0)
    end
end
