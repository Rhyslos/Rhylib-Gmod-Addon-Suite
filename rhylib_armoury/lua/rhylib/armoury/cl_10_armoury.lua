--[[
    Armoury, client side: the "claim this locker?" question, and the
    owner's Lock / Unclaim buttons in the locker window (the inventory
    window raises Rhylib.StorageControl when they're pressed).

    Nets: rhylib.armoury.prompt (server -> client, Entity: the free locker)
    opens the claim question; Claim sends rhylib.armoury.claim (Entity).
    rhylib.armoury.control (client -> server, 1 bit: 0 = lock / unlock,
    1 = unclaim) for the owner's buttons.
]]

net.Receive(Rhylib.Net.Name("armoury.prompt"), function()
    local ent = net.ReadEntity()
    if not IsValid(ent) then return end
    Derma_Query(
        "Claim this locker? It becomes yours (one per player) and starts locked. What you store in it is saved.",
        "Personal locker",
        "Claim", function()
            Rhylib.Net.Start("armoury.claim")
            net.WriteEntity(ent)
            net.SendToServer()
        end,
        "Cancel"
    )
end)

local function send(action)
    Rhylib.Net.Start("armoury.control")
    net.WriteUInt(action, 1)
    net.SendToServer()
end

Rhylib.Hook.Add("Rhylib.StorageControl", "armoury.control", function(action)
    if action ~= "unclaim" then
        send(0)
        return
    end
    Derma_Query(
        "Give up this locker? Your items stay saved and will be in the next locker you claim.",
        "Unclaim locker",
        "Unclaim", function() send(1) end,
        "Cancel"
    )
end)
