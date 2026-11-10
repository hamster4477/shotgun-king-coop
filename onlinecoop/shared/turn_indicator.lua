-- Cosmetic only: do not consume gameplay RNG or send animation packets.
function coop_load_turn_indicator()
    newsrf("coop_player_icons","assets/gfx/player_runtime.png")
    mode.coop_turn_indicator=nil
end
function coop_draw_turn_indicator(player,active)
    local now=time()
    local state=mode.coop_turn_indicator
    if not state then
        state={player=player or 1,changed=now-1,blink=now+4}
        mode.coop_turn_indicator=state
    end
    if player and player~=state.player then
        state.player=player;state.changed=now;state.blink=now+4
    end
    if now>state.blink+.13 then state.blink=now+3.5+(sin(now*.17)+1)*1.2 end
    local frame=state.player==1 and 0 or (now>=state.blink and 1 or 2)
    local elapsed=now-state.changed
    local lift=elapsed<.24 and sin(elapsed/.48)*2 or 0
    lift=lift-lift%1
    local previous=spritesheet()
    spritesheet("coop_player_icons")
    if not active then pal(4,3);pal(5,3) end
    -- Sit immediately left of the ammunition HUD, with a three-pixel gap.
    sspr(frame*15,18,15,19,(MCW-128)/2-18,8-lift)
    pal();spritesheet(previous)
end
