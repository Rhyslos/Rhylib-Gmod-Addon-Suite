--[[
    The Q (spawn) menu is off (owner): the Q key (+menu) is Mark target
    instead (hook Rhylib.MarkKey, rhylib_skills). Staff open it from the
    toolgun (R twice; one R opens our spawn window, cl_85_spawn.lua):
    Menus.OpenSpawnMenu(). Pressing Q
    while it's open closes it.
]]

local Menus = Rhylib.Menus

Menus.spawnAllowed = false

local function spawnOpen()
    return IsValid(g_SpawnMenu) and g_SpawnMenu:IsVisible()
end

function Menus.SpawnMenuOpen() return spawnOpen() end

-- Through the gamemode's own open/close (menubar, hooks).
function Menus.OpenSpawnMenu()
    Menus.spawnAllowed = true
    hook.Run("OnSpawnMenuOpen")
end

function Menus.CloseSpawnMenu()
    if IsValid(g_SpawnMenu) then g_SpawnMenu.m_bHangOpen = false end   -- (else Close only clears that)
    hook.Run("OnSpawnMenuClose")
    Menus.spawnAllowed = false
end

-- Opening the normal way (Q, +menu from anywhere) is refused.
Rhylib.Hook.Add("SpawnMenuOpen", "menus.nospawnmenu", function()
    if not Menus.spawnAllowed then return false end
end, -100)

Rhylib.Hook.Add("OnSpawnMenuClose", "menus.nospawnmenu", function()
    Menus.spawnAllowed = false
end)

Rhylib.Hook.Add("PlayerBindPress", "menus.qkey", function(ply, bind, pressed)
    if bind ~= "+menu" and bind ~= "-menu" then return end
    if pressed and bind == "+menu" then
        if spawnOpen() then
            Menus.CloseSpawnMenu()
        else
            hook.Run("Rhylib.MarkKey")
        end
    end
    return true
end, -100)

Rhylib.Hook.Add("InitPostEntity", "menus.qkey", function()
    if Menus.AddControl then
        Menus.AddControl("Combat", "{+menu}", "Mark target (Officer skill; the spawn menu is off, staff open it from the toolgun)")
    end
end)
