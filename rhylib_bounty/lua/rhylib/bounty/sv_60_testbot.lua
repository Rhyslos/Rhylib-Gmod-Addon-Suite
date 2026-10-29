--[[
    Test bots with a bounty (server, staff: rhylib.bounty.gm or the server
    console). For checking the whole loop on your own. Developer tool:
    the commands only exist while convar rhylib_dev is 1 (or with the
    rhylib_devtools addon installed).

      !bountybot [dead|alive|either] [reward]    chat (also /bountybot)
      rhylib_bounty_bot [dead|alive|either] [reward]   console
        Adds a bot ("Bounty target N") a few steps in front of you and puts
        a free (office) bounty on it: default dead or alive, 5000.
      !bountybot clear  /  rhylib_bounty_bot clear
        Kicks every test bot.
    A test bot is kicked 20 s after its last bounty is claimed, cancelled
    or expires (time to look at the body or the hand-in). Needs a free
    player slot (start the server with maxplayers above your player count).
]]

local B = Rhylib.Bounty

B.testBots = B.testBots or {}   -- [bot] = true
local count = 0

local function say(ply, text)
    Rhylib.Notify(IsValid(ply) and ply or nil, text, "info", "Bounty")
end

local function clear(ply)
    local n = 0
    for bot in pairs(B.testBots) do
        if IsValid(bot) then bot:Kick("Bounty test over") n = n + 1 end
    end
    B.testBots = {}
    say(ply, n .. " test bot" .. (n == 1 and "" or "s") .. " removed")
end

-- B.SpawnTestBot(by, mode, reward): add the bot and its bounty.
function B.SpawnTestBot(by, mode, reward)
    if not B.MODE_INDEX[mode] then mode = "either" end
    reward = math.Clamp(math.floor(tonumber(reward) or 5000), 1, 10000000)
    if player.GetCount() >= game.MaxPlayers() then return say(by, "No free player slot for a bot") end
    count = count + 1
    local bot = player.CreateNextBot("Bounty target " .. count)
    if not IsValid(bot) then return say(by, "Couldn't add a bot") end
    B.testBots[bot] = true
    timer.Simple(1, function()
        if not IsValid(bot) then return end
        if IsValid(by) then
            local tr = util.TraceHull({ start = by:EyePos(), endpos = by:EyePos() + by:GetAimVector() * 160,
                mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 72), filter = { by, bot } })
            local ground = util.TraceLine({ start = tr.HitPos, endpos = tr.HitPos - Vector(0, 0, 200), filter = { by, bot } })
            bot:SetPos(ground.HitPos)
            bot:SetEyeAngles(Angle(0, (by:GetPos() - ground.HitPos):Angle().y, 0))
        end
        B.Add({ kind = "player", tkey = B.PlayerKey(bot), sid = "", botId = bot:UserID(), name = bot:Nick(), model = bot:GetModel(),
            reward = reward, mode = mode, by = "", byName = "Bounty office (test)", free = true })
        say(by, bot:Nick() .. " added with a " .. mode .. " bounty of " .. B.Money(reward))
    end)
end

Rhylib.Hook.Add("Rhylib.BountyClosed", "bounty.testbot", function(b)
    for bot in pairs(B.testBots) do
        if IsValid(bot) and b.tkey == B.PlayerKey(bot) and #B.OnTarget(b.tkey) == 0 then
            timer.Simple(20, function()
                if IsValid(bot) and #B.OnTarget(B.PlayerKey(bot)) == 0 then
                    B.testBots[bot] = nil
                    bot:Kick("Bounty test over")
                end
            end)
        end
    end
end)

local function run(ply, args)
    local function go(ok)
        if not ok then return say(ply, "Staff only") end
        local a = string.lower(args[1] or "")
        if a == "clear" then return clear(ply) end
        local mode, reward = "either", 5000
        for _, w in ipairs(args) do
            w = string.lower(w)
            if B.MODE_INDEX[w] then mode = w elseif tonumber(w) then reward = tonumber(w) end
        end
        B.SpawnTestBot(ply, mode, reward)
    end
    if not IsValid(ply) then return go(true) end
    Rhylib.Perms.Check(ply, "rhylib.bounty.gm", function(ok) if IsValid(ply) then go(ok) end end)
end

-- Dev only: the commands exist while convar rhylib_dev is 1 or the
-- rhylib_devtools addon is installed (checked at InitPostEntity and when
-- rhylib_dev changes).
local devVar = GetConVar("rhylib_dev") or CreateConVar("rhylib_dev", "0", FCVAR_ARCHIVE, "Rhy's: developer tools on (test commands, debug output)")
local registered = false
local function register()
    if registered then return end
    if not (devVar:GetBool() or (Rhylib.Modules and Rhylib.Modules.devtools)) then return end
    registered = true
    -- (run() checks rhylib.bounty.gm itself; the console may always)
    Rhylib.Command.Add({
        name = "rhylib_bounty_bot", chat = { "bountybot" }, tag = "Bounty",
        help = "Add a test bot with a bounty, or clear them", args = "[dead|alive|either] [reward] | clear",
        fn = function(ply, args) run(IsValid(ply) and ply or nil, args) end,
    })
end
Rhylib.Hook.Add("InitPostEntity", "bounty.testbot", register)
cvars.AddChangeCallback("rhylib_dev", function() register() end, "bounty.testbot")
if GAMEMODE then register() end   -- (Lua refresh after load)
