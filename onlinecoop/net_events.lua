-- Presentation events. Hooks copy numbers only; no retained native pieces,
-- gameplay callbacks, native battle events, damage or turn execution on client.
-- E1: serial,floor,kind,id,x,y,toX,toY,type,team,hp,amount,angle128,ms,knight
-- kind: 1 move, 2 shot, 3 hurt, 4 death, 5 reload, 6 heal. Ordered, bounded queues.
local function event_host()
    return mode and mode.net and mode.net.role=="host" and mode.net.peer_ok
        and is_coop_active()
end
local function release_track(track)
    if track and track.entity then
        del(ents,track.entity)
        track.entity=nil
    end
end
function onlinecoop_events_clear(n)
    if not n then return end
    for _,track in pairs(n.motion or {}) do release_track(track) end
    for _,track in ipairs(n.effects or {}) do release_track(track) end
    for _,spawn in pairs(n.spawns or {}) do release_track(spawn.track) end
    release_track(n.board_track)
    n.board_track=nil; n.spawns={}; n.seen_units={}; n.board_visible=false
    n.motion={}; n.effects={}; n.ev_waiting={}
    n.shot_started=nil; n.shot_track=nil; n.swing_started=nil
    n.reload_track=nil
end
local function native_track(x,y,tx,ty,ms)
    local entity=mke(-1,x,y)
    -- A generic interpolation entity, never a native chess piece/enemy.
    entity.online_presentation=true
    entity.dr=function() end
    local frames=max(1,flr(ms*60/1000+.5))
    mvt(entity,tx,ty,frames)
    return {entity=entity,x=x,y=y,tx=tx,ty=ty,started=time(),duration=frames/60}
end
function onlinecoop_effect_progress(track)
    if track.entity then
        if track.entity.twc~=nil then return min(1,max(0,track.entity.twc)) end
        release_track(track)
    end
    return 1
end
local function track_position(track)
    local t=onlinecoop_effect_progress(track)
    if track.entity then return track.entity.x,track.entity.y,t end
    return track.tx,track.ty,t
end
local function movement_ms(piece)
    local frames=piece and piece.tws
    if type(frames)=="number" and frames>0 then return min(1000,max(50,flr(frames*1000/60+.5))) end
    return 300
end
local function event_copy(piece)
    if type(piece)~="table" or not piece.sq or type(piece.sq.px)~="number"
        or type(piece.sq.py)~="number" then return nil end
    local x,y=piece.sq.px,piece.sq.py
    if x<0 or x>7 or y<0 or y>7 then return nil end
    return {onlinecoop_net_id(piece),x,y,piece.type or 0,piece.team or 0,
        max(0,piece.hp or 1),piece==mode.coop_knight and 1 or 0}
end
local function event_emit(kind,p,tx,ty,amount,angle,ms)
    if not event_host() or not p then return end
    local n=mode.net
    if n.ev_floor~=mode.lvl then n.ev_floor=mode.lvl; n.ev_dead={}; n.ev_moves={}; n.ev_shot_at=nil end
    if kind==1 then
        local key=p[2]..","..p[3]..","..tx..","..ty
        local previous=n.ev_moves[p[1]]
        if previous and previous.key==key and time()-previous.at<.02 then return end
        n.ev_moves[p[1]]={key=key,at=time()}
    elseif kind==2 then
        if n.ev_shot_at==time() then return end
        n.ev_shot_at=time()
    elseif kind==5 then
        if n.ev_reload_at==time() then return end
        n.ev_reload_at=time()
    end
    if kind==4 then
        if n.ev_dead[p[1]] then return end
        n.ev_dead[p[1]]=true
    end
    n.ev_serial=(n.ev_serial or 0)+1
    local row={n.ev_serial,mode.lvl,kind,p[1],p[2],p[3],tx or p[2],ty or p[3],
        p[4],p[5],p[6],amount or 0,angle or 0,ms or 280,p[7]}
    local text="E1"
    for _,v in ipairs(row) do text=text..","..(v-v%1) end
    n.ev_out=n.ev_out or {}
    if #n.ev_out>=64 then
        -- Presentation may be dropped under overload; authoritative state wins.
        n.ev_out={}; n.last_state=nil
        _log("[ONLINE EVENTS] overload: reset presentation backlog")
    end
    add(n.ev_out,text)
    _log("[ONLINE EVENT SEND] kind="..kind.." id="..p[1].." serial="..n.ev_serial)
