--[[
    F4 menu (DarkRP), as pages of the pause menu: F4 opens the pause menu
    on Jobs (a fresh F4 press closes it). Replaces DarkRP's own F4 menu.
      Jobs       jobs by category; pick one to see its model, description
                 and weapons, then become it (or start a vote).
      Shop       entities, shipments, single weapons, ammo and vehicles you
                 can buy as your current job.
      Character  money, salary, job, and money / name / door commands.

    Everything runs DarkRP's own console commands ("darkrp <command>"),
    so DarkRP checks money, limits and jobs on the server as usual.
    Without DarkRP, F4 does what it did before.
]]

local Menus = Rhylib.Menus
local K = Menus.Kit
local C = K.C

local function isDarkRP() return DarkRP ~= nil and RPExtraTeams ~= nil end

local function money(n)
    if DarkRP and DarkRP.formatMoney then return DarkRP.formatMoney(n or 0) end
    return "$" .. tostring(n or 0)
end

local function myMoney()
    local ply = LocalPlayer()
    return ply.getDarkRPVar and (ply:getDarkRPVar("money") or 0) or 0
end

local function canAfford(price)
    local ply = LocalPlayer()
    if ply.canAfford then return ply:canAfford(price) end
    return myMoney() >= (price or 0)
end

local function categories(kind)
    if not (DarkRP and DarkRP.getCategories) then return {} end
    return DarkRP.getCategories()[kind] or {}
end

-- A server's customCheck can error on the client; treat that as "no".
local function check(fn, ...)
    local ok, res = pcall(fn, ...)
    return ok and res
end

-- Can the local player see / use this shop item as their job?
local function allowedItem(item)
    local ply = LocalPlayer()
    if item.allowed and istable(item.allowed) and #item.allowed > 0 and not table.HasValue(item.allowed, ply:Team()) then return false end
    if item.customCheck and not check(item.customCheck, ply) then return false end
    return true
end

-- How many can do this job, for display (0 = no limit). A max below 1 is
-- a share of the players.
local function jobLimit(job)
    local max = job.max or 0
    if max > 0 and max % 1 ~= 0 then return math.floor(player.GetCount() * max) end
    return max
end

-- Full, the way DarkRP decides it on the server.
local function jobFull(job, n)
    local max = job.max or 0
    if max == 0 then return false end
    if max % 1 == 0 then return n >= max end
    return (n + 1) / math.max(1, player.GetCount()) > max
end

local function jobBlockedNow(job, n)
    local ply = LocalPlayer()
    if ply:Team() == job.team then return "Your current job" end
    if jobFull(job, n) then return "Full" end
    if job.NeedToChangeFrom then
        local from = istable(job.NeedToChangeFrom) and job.NeedToChangeFrom or { job.NeedToChangeFrom }
        if not table.HasValue(from, ply:Team()) then return "Needs another job first" end
    end
    if job.customCheck and not check(job.customCheck, ply) then
        local msg = job.CustomCheckFailMsg
        if isfunction(msg) then msg = check(msg, ply, job) end
        return isstring(msg) and msg or "Not available to you"
    end
    if job.admin == 1 and not ply:IsAdmin() then return "Admins only" end
    if job.admin and job.admin > 1 and not ply:IsSuperAdmin() then return "Superadmins only" end
    return nil
end

-- Per job: players in it and why it's blocked, refreshed twice a second
-- (not every frame; the job list paints many of these).
local jobCache, jobCacheTime = {}, 0
local function jobState(job)
    if RealTime() - jobCacheTime > 0.5 then
        jobCache, jobCacheTime = {}, RealTime()
    end
    local st = jobCache[job]
    if not st then
        local n = team.NumPlayers(job.team)
        st = { count = n, limit = jobLimit(job), full = jobFull(job, n), blocked = jobBlockedNow(job, n) }
        jobCache[job] = st
    end
    return st
end
local function jobBlocked(job) return jobState(job).blocked end

local function needsVote(job)
    return job.vote or (job.RequiresVote and check(job.RequiresVote, LocalPlayer(), job.team))
end

local function becomeJob(job)
    RunConsoleCommand("darkrp", (needsVote(job) and "vote" or "") .. job.command)
end

local function firstModel(job)
    local m = job.model
    if istable(m) then return m[1], m end
    return m, nil
end

--------------------------------------------------------------------------
-- Jobs tab
--------------------------------------------------------------------------

