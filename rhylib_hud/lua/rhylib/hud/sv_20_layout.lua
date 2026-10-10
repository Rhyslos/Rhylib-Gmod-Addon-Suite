--[[
    The server's default first-person HUD layout (server). Players can
    pick their own in the pause menu's settings (client convar
    rhylib_hud_firstperson, sh_00_config.lua); this is what they get
    when they haven't.
        rhylib_hud_layout            shows the current one and the choices
                                     (anyone may ask)
        rhylib_hud_layout <name>     switches (f5, f4, thirdperson);
                                     needs perm rhylib.hud.layout (admin)
    Works from the server console too (no player = console). The choice
    is saved in Data "hud" / "layout", so it survives restarts, and sent
    to clients as the Global2String "rhylib_hud_layout".
]]

local HUD = Rhylib.HUD

Rhylib.Perms.Register("rhylib.hud.layout", "admin", "Pick the first-person HUD layout with rhylib_hud_layout")

-- Load the saved choice at file load (unknown names are ignored).
local saved = Rhylib.Data.Get("hud", "layout")
if saved and HUD.Layouts[saved] then SetGlobal2String("rhylib_hud_layout", saved) end

local function reply(ply, msg)
    if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
end

concommand.Add("rhylib_hud_layout", function(ply, _, args)
    local name = string.lower(args[1] or "")
    if name == "" then
        local names = {}
        for k in pairs(HUD.Layouts) do names[#names + 1] = k end
        table.sort(names)
        reply(ply, "Default HUD layout: " .. HUD.ServerLayout() .. " (choices: " .. table.concat(names, ", ") .. ")")
        return
    end
    Rhylib.Perms.Check(ply, "rhylib.hud.layout", function(ok)
        if not ok then
            reply(ply, "You don't have permission for rhylib_hud_layout")
            return
        end
        if not HUD.Layouts[name] then
            reply(ply, "Unknown layout '" .. name .. "'")
            return
        end
        SetGlobal2String("rhylib_hud_layout", name)
        Rhylib.Data.Set("hud", "layout", name)
        reply(ply, "Default HUD layout set to " .. name .. ": " .. HUD.Layouts[name])
    end)
end)
