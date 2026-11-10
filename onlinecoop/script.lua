-- Steam uses the Workshop item ID as the mod name. The engine assigns num
-- as it loads entries, including disabled local copies in the same list.
-- Native upload status icons fall through to the three-column mod reorder
-- handler when clicked. They are extra menu entries, so that index is invalid.
-- Consume their hover before native act_menu runs; keep actual upload/back/
-- reorder actions untouched. Re-enter Mods (or restart) to retry an error.
prepend("act_menu",function(id)
    if not inmods or (id~="⓵" and id~="ô") then return end
    for _,button in ipairs(menu or {}) do button.over=false end
    _log("[WORKSHOP GUARD] ignored upload status click; reopen Mods to retry")
end,"coop_workshop_status_guard")

for index, entry in ipairs(MODLIST or {}) do
    if entry.active and (entry.name == "onlinecoop" or entry.name == "3833493529") and not entry.ran then
        coop_mod_index = index
        break
    end
end
require("transport.lua")
require("rules.lua")
require("game_lobby.lua")
newsfx("onlinecoop_ping","sounds/bell_b.wav")
newsfx("onlinecoop_suggestion","sounds/bell_a.wav")
newsfx("onlinecoop_bell_a","sounds/Bell1.wav")
newsfx("onlinecoop_bell_b","sounds/Bell2.wav")
newsfx("onlinecoop_bell_c","sounds/Bell3.wav")
require("bell_sprite.lua")
