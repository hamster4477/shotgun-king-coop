-- Complete native animation clips, not arrival-paced live video. Only palette
-- pixels and bounded integers cross the wire; host gameplay stays authoritative.
-- Boss transformations can last over twenty seconds. Keep strict per-action
-- limits, but size them for two minutes at the highest selectable capture rate.
-- Pixel strings are retired as soon as sent/played; only tiny timing records
-- remain. Reserve one maximum-size image for the real tail on an extreme cap.
local MAX_FRAMES,MAX_BYTES,MAX_MS,TAIL_BYTES=7200,24000000,120000,60000
local function send(s) return onlinecoop_lan.send("data",s) end
-- Keep only three decoded future images, never a decoded copy of a whole
-- cinematic. Spread allocations over update ticks, including buffering ticks.
local function predecode(c)
    local first=(c.index or 0)+1
    for i=first,min(#c.frames,first+2) do
        local f=c.frames[i]
        if f.data and not f.runs then
            f.runs=onlinecoop_decode_board_pixels(f.data,true)
            return
        end
    end
end
local function remember_buffer(n,c)
    -- A new run has a new net table. Across turns/floors, remember bad jitter
    -- immediately and recover gradually; tiny clips cannot erase that history.
    if (c.underruns or 0)>0 then
        n.clip_buffer_ms=c.buffer_ms
    elseif c.duration>=500 and #c.frames>=2 and not c.story_seen then
        n.clip_buffer_ms=max(300,c.observed_buffer_ms or 300,(c.buffer_ms or 300)*.9)
    end
end
-- Frames already arrive while the host is animating. A short reservoir lets
-- the guest play alongside it instead of waiting for capture AND transfer to
-- finish. Keep one frame of lookahead so unknown tail timing never unlocks a
-- turn early. On a genuinely slower link, receive the complete clip first.
local function ready_to_stream(c)
    if #c.frames<2 then return false end
    local first=c.frames[(c.index or 0)+1]
    local last=c.frames[#c.frames]
    if not first then return false end
    local wanted=c.buffer_ms or 300
    if last.ms-first.ms<wanted then return false end
    if (c.underruns or 0)>=2 then return false end
    local source=last.ms-c.frames[1].ms
    local elapsed=max(0,(c.last_received-c.first_received)*1000)
    return source>=elapsed*.92
end
local function start_stream(c)
    if c.play_started then
        -- Shift time after an underrun; never sprint through retained frames.
        if c.buffering then c.due=max(c.due or time(),time()) end
    else
        c.index=0; c.play_started=time()
        c.due=time()+(c.frames[1] and c.frames[1].ms/1000 or 0)
        _log("[CLIP PLAY START] id="..c.id.." buffered="..#c.frames.." complete="..tostr(c.complete==true))
    end
    if c.story_prebuffer then
        _log("[CLIP STORY READY] id="..c.id.." waited_ms="..flr((time()-(c.story_wait_started or time()))*1000))
    end
    c.buffering=nil
    c.story_prebuffer=nil
    c.story_wait_started=nil
end
-- A modal choice waits for input, not animation. Finish the preceding clip
-- before allowing that input; otherwise the modal and playback lock deadlock.
function onlinecoop_playback_waiting_choice()
    local n=mode.net
    return disrupt_menu or (n.draft and n.draft.active)
        or n.native_choice or (n.campaign_scene and n.campaign_scene.kind~=0)
        or (type(onlinecoop_choices_live)=="function" and onlinecoop_choices_live())
end
local function animation_state()
    local n=mode.net
    local active=not n.cg_active and not n.cg_returned and onlinecoop_presentation_active()
    if not active or onlinecoop_playback_waiting_choice() then return active,false end
    local phase=onlinecoop_net_phase()
    local duel=mode.coop_duel
    local marshal=mode.coop_bounty_marshal
    -- Native hidden-Boss cinematics deliberately suspend coop_run_active.
    -- An inactive combat turn is therefore not the end of its visible action.
    local cinematic=mode.coop_hidden_boss_pending or mode.coop_throne_finishing
        or mode.coop_book_scene or (duel and (duel.busy or duel.finished))
        -- Native alt_move can animate without a King movement lock, e.g.
        -- after shooting. Its exact lifetime includes aim, fire and movement.
        or (marshal and not marshal.dead and (marshal.hp or 0)>0 and marshal.coop_action_pending)
    return active,cinematic or phase==3 or phase==4
end

-- These native selectors suspend their caller until a player picks a card.
-- The turn/event locks may correctly remain set during that wait.
-- Track their UI lifetime rather than clearing gameplay locks on a timeout.
function onlinecoop_playback_initialize()
    local n=mode.net
    if n.role~="host" then return end
    for _,name in ipairs({"ask_card","add_any_card"}) do
        local kind=name
        append(kind,function()
            if mode.net==n then
                n.native_choice=kind
                _log("[CLIP CHOICE] waiting "..kind)
            end
        end,"online_clip_choice_"..kind)
    end
    prepend("remove_buts",function()
        if mode.net==n then n.native_choice=nil end
    end,"online_clip_choice_end")
end
-- 1 = complete action, 0 = latest-frame catch-up. A mode change is committed
-- only after any already announced clip has been played and acknowledged.
function onlinecoop_playback_setting_tick()
    local n=mode.net
    if n.role~="host" or not n.peer_ok then return end
    local _,native_busy=animation_state()
    if n.playback_pending~=nil and not onlinecoop_playback_busy() and not native_busy then
        n.playback_mode=n.playback_pending; n.playback_pending=nil
        n.playback_setting_sent=nil; n.playback_show_until=time()+3
        _log("[PLAYBACK MODE] complete="..n.playback_mode)
    end
    local value=n.playback_mode==1 and 1 or 0
    if n.playback_setting_sent~=value and send("M2,"..value) then n.playback_setting_sent=value end
end
function onlinecoop_playback_setting_receive(payload)
    local n=mode.net
    local a=onlinecoop_net_numbers(sub(payload,4),1,1)
    if not a then return false end
    if n.role=="host" and sub(payload,1,3)=="M1," then
        n.playback_pending=a[1]; n.playback_show_until=time()+3
        return true
    elseif n.role=="client" and sub(payload,1,3)=="M2," then
        n.playback_mode=a[1]; n.playback_pending=nil; n.playback_show_until=time()+3
        return true
    end
    return false
end
function onlinecoop_playback_input()
    local n=mode.net
    if not n.peer_ok or n.cg_active or n.cg_returned or not btnp("online_playback",0) then return end
    if time()<(n.playback_key_at or 0) then return end
    n.playback_key_at=time()+.2
    local value=n.playback_pending
    if value==nil then value=n.playback_mode==1 and 1 or 0 end
    value=1-value
    if n.role=="host" or send("M1,"..value) then
        n.playback_pending=value; n.playback_show_until=time()+3
    end
end
function onlinecoop_draw_playback_setting()
    local n=mode and mode.net
    if not n or n.cg_active or n.cg_returned or time()>=(n.playback_show_until or 0) then return end
    local value=n.playback_pending
    if value==nil then value=n.playback_mode==1 and 1 or 0 end
    local zh=current_lang=="simplified_chinese"
    local label=value==1 and (zh and "完整动画" or "Complete animation") or (zh and "追帧模式" or "Catch-up frames")
    if n.playback_pending~=nil then label=label..(zh and "（待切换）" or " (pending)") end
    rectfill(MCW/2-74,1,MCW/2+74,11,1)
    lprint("F7: "..label,MCW/2,3,4,1)
end
function onlinecoop_playback_busy()
    local n=mode and mode.net
    return n and (n.clip_host~=nil or n.clip_client~=nil) or false
end
function onlinecoop_playback_snapshot()
    local n=mode.net
    local c=n.clip_client
    if c and c.snapshot and c.snapshot.floor==c.floor then return c.snapshot end
    return n.snapshot
end
function onlinecoop_playback_hint()
    local n=mode.net
    if not onlinecoop_playback_busy() then return end
    local zh=current_lang=="simplified_chinese"
    if n.role=="host" then
        local c=n.clip_host
        if not c.closed then return zh and "正在结算动作…" or "Resolving action..." end
        if not c.ended then return zh and "正在发送完整动画…" or "Sending complete animation..." end
        return zh and "等待 2P 播放完成…" or "Waiting for 2P playback..."
    end
    return (n.clip_client.complete or (n.clip_client.play_started and not n.clip_client.buffering)) and (zh and "正在播放动作…" or "Playing animation...")
        or (zh and "正在接收完整动作…" or "Buffering animation...")
end

-- A slow transfer, a paused client and a native turn lock look identical to
-- the host. Record their actual state only after a prolonged wait; never
-- force-unlock a turn or discard the guest's complete animation.
function onlinecoop_playback_wait_trace()
    local n=mode.net; local c=n.clip_host or n.clip_client
    if not c then return end
    c.wait_started=c.wait_started or time()
    if time()-c.wait_started<3 or time()<(c.wait_trace_at or 0) then return end
    c.wait_trace_at=time()+5
    local step
    if n.role=="host" then step=not c.closed and "native" or (not c.ended and "send" or "ack")
    else step=(c.complete or (c.play_started and not c.buffering)) and "play" or "receive" end
    _log("[CLIP WAIT] role="..n.role.." id="..c.id.." step="..step
        .." seconds="..flr(time()-c.wait_started).." frame="..(c.index or c.next or 0)
        .." buffered="..#c.frames.." phase="..onlinecoop_net_phase()
        .." king_lock="..tostr(mode.coop_king_move_input_locked)
        .." bonus="..tostr(mode.coop_extra_king_action_pending)
        .." penta="..tostr(mode.coop_penta_bonus_pending)
        .." queued="..(type(events)=="table" and #events or 0)
        .." selected="..tostr(mode.coop_selected)
        .." focus="..tostr(type(winspec)=="function" and winspec("focus")))
end

function onlinecoop_playback_capture(data,floor,turn)
    local n=mode.net; local c=n.clip_host
    if not c or c.closed then return false end
    if floor~=c.floor then return true end
    local ms=min(MAX_MS,max(0,flr((time()-c.started)*1000)))
    if not c.capped and data==c.last then return true end
    if not c.capped and (#c.frames>=MAX_FRAMES-1 or c.bytes+#data>MAX_BYTES-TAIL_BYTES) then
        c.capped=true
        _log("[CLIP LIMIT] action exceeded capture budget; preserving actual final image")
    end
    if c.capped then
        -- Never freeze forever on the frame where a defensive limit happened.
        -- A single replacement tail stays bounded and records the real ending.
        c.tail={data=data,ms=ms,turn=turn}
    else
        add(c.frames,{data=data,ms=ms,turn=turn})
        c.last=data; c.bytes=c.bytes+#data
    end
    return true
end

function onlinecoop_playback_host_tick()
    local n=mode.net
    if n.role~="host" or not n.peer_ok then return end
    local active,moving=animation_state()
    local c=n.clip_host
    if not c and moving and n.playback_mode==1 then
        n.clip_serial=(n.clip_serial or 0)+1
        c={id=n.clip_serial,floor=mode.lvl,started=time(),frames={},bytes=0,next=1,part=1}
        n.clip_host=c; n.board_tx=nil
        _log("[CLIP BEGIN] id="..c.id.." floor="..c.floor)
    end
    if not c then return end
    if not c.closed then
        if moving and mode.lvl==c.floor then c.idle_at=nil
        else
            c.idle_at=c.idle_at or time()
            if not active or mode.lvl~=c.floor or time()-c.idle_at>=.12 then
                c.closed=true; c.duration=min(MAX_MS,max(0,flr((time()-c.started)*1000)))
                if c.tail then
                    add(c.frames,c.tail);c.bytes=c.bytes+#c.tail.data;c.tail=nil
                end
                _log("[CLIP CAPTURED] id="..c.id.." frames="..#c.frames.." ms="..c.duration.." bytes="..c.bytes)
            end
        end
    end
    if not c.announced then
        if not send("T2,"..c.id..","..c.floor) then return end
        c.announced=true
    end
    -- Keep the bridge FIFO small, but retain captured action frames in memory
    -- until sent. A blocked network must never make capture skip these frames.
    for i=1,2 do
        local f=c.frames[c.next]
        if not f then break end
        if onlinecoop_lan.can_send_visual and not onlinecoop_lan.can_send_visual() then return end
        local parts=flr((#f.data+11999)/12000)
        local msg="F2,"..c.id..","..c.next..","..c.floor..","..f.turn..","..f.ms..","..c.part..","..parts
            ..":"..sub(f.data,(c.part-1)*12000+1,c.part*12000)
        if not send(msg) then return end
        c.part=c.part+1
        if c.part>parts then
            -- The bridge owns the immutable message now. Retaining every full
            -- image here would needlessly double memory on long Boss clips.
            f.data=nil;c.part=1;c.next=c.next+1
        end
    end
    if c.closed and c.next>#c.frames and not c.ended then
        if send("J2,"..c.id..","..#c.frames..","..c.duration..","..(c.capped and 1 or 0)) then
            c.ended=true; c.frames={}; c.bytes=0;c.last=nil
        end
    end
end

function onlinecoop_playback_receive(payload)
    local n=mode.net; local tag=sub(payload,1,3)
    if tag=="U2," then
        local a=onlinecoop_net_numbers(sub(payload,4),1,10000000)
        local c=n.clip_host
        if n.role~="host" or not a or not c or not c.ended or a[1]~=c.id then return false end
        _log("[CLIP ACK] id="..c.id)
        n.clip_host=nil; n.board_last_pixels=nil; n.board_capture_at=nil
        return true
    end
    if n.role~="client" then return false end
    local c=n.clip_client
    if tag=="T2," then
        local a=onlinecoop_net_numbers(sub(payload,4),2,10000000)
        if not a or a[1]~=(n.clip_received or 0)+1 or a[2]>10000 or c then return false end
        n.clip_received=a[1]
        n.clip_client={id=a[1],floor=a[2],frames={},bytes=0,snapshot=n.snapshot,deferred={},
            buffer_ms=min(1500,max(300,n.clip_buffer_ms or 300))}
        return true
    elseif tag=="F2," then
        if not c or c.complete or #payload>12130 then return false end
        local head=match(payload,"^F2,([%d,]+):")
        local a=head and onlinecoop_net_numbers(head,7,10000000)
        if not a or a[1]~=c.id or a[2]~=#c.frames+1 or a[2]>MAX_FRAMES or a[3]~=c.floor
            or a[5]>MAX_MS or a[6]<1 or a[7]<1 or a[7]>5 or a[6]>a[7] then return false end
        local data=sub(payload,#head+5)
        if #data<4 or #data>12000 or #data%4~=0 or not match(data,"^[0-9a-f]+$") then return false end
        local f=c.partial
        if not f then
            if a[6]~=1 or (#c.frames>0 and a[5]<c.frames[#c.frames].ms) then return false end
            f={ms=a[5],turn=a[4],parts=a[7],next=1,data=""}; c.partial=f
        end
        if a[4]~=f.turn or a[5]~=f.ms or a[7]~=f.parts or a[6]~=f.next then return false end
        if c.bytes+#f.data+#data>MAX_BYTES then return false end
        f.data=f.data..data; f.next=f.next+1
        if a[6]<a[7] then return true end
        if not onlinecoop_decode_board_pixels(f.data,false) then c.partial=nil; return false end
        local previous=c.frames[#c.frames]
        if previous and c.last_received then
            local jitter=max(0,(time()-c.last_received)*1000-(f.ms-previous.ms))
            c.observed_buffer_ms=min(1000,max(c.observed_buffer_ms or 300,150+jitter*2))
            c.buffer_ms=max(c.buffer_ms or 300,c.observed_buffer_ms)
        end
        c.first_received=c.first_received or time(); c.last_received=time()
        c.bytes=c.bytes+#f.data; add(c.frames,f); c.partial=nil
        if #c.frames==1 and sub(f.data,1,4)~="0000"
            and (not n.board_native or n.board_native.floor~=c.floor) then
            f.runs=onlinecoop_decode_board_pixels(f.data,true)
            n.board_native={floor=c.floor,turn=f.turn,runs=f.runs,received=time()}
        end
        return true
    elseif tag=="J2," then
        local a=onlinecoop_net_numbers(sub(payload,4),4,10000000)
        if not c or c.complete or not a or a[1]~=c.id or a[2]~=#c.frames or c.partial
            or a[3]>MAX_MS or a[4]>1 or (#c.frames>0 and a[3]<c.frames[#c.frames].ms) then return false end
        c.complete=true; c.duration=a[3]; c.capped=a[4]==1
        start_stream(c)
        _log("[CLIP READY] id="..c.id.." frames="..#c.frames.." ms="..c.duration)
        return true
    end
    return false
end

function onlinecoop_playback_defer(payload)
    local n=mode.net; local c=n.clip_client
    if n.role~="client" or not c then return false end
    if sub(payload,1,3)~="C2," and sub(payload,1,3)~="C1," and sub(payload,1,3)~="G3," then return false end
    if #c.deferred<16 then add(c.deferred,payload) end
    return true
end
function onlinecoop_playback_client_tick()
    local n=mode.net; local c=n.clip_client
    if n.role~="client" or n.cg_active or not c then return end
    local next_frame=c.frames[(c.index or 0)+1]
    if not c.complete and next_frame and sub(next_frame.data or "",1,4)=="0000" then
        -- Long native stories can outgrow a small live jitter reservoir even
        -- on an otherwise healthy link. Finish receiving at the first scene
        -- boundary, before showing the transformation; ordinary board frames
        -- before it still stream. J2 shifts due without replaying that prefix.
        if not c.story_prebuffer then
            c.story_prebuffer=true
            c.story_seen=true
            c.story_wait_started=time()
            _log("[CLIP STORY BUFFER] id="..c.id.." frame="..((c.index or 0)+1))
        end
        c.buffering=true
        predecode(c)
        return
    end
    if not c.play_started or c.buffering then
        if not c.complete and not ready_to_stream(c) then predecode(c); return end
        start_stream(c)
    end
    if time()+.00001<c.due then predecode(c); return end
    local f=c.frames[c.index+1]
    if not c.complete and (not f or not c.frames[c.index+2]) then
        c.buffering=true; c.underruns=(c.underruns or 0)+1
        c.buffer_ms=min(1500,max(500,(c.buffer_ms or 300)*2))
        _log("[CLIP REBUFFER] id="..c.id.." frame="..c.index.." target_ms="..flr(c.buffer_ms))
        predecode(c)
        return
    end
    if f then
        local cached=f.runs~=nil
        c.index=c.index+1
        n.board_native={floor=c.floor,turn=f.turn,runs=f.runs or onlinecoop_decode_board_pixels(f.data,true),received=time()}
        f.runs=nil -- the displayed image now owns this table
        f.data=nil -- timing metadata stays dense for validation and lookahead
        -- Keep source timing across normal render-tick quantization. A genuine
        -- local stall shifts the timeline instead of skipping frames to catch up.
        local next_frame=c.frames[c.index+1]
        local next_ms=next_frame and next_frame.ms or c.duration
        if time()-c.due>.02 then c.due=time() end
        c.due=c.due+max(0,next_ms-f.ms)/1000
        -- At most one new decoded image per tick, even on an empty cache.
        if cached then predecode(c) end
        return
    end
    if not send("U2,"..c.id) then return end
    remember_buffer(n,c)
    _log("[CLIP PLAYED] id="..c.id.." frames="..c.index.." capped="..tostr(c.capped)
        .." elapsed_ms="..flr((time()-c.play_started)*1000))
    n.clip_client=nil
    onlinecoop_events_clear(n)
    -- Discard already displayed fallback tweens without replaying spawn tracks.
    if n.snapshot then
        n.board_visible=(n.snapshot.board or 0)>0
        for _,p in ipairs(n.snapshot.units) do n.seen_units[p[1]]=true end
    end
    for _,payload in ipairs(c.deferred) do
        if sub(payload,1,3)=="C2," or sub(payload,1,3)=="C1," then onlinecoop_scenes_receive(payload) else onlinecoop_receive_cg(payload) end
    end
end