local function buildJobs(body, frame)
    local s = K.S
    local left = K.Scroll(body)
    left:Dock(LEFT)
    left:SetWide(s(420))

    local detail = vgui.Create("DPanel", body)
    detail:Dock(FILL)
    detail:DockMargin(s(12), 0, 0, 0)
    detail:DockPadding(s(16), s(16), s(16), s(16))
    function detail:Paint(w, h)
        K.SetCol(C.row)
        surface.DrawRect(0, 0, w, h)
        K.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        if not self.job then
            draw.SimpleText("Pick a job on the left.", K.Font(14), w * 0.5, h * 0.5, C.textDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end

    local function showJob(job)
        detail:Clear()
        detail.job = job
        local model, models = firstModel(job)
        local modelIndex = 1

        local top = vgui.Create("DPanel", detail)
        top:Dock(TOP)
        top:SetTall(s(64))
        function top:Paint(w, h)
            K.SetCol(job.color or C.accent)
            surface.DrawRect(0, 0, s(4), h - s(10))
            draw.SimpleText(job.name, K.Font(24, 700), s(14), s(18), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            local st = jobState(job)
            local slots = st.count .. " / " .. (st.limit > 0 and st.limit or "∞")
            draw.SimpleText("Salary " .. money(job.salary or 0) .. "   ·   Slots " .. slots .. (needsVote(job) and "   ·   Needs a vote" or ""),
                K.Font(13), s(14), s(44), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        local bottom = vgui.Create("DPanel", detail)
        bottom:Dock(BOTTOM)
        bottom:SetTall(s(40))
        bottom.Paint = nil
        local become = K.Button(bottom, needsVote(job) and "Start vote" or "Become " .. job.name, function()
            becomeJob(job)
            frame:Remove()
        end, { accent = true, enabled = function() return jobBlocked(job) == nil end })
        become:Dock(RIGHT)
        become:SetWide(s(240))
        local note = vgui.Create("DPanel", bottom)
        note:Dock(FILL)
        function note:Paint(w, h)
            local reason = jobBlocked(job)
            if reason then draw.SimpleText(reason, K.Font(13), 0, h * 0.5, C.warn, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
        end

        local mid = vgui.Create("DPanel", detail)
        mid:Dock(FILL)
        mid:DockMargin(0, s(8), 0, s(8))
        mid.Paint = nil

        local mp = vgui.Create("DModelPanel", mid)
        mp:Dock(LEFT)
        mp:SetWide(s(260))
        mp:SetFOV(36)
        local function setModel(m)
            if not m then return end
            mp:SetModel(m)
            local ent = mp:GetEntity()
            if IsValid(ent) then
                local mn, mx = ent:GetRenderBounds()
                local size = math.max(mx.z - mn.z, 1)
                mp:SetLookAt(Vector(0, 0, size * 0.5))
                mp:SetCamPos(Vector(size * 1.55, size * 0.25, size * 0.6))
                local seq = ent:LookupSequence("idle_all_01")
                if seq and seq > 0 then ent:ResetSequence(seq) end
            end
        end
        setModel(model)
        function mp:LayoutEntity(ent)
            ent:SetAngles(Angle(0, 20 + math.sin(RealTime() * 0.6) * 18, 0))
            self:RunAnimation()
        end

        if models and #models > 1 then
            local arrows = vgui.Create("DPanel", mp)
            arrows:Dock(BOTTOM)
            arrows:SetTall(s(28))
            arrows.Paint = nil
            local function step(d)
                modelIndex = (modelIndex - 1 + d) % #models + 1
                setModel(models[modelIndex])
                if DarkRP.setPreferredJobModel then DarkRP.setPreferredJobModel(job.team, models[modelIndex]) end
            end
            local l = K.Button(arrows, "<", function() step(-1) end, { small = true })
            l:Dock(LEFT) l:SetWide(s(40))
            local r = K.Button(arrows, ">", function() step(1) end, { small = true })
            r:Dock(RIGHT) r:SetWide(s(40))
        end

        local info = K.Scroll(mid)
        info:Dock(FILL)
        info:DockMargin(s(14), 0, 0, 0)
        local desc = K.Label(info, string.Trim(job.description or ""), 14, 400, C.text)
        desc:Dock(TOP)
        local wl = {}
        for _, class in ipairs(job.weapons or {}) do
            local stored = weapons.GetStored(class)
            wl[#wl + 1] = stored and stored.PrintName or class
        end
        if #wl > 0 then
            local h = K.Heading(info, "Weapons")
            h:Dock(TOP)
            h:DockMargin(0, s(12), s(8), s(4))
            local wtxt = K.Label(info, table.concat(wl, ", "), 13, 400, C.textDim)
            wtxt:Dock(TOP)
        end
    end

    -- The job list, by category.
    for _, cat in ipairs(categories("jobs")) do
        local visible = {}
        for _, job in ipairs(cat.members or {}) do
            if not job.hidden then visible[#visible + 1] = job end
        end
        if #visible > 0 and (not cat.canSee or cat.canSee(LocalPlayer())) then
            local h = K.Heading(left, cat.name or "Jobs")
            h:Dock(TOP)
            h:DockMargin(0, s(6), s(10), s(4))
            for _, job in ipairs(visible) do
                local b = vgui.Create("DButton", left)
                b:SetText("")
                b:Dock(TOP)
                b:SetTall(s(44))
                b:DockMargin(0, 0, s(10), s(3))
                function b:Paint(w, hh)
                    local sel = detail.job == job
                    K.SetCol(sel and C.buttonDown or (self:IsHovered() and C.rowHover or C.row))
                    surface.DrawRect(0, 0, w, hh)
                    K.SetCol(job.color or C.accent)
                    surface.DrawRect(0, 0, s(4), hh)
                    local st = jobState(job)
                    draw.SimpleText(job.name, K.Font(15, 600), s(14), hh * 0.36, st.blocked and C.textDim or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    draw.SimpleText(money(job.salary or 0) .. " salary", K.Font(12), s(14), hh * 0.72, C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    draw.SimpleText(st.count .. " / " .. (st.limit > 0 and st.limit or "∞"), K.Font(13, 700), w - s(12), hh * 0.5,
                        st.full and C.bad or C.textDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                    return true
                end
                function b:DoClick() showJob(job) end
            end
        end
    end

    -- Start on your current job.
    local cur = RPExtraTeams and RPExtraTeams[LocalPlayer():Team()]
    if cur then showJob(cur) end
end

--------------------------------------------------------------------------
-- Shop tab
--------------------------------------------------------------------------

-- kind: DarkRP category list name, and how to buy and price an item.
local SHOP = {
    { id = "entities", title = "Entities", price = function(i) return i.price end,
      buy = function(i) RunConsoleCommand("darkrp", i.cmd) end },
    { id = "weapons", title = "Weapons", price = function(i) return i.pricesep or i.price end,
      filter = function(i) return i.separate end,
      buy = function(i) RunConsoleCommand("darkrp", "buy", i.name) end },
    { id = "shipments", title = "Shipments", price = function(i) return i.price end,
      filter = function(i) return not i.noship end,
      buy = function(i) RunConsoleCommand("darkrp", "buyshipment", i.name) end },
    { id = "ammo", title = "Ammo", price = function(i) return i.price end,
      buy = function(i) RunConsoleCommand("darkrp", "buyammo", tostring(i.id)) end },
    { id = "vehicles", title = "Vehicles", price = function(i) return i.price end,
      buy = function(i) RunConsoleCommand("darkrp", "buyvehicle", i.name) end },
}

-- DarkRP keeps single weapons inside the shipments list.
local function shopItems(kind)
    local src = kind.id == "weapons" and "shipments" or kind.id
    local out = {}
    for _, cat in ipairs(categories(src)) do
        local items = {}
        for _, item in ipairs(cat.members or {}) do
            if (not kind.filter or kind.filter(item)) and allowedItem(item) then items[#items + 1] = item end
        end
        if #items > 0 and (not cat.canSee or cat.canSee(LocalPlayer())) then
            out[#out + 1] = { name = cat.name, items = items }
        end
    end
    return out
end

local function buildShop(body)
    local s = K.S
    local tabs = vgui.Create("DPanel", body)
    tabs:Dock(TOP)
    tabs:SetTall(s(30))
    tabs:DockMargin(0, 0, 0, s(10))
    tabs.Paint = nil
    local area = vgui.Create("DPanel", body)
    area:Dock(FILL)
    area.Paint = nil

    local current
    local function show(kind)
        current = kind.id
        area:Clear()
        local sp = K.Scroll(area)
        sp:Dock(FILL)
        local groups = shopItems(kind)
        if #groups == 0 then
            local l = K.Label(sp, "Nothing to buy here as your current job.", 14, 400, C.textDim)
            l:Dock(TOP)
            return
        end
        for _, g in ipairs(groups) do
            local h = K.Heading(sp, g.name or kind.title)
            h:Dock(TOP)
            h:DockMargin(0, s(6), s(10), s(6))
            local grid = vgui.Create("DIconLayout", sp)
            grid:Dock(TOP)
            grid:SetSpaceX(s(8))
            grid:SetSpaceY(s(8))
            for _, item in ipairs(g.items) do
                local price = kind.price(item) or 0
                local card = grid:Add("DPanel")
                card:SetSize(s(180), s(220))
                function card:Paint(w, hh)
                    K.SetCol(C.row)
                    surface.DrawRect(0, 0, w, hh)
                    K.SetCol(C.edgeDark)
                    surface.DrawOutlinedRect(0, 0, w, hh)
                    K.SetCol(C.edgeLight)
                    surface.DrawLine(1, 1, w - 1, 1)
                    draw.SimpleText(K.Fit(item.name or "?", K.Font(14, 600), w - s(16)), K.Font(14, 600), s(8), s(140), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    local extra = ""
                    if kind.id == "shipments" and item.amount then extra = " · " .. item.amount .. " pcs"
                    elseif kind.id == "ammo" and item.amountGiven then extra = " · " .. item.amountGiven .. " rounds" end
                    draw.SimpleText(money(price) .. extra, K.Font(13, 700), s(8), s(162), canAfford(price) and C.good or C.bad, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    K.Ticks(0, 0, w, hh, false)
                end
                if item.model and item.model ~= "" then
                    local icon = vgui.Create("ModelImage", card)
                    icon:SetPos(s(26), s(8))
                    icon:SetSize(s(128), s(118))
                    icon:SetModel(item.model)
                    icon:SetMouseInputEnabled(false)
                end
                local buy = K.Button(card, "Buy", function() kind.buy(item) end,
                    { small = true, accent = true, enabled = function() return canAfford(price) end })
                buy:SetPos(s(8), s(184))
                buy:SetSize(s(164), s(28))
            end
            grid:InvalidateLayout(true)
            grid:SizeToChildren(false, true)
        end
    end

    local first
    for _, kind in ipairs(SHOP) do
        if #shopItems(kind) > 0 then
            first = first or kind
            local b = K.Button(tabs, kind.title, function() show(kind) end, { small = true, selected = function() return current == kind.id end })
            b:Dock(LEFT)
            b:SetWide(s(130))
            b:DockMargin(0, 0, s(6), 0)
        end
    end
    if first then
        show(first)
    else
        local l = K.Label(area, "Nothing to buy as your current job.", 14, 400, C.textDim)
        l:Dock(TOP)
    end
end

--------------------------------------------------------------------------
-- Character tab
--------------------------------------------------------------------------

local function buildCharacter(body, frame)
    local s = K.S
    local ply = LocalPlayer()
    local stats = vgui.Create("DPanel", body)
    stats:Dock(TOP)
    stats:SetTall(s(150))
    function stats:Paint(w, h)
        K.SetCol(C.row)
        surface.DrawRect(0, 0, w, h)
        K.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        local lines = {
            { "Name", ply:Nick() },
            { "Job", (ply.getDarkRPVar and ply:getDarkRPVar("job")) or team.GetName(ply:Team()) },
            { "Money", money(myMoney()) },
            { "Salary", money(ply.getDarkRPVar and ply:getDarkRPVar("salary") or 0) },
            { "Kills / deaths", ply:Frags() .. " / " .. ply:Deaths() },
        }
        local weight = ply:GetNW2Float("rhylib_weight", -1)
        if weight >= 0 then
            lines[#lines + 1] = { "Carrying", string.format("%.1f / %.0f kg", weight, ply:GetNW2Float("rhylib_carry", 20)) }
        end
        local colW = w / 2
        for i, l in ipairs(lines) do
            local cx = s(16) + ((i - 1) % 2) * colW
            local cy = s(24) + math.floor((i - 1) / 2) * s(42)
            K.Caps(l[1], cx, cy)
            draw.SimpleText(tostring(l[2]), K.Font(16, 600), cx, cy + s(18), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end

    local h = K.Heading(body, "Actions")
    h:Dock(TOP)
    h:DockMargin(0, s(14), 0, s(8))
    local grid = vgui.Create("DIconLayout", body)
    grid:Dock(FILL)
    grid:SetSpaceX(s(8))
    grid:SetSpaceY(s(8))
    local function number(text)
        local n = tonumber(string.Trim(text or ""))
        return n and n > 0 and math.floor(n) or nil
    end
    local actions = {
        { "Drop money", function()
            K.Prompt("Drop money", "How much?", "", function(t) local n = number(t) if n then RunConsoleCommand("darkrp", "dropmoney", tostring(n)) end end)
        end },
        { "Give money", function()
            K.Prompt("Give money", "To the player you're looking at. How much?", "", function(t) local n = number(t) if n then RunConsoleCommand("darkrp", "give", tostring(n)) end end)
        end },
        { "Change RP name", function()
            K.Prompt("RP name", "Your new name", ply:Nick(), function(t) t = string.Trim(t) if t ~= "" then RunConsoleCommand("darkrp", "rpname", t) end end)
        end },
        { "Sell all doors", function()
            K.Prompt("Sell all doors", "Type yes to sell every door you own.", "", function(t)
                if string.lower(string.Trim(t)) == "yes" then RunConsoleCommand("darkrp", "unownalldoors") end
            end)
        end },
        { "Inventory", function()
            frame:Remove()
            if Rhylib.Inventory and Rhylib.Inventory.Toggle then Rhylib.Inventory.Toggle() end
        end },
    }
    for _, a in ipairs(actions) do
        local b = K.Button(grid, a[1], a[2])
        b:SetSize(s(200), s(36))
    end
end

--------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------

-- The F4 menu lives in the pause menu: Jobs, Shop and Character pages.
-- F4 opens it on Jobs (or closes it); Esc opens it where you left off.

-- The tab builders close "the frame" after choosing a job; here that's the pause menu.
local frame = { Remove = function() Menus.ClosePause() end }

local function sub()
    local ply = LocalPlayer()
    local job = (ply.getDarkRPVar and ply:getDarkRPVar("job")) or team.GetName(ply:Team())
    return job .. "   ·   " .. money(myMoney())
end

local function page(id, title, order, fn, group)
    Menus.AddPage(id, {
        title = title,
        order = order,
        group = group,
        visible = isDarkRP,
        build = function(p)
            Menus.pages[id].sub = sub()
            fn(p, frame)
        end,
    })
end
page("jobs", "Jobs", 1, buildJobs, "play")
page("shop", "Shop", 2, buildShop, "play")
page("character", "Profile", 20, buildCharacter, "character")

function Menus.ToggleF4()
    if not isDarkRP() then return end
    if IsValid(Menus.pause) then
        if Menus.pause.pageId == "jobs" then
            Menus.ClosePause()
        else
            Menus.pause:ShowPage("jobs")
        end
        return
    end
    Menus.lastPage = "jobs"
    Menus.OpenPause()
    Menus.f4Held = true   -- the key that opened it must be let go before it can close it
end

-- F4 (gm_showspare2): ours, before DarkRP's runs on the server.
Rhylib.Hook.Add("PlayerBindPress", "menus.f4", function(_, bind, pressed)
    if pressed and isDarkRP() and string.find(bind, "gm_showspare2", 1, true) then
        Menus.ToggleF4()
        return true
    end
end)

-- While the menu is open it has the keyboard, so binds don't fire: watch
-- the F4 key itself (a fresh press closes it).
local f4Down = false
Rhylib.Hook.Add("Think", "menus.f4key", function()
    if not IsValid(Menus.pause) then
        f4Down = false
        return
    end
    local down = input.IsKeyDown(KEY_F4)
    if not down then Menus.f4Held = false end
    if down and not f4Down and not Menus.f4Held then Menus.ToggleF4() end
    f4Down = down
end)

-- In case DarkRP opens its menu another way: it opens ours.
local function takeOver()
    if not DarkRP then return end
    local function open()
        if not (IsValid(Menus.pause) and Menus.pause.pageId == "jobs") then Menus.ToggleF4() end
    end
    DarkRP.openF4Menu = open
    DarkRP.toggleF4Menu = open
    DarkRP.closeF4Menu = function() end
    DarkRP.getF4MenuPanel = function() return Menus.pause end
end
Rhylib.Hook.Add("InitPostEntity", "menus.f4", takeOver)
Rhylib.Hook.Add("DarkRPFinishedLoading", "menus.f4", takeOver)
takeOver()

concommand.Add("rhylib_f4", Menus.ToggleF4)
