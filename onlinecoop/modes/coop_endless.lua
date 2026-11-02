require("modes/coop.lua")
require("campaigns/common.lua")
coop_variant = "endless"
base = {chamber_max=2,firepower=4,firerange=3,spread=55,ammo_max=5,
    pawn_global_promote=1,surrender=1,gain={3,0,0,0,1,5,2,0},ai_lvl=1}
function coop_campaign_grow()
    if mode.lvl < 11 then
        level_up(coop_campaign_choices(mode.lvl==3), next_floor)
    else
        decay_up(next_floor)
    end
end
function on_hero_death()
    if mode.coop_stats then mode.coop_stats.running=false end
    mode.coop_run_active=false
    mode.coop_opening_king_turn=false
    SAVE.coop_endless_best=max(SAVE.coop_endless_best or 0,mode.lvl or 0)
    gameover(function() coop_show_run_stats(false) end)
end
