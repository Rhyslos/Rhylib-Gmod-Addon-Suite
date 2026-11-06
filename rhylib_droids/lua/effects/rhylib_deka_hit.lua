--[[
    A bolt stopped on a droideka's shield (entities/rhylib_droideka.lua,
    ENT:BoltShield): sparks where it hit, and a flash on the bubble
    (ENT:ShieldHit, drawn by the droideka).
    EffectData: Origin (the spot on the bubble), Normal (outward), Entity
    (the droideka). Client only (effects are sent to clients by GMod).
]]

function EFFECT:Init(data)
    local pos = data:GetOrigin()
    local ent = data:GetEntity()
    if IsValid(ent) and ent.ShieldHit then ent:ShieldHit(pos) end
    local fx = EffectData()
    fx:SetOrigin(pos)
    fx:SetNormal(data:GetNormal())
    fx:SetMagnitude(1)
    fx:SetScale(1)
    fx:SetRadius(2)
    util.Effect("MetalSpark", fx)
end

function EFFECT:Think() return false end

function EFFECT:Render() end
