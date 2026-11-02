-- LAN owns input and presentation only. Combat and campaigns live in shared/.
local local_initialize=initialize
local local_start=start

coop_controller={
    native_choice_waiting=function() return mode.net.native_choice~=nil or (mode.net.campaign_scene and mode.net.campaign_scene.kind==2) end,
    show_stats=onlinecoop_results_show,
    can_restart=function() return mode.net.role=="host" end,
    begin_choices=onlinecoop_choices_begin,
    choice_button=onlinecoop_choices_button,
    owns_input=function()
        local n=mode.net
        return n and n.role=="host" and n.peer_ok
            and onlinecoop_lan.status=="connected" and not n.cg_active
            and mode.coop_selected~="knight"
    end,
    can_switch=function() return false end,
    weapon_aim=function(knight,angle,spear)
        local n=mode.net
        if n and n.role=="host" then
            angle=n.remote_aim or -.125
            knight.coop_weapon_angle=angle
            local x,y=n.remote_cell_x,n.remote_cell_y
            spear=x and y and x>=0 and y>=0 and x<=7 and y<=7
                and not coop_knight_soul_ready(knight)
                and coop_knight_can_spear_square(knight,gsq(x,y)) or false
        end
        return angle,spear
    end,
    hover=function(mx,my)
        local n=mode.net
        if n and n.role=="host" then
            local x,y=n.remote_cell_x,n.remote_cell_y
            if x and y and x>=0 and y>=0 and x<=7 and y<=7 then
                local bx,by=coop_get_board_geometry()
                return bx+x*16+8,by+y*16+8
            end
            return -100,-100
        end
        return mx,my
    end,
}

function initialize()
    for _,entry in ipairs(MODLIST or {}) do
        if entry.name=="onlinecoop" and entry.lan_lobby and entry.lan_lobby.enter(coop_variant and ("onlinecoop_"..coop_variant) or "onlinecoop") then
            newbnk(128,64,4)
            mode.coop_lobby_only=true
            mode.ranks_index=0;mode.weapons_index=0
            mode.sel=1;mode.weapon_sel=1;mode.rank_sel=1
            return
        end
    end
    local_initialize()
    onlinecoop_net_initialize()
end

function start()
    if not mode.net or mode.net.role~="host" or not mode.net.peer_ok or mode.net.cg_active
        or not onlinecoop_lan or onlinecoop_lan.status~="connected" then return end
    onlinecoop_results_restart()
    local_start()
end

function onlinecoop_execute_knight_action(target)
    if onlinecoop_net_phase()~=2 then return false end
    local result=coop_perform_knight_action(mode.coop_knight,target)
    if result then onlinecoop_remember_knight_events() end
    return result
end

-- Pick the sequence on the authoritative host once. Both players render the
-- exact shared story assets/captions; native callbacks never cross the wire.
function coop_start_story(ending,done)
    local available=isfile("assets/gfx/coop_cg.png")
    local seq=coop_story_sequence(ending,not available)
    onlinecoop_play_cg(ending and 3 or 1,done,nil,seq)
end
function coop_start_boss_story(done)
    onlinecoop_play_cg(2,done,nil,coop_floor12_story_sequence())
end
