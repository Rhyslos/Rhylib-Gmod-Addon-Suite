--[[
    Client side of the lying ragdolls (sh_60_lying.lua): your own ragdoll
    isn't drawn in first person, ragdolls show their player's colour, and
    the engine's death ragdoll is hidden when the server ragdoll is the
    corpse.
]]

local L = Rhylib.Lying

-- Set up each lying ragdoll once (checked a few times a second).
timer.Create("Rhylib.Lying", 0.25, 0, function()
    for _, rag in ipairs(ents.FindByClass("prop_ragdoll")) do
        if not rag.rhylibSetUp then
            local owner = L.Owner(rag)
            if owner then
                rag.rhylibSetUp = true
                rag.GetPlayerColor = function() return IsValid(owner) and owner:GetPlayerColor() or Vector(1, 1, 1) end
                rag.RenderOverride = function(self, flags)
                    local me = LocalPlayer()
                    if owner == me and IsValid(me) and not me:ShouldDrawLocalPlayer() and L.Ragdoll(me) == self then return end
                    -- (your own corpse while the death camera sits in it, cl_65_bodycam.lua)
                    if L.BodyCamOn and L.BodyCamOn() and IsValid(me) and me:GetNW2Entity("rhylib_corpse") == self then return end
                    self:DrawModel(flags)
                end
            end
        end
    end
end)

-- Died lying: the server ragdoll is the body; hide the engine's one.
Rhylib.Hook.Add("CreateClientsideRagdoll", "core.lying", function(ent, rag)
    if IsValid(ent) and ent:IsPlayer() and ent:GetNW2Bool("rhylib_ragCorpse") then rag:SetNoDraw(true) end
end)

Rhylib.Hook.Add("Think", "core.lying.corpse", function()
    for _, ply in ipairs(player.GetAll()) do
        if not ply:Alive() and ply:GetNW2Bool("rhylib_ragCorpse") then
            local r = ply:GetRagdollEntity()
            if IsValid(r) and not r:GetNoDraw() then r:SetNoDraw(true) end
        end
    end
end)