end

function onlinecoop_events_flush()
    local n=mode.net
    local queue=n.ev_out or {}
    local sent=0
    for i=1,min(8,#queue) do
        if not onlinecoop_lan.send("data",queue[i]) then break end
        sent=i
    end
    if sent>0 then
        local remaining={}
        for i=sent+1,#queue do add(remaining,queue[i]) end
        n.ev_out=remaining
    end
end

function onlinecoop_events_initialize()
    if mode.net.role=="client" then
        prepend("set_mode",function() onlinecoop_events_clear(mode and mode.net) end,"online_release_visual_mode")
        prepend("init_menu",function() onlinecoop_events_clear(mode and mode.net) end,"online_release_visual_menu")
        return
    end
    if mode.net.role~="host" then return end
    -- Observe actual HP increases. Keep only numeric baselines: new spawns,
    -- transformed pieces, max-HP upgrades and new floors are not healing cues.
    local health_floor,health=nil,{}
    append("_update",function()
        if not event_host() or mode.net.cg_active then health={}; health_floor=nil; return end
        if health_floor~=mode.lvl then health={}; health_floor=mode.lvl end
        local current={}
        for y=0,7 do for x=0,7 do
            local p=coop_piece_on_square(gsq(x,y))
            local copy=p and not p.dead and event_copy(p)
            if copy and copy[6]>0 then
                local id=copy[1]; local previous=health[id]
                local maximum=p.hp_max or p.hp
                if previous and previous.hp>0 and previous.typ==p.type
                    and previous.maximum==maximum and copy[6]>previous.hp then
                    event_emit(6,copy,nil,nil,copy[6]-previous.hp,0,650)
                end
                current[id]={hp=copy[6],typ=p.type,maximum=maximum}
            end
        end end
        health=current
    end,"online_event_healing")
    local moves,hits,king_moves={},{},{}
    prepend("move_hero",function(destination)
        local copy=event_host() and event_copy(hero) or nil
        add(king_moves,copy and destination and type(destination.px)=="number"
            and type(destination.py)=="number" and {p=copy,x=destination.px,y=destination.py} or false)
    end,"online_event_king_begin")
    append("move_hero",function(destination)
        local entry=king_moves[#king_moves]; king_moves[#king_moves]=nil
        if entry and hero and (hero.in_move or hero.sq==destination) then
            event_emit(1,entry.p,entry.x,entry.y,0,0,movement_ms(hero))
        end
    end,"online_event_king_commit")
    prepend("move_piece",function(p,destination)
        local entry=false
        if event_host() and destination and type(destination.px)=="number" and type(destination.py)=="number"
            and destination.px>=0 and destination.px<=7 and destination.py>=0 and destination.py<=7 then
            local copy=event_copy(p)
            if copy and (copy[2]~=destination.px or copy[3]~=destination.py) then
                entry={p=copy,x=destination.px,y=destination.py}
            end
        end
        add(moves,entry)
    end,"online_event_move_begin")
    append("move_piece",function(p,destination)
        local entry=moves[#moves]; moves[#moves]=nil
        if entry and p and (p.in_move or p.sq==destination) then
            event_emit(1,entry.p,entry.x,entry.y,0,0,movement_ms(p))
        end
    end,"online_event_move_commit")
    prepend("hit",function(p)
        add(hits,event_host() and event_copy(p) or false)
    end,"online_event_hit_begin")
    append("hit",function(p)
        local before=hits[#hits]; hits[#hits]=nil
        if before and p then
            local hp=max(0,p.hp or 0)
            if hp<before[6] then event_emit(3,before,nil,nil,before[6]-hp,0,260) end
            if p.dead or (p.hp and p.hp<=0) then event_emit(4,before,nil,nil,0,0,420) end
        end
    end,"online_event_hit_commit")
    -- Capture the numeric portrait before removal clears its square.
    prepend("kill_piece",function(p)
        if event_host() then event_emit(4,event_copy(p),nil,nil,0,0,420) end
    end,"online_event_death")
    -- The engine's successful gunshot sound covers weapon variants, whereas
    -- input/shoot attempts also include blocked or empty-chamber clicks.
    append("sfx",function(name)
        if event_host() and type(name)=="string" and (name=="shoot" or sub(name,1,6)=="shoot_") then
            local angle=((hero.current_an or hero.an or 0)%1)*128
            event_emit(2,event_copy(hero),nil,nil,0,angle,180)
        elseif event_host() and name=="reload" and hero and onlinecoop_net_phase()>=1
            and onlinecoop_net_phase()<=3 then
            -- Observed native reload cue; no guessed reload callback or second refill.
            event_emit(5,event_copy(hero),nil,nil,0,0,350)
        end
    end,"online_event_shot")
end

local function event_accept(e)
    local n=mode.net
    n.motion=n.motion or {}; n.effects=n.effects or {}
    local now=time()
    if (e[3]==1 or e[3]==4) and n.spawns and n.spawns[e[4]] then
        release_track(n.spawns[e[4]].track); n.spawns[e[4]]=nil
    end
    if e[3]==1 then
        local x,y=e[5],e[6]
        local old=n.motion[e[4]]
        if not old then
            local count=0; for _ in pairs(n.motion) do count=count+1 end
            if count>=64 then
                for _,track in pairs(n.motion) do release_track(track) end
                n.motion={}
            end
        end
        if old then
            x,y=track_position(old)
            release_track(old)
        end
        n.motion[e[4]]=native_track(x,y,e[7],e[8],e[14])
    else
        if #n.effects>=64 then
            for _,fx in ipairs(n.effects) do release_track(fx) end
            n.effects={}
        end
        local fx=native_track(0,0,1,0,e[14]); fx.event=e
        if n.motion[e[4]] then fx.x,fx.y=track_position(n.motion[e[4]]) else fx.x,fx.y=e[5],e[6] end
        if e[3]==4 then release_track(n.motion[e[4]]); n.motion[e[4]]=nil end
        add(n.effects,fx)
        if e[3]==2 then n.shot_started=now; n.shot_track=fx; n.shot_angle=e[13]/128; sfx("shoot",.6) end
        if e[3]==5 then n.reload_track=fx; sfx("reload",.6) end
        if e[3]==6 then sfx("healing",.6) end
    end
    n.event_counts=n.event_counts or {}
    n.event_counts[e[3]]=(n.event_counts[e[3]] or 0)+1
    _log("[ONLINE EVENT PLAY] kind="..e[3].." id="..e[4].." serial="..e[1])
end

function onlinecoop_events_receive(payload)
    if not mode or not mode.net or mode.net.role~="client" or sub(payload,1,3)~="E1," then return false end
    local e=onlinecoop_net_numbers(sub(payload,4),15,1000000)
    local n=mode.net
    if not e or e[1]<1 or e[1]<=(n.ev_received or 0) or e[3]<1 or e[3]>6
        or e[4]<1 or e[5]>7 or e[6]>7 or e[7]>7 or e[8]>7 or e[10]>1
        or e[13]>127 or e[14]<50 or e[14]>1000 or e[15]>1 then return false end
    n.ev_received=e[1]
    local s=n.snapshot
    if s and s.floor==e[2] then event_accept(e)
    elseif not s or s.floor<e[2] then
        n.ev_waiting=n.ev_waiting or {}
        if #n.ev_waiting>=64 then n.ev_waiting={} end
        add(n.ev_waiting,e)
    end
    return true
end

function onlinecoop_events_snapshot(old,s)
    if mode.net.cg_active then return end
    local n=mode.net
    if not old or old.floor~=s.floor or old.board~=s.board then
        local waiting=n.ev_waiting
        onlinecoop_events_clear(n)
        n.ev_waiting=waiting
        if (s.board or 0)>0 then
            n.board_visible=true
            n.board_track=native_track(0,0,1,0,850)
            _log("[ONLINE ENTRY] board="..s.board.." floor="..s.floor)
        end
    end
    n.motion=n.motion or {}
    -- Snapshot fallback catches teleports/special moves outside move_piece.
    -- Unrelated snapshots do NOT restart an in-flight movement animation.
    if old and old.floor==s.floor then
        for _,p in ipairs(s.units) do for _,prev in ipairs(old.units) do
            if p[1]==prev[1] and (p[2]~=prev[2] or p[3]~=prev[3]) then
                local m=n.motion[p[1]]
                if not m or m.tx~=p[2] or m.ty~=p[3] then
                    local x,y=prev[2],prev[3]
                    if m then x,y=track_position(m); release_track(m) end
                    n.motion[p[1]]=native_track(x,y,p[2],p[3],300)
                end
            end
        end end
    end
    local waiting={}
    for _,e in ipairs(n.ev_waiting or {}) do
        if e[2]==s.floor then event_accept(e)
        elseif e[2]>s.floor then add(waiting,e) end
    end
    n.ev_waiting=waiting
    -- Bound tracks to current snapshot units (death effects own their portrait).
    local current={}
    for _,p in ipairs(s.units) do current[p[1]]=n.motion[p[1]] end
    for id,m in pairs(n.motion) do if not current[id] then release_track(m) end end
    n.motion=current
    n.seen_units=n.seen_units or {}; n.spawns=n.spawns or {}
    local alive={}
    for _,p in ipairs(s.units) do
        alive[p[1]]=true
        if not n.seen_units[p[1]] then
            n.seen_units[p[1]]=true
            n.spawns[p[1]]={delay=(p[2]+p[3])*.018}
            _log("[ONLINE ENTRY] spawn="..p[1])
        end
    end
    for id,spawn in pairs(n.spawns) do
        if not alive[id] then release_track(spawn.track); n.spawns[id]=nil end
    end
end

-- Only presentation entities are animated. Gameplay and native event queues
-- remain host-owned. Entry uses a short stagger, not a second local simulation.
function onlinecoop_board_ready()
    local n=mode.net
    return n.board_visible and (not n.board_track or onlinecoop_effect_progress(n.board_track)>=1)
end
function onlinecoop_board_tile_progress(x,y)
    local n=mode.net
    if not n.board_visible then return 0 end
    local t=n.board_track and onlinecoop_effect_progress(n.board_track) or 1
    return min(1,max(0,t*1.6-(x+y)/14*.6))
end
local function spawn_progress(spawn)
    if not onlinecoop_board_ready() then return 0 end
    if not spawn.due then spawn.due=time()+spawn.delay end
    if time()<spawn.due then return 0 end
    if not spawn.track then spawn.track=native_track(0,0,1,0,350) end
    return onlinecoop_effect_progress(spawn.track)
end
function onlinecoop_spawn_visual(p)
    local n=mode.net
    if not onlinecoop_board_ready() then return 0,false end
    local spawn=n.spawns and n.spawns[p[1]]
    if not spawn then return 0,true end
    local t=spawn_progress(spawn)
    if t>=1 then n.spawns[p[1]]=nil; return 0,true end
    return 36*(1-t)*(1-t),t>0
end

function onlinecoop_events_busy()
    local n=mode.net
    if n.board_track and onlinecoop_effect_progress(n.board_track)<1 then return true end
    for _,spawn in pairs(n.spawns or {}) do if spawn_progress(spawn)<1 then return true end end
    for _,m in pairs(n.motion or {}) do
        if onlinecoop_effect_progress(m)<1 then return true end
    end
    for _,fx in ipairs(n.effects or {}) do
        -- Reload feedback must not delay the Knight's already-authorized turn.
        if fx.event[3]~=5 and fx.event[3]~=6 and onlinecoop_effect_progress(fx)<1 then return true end
    end
    return false
end

function onlinecoop_visual_position(p)
    local m=mode.net.motion and mode.net.motion[p[1]]
    if not m then return p[2],p[3],0 end
    local x,y,t=track_position(m)
    if t>=1 and (p[2]~=m.tx or p[3]~=m.ty) and time()-m.started>m.duration+.6 then
        mode.net.motion[p[1]]=nil; return p[2],p[3],0
    end
    -- Native linear tween and the measured 8-pixel jump arc.
    return x,y,t<1 and 8*sin(t/2) or 0
end
