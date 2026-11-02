-- Mobile 2x2 reinforcement boss. One native alt_move owns each volley;
-- no input hook, polling timer or second enemy-turn driver is introduced.
function coop_marshal_live()
    local e=mode and mode.coop_bounty_marshal
    if not e or e.dead or not e.sq or not e.hp or e.hp<=0 then return nil end
    return e
end

function coop_marshal_close(e,sq)
    if not e or not e.sq or not sq then return false end
    local dx=max(max(e.sq.px-sq.px,0),sq.px-e.sq.px-1)
    local dy=max(max(e.sq.py-sq.py,0),sq.py-e.sq.py-1)
    if dx==0 and dy==0 then return false end
    return (dx==0 and dy<=2) or (dy==0 and dx<=2) or (dx==1 and dy==1)
end

function coop_marshal_aim(e)
    if not e or not e.sq then return end
    local x,y=e.sq.px,e.sq.py
    local targets={}
    if hero and hero.sq and not hero.dead and (hero.hp or 1)>0
        and (not hero.cloaked or e.uncover) then targets[#targets+1]=hero.sq end
    local knight=mode and mode.coop_knight
    if knight and knight.sq and not knight.dead and (knight.hp or 1)>0 then
        targets[#targets+1]=knight.sq
    end
    -- Each side of a 2x2 piece has two possible single-square firing lanes.
    -- Prefer a lane that actually contains a target, not merely its quadrant.
    local lanes={}
    for offset=0,1 do
        lanes[#lanes+1]={x+2,y+offset,1,0}
        lanes[#lanes+1]={x-1,y+offset,-1,0}
        lanes[#lanes+1]={x+offset,y+2,0,1}
        lanes[#lanes+1]={x+offset,y-1,0,-1}
    end
    -- A diagonal exits from three cells of the 2x2 footprint. Include every
    -- exposed lane, but never start a ray inside the boss's own body.
    for _,vx in ipairs({-1,1}) do for _,vy in ipairs({-1,1}) do
        for ox=0,1 do for oy=0,1 do
            local nx,ny=ox+vx,oy+vy
            if nx<0 or nx>1 or ny<0 or ny>1 then
                lanes[#lanes+1]={x+nx,y+ny,vx,vy}
            end
        end end
    end end
    local best
    for _,lane in ipairs(lanes) do
        local candidate={sx=lane[1],sy=lane[2],vx=lane[3],vy=lane[4],
            ray={},hits=0,nearest=99,gap=99}
        for step=0,7 do
            local sq=gsq(lane[1]+step*lane[3],lane[2]+step*lane[4])
            if not sq then break end
            candidate.ray[#candidate.ray+1]=sq
            for _,target in ipairs(targets) do
                local gap=abs(sq.px-target.px)+abs(sq.py-target.py)
                if gap<candidate.gap then candidate.gap=gap end
                if gap==0 then
                    candidate.hits=candidate.hits+1
                    if step<candidate.nearest then candidate.nearest=step end
                end
            end
        end
        if #candidate.ray>0 and (not best or candidate.hits>best.hits
            or candidate.hits==best.hits and candidate.nearest<best.nearest
            or candidate.hits==best.hits and candidate.nearest==best.nearest
                and candidate.gap<best.gap) then best=candidate end
    end
    if not best then return end
    e.coop_marshal_phase="fire"
    e.coop_aim_origin=e.sq
    e.coop_ray=best.ray
    e.coop_ray_spent=false
    e.coop_aim_dx=best.vx;e.coop_aim_dy=best.vy
    e.coop_aim_started=time()
    e.coop_muzzle_x=best.sx-best.vx+.5
    e.coop_muzzle_y=best.sy-best.vy+.5
    if _log then _log("[COOP MARSHAL] locked lane; targets="..best.hits
        .." direction="..best.vx..","..best.vy.." squares="..#best.ray) end
end

function coop_marshal_in_ray(e,sq)
    if not sq or e.coop_marshal_phase~="fire" or e.coop_ray_spent then return false end
    for _,target in ipairs(e.coop_ray or {}) do
        if target==sq then return true end
    end
    return false
end

function coop_marshal_danger()
    local e=coop_marshal_live()
    if not e or not is_coop_active() or mode.coop_floor_transition
        or e.stun or e.peace or e.fear or e.jail then return end
    if hero.cloaked and not e.uncover then return end
    -- Use the actual living attacker in the native danger list. The original
    -- check_folly_shields owns charges, repeated clicks and unsafe overrides.
    local threatened={}
    for y=0,7 do for x=0,7 do
        local sq=gsq(x,y)
        if sq and (coop_marshal_close(e,sq) or coop_marshal_in_ray(e,sq)) then
            threatened[#threatened+1]=sq
        end
    end end
    for _,sq in ipairs(threatened) do
        local present=false
        for _,p in ipairs(sq.danger or {}) do if p==e then present=true end end
        if not present then add(sq.danger,e) end
    end
end

function coop_marshal_reinforce(e)
    local available={}
    for dy=-1,2 do
        for dx=-1,2 do
            if dx==-1 or dx==2 or dy==-1 or dy==2 then
                local sq=gsq(e.sq.px+dx,e.sq.py+dy)
                if sq and is_free(sq) and not coop_piece_on_square(sq)
                    and not sq.moat and not coop_has_barricade(sq) then
                    available[#available+1]=sq
                end
            end
        end
    end
    if #available==0 then return end
    e.coop_spawn_index=(e.coop_spawn_index or 0)+1
    local sq=available[1+(e.coop_spawn_index-1)%#available]
    local rider=new_piece(1,true,sq)
    rider.cd=0
    rider.ready=false
    fx_spawn(rider)
    mode.coop_bounty_notice={floor=mode.lvl,started=time(),piece_type=1,count=1}
end

function coop_marshal_reinforce_tick(e)
    e.coop_reinforce_round=(e.coop_reinforce_round or 0)+1
    if e.coop_reinforce_round%2==0 then coop_marshal_reinforce(e) end
end

function coop_marshal_volley(e)
    if e~=coop_marshal_live() or not is_coop_active() or e.coop_action_pending
        or e.coop_action_turn==mode.turns or e.stun or e.fear or e.jail
        or mode.coop_floor_transition then return false end
    e.coop_action_pending=true
    e.coop_action_turn=mode.turns
    local phase=e.coop_marshal_phase or "aim"
    -- Native opp_move exhausts the piece after alt_move returns true.
    wait(12,function()
        if e~=coop_marshal_live() or not is_coop_active() or mode.coop_floor_transition then
            e.coop_action_pending=nil
            if is_coop_active() then opp_turn() end
            return
        end
        local knight=mode.coop_knight
        -- Point-blank defence is always active; the long shot is fire-phase only.
        local king_hit=not e.peace and hero and not hero.cloaked
            and (coop_marshal_close(e,hero.sq) or coop_marshal_in_ray(e,hero.sq))
        local knight_hit=not e.peace and knight and not knight.dead and knight.sq
            and (coop_marshal_close(e,knight.sq) or coop_marshal_in_ray(e,knight.sq))
        if phase=="fire" or king_hit or knight_hit then
            e.coop_shot_until=time()+.22
            -- Visual state is captured before the phase changes. The rifle
            -- keeps its locked direction throughout recoil and recovery.
            local dx,dy=e.coop_aim_dx or 0,e.coop_aim_dy or 1
            if phase~="fire" then
                local target=king_hit and hero or knight
                dx=target.sq.px-e.sq.px-.5
                dy=target.sq.py-e.sq.py-.5
            end
            e.coop_art_shot={started=time(),dx=dx,dy=dy,lane=phase=="fire"}
            sfx("shoot")
        end
        if phase=="aim" then
            coop_marshal_aim(e)
        elseif phase=="fire" then
            e.coop_ray_spent=true
            e.coop_marshal_phase="move"
        else
            e.coop_ray_spent=true
            e.coop_marshal_phase="aim"
        end
        if knight_hit then
            hit(knight,max(1,knight.hp or 1))
            if mode.coop_knight==knight then coop_mark_knight_dead(knight) end
        end
        if _log then _log("[COOP MARSHAL] phase="..phase
            .." knight="..(knight_hit and "hit" or "safe")
            .." king="..(king_hit and "hit" or "safe")) end
        local function finish_action()
            e.coop_action_pending=nil
            if e~=coop_marshal_live() or not is_coop_active() then return end
            coop_marshal_reinforce_tick(e)
            opp_move()
        end
        if king_hit then
            e.coop_action_pending=nil
            coop_marshal_reinforce_tick(e)
            xpl_king(hero)
        elseif phase=="move" then
            -- Resolve the OLD position's close defence first. There is no
            -- second hit on arrival: the player has the next action to escape.
            local destination=choose_piece_move(e)
            if destination then
                e.coop_art_move_started=time()
                move_piece(e,destination,function()
                    e.coop_art_move_started=nil
                    e.coop_art_land_started=time()
                    finish_action()
                end)
            else wait(12,finish_action) end
        else
            wait(12,finish_action)
        end
    end)
    return true
end

function coop_marshal_draw()
    local e=coop_marshal_live()
    if not e or not is_coop_active() or mode.coop_floor_transition
        or mode.coop_pause_menu_open or mode.coop_hidden_boss_pending then return end
    local bx,by=coop_get_board_geometry()
    local firing=e.coop_shot_until and time()<e.coop_shot_until
        and e.coop_art_shot and e.coop_art_shot.lane
    if firing then
        local first,last=e.coop_ray[1],e.coop_ray[#e.coop_ray]
        if first and last then
            -- Only the actual shot has a continuous, briefly bright tracer.
            line(bx+first.px*16+8,by+first.py*16+8,
                bx+last.px*16+8,by+last.py*16+8,4)
        end
    elseif e.coop_marshal_phase=="fire" and not e.coop_ray_spent then
        -- Slim red dashes at tile edges leave the centers/figures unobscured.
        -- These use the SAME locked squares as damage and folly warnings.
        local horizontal=e.coop_aim_dx~=0
        local diagonal=horizontal and e.coop_aim_dy~=0
        for _,sq in ipairs(e.coop_ray or {}) do
            local x,y=bx+sq.px*16,by+sq.py*16
            if diagonal then
                if e.coop_aim_dx==e.coop_aim_dy then
                    line(x,y,x+3,y+3,5);line(x+12,y+12,x+15,y+15,5)
                else
                    line(x,y+15,x+3,y+12,5);line(x+12,y+3,x+15,y,5)
                end
            elseif horizontal then
                line(x,y+8,x+3,y+8,5);line(x+12,y+8,x+15,y+8,5)
            else
                line(x+8,y,x+8,y+3,5);line(x+8,y+12,x+8,y+15,5)
            end
        end
    end
end

function coop_marshal_spawn_square(origin)
    -- Prefer the upper edge, but never overwrite the King or an ally.
    if origin then
        for _,offset in ipairs({{0,0},{-1,0},{0,-1},{-1,-1}}) do
            local x,y=origin.px+offset[1],origin.py+offset[2]
            local free=true
            for dy=0,1 do for dx=0,1 do
                local sq=gsq(x+dx,y+dy)
                if not sq or not is_free(sq) or coop_piece_on_square(sq)
                    or sq.moat or coop_has_barricade(sq) then free=false end
            end end
            if free then return gsq(x,y) end
        end
    end
    for y=0,6 do
        for _,x in ipairs({3,2,4,1,5,0,6}) do
            local free=true
            for dy=0,1 do for dx=0,1 do
                local sq=gsq(x+dx,y+dy)
                if not sq or not is_free(sq) or coop_piece_on_square(sq)
                    or sq.moat or coop_has_barricade(sq) then free=false end
            end end
            if free then return gsq(x,y) end
        end
    end
end

function coop_marshal_candidate()
    for _,e in ipairs(bads or {}) do
        if e.name=="warrant_knight" and e.team==1 and e.sq
            and not e.dead and (e.hp or 0)>0 then return e end
    end
end

function coop_begin_bounty_marshal(candidate)
    local run=mode
    local token={}
    mode.coop_marshal_transition=token
    local function current() return mode==run and mode.coop_marshal_transition==token
        and mode.coop_hidden_boss_pending=="marshal" end
    local cards={}
    for _,id in ipairs({"Co-op Warrant","Co-op Bounty Cavalry"}) do
        local ca=get_slot_card(id)
        if ca then cards[#cards+1]={card=ca,draw=ca.dr,slot=ca.sl} end
    end
    local consumed=false
    local function consume_cards()
        if not current() or consumed then return end
        consumed=true
        for _,entry in ipairs(cards) do
            local ca=entry.card
            ca.dr=entry.draw
            if ca.sl and ca.sl.ca==ca then ca.sl.ca=nil end
            kl(ca)
        end
        -- Keep the gifted card black, but display it in the vacated white
        -- slot for this final battle. Never duplicate an already owned card.
        if not has_card("Co-op Knight Spirit") then
            local slot=cards[1] and cards[1].slot
            if slot and not slot.ca then
                local gift=new_card("Co-op Knight Spirit")
                gift.sl=slot;slot.ca=gift;gift.x=slot.x;gift.y=slot.y;gift.c_show=60
            end
        end
        build_stack()
        mode.coop_bounty_pending={}
        mode.coop_warrant_check_pending=nil
    end
    local function awaken()
        if not current() then return end
        if not candidate or candidate.dead or not candidate.sq or (candidate.hp or 0)<=0 then
            coop_finish_throne_story();return
        end
        -- Native storm treats any chosen non-Knight/non-Queen as the dark
        -- Bishop: it sets bad=false and c_bishop_mute, recoloring this officer
        -- black. Exclude him from that conversion; the local lightning below
        -- owns his transformation after the rest of the board is cleared.
        local stormed=candidate.stormed
        candidate.stormed=true
        storm_all_but(candidate,function()
            candidate.stormed=stormed
            if not current() then return end
            coop_duel_lightning(candidate)
            fx_emote(candidate,current_lang=="simplified_chinese" and "蠢货白王" or "Foolish White King!",75,function()
                if not current() then return end
                local origin=candidate.sq
                leave_sq(candidate);del(bads,candidate);kl(candidate)
                local square=coop_marshal_spawn_square(origin)
                local typ
                for _,definition in ipairs(PIECES) do
                    if definition.name=="bounty_marshal" then typ=definition.type;break end
                end
                if not square or not typ then
                    if _log then _log("[COOP MARSHAL] no safe 2x2 spawn; finish ending") end
                    coop_finish_throne_story()
                    return
                end
                local e=new_piece(typ,true,square)
                mode.coop_bounty_marshal=e
                e.cd=1;e.ready=true
                e.alt_move=function() return coop_marshal_volley(e) end
                e.coop_marshal_phase="aim"
                e.coop_ray_spent=true
                e.coop_ray={}
                if isfile("assets/gfx/bounty_marshal.png") then
                    newsrf("coop_bounty_marshal","assets/gfx/bounty_marshal.png")
                    e.coop_custom_marshal_art=true
                end
                fx_spawn(e)
                inter.bossfight=1
                start_music("boss_queen_A")
                if _log then _log("[COOP MARSHAL] reinforcement boss spawned") end
                wait(60,function()
                    if current() and e==coop_marshal_live() then clean_up(refill_ammo) end
                end)
            end)
        end)
    end
    local function fly()
        if not current() then return end
        if not candidate or candidate.dead or not candidate.sq or (candidate.hp or 0)<=0 then
            consume_cards();coop_finish_throne_story();return
        end
        if #cards==0 then consume_cards();awaken();return end
        local arrived=0
        for _,entry in ipairs(cards) do
            local ca=entry.card
            local light=mke(0,ca.x+10,ca.y+14);light.dp=DP_FX
            light.dr=function(o,x,y)
                if current() then circfill(x,y,max(12-o.t/2,1)+rnd(2),5) end
            end
            light.twcv=ease_in_out
            mvt(light,candidate.x+8,candidate.y+8,90,function()
                if not current() then return end
                kl(light);arrived=arrived+1
                if arrived==#cards then awaken() end
            end)
        end
        -- Both lights originate while their cards are still on screen.
        wait(12,consume_cards)
    end
    local function blink(step)
        if not current() then return end
        for _,entry in ipairs(cards) do
            entry.card.dr=step%2==0 and entry.draw or function() end
        end
        if step<4 then wait(10,function() blink(step+1) end);return end
        fly()
    end
    sfx("show_book")
    blink(1)
end
