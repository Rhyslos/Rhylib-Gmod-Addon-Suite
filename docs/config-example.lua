--[[
    Example host config.

    Copy this file to:
        garrysmod/addons/rhylib_config/lua/rhylib_config/settings.lua

    Keeping it in its own addon folder means Workshop updates never
    overwrite it. Any file in lua/rhylib_config/ is loaded after the core.
]]

-- Seconds between batched database saves.
Rhylib.Config.Set("core", "dataFlushDelay", 3)
