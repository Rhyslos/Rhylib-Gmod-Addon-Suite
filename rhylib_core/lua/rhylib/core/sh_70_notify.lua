--[[
    Notices to players (shared): one way for every addon to tell a player
    something ("Too far away", "Saved 4 jail cells", "You can't do that").

        Rhylib.Notify(ply, "Too far away", "bad", "Medical")
        Rhylib.Notify(nil, "Saved 12 placements")        -- server console
        Rhylib.Notify({ a, b }, "Briefing in 5", "info", "Admin")
        Rhylib.Notify(nil, "Copied", "good")             -- client: shows locally

    Rhylib.Notify(target, text, kind, tag)
      target  server: a player, a list of players, true (everyone) or nil
              (the server console). Client: ignored, shown to yourself.
      text    the message (cut to 240 characters).
      kind    "info" (default), "good" or "bad".
      tag     optional source, shown as "[Rhy's <tag>]" in chat ("MP",
              "Medical"...). "" or nil = no tag.
    Server: net core.notify (tag string, text string, kind UInt 2).

    Client presenter: a short line under the crosshair for 3 s (the newest
    replaces the last), coloured by kind, and a chat line with the tag
    while client convar rhylib_notify_chat is 1 (default; Settings); the
    same notice again within 8 s doesn't repeat in chat.
    Hook Rhylib.NotifyShow(tag, text, kind) runs first: return true to
    draw it yourself instead (a HUD addon restyling notices).
]]

Rhylib.KIND_INFO, Rhylib.KIND_GOOD, Rhylib.KIND_BAD = 0, 1, 2
local KINDS = { info = 0, good = 1, bad = 2 }
local KIND_NAMES = { [0] = "info", [1] = "good", [2] = "bad" }

if SERVER then
    Rhylib.Net.Register("core.notify")

    function Rhylib.Notify(target, text, kind, tag)
        text = string.sub(tostring(text or ""), 1, 240)
        if text == "" then return end
        tag = tag and tostring(tag) or ""
        if target == nil then
            MsgN((tag ~= "" and ("[Rhy's " .. tag .. "] ") or "[Rhy's] ") .. text)
            return
        end
        Rhylib.Net.Start("core.notify")
        net.WriteString(tag)
        net.WriteString(text)
        net.WriteUInt(KINDS[kind] or 0, 2)
        if target == true then
            net.Broadcast()
        elseif istable(target) then
            local list = {}
            for _, p in ipairs(target) do if IsValid(p) and p:IsPlayer() then list[#list + 1] = p end end
            if #list > 0 then net.Send(list) end
        elseif IsValid(target) and target:IsPlayer() then
            net.Send(target)
        end
    end
    return
end

-- Client ------------------------------------------------------------------

local chatVar = CreateClientConVar("rhylib_notify_chat", "1", true, false, "Also put Rhy's notices in chat")

local COLS = {
    [0] = Color(228, 227, 220),
    [1] = Color(151, 196, 89),
    [2] = Color(226, 75, 74),
}
local COL_TAG = Color(133, 183, 235)

local cur   -- { text, kind, at }

local lastChat = {}   -- [tag .. "\0" .. text] = RealTime: the same notice again within
                      -- 8 s shows on screen but not in chat again (no "No room" spam)
local function show(tag, text, kind)
    if hook.Run("Rhylib.NotifyShow", tag, text, KIND_NAMES[kind] or "info") == true then return end
    cur = { text = text, kind = kind, at = RealTime() }
    local k = tag .. "\0" .. text
    local now = RealTime()
    local repeated = lastChat[k] and now - lastChat[k] < 8
    lastChat[k] = now
    if table.Count(lastChat) > 64 then lastChat = { [k] = now } end
    if chatVar:GetBool() and not repeated then
        if tag ~= "" then
            chat.AddText(COL_TAG, "[Rhy's " .. tag .. "] ", COLS[kind] or COLS[0], text)
        else
            chat.AddText(COLS[kind] or COLS[0], text)
        end
    end
end

function Rhylib.Notify(_, text, kind, tag)
    text = string.sub(tostring(text or ""), 1, 240)
    if text == "" then return end
    show(tag and tostring(tag) or "", text, KINDS[kind] or 0)
end

Rhylib.Net.Receive("core.notify", function()
    local tag, text, kind = net.ReadString(), net.ReadString(), net.ReadUInt(2)
    show(tag, text, kind)
end)

local SHOW, FADE = 3, 0.5
Rhylib.Hook.Add("HUDPaint", "core.notify", function()
    if not cur then return end
    local age = RealTime() - cur.at
    if age > SHOW then cur = nil return end
    local a = age > SHOW - FADE and (SHOW - age) / FADE or 1
    local col = COLS[cur.kind] or COLS[0]
    local font = Rhylib.UI and Rhylib.UI.Font and Rhylib.UI.Font(16, 600) or "DermaDefaultBold"
    draw.SimpleTextOutlined(cur.text, font, ScrW() * 0.5, ScrH() * 0.5 + ScrH() * 0.1,
        Color(col.r, col.g, col.b, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 200 * a))
end)

-- The chat switch on Settings > Interface (rhylib_menus, if installed).
Rhylib.After("menus", function()
    local M = Rhylib.Menus
    if not (M and M.AddSetting) then return end
    M.AddSetting("Chat", { id = "core.notifychat", order = 90, tab = "Interface",
        title = "Notices in chat", desc = "Also put the short notices (\"Too far away\", \"Saved\") in chat",
        kind = "toggle", convar = "rhylib_notify_chat" })
end)
