--[[
    Which body part a hit landed on, worked out from where it hit.

    Many player models give every hitbox the "generic" group, so traces
    can't tell a leg from a head. This guesses from the hit position
    relative to the player: height share of the hull (head, chest,
    stomach, legs) and which side of the body (arms, left/right leg).
    A few vector maths, no traces: cheap enough for every hit. Shared.

    Rhylib.HitGroupAt(ent, pos) -> a HITGROUP_ constant. pos is a world
    position on or near ent (e.g. a trace's HitPos). Share of the hull
    height: 84% and up = head; 50-84% = an arm if more than 9 units to
    the side, else chest (66% and up) or stomach; under 50% = left or
    right leg by side. A missing pos gives HITGROUP_GENERIC.
    Example: local group = Rhylib.HitGroupAt(tr.Entity, tr.HitPos)
]]

local HEAD, CHEST_AT, BODY_AT, ARM_SIDE = 0.84, 0.66, 0.5, 9

function Rhylib.HitGroupAt(ent, pos)
    if not IsValid(ent) or not pos or pos == vector_origin then return HITGROUP_GENERIC end
    local top = ent:OBBMaxs().z
    if top <= 1 then return HITGROUP_CHEST end
    local rel = pos - ent:GetPos()
    local h = rel.z / top
    local yaw = ent:IsPlayer() and ent:EyeAngles().y or ent:GetAngles().y
    local side = rel:Dot(Angle(0, yaw, 0):Right())   -- + right, - left
    if h >= HEAD then return HITGROUP_HEAD end
    if h >= BODY_AT then
        if math.abs(side) > ARM_SIDE then return side > 0 and HITGROUP_RIGHTARM or HITGROUP_LEFTARM end
        return h >= CHEST_AT and HITGROUP_CHEST or HITGROUP_STOMACH
    end
    return side > 0 and HITGROUP_RIGHTLEG or HITGROUP_LEFTLEG
end
