-- Commands shared by native mouse/keyboard and the validated LAN adapter.
function coop_knight_soul_usable(soul)
    return soul and ((soul.id==1 and coop_has_knight_skill("Co-op Knight Spirit"))
        or ((soul.id==2 or soul.id==3) and coop_has_knight_skill("Co-op In-Law")))
end
function coop_select_knight_soul(soul)
    local k=mode.coop_knight
    if not k or k.ready==false or not coop_knight_soul_usable(soul) then return false end
    mode.coop_knight_selected_soul=soul
    mode.coop_soul_selection_fx={x=soul.x,y=soul.y,frame=0}
    sfx("menu_in",.7)
    return true
end
function coop_cancel_knight_soul()
    mode.coop_knight_selected_soul=nil
    mode.coop_soul_selection_fx=nil
end
function coop_pass_knight_action()
    local k=mode.coop_knight
    if not k or k.ready==false or mode.coop_selected~="knight"
        or mode.coop_surrender_input_locked or coop_white_move_animation_pending() then return false end
    coop_cancel_knight_soul()
    k.ready=false
    coop_queue_warrant_knight_check(k)
    mode.coop_auto_select_knight_pending=nil
    mode.black_actions=1
    coop_set_selected("king")
    return true
end
function coop_revive_with_soul(soul)
    if not is_coop_active() or mode.coop_knight or not mode.knight_ever_died
        or not soul or soul.id~=1 or type(activate_soul)~="function" then return false end
    -- Go through the same native activation + shared completion hooks as a
    -- physical soul-card click. Do not duplicate consumption/refund handling.
    activate_soul(soul,hero.sq)
    return mode.coop_knight~=nil
end
