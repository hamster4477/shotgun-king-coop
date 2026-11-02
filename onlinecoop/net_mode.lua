-- Included in the mode environment, not run as received network code.
local ONLINE_BUILD = "unified72lan1"
local function net_join(values,separator)
    local text=""
    for i,v in ipairs(values) do text=text .. (i>1 and separator or "") .. v end
    return text
end
local function net_split(text,separator)
    local values,first={},1
    for i=1,#text do
        if sub(text,i,i)==separator then values[#values+1]=sub(text,first,i-1); first=i+1 end
    end
    values[#values+1]=sub(text,first)
    return values
end

function onlinecoop_presentation_active()
    if not mode or not hero or not hero.sq or mode.coop_stats_screen then return false end
    return is_coop_active() or mode.coop_book_scene or mode.coop_duel
        or mode.coop_hidden_boss_pending or mode.coop_throne_finishing
end

-- Knight hits can queue native effects (for example Emergency Call) that native
-- play() only consumes after the King's action. A queued callback is not an
-- animation in progress. Remember only this exact, untouched queue; any
-- native consumption, new event, new turn or new floor invalidates the marker.
function onlinecoop_remember_knight_events()
    local n=mode.net
    n.knight_waiting_events=nil
    if type(events)~="table" or #events==0 then return end
    local pending={floor=mode.lvl,turn=mode.turns,queue=events,items={}}
    for i,event in ipairs(events) do pending.items[i]=event end
    n.knight_waiting_events=pending
    _log("[ONLINE QUEUED EVENTS] Knight action left "..#events.." callbacks for native King action")
end
function onlinecoop_knight_events_waiting()
    local n=mode.net;local pending=n.knight_waiting_events
    if not pending then return false end
    local same=pending.floor==mode.lvl and pending.turn==mode.turns
        and pending.queue==events and #pending.items==#events
    if same then
        for i,event in ipairs(events) do
            if pending.items[i]~=event then same=false;break end
        end
    end
    if not same then n.knight_waiting_events=nil;return false end
    return mode.coop_selected=="king"
end

function onlinecoop_net_phase()
    if not onlinecoop_lan or onlinecoop_lan.status ~= "connected" then return 7 end
    if not mode.net.peer_ok then return 8 end
    if mode.net.cg_active then return mode.net.cg_active==1 and 0 or 4 end
    if mode.net.draft and mode.net.draft.active then return 4 end
    if onlinecoop_choices_live() then return 4 end
    if mode.net.native_choice or (mode.net.campaign_scene and mode.net.campaign_scene.kind~=0) then return 4 end
    if disrupt_menu then return 4 end
    if not is_coop_active() then return 0 end
    if hero.dead or (hero.hp and hero.hp <= 0) then return 5 end
    if mode.coop_pause_menu_open then return 6 end
    if coop_floor_is_ending() then return 4 end
    if mode.coop_native_turn_in_progress or mode.coop_spawn_wait_for_turn
        or mode.coop_select_king_pending or mode.coop_auto_select_knight_pending
        or mode.coop_king_move_input_locked or coop_white_move_animation_pending()
        or hero.in_move or (type(events)=="table" and #events>0
            and not onlinecoop_knight_events_waiting()) then return 3 end
    local knight=mode.coop_knight
    if knight and knight.in_move then return 3 end
    if mode.coop_selected=="knight" then
        if knight and knight.sq and knight.ready~=false then return 2 end
        return 3
    end
    return 1
end

function onlinecoop_net_id(piece)
    if not piece then return 0 end
    if not piece.online_net_id then
        mode.net.next_id=mode.net.next_id+1
        piece.online_net_id=mode.net.next_id
    end
    return piece.online_net_id
end

local function net_int(value, default)
    if type(value)~="number" then return default or 0 end
    return max(0,min(1000000,value-value%1))
end
local function net_list(records)
    return #records>0 and net_join(records,"_") or "-"
end
function onlinecoop_net_soul(index)
    if type(souls)~="table" then return nil end
    return souls[index]
end
function onlinecoop_net_soul_usable(soul)
    return coop_knight_soul_usable(soul)
end
function onlinecoop_net_moves(knight)
    if coop_knight_soul_ready(knight) then return coop_get_knight_input_targets(knight) end
    return coop_get_knight_move_targets(knight)
end
function onlinecoop_net_board_identity()
    local n=mode.net
    -- Observe the actual board identity. mk_grid also recalculates threats
    -- during normal turns and is not a reliable level-entry event.
    if onlinecoop_presentation_active() then
        local square=gsq(0,0)
        if square and square~=n.board_reference then
            n.board_reference=square
            n.board_serial=(n.board_serial or 0)+1
        end
    end
    return n.board_serial or 0
end
function onlinecoop_net_state()
    local n=mode.net
    onlinecoop_net_board_identity()
    local phase=onlinecoop_net_phase()
    if phase~=n.last_phase then n.epoch=n.epoch+1; n.last_phase=phase end
    local knight=mode.coop_knight
    local header=net_join({mode.lvl or 0,mode.turns or 0,phase,n.epoch,
        onlinecoop_net_id(hero),onlinecoop_net_id(knight),n.board_serial or 0},",")
    local units,moves,attacks,deck,slots,terrain={},{},{},{},{},{}
    local seen_pieces={}
    local selected=0
    if onlinecoop_presentation_active() then
        for y=0,7 do for x=0,7 do
            local sq=gsq(x,y)
            local p=coop_piece_on_square(sq)
            if p and not seen_pieces[p] and not p.dead and (not p.hp or p.hp>0) then
                seen_pieces[p]=true
                units[#units+1]=net_join({onlinecoop_net_id(p),p.sq.px,p.sq.py,net_int(p.type),net_int(p.team),
                    net_int(p.hp,1),p.ready and 1 or 0,net_int(p.cd),net_int(p.hp_max or p.max_hp,p.hp or 1),
                    p.coop_phantom and 1 or 0},",")
            end
            local ground=coop_has_barricade(sq) and 1 or (sq.moat and 2 or ((sq.penta or sq.pentagram) and 3 or 0))
            if ground>0 then terrain[#terrain+1]=x..","..y..","..ground end
        end end
        if phase==2 then
            for _,sq in ipairs(onlinecoop_net_moves(knight)) do moves[#moves+1]=sq.px..","..sq.py end
            if not coop_knight_soul_ready(knight) then
                for y=0,7 do for x=0,7 do
                    if coop_knight_can_attack_target(knight,gsq(x,y)) then attacks[#attacks+1]=x..","..y end
                end end
            end
        end
        for i,soul in ipairs(souls or {}) do
            if i<=12 then
                if soul==mode.coop_knight_selected_soul then selected=i end
                slots[#slots+1]=net_join({i,net_int(soul.id),onlinecoop_net_soul_usable(soul) and 1 or 0},",")
            end
        end
        -- Catalog IDs identify card types, not owned copies. Read native slots
        -- in their actual order so repeated cards occupy separate client slots.
        local catalog={}
        for i,card in ipairs(CARDS) do
            if card.id then catalog[card.id]=i end
        end
        for _,card in ipairs(get_slot_cards(true)) do
            local i=catalog[card.id]
            if i then
                deck[#deck+1]=net_join({i,net_int(card.gid,CARDS[i].gid),net_int(card.team,CARDS[i].team)},",")
            end
        end
        n.owned_deck=deck
    else
        -- Native floor teardown temporarily removes the hero/board before
        -- level_up opens. Keep the last owned copies through the draft.
        deck=n.owned_deck or {}
    end
    local stats=stack or {}
    local charge=mode.coop_knight_charge
    local ability=is_coop_active() and has_card and has_card("Co-op Mechanism Order")
    local ui={net_int(chamber),net_int(stats.chamber_max),net_int(ammo),net_int((stats.firepower or 0)+1000),
        net_int(stats.spread),net_int((stats.firerange or 0)+1000),net_int(stats.blade),
        knight and net_int(coop_knight_blade_damage(knight)) or 0,#slots,
        ability and (coop_can_activate_mechanism_order() and phase==2 and 1 or 2) or 0,selected,
        (phase==1 and mode.knight_ever_died and not knight and not mode.coop_spawning) and 1 or 0,
        charge and charge.target_px+1 or 0,charge and charge.target_py+1 or 0,
        is_coop_active() and has_card and has_card("Co-op Timar Cavalry Pact") and 1 or 0,
        get_coop_warrant_type() or 0,net_int(mode.weapons_index),net_int(n.attack_serial),
        net_int(n.attack_x),net_int(n.attack_y)}
    return header..":"..net_list(units)..":"..net_list(moves)..":"..net_list(attacks)
        ..":"..net_join(ui,",")..":"..net_list(slots)..":"..net_list(deck)..":"..net_list(terrain)
end

function onlinecoop_net_numbers(text, count, maximum)
    local fields=net_split(text,",")
    if #fields~=count then return nil end
    for i,v in ipairs(fields) do
        if not match(v,"^%d+$") then return nil end
        fields[i]=tonum(v)
        if fields[i]<0 or fields[i]>maximum then return nil end
    end
    return fields
end

function onlinecoop_net_snapshot(payload)
    local chunks=net_split(payload,":")
    if #chunks~=9 then return false end
    local revision=match(chunks[1],"^S2,(%d+)$")
    if not revision or #revision>9 or tonum(revision)<=mode.net.revision then return false end
    local h=onlinecoop_net_numbers(chunks[2],7,1000000)
    if not h or h[3]>8 then return false end
    local snapshot={floor=h[1],turn=h[2],phase=h[3],epoch=h[4],king=h[5],knight=h[6],board=h[7],units={},moves={},attacks={}}
    if chunks[3]~="-" then
        local ids,occupied={},{}
        for _,record in ipairs(net_split(chunks[3],"_")) do
            local p=onlinecoop_net_numbers(record,10,1000000)
            if not p or p[1]<1 or p[2]>7 or p[3]>7 or p[5]>1 or p[7]>1 or p[10]>1 then return false end
            local cell=p[2]+p[3]*8
            if ids[p[1]] or occupied[cell] then return false end
            ids[p[1]],occupied[cell]=true,true
            snapshot.units[#snapshot.units+1]=p
        end
        if #snapshot.units>64 then return false end
    end
    for index=4,5 do
        if chunks[index]~="-" then
            local records=net_split(chunks[index],"_")
            if #records>64 then return false end
            for _,record in ipairs(records) do
                local p=onlinecoop_net_numbers(record,2,7)
                if not p then return false end
                local targets=index==4 and snapshot.moves or snapshot.attacks
                targets[#targets+1]=p
            end
        end
    end
    snapshot.ui=onlinecoop_net_numbers(chunks[6],20,1000000)
    if not snapshot.ui or snapshot.ui[9]>12 or snapshot.ui[10]>2 or snapshot.ui[11]>12
        or snapshot.ui[12]>1 or snapshot.ui[13]>8 or snapshot.ui[14]>8 then return false end
    snapshot.souls,snapshot.cards,snapshot.terrain={},{},{}
    for index=7,9 do
        if chunks[index]~="-" then
            local records=net_split(chunks[index],"_")
            if #records>(index==7 and 12 or (index==8 and 256 or 64)) then return false end
            local seen={}
            for _,record in ipairs(records) do
                local p=onlinecoop_net_numbers(record,3,1000000)
                if not p then return false end
                if index==7 then
                    if p[1]<1 or p[1]>12 or p[2]>5 or p[3]>1 or seen[p[1]] then return false end
                    snapshot.souls[#snapshot.souls+1]=p
                elseif index==8 then
                    if not CARDS[p[1]] or p[2]>199 or p[3]>1 then return false end
                    snapshot.cards[#snapshot.cards+1]=p
                else
                    if p[1]>7 or p[2]>7 or p[3]<1 or p[3]>3 then return false end
                    snapshot.terrain[#snapshot.terrain+1]=p
                end
                seen[p[1]]=true
            end
        end
    end
    if #snapshot.souls~=snapshot.ui[9] then return false end
    snapshot.received=time()
    local old=mode.net.snapshot
    if old and old.floor==snapshot.floor then
        if snapshot.ui[18]~=old.ui[18] then
            mode.net.swing_started=time()
            sfx("blade")
        end
        if snapshot.ui[11]~=old.ui[11] then sfx(snapshot.ui[11]>0 and "menu_in" or "menu_out",.6) end
        for i,slot in ipairs(snapshot.souls) do
            if old.souls[i] and old.souls[i][2]>0 and slot[2]==0 then
                mode.net.soul_fx={index=i,started=time()}
            end
        end
    end
    mode.net.revision=tonum(revision)
    mode.net.snapshot=snapshot
    onlinecoop_events_snapshot(old,snapshot)
    _log("[ONLINE SNAPSHOT] rev=" .. revision .. " floor=" .. h[1] .. " turn=" .. h[2] .. " phase=" .. h[3] .. " pieces=" .. #snapshot.units)
    return true
end

function onlinecoop_net_request(kind,x,y)
    local n=mode.net
    local s=n.snapshot
    if n.role~="client" or n.pending or not n.peer_ok or not s or onlinecoop_playback_busy() or onlinecoop_events_busy() or (s.phase~=2 and not (kind=="revive" and s.phase==1))
        or (n.await_revision and n.revision<=n.await_revision)
        or onlinecoop_lan.status~="connected" then return false end
    local id=n.next_command+1
    local message=net_join({"R1",id,n.revision,s.floor,s.turn,s.epoch,kind,x or 0,y or 0},",")
    if not onlinecoop_lan.send("data",message) then return false end
    n.next_command=id
    n.await_revision=n.revision
    n.pending=id
    n.last_request=message
    _log("[ONLINE REQUEST] " .. message)
    return true
end

function onlinecoop_net_apply_request(payload)
    local n=mode.net
    local p=net_split(payload,",")
    if #p~=9 or p[1]~="R1" then return end
    local a=onlinecoop_net_numbers(net_join({p[2],p[3],p[4],p[5],p[6],p[8],p[9]},","),7,1000000)
    if not a then return end
    local reason="invalid"
    if a[1]<=n.last_command then
        reason="duplicate"
    else
        n.last_command=a[1]
        if a[1]~=n.expected_command then reason="sequence"
        elseif not n.peer_ok then reason="version"
        elseif a[2]~=n.revision or a[3]~=mode.lvl or a[4]~=mode.turns or a[5]~=n.epoch then reason="stale"
        elseif n.applying or onlinecoop_playback_busy() then reason="phase"
        else
            local phase=onlinecoop_net_phase()
            local kind=p[7]
            local knight=mode.coop_knight
            local allowed=false
            local target
            if kind=="revive" then allowed=phase==1 and not knight and mode.knight_ever_died
            elseif phase==2 then
                if kind=="soul" or kind=="cancel" or kind=="skip" or kind=="mechanism" then allowed=true
                elseif kind=="move" or kind=="attack" then
                    if a[6]<=7 and a[7]<=7 then
                        target=gsq(a[6],a[7])
                        if kind=="move" then
                            for _,sq in ipairs(onlinecoop_net_moves(knight)) do if sq==target then allowed=true break end end
                        else allowed=not coop_knight_soul_ready(knight) and coop_knight_can_attack_target(knight,target) end
                    end
                end
            end
            if allowed then
                n.applying=true
                if kind=="soul" then
                    local soul=onlinecoop_net_soul(a[6])
                    if soul and soul.id==a[7] and coop_select_knight_soul(soul) then
                        reason="ok"
                    end
                elseif kind=="cancel" then
                    coop_cancel_knight_soul()
                    reason="ok"
                elseif kind=="revive" then
                    local soul=onlinecoop_net_soul(a[6])
                    if a[7]==1 and coop_revive_with_soul(soul) then reason="ok" end
                elseif kind=="mechanism" then
                    if coop_activate_mechanism_order() then
                        mode.coop_knight_selected_soul=nil; mode.coop_soul_selection_fx=nil
                        mode.coop_select_king_pending=true; reason="ok"
                    end
                elseif kind=="skip" then
                    if coop_pass_knight_action() then reason="ok" end
                elseif onlinecoop_execute_knight_action(target) then
                    reason="ok"
                    if kind=="attack" then
                        n.attack_serial=(n.attack_serial or 0)+1; n.attack_x=a[6]; n.attack_y=a[7]
                    end
                end
                n.applying=false
            else reason="phase_or_target" end
        end
        n.expected_command=n.last_command+1
    end
    if reason=="ok" then n.last_state=nil; n.publish_at=0 end
    onlinecoop_lan.send("data","A1," .. a[1] .. "," .. reason)
    _log("[ONLINE ACTION] id=" .. a[1] .. " kind=" .. p[7] .. " result=" .. reason)
end

-- A transport can outlive several games. Bind each mode entry to a fresh peer
-- entry before publishing: a peer still in the previous ending is not ready.
function onlinecoop_net_handshake_initialize()
    local n=mode.net
    if onlinecoop_lan.handshake_session~=onlinecoop_lan.session then
        onlinecoop_lan.handshake_session=onlinecoop_lan.session
        onlinecoop_lan.mode_entry=0
        onlinecoop_lan.bound_peer_entry=0
    end
    onlinecoop_lan.mode_entry=(onlinecoop_lan.mode_entry or 0)+1
    n.entry=onlinecoop_lan.mode_entry
    n.previous_peer_entry=onlinecoop_lan.bound_peer_entry or 0
    n.peer_entry=0
end
function onlinecoop_net_hello()
    local n=mode.net
    return "V2,"..ONLINE_BUILD..","..n.role..","..n.entry..","..n.peer_entry..","..(mode.coop_variant or "throne")
end
function onlinecoop_net_receive_hello(payload)
    local n=mode.net
    local p=net_split(payload,",")
    if #p~=6 or p[1]~="V2" or p[2]~=ONLINE_BUILD or p[3]==n.role
        or (p[3]~="host" and p[3]~="client") then
        n.peer_ok=false; n.error="version_mismatch"; return false
    end
    if p[6]~=(mode.coop_variant or "throne") then
        n.peer_ok=false;n.error="campaign_mismatch";return false
    end
    local a=onlinecoop_net_numbers(p[4]..","..p[5],2,1000000)
    if not a or a[1]==0 then return false end
    if n.cg_returned or a[1]<=n.previous_peer_entry then return false end
    if n.peer_entry~=0 and n.peer_entry~=a[1] then
        n.peer_ok=false; return false
    end
    if n.peer_entry==0 then n.peer_entry=a[1]; n.hello_at=0 end
    if a[2]==n.entry then
        n.peer_ok=true; n.error=nil
        onlinecoop_lan.bound_peer_entry=n.peer_entry
    end
    return true
end

function onlinecoop_net_tick()
    if not mode or mode.id~="coop" or not mode.net or not onlinecoop_lan then return end
    local n=mode.net
    if onlinecoop_lan.status~="connected" then return end
    local now=time()
    if now>=n.hello_at then
        onlinecoop_lan.send("data",onlinecoop_net_hello())
        n.hello_at=now+1
    end
    for i=1,16 do
        local packet=onlinecoop_lan.receive()
        if not packet then break end
        local payload=packet.payload
        if sub(payload,1,3)=="V1," or sub(payload,1,3)=="V2," then
            onlinecoop_net_receive_hello(payload)
        elseif n.peer_ok and sub(payload,1,3)=="U2," then onlinecoop_playback_receive(payload)
        elseif n.peer_ok and not n.cg_returned then
            if onlinecoop_playback_defer(payload) then
                -- The next scene must not cut off a buffered action.
            elseif sub(payload,1,3)=="T2," or sub(payload,1,3)=="F2," or sub(payload,1,3)=="J2," then onlinecoop_playback_receive(payload)
            elseif sub(payload,1,3)=="W1," then onlinecoop_campaign_receive(payload)
            elseif sub(payload,1,3)=="Z1," or sub(payload,1,3)=="Z2," then onlinecoop_results_receive(payload)
            elseif sub(payload,1,3)=="G3," then onlinecoop_receive_cg(payload)
            elseif sub(payload,1,3)=="D1," or sub(payload,1,3)=="D2," then onlinecoop_choices_receive(payload)
            elseif sub(payload,1,3)=="M1," or sub(payload,1,3)=="M2," then onlinecoop_playback_setting_receive(payload)
            elseif sub(payload,1,3)=="Q1," then onlinecoop_signals_receive(payload)
            elseif sub(payload,1,3)=="L1," or sub(payload,1,3)=="L2," then onlinecoop_board_rate_receive(payload)
            elseif sub(payload,1,3)=="F1," then onlinecoop_board_frame_receive(payload)
            elseif sub(payload,1,3)=="F3," then onlinecoop_board_ack_receive(payload)
            elseif sub(payload,1,3)=="C2," or sub(payload,1,3)=="C1," or sub(payload,1,3)=="K1," or sub(payload,1,3)=="B1," then onlinecoop_scenes_receive(payload)
            elseif n.role=="host" and sub(payload,1,3)=="R1," then onlinecoop_net_apply_request(payload)
            elseif n.role=="host" and sub(payload,1,3)=="H1," then
                local a=onlinecoop_net_numbers(sub(payload,4),3,127)
                if a and a[2]<=8 and a[3]<=8 and onlinecoop_net_phase()==2 then
                    n.remote_aim=a[1]/128; n.remote_cell_x=a[2]-1; n.remote_cell_y=a[3]-1
                end
            elseif n.role=="client" and sub(payload,1,3)=="P1," then
                local a=onlinecoop_net_numbers(sub(payload,4),1,127)
                if a then n.king_aim=a[1]/128 end
            elseif n.role=="client" and sub(payload,1,3)=="S2," then onlinecoop_net_snapshot(payload)
            elseif n.role=="client" and sub(payload,1,3)=="E1," then onlinecoop_events_receive(payload)
            elseif n.role=="client" and sub(payload,1,3)=="A1," then
                local p=net_split(payload,",")
                if #p==3 and tonum(p[2])==n.pending then
                    n.pending=nil; n.last_result=p[3]
                    n.result_at=now
                    if p[3]~="ok" then n.await_revision=nil end
                end
            end
        end
    end
    onlinecoop_playback_setting_tick()
    onlinecoop_playback_host_tick()
    onlinecoop_playback_client_tick()
    onlinecoop_playback_wait_trace()
    if n.cg_returned then return end
    if n.role=="host" and n.peer_ok then onlinecoop_events_flush() end
    onlinecoop_results_tick()
    onlinecoop_campaign_tick()
    onlinecoop_choices_tick()
    onlinecoop_scenes_tick()
    if n.role=="host" and n.peer_ok and now>=(n.pose_at or 0) then
        n.pose_at=now+.2
        if is_coop_active() then
            local angle=hero.current_an or hero.an or 0
            local pose=net_int((angle%1)*128)%128
            if pose~=n.last_pose and onlinecoop_lan.send("data","P1,"..pose) then n.last_pose=pose end
        end
    end
    if n.role=="host" and n.peer_ok and now>=n.publish_at then
        n.publish_at=now+0.1
        local serialized=onlinecoop_net_state()
        if serialized~=n.last_state then
            local revision=n.revision+1
            if onlinecoop_lan.send("data","S2," .. revision .. ":" .. serialized) then
                n.last_state=serialized
                n.revision=revision
                _log("[ONLINE PUBLISH] rev=" .. revision .. " " .. serialized)
            end
        end
    end
    -- Put authoritative state / controls into the reliable FIFO before this
    -- tick's bulk pixels. The visual budget must not hold a new turn behind it.
    onlinecoop_board_frame_tick()
end

function onlinecoop_net_initialize()
    for _,entry in ipairs(MODLIST or {}) do
        if entry.name=="onlinecoop" then onlinecoop_lan=entry.lan_transport end
    end
    local role=onlinecoop_lan and onlinecoop_lan.role or "offline"
    mode.net={role=role,playback_mode=1,next_id=0,revision=0,epoch=0,last_command=0,expected_command=1,next_command=0,publish_at=0,hello_at=0}
    if onlinecoop_lan then onlinecoop_net_handshake_initialize() end
    onlinecoop_events_initialize()
    onlinecoop_scenes_initialize()
    onlinecoop_cg_initialize()
    onlinecoop_signals_initialize()
    onlinecoop_board_frame_initialize()
    onlinecoop_playback_initialize()
    onlinecoop_campaign_initialize()
    defbtn("online_lclick",0,"m:lb")
    defbtn("online_mx",0,"m:x")
    defbtn("online_my",0,"m:y")
    defbtn("online_skip",0,"k:tab")
    defbtn("online_cancel",0,"m:rb")
    defbtn("online_cards",0,"k:c")
    defbtn("online_soul_page",0,"k:v")
    defbtn("online_pause",0,"k:escape")
    defbtn("online_ping",0,"k:e")
    defbtn("online_fps",0,"k:f6")
    defbtn("online_playback",0,"k:f7")
    defbtn("online_wait_jump",0,"k:space")
    prepend("_update",onlinecoop_net_client_input,"online_client_input")
    append("_update",onlinecoop_net_tick,"online_authority_tick")
    append("_draw",onlinecoop_net_draw_client,"online_client_view")
    append("_draw",onlinecoop_signals_draw,"online_signals_view")
    append("_draw",onlinecoop_minigames_draw,"online_wait_games")
    append("_draw",onlinecoop_draw_board_rate,"online_rate_setting")
    append("_draw",onlinecoop_draw_playback_setting,"online_playback_setting")
    append("_draw",onlinecoop_draw_card_tooltip_overlay,"online_card_tooltip_overlay")
    if role=="client" then
        -- The client intentionally stays outside native gameplay. Its title
        -- prompt is deferred text and can be painted after the mirror, so
        -- suppress that one local label until returning to the native menu.
        local click_start=lang.click_start
        lang.click_start=""
        prepend("init_menu",function() lang.click_start=click_start end,"online_restore_title_label")
    end
    _log("[ONLINE MODE] initialized role=" .. role .. " transport=" .. type(onlinecoop_lan))
end
