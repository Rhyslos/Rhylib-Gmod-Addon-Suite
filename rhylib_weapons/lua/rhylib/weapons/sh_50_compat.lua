--[[
    Workshop content we depend on for models only (Star Wars Shared
    Resources, cs574's shields pack...) is built for TFA Base, which Rhylib
    doesn't use:
    - their "Install TFA Base !!!" popup / server warning (hook
      InitPostEntity "INSTALL TFA BASE") is removed: at load, at
      Initialize and again at the start of InitPostEntity, in case one of
      those addons loads after us;
    - their own TFA weapons can't work without TFA Base (their base is
      missing), so while it isn't installed they're taken out of the spawn
      menus (not spawnable) instead of erroring when picked.
    Only their hooks and weapon list entries; none of their files.
    Realm: shared.
]]

local function quiet()
    hook.Remove("InitPostEntity", "INSTALL TFA BASE")
end

local function hideTFAWeapons()
    if TFA and TFA_BASE_VERSION then return end      -- (TFA Base installed: leave them)
    if weapons.GetStored("tfa_gun_base") then return end
    local list = list.GetForEdit and list.GetForEdit("Weapon") or nil
    for _, w in ipairs(weapons.GetList()) do
        local class = w.ClassName
        local base = w.Base
        if class and isstring(base) and string.sub(base, 1, 4) == "tfa_" then
            local stored = weapons.GetStored(class)
            if stored then
                stored.Spawnable = false
                stored.AdminSpawnable = false
            end
            if list and list[class] then
                list[class].Spawnable = false
                list[class].AdminSpawnable = false
            end
        end
    end
end

quiet()
Rhylib.Hook.Add("Initialize", "weapons.notfaprompt", function()
    quiet()
    hideTFAWeapons()
end)
-- (first thing at InitPostEntity, before that hook would run)
Rhylib.Hook.Add("InitPostEntity", "weapons.notfaprompt", function()
    quiet()
    hideTFAWeapons()
end, -10000)
