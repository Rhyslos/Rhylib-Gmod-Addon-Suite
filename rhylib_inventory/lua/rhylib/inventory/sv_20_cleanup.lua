--[[
    Hotbar cleanup (server only). Anything in your hands that isn't an
    inventory item (the sandbox physgun, tool gun, HL2 weapons...) shows
    in an overflow hotbar slot; these commands strip those weapons.

    rhylib_cleanhotbar
        Strips every weapon you're holding that isn't in your inventory
        (the physgun, tool gun, HL2 weapons from the sandbox loadout, ...).
    rhylib_cleanhotbar auto
        Toggles doing that automatically every time you spawn, until you
        leave the server.

    Only affects your own weapons. Anyone may use it (no permission). The
    Stowed and hand weapons are never stripped.
]]

local Inv = Rhylib.Inventory
local Items = Rhylib.Items

local function inInventory(ply, class)
    local def = Items.defs[class]
    return def and def.weapon and Inv.Has(ply, class)
end

-- Inv.CleanHotbar(ply): strips every weapon ply holds that isn't an
-- inventory item they carry. Returns how many were removed.
function Inv.CleanHotbar(ply)
    local removed = 0
    for _, wep in ipairs(ply:GetWeapons()) do
        if IsValid(wep) and not inInventory(ply, wep:GetClass()) and wep:GetClass() ~= Inv.STOWED and wep:GetClass() ~= Inv.HAND then
            ply:StripWeapon(wep:GetClass())
            removed = removed + 1
        end
    end
    return removed
end

concommand.Add("rhylib_cleanhotbar", function(ply, _, args)
    if not IsValid(ply) then return end

    if args[1] == "auto" then
        ply.rhylibAutoClean = not ply.rhylibAutoClean
        ply:ChatPrint("Clean hotbar on spawn: " .. (ply.rhylibAutoClean and "on" or "off"))
        if not ply.rhylibAutoClean then return end
    end

    local n = Inv.CleanHotbar(ply)
    ply:ChatPrint("Removed " .. n .. " weapon" .. (n == 1 and "" or "s") .. " that weren't in your inventory.")
end)

-- Runs after the loadout and after inventory weapons are given back.
Rhylib.Hook.Add("PlayerSpawn", "inventory.autoclean", function(ply)
    if not ply.rhylibAutoClean then return end
    timer.Simple(0.1, function()
        if IsValid(ply) and ply:Alive() then Inv.CleanHotbar(ply) end
    end)
end)
