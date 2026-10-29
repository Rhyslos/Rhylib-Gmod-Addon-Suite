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

local function reply(ply, msg, kind)
    Rhylib.Notify(IsValid(ply) and ply or nil, msg, kind or "info", "HUD")
end

-- rhylib_hud_layout [name]: no name = show the default and the choices
-- (anyone); a name sets it (perm rhylib.hud.layout).
Rhylib.Command.Add({
    name = "rhylib_hud_layout",
    args = "[layout]",
    help = "Show or set the server's default first-person HUD layout",
    tag = "HUD",
    fn = function(ply, args)
        local name = string.lower(args[1] or "")
        if name == "" then
            local names = {}
            for k in pairs(HUD.Layouts) do names[#names + 1] = k end
            table.sort(names)
            return "Default HUD layout: " .. HUD.ServerLayout() .. " (choices: " .. table.concat(names, ", ") .. ")"
        end
        Rhylib.Perms.Check(ply, "rhylib.hud.layout", function(ok)
            if not ok then return reply(ply, "You don't have permission for rhylib_hud_layout", "bad") end
            if not HUD.Layouts[name] then return reply(ply, "Unknown layout '" .. name .. "'", "bad") end
            SetGlobal2String("rhylib_hud_layout", name)
            Rhylib.Data.Set("hud", "layout", name)
            reply(ply, "Default HUD layout set to " .. name .. ": " .. HUD.Layouts[name], "good")
        end)
    end,
})
