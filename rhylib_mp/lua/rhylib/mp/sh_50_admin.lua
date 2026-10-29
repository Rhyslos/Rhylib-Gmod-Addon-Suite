--[[
    Military police staff commands for rhylib_admin (shared: the staff menu
    needs the list; the server runs them). Registered with
    Rhylib.Admin.AddCommand once rhylib_admin is there (Rhylib.After), so
    without rhylib_admin they simply don't exist.

      !jail <player> <minutes> [reason]   into a jail cell; items to evidence
      !unjail <player>                    released and processed at once
      !free [player]  (!uncuff, !unstun)  uncuff / end a stun
      !hidecells                          jail cell rings hidden / shown for
                                          everyone (Global2Bool rhylib_hideCells,
                                          saved in Data "admin" "hideCells")
    Also adds the jail line to !info (hook Rhylib.AdminInfo).
]]

local MP = Rhylib.MP

local function name(p) return IsValid(p) and p:Nick() or "Console" end
local function you(caller, t) return caller == t and "themselves" or name(t) end

local function register()
    local A = Rhylib.Admin
    if not (A and A.AddCommand) then return end

    A.AddCommand({ id = "jail", name = "Jail", cat = "Discipline", target = "player",
        args = { { "minutes", "Minutes", "minutes" }, { "reason", "Reason", "text" } }, desc = "Into a jail cell; items go to evidence" },
        SERVER and function(caller, t, a)
            if MP.IsJailed(t) then return nil, name(t) .. " is already jailed" end
            local minutes = math.floor(a.minutes)
            if minutes < 1 then return nil, "At least 1 minute" end
            local ok, err = MP.Jail(t, caller, minutes, a.reason or "")
            if not ok then return nil, err or ("Couldn't jail " .. name(t)) end
            return name(caller) .. " jailed " .. name(t) .. " for " .. A.FormatMinutes(math.min(minutes, MP.Cfg("maxSentence")))
                .. (a.reason ~= "" and (" (" .. a.reason .. ")") or "")
        end, { "player", "Restrain" })

    A.AddCommand({ id = "unjail", name = "Release from jail", cat = "Discipline", target = "player", args = {} },
        SERVER and function(caller, t)
            if not MP.IsJailed(t) then return nil, name(t) .. " isn't jailed" end
            -- (admins skip the wait: processed straight away)
            if MP.Process then MP.Process(t, caller) else MP.Release(t, caller) end
            return name(caller) .. " released " .. name(t) .. " from jail"
        end, { "player", "Restrain" })

    A.AddCommand({ id = "free", name = "Uncuff / unstun", cat = "Discipline", mass = true, target = "self", args = {}, aliases = { "uncuff", "unstun" } },
        SERVER and function(caller, t)
            local did = false
            if MP.IsCuffed(t) then MP.Uncuff(t, caller) did = true end
            if MP.IsStunned(t) and MP.EndStun then MP.EndStun(t) did = true end
            if not did then return nil, name(t) .. " isn't cuffed or stunned" end
            return name(caller) .. " freed " .. you(caller, t)
        end, { "player", "Restrain" })

    A.AddCommand({ id = "hidecells", name = "Show / hide jail cells", cat = "Server", args = {}, desc = "Hides the jail cell rings for everyone (again to show them)" },
        SERVER and function(caller)
            local hide = not GetGlobal2Bool("rhylib_hideCells", false)
            SetGlobal2Bool("rhylib_hideCells", hide)
            Rhylib.Data.Set("admin", "hideCells", hide and 1 or 0)
            return name(caller) .. (hide and " hid the jail cells" or " showed the jail cells")
        end, { "server", "Cleanup" })
end
Rhylib.After("admin", register)

if SERVER then
    Rhylib.Hook.Add("InitPostEntity", "mp.hidecells", function()
        SetGlobal2Bool("rhylib_hideCells", Rhylib.Data.Get("admin", "hideCells") == 1)
    end)
    Rhylib.Hook.Add("Rhylib.AdminInfo", "mp.info", function(t, sid, add)
        if IsValid(t) and MP.IsJailed(t) then add("In jail: " .. math.ceil(MP.JailLeft(t) / 60) .. " min left") end
    end)
end
