--[[
    First-person arms: everyone's hands model is config handsModel (a
    c_arms model), unless their DarkRP job sets handsModel = "...".
    An empty config keeps the player model's own hands.
    Realm: server. Config weapons "handsModel" (sh_00_config.lua).
    Example DarkRP job field: handsModel = "models/weapons/c_arms_combine.mdl"
]]

local Config = Rhylib.Config

Rhylib.Hook.Add("PlayerSetHandsModel", "weapons.hands", function(ply, ent)
    local job = RPExtraTeams and RPExtraTeams[ply:Team()]
    local mdl = (job and job.handsModel) or Config.Get("weapons", "handsModel")
    if not isstring(mdl) or mdl == "" then return end
    ent:SetModel(mdl)
    ent:SetSkin(0)
    ent:SetBodyGroups("0000000")
    return true
end)
