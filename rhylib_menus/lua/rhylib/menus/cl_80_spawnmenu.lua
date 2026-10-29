--[[
    The Q (spawn) menu is off: the Q key (+menu) is Mark target
    instead (hook Rhylib.MarkKey, rhylib_skills). Staff open it from the
    toolgun (R twice; one R opens our spawn window, cl_85_spawn.lua):
    Menus.OpenSpawnMenu(). Pressing Q
    while it's open closes it.

    Without the toolgun (so gamemasters still have a way to spawn):
      - console command `rhylib_spawnmenu` (staff, Menus.MaySpawn) opens
        the spawn window (cl_85_spawn.lua) when rhylib_toolgun is installed
        (its picks spawn with the toolgun), else the normal Q menu; the
        Staff > Commands page has a "Spawn menu" button for it. The window
        itself grants nothing: every spawn is checked on the server
        (toolgun permissions, sandbox's PlayerSpawn* hooks).
      - with rhylib_toolgun not installed, staff's Q opens the normal Q
        menu again (held, like sandbox); everyone else keeps Mark target.

    Client only, so it hides the menu but doesn't take spawn rights away:
    gm_spawn and the other sandbox commands still work for players the
    server lets spawn. Adds Menus.spawnAllowed, Menus.SpawnMenuOpen,
    Menus.OpenSpawnMenu, Menus.CloseSpawnMenu, Menus.MaySpawn. Hooks:
    SpawnMenuOpen and PlayerBindPress at -100; fires Rhylib.MarkKey (no
    arguments) on Q.
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

-- Menus.MaySpawn(): staff (Menus.IsStaff) or rhylib_admin's "spawn"
-- power. Only decides what the client shows; the server checks spawns.
function Menus.MaySpawn()
    local me = LocalPlayer()
    if not IsValid(me) then return false end
    if Menus.IsStaff and Menus.IsStaff() then return true end
    local A = Rhylib.Admin
    return A ~= nil and A.Has ~= nil and A.Has(me, "spawn") and true or false
end

local function hasToolgun()
    return Rhylib.Tool ~= nil and weapons.GetStored("rhylib_toolgun") ~= nil
end

concommand.Add("rhylib_spawnmenu", function()
    if not Menus.MaySpawn() then
        Rhylib.Notify(nil, "The spawn menu is for staff", "bad", "Menus")
        return
    end
    local SP = Menus.Spawn
    if hasToolgun() and SP and SP.Open then
        if SP.IsOpen() then SP.Close() else SP.Open() end
    elseif spawnOpen() then
        Menus.CloseSpawnMenu()
    else
        Menus.OpenSpawnMenu()
    end
end, nil, "Staff: open the spawn window (the old Q menu without the toolgun)")

if Menus.AddCommand then   -- (cl_30_commands.lua, loaded before this file)
    Menus.AddCommand("Server", {
        id = "spawnmenu", order = 5,
        title = "Spawn menu", desc = "Open the spawn window without the toolgun (console: rhylib_spawnmenu)",
        run = function() RunConsoleCommand("rhylib_spawnmenu") end,
    })
end

Rhylib.Hook.Add("PlayerBindPress", "menus.qkey", function(ply, bind, pressed)
    if bind ~= "+menu" and bind ~= "-menu" then return end
    -- No toolgun addon: staff hold Q for the normal Q menu, like sandbox.
    if not hasToolgun() and Menus.MaySpawn() then
        if pressed and bind == "+menu" then Menus.spawnAllowed = true end
        return
    end
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
        Menus.AddControl("Combat", "{+menu}", "Mark target (Officer skill; the spawn menu is off, staff open it from the toolgun or Staff > Commands > Spawn menu)")
    end
end)
