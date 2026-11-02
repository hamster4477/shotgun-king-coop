require("modes/coop.lua")
local coop_initialize = initialize
local coop_start_run = start
require("campaigns/common.lua")
require("campaigns/charnier_menu.lua")
require("campaigns/knight_brands.lua")
local raid_initialize = initialize
local raid_menu = charnier_menu
coop_variant = "charnier"
-- Native raids begin at floor zero and finish after floor HOUSE_MAX.
coop_initial_floor = -1
function initialize()
    coop_initialize()
    raid_initialize()
    coop_raid_load_brand_icons()
end
function charnier_menu()
    mode.coop_run_active=false
    mode.coop_auto_select_knight_pending=nil
    mode.coop_knight=nil
    mode.coop_selected="king"
    mode.coop_stats_screen=nil
    raid_menu()
end
function start()
    charnier_menu()
end
function coop_stats_continue()
    charnier_menu()
end
function next_raid()
    mode.lvl_max=HOUSE_MAX
    mode.upgrades={}
    for index in all(SAVE.coop_charnier.burdens) do
        local burden=BURDENS[index+1]
        add(mode.upgrades,burden)
        mode.lvl_max=mode.lvl_max+(burden.extra_floor or 0)
    end
    coop_raid_apply_brands()
    SAVE.coop_charnier.ingame=1
    coop_start_run()
end
function coop_campaign_grow()
    if mode.lvl < mode.lvl_max then
        -- Native Charnier advances the counter before generating this offer.
        level_up(coop_campaign_choices(mode.lvl+1==3),next_floor)
        return
    end
    mode.coop_run_active=false
    if mode.coop_stats then mode.coop_stats.running=false end
    fast_tracker(false)
    music()
    SAVE.coop_charnier.success=1
    SAVE.coop_charnier.ingame=nil
    success_msg(lang.raid_won,function() coop_show_run_stats(true) end)
    sfx("raid_won")
end
function on_hero_death()
    mode.coop_run_active=false
    mode.coop_opening_king_turn=false
    if mode.coop_stats then mode.coop_stats.running=false end
    SAVE.coop_charnier.defeat=1
    SAVE.coop_charnier.ingame=nil
    gameover(function() coop_show_run_stats(false) end)
end
function get_slot_data(team,i)
    if i>=mode.lvl_max then return nil end
    return {x=7+(i%2)*24+team*(MCW-48-14),y=13+(i-i%2)/2*32,team=team,village=1}
end
