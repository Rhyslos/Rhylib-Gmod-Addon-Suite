--[[
    First-person arms: everyone's hands model is config handsModel (a
    c_arms model), unless their DarkRP job sets handsModel = "...".
    An empty config keeps the player model's own hands.
    Realm: server. Config weapons "handsModel" (sh_00_config.lua).
    Example DarkRP job field: handsModel = "models/weapons/c_arms_combine.mdl"
    and, for a job with several player models, handsByModel =
    { ["models/a.mdl"] = "models/a_arms.mdl" } (that model's arms; others
    use handsModel). Staff > Jobs edits leave handsByModel as it is.
]]

local Config = Rhylib.Config

Rhylib.Hook.Add("PlayerSetHandsModel", "weapons.hands", function(ply, ent)
    local job = RPExtraTeams and RPExtraTeams[ply:Team()]
    local mdl = (job and job.handsModel) or Config.Get("weapons", "handsModel")
    -- (a job with several player models: handsByModel[model] for that one)
    local by = job and job.handsByModel
    if istable(by) then
        local pm = string.lower(ply:GetModel() or "")
        for k, v in pairs(by) do
            if isstring(k) and string.lower(k) == pm and isstring(v) then mdl = v end
        end
    end
    if not isstring(mdl) or mdl == "" then return end
    ent:SetModel(mdl)
    ent:SetSkin(0)
    ent:SetBodyGroups("0000000")
    return true
end)
