-- rhylib_chat loader (shared). Runs on server and client at startup.
-- Needs rhylib_core (which defines Rhylib.LoadModule). LoadModule then loads
-- every file in lua/rhylib/chat/ by prefix: sh_ (both), sv_ (server),
-- cl_ (client), in name order: sh_00_config, sv_10_chat, cl_10_chat,
-- cl_20_voice.

if not Rhylib then
    print("[Rhylib] rhylib_chat needs rhylib_core. Install it and restart the map.")
    return
end

Rhylib.LoadModule("chat", { name = "Chat", version = "0.1.0" })
