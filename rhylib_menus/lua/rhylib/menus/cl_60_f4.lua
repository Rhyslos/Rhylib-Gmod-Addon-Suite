--[[
    F4 menu (DarkRP), as pages of the pause menu: F4 opens the pause menu
    on Jobs (a fresh F4 press closes it). Replaces DarkRP's own F4 menu.
      Jobs       jobs by category; pick one to see its model, description
                 and weapons, then become it (or start a vote). The
                 preview wears your skin (picked on Trooper > Appearance).
      Shop       entities, shipments, single weapons, ammo and vehicles you
                 can buy as your current job (only shown when the server
                 has anything to sell).
      Trooper > Overview ("character")  your model, name, battalion,
                 rank, job and qualifications (rhylib_roster); tiles to
                 Skills (points left, rhylib_skills), Jobs and Battalion;
                 the service record (clone number, kills, carried weight;
                 money and salary only while money is in use,
                 R.MoneyOn); quick actions (appearance, inventory, class,
                 the money / door commands while money is on, RP name
                 only without rhylib_roster).

    Everything runs DarkRP's own console commands ("darkrp <command>"),
    so DarkRP checks money, limits and jobs on the server as usual.
    Without DarkRP, F4 does what it did before.

    Client only. Pages: "jobs" (section you, order 30, key F4), "shop"
    (you, 32), "character" (the Overview tab of the Trooper group, order
    10); each only while DarkRP is loaded. Adds Menus.ToggleF4,
    Menus.SkillPointsLeft(ply) (left, total; nil without rhylib_skills;
    math.huge = free) and console command
    rhylib_f4. Replaces DarkRP.openF4Menu / toggleF4Menu / closeF4Menu /
    getF4MenuPanel so DarkRP's own calls open ours.
    The client-side checks (job full, customCheck, can afford) only grey
    out buttons; DarkRP decides on the server.
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

-- Is DarkRP money in use? rhylib_roster's money setting (R.MoneyOn); without
-- rhylib_roster always yes.
local function moneyOn()
    local Ro = Rhylib.Roster
    return not (Ro and Ro.MoneyOn) or Ro.MoneyOn()
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
        -- Start on the model you wear (your job) or the one you picked before.
        if models then
            local me = LocalPlayer()
            local want = job.team == me:Team() and me:GetModel()
                or (DarkRP.getPreferredJobModel and DarkRP.getPreferredJobModel(job.team))
            for i, m in ipairs(models) do
                if want and string.lower(m) == string.lower(want) then modelIndex = i end
            end
            model = models[modelIndex]
        end
        local function wearing()
            return string.lower(LocalPlayer():GetModel() or "") == string.lower(models and models[modelIndex] or model or "")
        end

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
        -- Your own job with several models: put the picked one on now
        -- (rhylib_roster changes it in place, no respawn; DarkRP remembers it).
        if models and #models > 1 and job.team == LocalPlayer():Team() and Rhylib.Roster then
            become:SetVisible(false)
            local upd = K.Button(bottom, "Update job", function()
                if DarkRP.setPreferredJobModel then DarkRP.setPreferredJobModel(job.team, models[modelIndex]) end
                Rhylib.Net.Start("roster.jobmodel")
                net.WriteString(models[modelIndex])
                net.SendToServer()
            end, { accent = true, enabled = function() return not wearing() end, tooltip = "Wear the model shown, and keep it next time" })
            upd:Dock(RIGHT)
            upd:SetWide(s(240))
        end
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
        -- (the preview wears your own skin when the model has it; skins
        -- are picked on Trooper > Appearance)
        local function mySkin() return LocalPlayer():GetNW2Int("rhylib_skin", 0) end

        local function setModel(m)
            if not m then return end
            mp:SetModel(m)
            local ent = mp:GetEntity()
            if IsValid(ent) then
                local sk = mySkin()
                if sk < (ent:SkinCount() or 1) then ent:SetSkin(sk) end
            end
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

-- Skill points left (rhylib_skills), or nil without it. math.huge = free.
local function skillPointsLeft(ply)
    local Sk = Rhylib.Skills
    if not (Sk and Sk.Points and Sk.Spent and Sk.Set) then return nil end
    local pts = Sk.Points(ply)
    if pts == math.huge then return math.huge, pts end
    return math.max(0, pts - Sk.Spent(Sk.Set(ply))), pts
end
Menus.SkillPointsLeft = skillPointsLeft

local function goPage(id)
    return function()
        if IsValid(Menus.pause) and Menus.pages and Menus.pages[id] then Menus.pause:ShowPage(id) end
    end
end

-- A clickable tile: caps label, a big line, a dim line, a link line.
local function tile(parent, label, getBig, getDim, link, fn, col)
    local s = K.S
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    function b:Paint(w, h)
        local on = fn ~= nil
        K.SetCol(on and self:IsHovered() and C.buttonHover or C.row)
        surface.DrawRect(0, 0, w, h)
        K.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        K.SetCol(col or C.accent)
        surface.DrawRect(0, 0, w, s(2))
        K.Caps(label, s(14), s(20))
        draw.SimpleText(K.Fit(getBig(), K.Font(19, 700), w - s(28)), K.Font(19, 700), s(14), s(46), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(K.Fit(getDim() or "", K.Font(13), w - s(28)), K.Font(13), s(14), s(70), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if link and on then
            draw.SimpleText(link, K.Font(13, 700), s(14), h - s(16), col or C.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        return true
    end
    function b:DoClick()
        if not fn then return end
        surface.PlaySound("ui/buttonclick.wav")
        fn()
    end
    return b
end

-- Trooper > Overview: who you are (model, name, battalion, rank, job,
-- qualifications), tiles to Skills / Jobs / Battalion, the service
-- record and quick actions.
local function buildCharacter(body, frame)
    local s = K.S
    local ply = LocalPlayer()
    local R = Rhylib.Roster
    local function char() return R and R.Get and R.Get(ply) or { has = false } end
    local function jobName() return (ply.getDarkRPVar and ply:getDarkRPVar("job")) or team.GetName(ply:Team()) end

    -- Who you are.
    local top = vgui.Create("DPanel", body)
    top:Dock(TOP)
    top:SetTall(s(200))
    function top:Paint(w, h)
        K.SetCol(C.row)
        surface.DrawRect(0, 0, w, h)
        K.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        local x = s(196)
        local c = char()
        local name = (R and R.FullName and R.FullName(ply)) or ply:Nick()
        draw.SimpleText(K.Fit(string.upper(name), K.Font(28, 700), w - x - s(16)), K.Font(28, 700), x, s(38), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local tc = team.GetColor(ply:Team()) or C.accent
        local unit
        if c.has then
            unit = (c.bn ~= "" and c.bn or (c.trained and "No battalion yet" or "Cadet: waiting for basic training"))
            if c.rank and c.rank > 0 and R.RankName then unit = unit .. "  ·  " .. R.RankName(c.rank) end
        end
        if unit then
            -- (a small diamond in the job's colour)
            local dx, dy, r = x + s(6), s(72), s(5)
            draw.NoTexture()
            K.SetCol(tc)
            surface.DrawPoly({ { x = dx, y = dy - r }, { x = dx + r, y = dy }, { x = dx, y = dy + r }, { x = dx - r, y = dy } })
            draw.SimpleText(unit, K.Font(16, 600), x + s(18), dy, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        draw.SimpleText("Job: " .. jobName(), K.Font(14), x, s(100), C.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        -- Qualifications as chips.
        local cx = x
        local f = K.Font(12, 700)
        surface.SetFont(f)
        for id in string.gmatch(ply:GetNW2String("rhylib_quals", ""), "[^,]+") do
            local q = R and R.QualName and R.QualName(id) or id
            local tw = surface.GetTextSize(q) + s(14)
            if cx + tw > w - s(12) then break end
            K.SetCol(C.good, 160)
            surface.DrawOutlinedRect(cx, s(124), tw, s(22))
            draw.SimpleText(q, f, cx + tw * 0.5, s(135), C.good, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            cx = cx + tw + s(6)
        end
    end
    local mp = vgui.Create("DModelPanel", top)
    mp:SetPos(s(8), s(8))
    mp:SetSize(s(172), s(184))
    mp:SetFOV(30)
    mp:SetModel(ply:GetModel())
    local ent = mp:GetEntity()
    if IsValid(ent) then
        ent:SetSkin(ply:GetSkin())
        for i = 0, ply:GetNumBodyGroups() - 1 do ent:SetBodygroup(i, ply:GetBodygroup(i)) end
        local mn, mx = ent:GetRenderBounds()
        local size = math.max(mx.z - mn.z, 1)
        mp:SetLookAt(Vector(0, 0, size * 0.62))
        mp:SetCamPos(Vector(size * 1.25, size * 0.2, size * 0.7))
        local seq = ent:LookupSequence("idle_all_01")
        if seq and seq > 0 then ent:ResetSequence(seq) end
    end
    function mp:LayoutEntity(e)
        e:SetAngles(Angle(0, 20 + math.sin(RealTime() * 0.6) * 18, 0))
        self:RunAnimation()
    end

    -- Tiles.
    local tiles = vgui.Create("DPanel", body)
    tiles:Dock(TOP)
    tiles:DockMargin(0, s(10), 0, 0)
    tiles:SetTall(s(118))
    tiles.Paint = nil
    local list = {}
    if Menus.pages.skills then
        list[#list + 1] = tile(tiles, "Skills", function()
            local left = skillPointsLeft(ply)
            if left == math.huge then return "Free (testing)" end
            if not left then return "-" end
            return left == 1 and "1 point to spend" or (left .. " points to spend")
        end, function()
            local left, pts = skillPointsLeft(ply)
            if not pts or pts == math.huge then return "" end
            return (pts - left) .. " of " .. pts .. " spent"
        end, "Spend points ›", goPage("skills"), C.warn)
    end
    if Menus.pages.jobs and isDarkRP() then
        list[#list + 1] = tile(tiles, "Job", jobName, function()
            local j = RPExtraTeams and RPExtraTeams[ply:Team()]
            if not j then return "" end
            local lim = jobLimit(j)
            local n = team.NumPlayers(ply:Team())
            return lim and lim > 0 and (n .. " of " .. lim .. " slots taken") or (n .. " on this job")
        end, "Change job ›", goPage("jobs"))
    end
    if Menus.pages.roster then
        list[#list + 1] = tile(tiles, "Battalion", function()
            local c = char()
            return c.bn ~= "" and c.bn or "None yet"
        end, function()
            local c = char()
            if not c.bn or c.bn == "" then return "" end
            local n = 0
            for _, p in ipairs(player.GetAll()) do
                if p:GetNW2String(Rhylib.NW.BATTALION, "") == c.bn then n = n + 1 end
            end
            return n .. " online"
        end, "See your unit ›", goPage("roster"), team.GetColor(ply:Team()))
    end
    function tiles:PerformLayout(w, h)
        local n = #list
        if n == 0 then return end
        local gap = s(10)
        local tw = (w - gap * (n - 1)) / n
        for i, t in ipairs(list) do
            t:SetPos(math.floor((i - 1) * (tw + gap)), 0)
            t:SetSize(math.floor(tw), h)
        end
    end
    if #list == 0 then tiles:SetVisible(false) end

    -- Service record.
    local h1 = K.Heading(body, "Service record")
    h1:Dock(TOP)
    h1:DockMargin(0, s(14), 0, s(8))
    local rec = vgui.Create("DPanel", body)
    rec:Dock(TOP)
    rec:SetTall(s(66))
    function rec:Paint(w, h)
        K.SetCol(C.row)
        surface.DrawRect(0, 0, w, h)
        K.SetCol(C.edgeDark)
        surface.DrawOutlinedRect(0, 0, w, h)
        local c = char()
        local lines = {}
        if c.has then lines[#lines + 1] = { "Clone number", c.num ~= "" and c.num or "-" } end
        lines[#lines + 1] = { "Kills / deaths", ply:Frags() .. " / " .. ply:Deaths() }
        local weight = ply:GetNW2Float("rhylib_weight", -1)
        if weight >= 0 then
            lines[#lines + 1] = { "Carrying", string.format("%.1f / %.0f kg", weight, ply:GetNW2Float("rhylib_carry", 20)) }
        end
        if moneyOn() then
            lines[#lines + 1] = { "Money", money(myMoney()) }
            lines[#lines + 1] = { "Salary", money(ply.getDarkRPVar and ply:getDarkRPVar("salary") or 0) }
        end
        local per = math.min(#lines, 5)
        local rows = math.ceil(#lines / per)
        local need = rows * s(58) + s(8)
        if math.abs(self:GetTall() - need) > 1 then self:SetTall(need) end
        local colW = (w - s(16)) / per
        for i, l in ipairs(lines) do
            local cx = s(16) + ((i - 1) % per) * colW
            local cy = s(22) + math.floor((i - 1) / per) * s(58)
            K.Caps(l[1], cx, cy)
            draw.SimpleText(tostring(l[2]), K.Font(17, 700), cx, cy + s(20), C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end

    -- Quick actions.
    local h2 = K.Heading(body, "Quick actions")
    h2:Dock(TOP)
    h2:DockMargin(0, s(14), 0, s(8))
    local grid = vgui.Create("DIconLayout", body)
    grid:Dock(FILL)
    grid:SetSpaceX(s(8))
    grid:SetSpaceY(s(8))
    local function number(text)
        local n = tonumber(string.Trim(text or ""))
        return n and n > 0 and math.floor(n) or nil
    end
    local actions = {}
    local looks = Menus.pages.looks
    if looks and (not looks.visible or looks.visible()) then actions[#actions + 1] = { "Change appearance", goPage("looks") } end
    actions[#actions + 1] = { "Open inventory", function()
        frame:Remove()
        if Rhylib.Inventory and Rhylib.Inventory.Toggle then Rhylib.Inventory.Toggle() end
    end }
    local cls = Menus.pages.class
    if cls and (not cls.visible or cls.visible()) then actions[#actions + 1] = { "Pick class", goPage("class") } end
    -- Money and door actions only while money is in use; the name comes
    -- from the character when rhylib_roster is installed.
    if moneyOn() then
        actions[#actions + 1] = { "Drop money", function()
            K.Prompt("Drop money", "How much?", "", function(t) local n = number(t) if n then RunConsoleCommand("darkrp", "dropmoney", tostring(n)) end end)
        end }
        actions[#actions + 1] = { "Give money", function()
            K.Prompt("Give money", "To the player you're looking at. How much?", "", function(t) local n = number(t) if n then RunConsoleCommand("darkrp", "give", tostring(n)) end end)
        end }
        actions[#actions + 1] = { "Sell all doors", function()
            K.Prompt("Sell all doors", "Type yes to sell every door you own.", "", function(t)
                if string.lower(string.Trim(t)) == "yes" then RunConsoleCommand("darkrp", "unownalldoors") end
            end)
        end }
    end
    if not Rhylib.Roster then
        actions[#actions + 1] = { "Change RP name", function()
            K.Prompt("RP name", "Your new name", ply:Nick(), function(t) t = string.Trim(t) if t ~= "" then RunConsoleCommand("darkrp", "rpname", t) end end)
        end }
    end
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
    if not moneyOn() then return job end
    return job .. "   ·   " .. money(myMoney())
end

-- Is there anything at all in the shop (any category of any kind with a
-- member)? A server that removed every DarkRP item has no Shop page.
local function shopHasItems()
    for _, kind in ipairs({ "entities", "shipments", "weapons", "ammo", "vehicles" }) do
        for _, cat in ipairs(categories(kind)) do
            if cat.members and #cat.members > 0 then return true end
        end
    end
    return false
end

local function page(id, def, fn)
    def.visible = def.visible or isDarkRP
    def.build = function(p)
        Menus.pages[id].sub = sub()
        fn(p, frame)
    end
    Menus.AddPage(id, def)
end
page("jobs", { title = "Jobs", order = 30, section = "you", icon = "jobs", key = "F4" }, buildJobs)
page("shop", { title = "Shop", order = 32, section = "you", icon = "shop",
    visible = function() return isDarkRP() and shopHasItems() end }, buildShop)
page("character", { title = "Overview", order = 10, group = "trooper" }, buildCharacter)

-- Menus.ToggleF4(): F4. Opens the pause menu on Jobs; if it's already open
-- on Jobs it closes it, on another page it switches to Jobs.
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
