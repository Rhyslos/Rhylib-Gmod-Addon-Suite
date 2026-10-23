--[[
    Interaction wheel, item menus and the datapad tab (client).
      - A wanted target's body (NW2Bool rhylib_bountyBody on the ragdoll)
        gets E-wheel option "Collect proof" (anyone; timed on the server,
        bar here; Menus.WheelProgress). Bodies are flagged RhylibWheel
        here so rhylib_menus' wheel targets them.
      - Staff (rhylib.bounty.gm): NPCs get "Put a bounty on it" (reward and
        name prompts -> bounty.npc).
      - Items: the Bounty Puck's right-click menu has "Switch on / off" and
        "Track the next contract".
      - Datapad (rhylib_datapad D.AddTab): a "Bounties" tab with the board,
        and a warning when there's a price on your own head.
]]

local B = Rhylib.Bounty
local Net = Rhylib.Net

local function isStaff()
    local me = LocalPlayer()
    local A = Rhylib.Admin
    if A and A.Has then return A.Has(me, "rhylib.bounty.gm", "admin") end
    return me:IsAdmin()
end

-- Flag bodies (and, for staff, NPCs) as wheel targets every half second.
local flaggedNPCs = false
timer.Create("Rhylib.Bounty.WheelFlags", 0.5, 0, function()
    for _, e in ipairs(ents.FindByClass("prop_ragdoll")) do
        if e:GetNW2Bool("rhylib_bountyBody", false) then
            e.RhylibWheel = true
            e.rhylibBountyWheel = true
            local col = e:GetNW2Vector("rhylib_bountyCol", nil)
            if col and not e.GetPlayerColor then e.GetPlayerColor = function() return col end end
        elseif e.rhylibBountyWheel then
            e.RhylibWheel = nil
            e.rhylibBountyWheel = nil
        end
    end
    if not IsValid(LocalPlayer()) then return end
    local staff = isStaff()
    if not staff and not flaggedNPCs then return end
    flaggedNPCs = staff
    for _, e in ipairs(ents.GetAll()) do
        if e:IsNPC() or e:IsNextBot() then
            if staff and not e.RhylibWheel then
                e.RhylibWheel = true
                e.rhylibBountyNPC = true
            elseif not staff and e.rhylibBountyNPC then
                e.RhylibWheel = nil
                e.rhylibBountyNPC = nil
            end
        end
    end
end)

Rhylib.Hook.Add("Rhylib.WheelEntityOptions", "bounty.wheel", function(ent, me, add)
    if ent:GetNW2Bool("rhylib_bountyBody", false) then
        local name = ent:GetNW2String("rhylib_bountyName", "")
        local taken = ent:GetNW2Bool("rhylib_bountyTaken", false)
        add("Collect proof", function(t)
            Net.Start("bounty.collect")
            net.WriteEntity(t)
            net.SendToServer()
            local secs = tonumber(B.Cfg("collectTime")) or 5
            if B.Has(me, "bh_kit") then secs = secs * B.Mult("fieldKit") end
            if B.Has(me, "bh_finisher") then secs = secs * B.Mult("finisherCollect") end
            local M = Rhylib.Menus
            if M and M.WheelProgress then M.WheelProgress("Collecting proof: " .. name, secs) end
        end, { order = 10, sub = name ~= "" and name or nil, disabled = taken and "Already taken" or nil })
    end
    if ent.rhylibBountyNPC and isStaff() then
        add("Put a bounty on it", function(t)
            local K = Rhylib.Menus and Rhylib.Menus.Kit
            if not K then return end
            K.Prompt("Bounty on an NPC", "Reward (paid by the office)", "5000", function(r)
                local reward = math.floor(tonumber(r) or 0)
                if reward <= 0 then return end
                K.Prompt("Bounty on an NPC", "The name on the board", t.PrintName or t:GetClass(), function(name)
                    if not IsValid(t) then return end
                    Net.Start("bounty.npc")
                    net.WriteEntity(t)
                    net.WriteUInt(math.min(reward, 10000000), 32)
                    net.WriteString(string.sub(name, 1, 40))
                    net.SendToServer()
                end)
            end)
        end, { order = 90, sub = "Staff" })
    end
end)

-- The puck's item menu.
Rhylib.Hook.Add("Rhylib.ItemMenu", "bounty.puck", function(inst, menu)
    if inst.id ~= B.PUCK then return end
    local on = LocalPlayer():GetNW2Bool("rhylib_puckOn", false)
    menu:AddOption(on and "Switch the puck off" or "Switch the puck on", function()
        Net.Start("bounty.puck") net.WriteUInt(0, 2) net.SendToServer()
    end)
    menu:AddOption("Track the next contract", function()
        Net.Start("bounty.puck") net.WriteUInt(1, 2) net.SendToServer()
    end)
end)

--------------------------------------------------------------------------
-- Datapad tab
--------------------------------------------------------------------------

local function addDatapadTab()
    local D = Rhylib.Datapad
    if not (D and D.AddTab) then return end
    D.AddTab({
        id = "bounty", name = "Bounties", order = 60,
        has = function() return #B.board > 0 end,
        build = function(content, k)
            if not k then return end
            local s = k.S
            local mySid = LocalPlayer():SteamID64() or ""
            local sp = k.Scroll(content)
            sp:Dock(FILL)
            for _, b in ipairs(B.board) do
                if b.tsid == mySid then
                    local l = k.Label(sp, "There's a price on your head: " .. B.FormatMoney(b.reward) .. " (" .. (b.mode == "alive" and "alive" or (b.mode == "dead" and "dead" or "dead or alive")) .. ").", 15, 700, k.C.bad)
                    l:Dock(TOP)
                    l:DockMargin(0, 0, s(8), s(8))
                end
            end
            local h = k.Heading(sp, "Open bounties")
            h:Dock(TOP)
            h:DockMargin(0, 0, s(8), s(4))
            for _, b in ipairs(B.board) do
                local label = b.mode == "dead" and "Dead" or (b.mode == "alive" and "Alive" or "Dead or alive")
                local r = k.Row(sp, b.name .. "  —  " .. B.FormatMoney(b.reward), label .. "  ·  posted by " .. tostring(b.byName) .. (b.std and "  ·  standalone" or ""))
                r:Dock(TOP)
                r:DockMargin(0, 0, s(8), s(3))
                r.right:SetWide(0)
            end
        end,
    })
end
addDatapadTab()
Rhylib.Hook.Add("Rhylib.ModuleLoaded", "bounty.datapad", function(id) if id == "datapad" then addDatapadTab() end end)
Rhylib.Hook.Add("InitPostEntity", "bounty.datapad", addDatapadTab)
