--[[
    Medical staff commands and answers for rhylib_admin (shared: the staff
    menu needs the list; the server runs them). Registered with
    Rhylib.Admin.AddCommand once rhylib_admin is there (Rhylib.After);
    without rhylib_admin they don't exist.

      !infect [player] <viral|bacterial|poison> [load 1-100, 40]
      !cure [player]
    Hooks answered (server):
      Rhylib.AdminRevive(target, caller)   !revive on a downed player
      Rhylib.AdminHeal(target, caller)     !heal: up, injuries cleared, cured
      Rhylib.KeepNoTarget(ply)             downed players keep FL_NOTARGET
                                           (setting noTarget) when staff
                                           turn !notarget off
    Client: the staff menu's pickers for illness / illload (Admin.ArgChoices).
]]

local Med = Rhylib.Medical

local function name(p) return IsValid(p) and p:Nick() or "Console" end
local function you(caller, t) return caller == t and "themselves" or name(t) end

local function infect(caller, t, a)
    if Med.Simple and Med.Simple() then return nil, "The simplified medical system is on: no illnesses" end
    local k = Med.ILL_BY_ID[string.lower(tostring(a and a.kind or ""))]
    if not k then return nil, "Kind: viral, bacterial or poison" end
    local load = math.Clamp(math.floor(tonumber(a and a.load) or 40), 1, 100)
    Med.Infect(t, k, load)
    return name(caller) .. " infected " .. you(caller, t) .. " (" .. Med.ILL[k].id .. ", " .. load .. ")"
end

local function cure(caller, t)
    Med.Cure(t)
    return name(caller) .. " cured " .. you(caller, t)
end

local function register()
    local A = Rhylib.Admin
    if not (A and A.AddCommand) then return end
    A.NumberKinds = A.NumberKinds or {}
    A.NumberKinds.illload = true
    A.AddCommand({ id = "infect", name = "Infect (illness)", cat = "Powers", mass = true, target = "self",
        args = { { "kind", "Kind", "illness" }, { "load", "Strength 1-100", "illload", opt = true, def = 40 } },
        desc = "Gives them an illness for medics to find and treat" }, SERVER and infect, { "player", "Health" })
    A.AddCommand({ id = "cure", name = "Cure illness", cat = "Powers", mass = true, target = "self", args = {}, desc = "Takes an illness away" },
        SERVER and cure, { "player", "Health" })
    if CLIENT then
        A.ArgChoices = A.ArgChoices or {}
        A.ArgChoices.illness = function() return { { "viral", "Viral" }, { "bacterial", "Bacterial" }, { "poison", "Poison" } } end
        A.ArgChoices.illload = function() return { { "20", "Light (20)" }, { "45", "Moderate (45)" }, { "75", "Severe (75)" }, { "?", "Other..." } } end
    end
end
Rhylib.After("admin", register)

if SERVER then
    Rhylib.Hook.Add("Rhylib.AdminRevive", "medical.admin", function(t, caller)
        if Med.IsDown(t) then
            Med.Revive(t, t:GetMaxHealth(), caller)
            return true
        end
    end)
    Rhylib.Hook.Add("Rhylib.AdminHeal", "medical.admin", function(t, caller)
        if Med.IsDown(t) then Med.Revive(t, t:GetMaxHealth(), caller) end
        if Med.ClearInjuries then Med.ClearInjuries(t) end
        if Med.Cure then Med.Cure(t) end
    end)
    Rhylib.Hook.Add("Rhylib.KeepNoTarget", "medical.admin", function(ply)
        if Med.IsDown(ply) and Med.Cfg("noTarget") then return true end
    end)
end
