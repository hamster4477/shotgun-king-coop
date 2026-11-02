-- Loaded after the shared controller; mode filename/game_mode select the menu entry.
-- Internal id stays coop for existing card and input hooks.
intro = false
weapons = nil
ranks = nil
function check_unlocks() end
function save_preferences() end
function coop_campaign_choices(homecoming)
    local data = {id="level_up", pan_xm=1, pan_ym=2, pan_width=80, pan_height=96,
        choices={{{team=0},{team=1}},{{team=0},{team=1}}}}
    if homecoming then
        for i=1,2 do data.choices[i][2].id="Homecoming" end
    end
    return data
end

-- These campaigns never enter Throne's rank-unlock ending.
function on_boss_death()
    on_empty()
end
