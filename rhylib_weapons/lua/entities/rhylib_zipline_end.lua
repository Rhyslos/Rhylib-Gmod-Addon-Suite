--[[
    The far end of a zipline, as something that can be shot: a small
    server-only box at the hook (or around the far post). It's created and
    removed by its rhylib_zipline (ENT:SetZip / ENT:OnRemove); any damage
    to it breaks that line (rhylib_zipline ENT:Break). Never sent to
    clients, never drawn, nobody bumps into it.

    Realm: shared file, server-only entity. Fields: ent.zip (its line),
    ent.post (true: a floor post, false: a wall hook).
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Zipline end"
ENT.Spawnable = false

local MODEL = "models/hunter/blocks/cube025x025x025.mdl"   -- (only for the engine; never drawn)
local HOOK_BOX = Vector(5, 5, 5)
local POST_MINS, POST_MAXS = Vector(-3, -3, 0), Vector(3, 3, 88)

function ENT:Initialize()
    self:SetModel(MODEL)
    self:SetNoDraw(true)
    if SERVER then
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_BBOX)
        if self.post then
            self:SetCollisionBounds(POST_MINS, POST_MAXS)
        else
            self:SetCollisionBounds(-HOOK_BOX, HOOK_BOX)
        end
        self:SetCollisionGroup(COLLISION_GROUP_WEAPON)  -- shots hit it, players walk through
    end
end

function ENT:UpdateTransmitState()
    return TRANSMIT_NEVER
end

if SERVER then
    function ENT:OnTakeDamage(dmg)
        if dmg:GetDamage() > 0 and IsValid(self.zip) then self.zip:Break() end
    end
end
