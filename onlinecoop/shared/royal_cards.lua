-- State belongs to each entity, so new floors and revived Knights start clean.
function coop_deflect_active(e)
    return is_coop_active() and e and e.sq and e.dead~=true and (e.hp or 0)>0
        and coop_is_white_king(e) and has_card("Co-op Deflect Armor")
end
function coop_deflect_shielded(e)
    return coop_deflect_active(e) and not e.coop_deflect_broken
end
function coop_saddle_bonus(e)
    return e and has_card("Co-op High Cantle Saddle")
        and e.coop_saddle_floor==mode.lvl and e.coop_saddle_turn==mode.turns and 2 or 0
end
function coop_royal_cards_turn()
    if not is_coop_active() then return end
    local key=tostr(mode.lvl)..":"..tostr(mode.turns)
    if mode.coop_abbey_turn==key then return end
    mode.coop_abbey_turn=key
    if not has_card("Co-op Abbey of Kings") then return end
    local healed={};local audible=false
    for _,king in ipairs(get_pieces(5)) do
        if king.sq and king.dead~=true and king.hp>0 then
            for dy=-1,1 do for dx=-1,1 do
                local p=coop_piece_on_square(gsq(king.sq.px+dx,king.sq.py+dy))
                if p and p.team==1 and not p.dead and p.hp and p.hp_max
                    and p.hp>0 and p.hp<p.hp_max and not healed[p] then
                    healed[p]=true;p.hp=min(p.hp+1,p.hp_max)
                    fx_emote(p,"heart");audible=true
                end
            end end
        end
    end
    if audible then sfx("healing") end
end
function coop_install_royal_cards()
    newsrf("coop_deflect_shield","assets/gfx/deflect_armor_runtime.png")
    -- Native projectile collision already produces MISS from dodge >= 100.
    prepend("get_dodge",function(e)
        if coop_deflect_shielded(e) and e.ready~=true then
            e.coop_deflect_saved_dodge=e.dodge;e.coop_deflect_dodge_override=true;e.dodge=100
        end
    end,"coop_deflect_dodge_before")
    append("get_dodge",function(e)
        if e and e.coop_deflect_dodge_override then
            e.dodge=e.coop_deflect_saved_dodge;e.coop_deflect_saved_dodge=nil;e.coop_deflect_dodge_override=nil
        end
    end,"coop_deflect_dodge_after")
    prepend("get_piece_tempo",function(e)
        if coop_deflect_shielded(e) then
            e.coop_deflect_saved_tempo=e.tempo;e.tempo=max(1,e.tempo-1)
        end
    end,"coop_deflect_tempo_before")
    append("get_piece_tempo",function(e)
        if e and e.coop_deflect_saved_tempo then e.tempo=e.coop_deflect_saved_tempo;e.coop_deflect_saved_tempo=nil end
    end,"coop_deflect_tempo_after")
    prepend("hit",function(e,dmg,at)
        if not coop_deflect_active(e) then return end
        at=at or {}
        local blade=at.blade or at.coop_stats_owner==2
        if blade and not e.coop_deflect_broken then
            e.coop_deflect_broken=true;e.coop_deflect_break_turn=mode.turns
            sfx("shield")
        end
        if at.bullet and coop_deflect_shielded(e) and e.ready==true
            and e.coop_deflect_break_turn~=mode.turns then
            if e.coop_deflect_shot_turn~=mode.turns then
                e.coop_deflect_shot_turn=mode.turns;e.coop_deflect_shot_damage=0
            end
            e.coop_deflect_saved_cap=e.dmg_cap
            e.coop_deflect_cap_override=true;e.coop_deflect_before_hp=e.hp
            e.dmg_cap=min(e.dmg_cap or 1,max(0,1-(e.coop_deflect_shot_damage or 0)))
        end
        if (at.bullet and not e.coop_deflect_broken and e.ready~=true)
            or e.coop_deflect_break_turn==mode.turns then
            -- The native shield check returns before HP/death/escape effects.
            e.c_protected=16
        end
    end,"coop_deflect_hit")
    append("hit",function(e)
        if not e or not e.coop_deflect_cap_override then return end
        local lost=max(0,(e.coop_deflect_before_hp or e.hp)-e.hp)
        e.coop_deflect_shot_damage=(e.coop_deflect_shot_damage or 0)+lost
        local cap=e.coop_deflect_saved_cap
        e.dmg_cap=cap and max(0,cap-lost) or nil
        e.coop_deflect_cap_override=nil;e.coop_deflect_saved_cap=nil
        e.coop_deflect_before_hp=nil
    end,"coop_deflect_hit_restore")
    prepend("move_piece",function(e,sq)
        if coop_deflect_active(e) and sq and sq~=e.sq then
            e.coop_deflect_broken=nil;e.coop_deflect_break_turn=nil
        end
    end,"coop_deflect_move")
    append("init_new_turn",coop_royal_cards_turn,"coop_abbey_heal")
    append("dr_piece",function(e,x,y)
        if not coop_deflect_shielded(e) then return end
        spritesheet("coop_deflect_shield")
        sspr(0,0,9,10,x+8,y+5+(e.z or 0))
        spritesheet("gfx")
    end,"coop_deflect_draw")
end
