-- Data-only scene presentation. Suggestions never invoke a card button/callback.
local function scene_join(a,sep)
    local s=""; for i,v in ipairs(a) do s=s..(i>1 and sep or "")..v end; return s
end
local function scene_split(s,sep)
    local a,start={},1
    for i=1,#s+1 do if i>#s or sub(s,i,i)==sep then add(a,sub(s,start,i-1)); start=i+1 end end
    return a
end
local function scene_text(zh,en) return current_lang=="simplified_chinese" and zh or en end
local function close_draft()
    if mode and mode.net then
        mode.net.draft_watch=nil
        if mode.net.draft then mode.net.draft.active=false end
    end
end
function onlinecoop_scenes_initialize()
    local n=mode.net
    if n.role~="host" then return end
    prepend("draw_game",function()
        if mode.net==n and is_coop_active() and type(boss)=="table"
            and boss.big and boss.type==6 and not boss.dead then
            -- The two-row footprint sorts at its bottom edge, not at the
            -- first row like a normal 16px piece. Keep native depth buckets.
            boss.ysort_dy=31
        end
    end,"online_boss_footprint_depth")
    prepend("level_up",function(data)
        if mode.net~=n or type(data)~="table" or data.id~="level_up" or type(data.choices)~="table" then return end
        -- Native level_up clones these constraints before picking cards. Observe
        -- its actual panels, including delayed Patience entry and Search rerolls.
        close_draft()
        n.draft_watch={panels={},floor=mode.lvl}
    end,"online_draft_open")
    append("add_child",function(parent,child)
        local watch=mode.net==n and n.draft_watch
        if not watch or type(parent)~="table" or type(child)~="table"
            or type(parent.cards)~="table" or not child.ghost
            or (parent.id~=0 and parent.id~=1) then return end
        watch.panels[parent.id+1]=parent
    end,"online_draft_panel")
    -- next_floor belongs to each mode, not the engine. Hooking it creates a
    -- protected global in the native hook registry; subsequent safe_require
    -- calls then reject its definition in both Co-op and the base Throne mode.
    -- new_level is an engine entry point shared by every floor transition.
    prepend("new_level",close_draft,"online_draft_new_level")
    prepend("add_card",close_draft,"online_draft_card_confirmed")
    prepend("init_menu",close_draft,"online_draft_menu")

    -- Capture only the observed native Boss's drawing primitives, never code.
    -- A single latest frame is kept; old frames cannot accumulate in a queue.
    local capture
    local specs={{"sspr",1},{"line",2},{"pal",3}}
    for _,spec in ipairs(specs) do
        local opcode=spec[2]
        prepend(spec[1],function(...)
            if not capture or #capture>=160 then return end
            local args={opcode}
            for _,v in ipairs({...}) do
                if type(v)~="number" or abs(v)>4096 then return end
                add(args,flr(v*1000+.5))
            end
            add(capture,scene_join(args,","))
        end,"online_boss_capture_"..spec[1])
    end
    append("_update",function()
        if not mode.net or type(boss)~="table" or boss.type~=6 or boss.dead or not is_coop_active() then
            n.boss_frame=nil; return
        end
        if n.boss_watched==boss then return end
        n.boss_watched=boss
        local actor=boss; local original=actor.dr
        if type(original)~="function" then return end
        actor.dr=function(...)
            -- Native board images already contain the Boss. Keep this path
            -- only as a low-rate fallback, not a second competing video stream.
            local record=n.peer_ok and not n.clip_host and time()-(n.board_ack_at or -999)>2
                and time()>=(n.boss_capture_at or 0)
                and (not onlinecoop_lan.can_send_visual or onlinecoop_lan.can_send_visual())
            if record then capture={}; n.boss_capture_at=time()+.5 end
            original(...)
            if record then
                local commands=capture; capture=nil
                local bx,by=coop_get_board_geometry()
                local frame="B1,"..mode.lvl..","..onlinecoop_net_id(actor)..","..bx..","..by..":"..scene_join(commands,"_")
                if #commands>0 and #commands<160 and #frame<14000 then n.boss_frame=frame end
            end
        end
    end,"online_boss_watch")
end
function onlinecoop_observe_draft(n)
    local watch=n.draft_watch
    if not watch or watch.floor~=mode.lvl then return end
    local indices,counts={},{}
    for row=1,2 do
        local panel=watch.panels[row]
        if not panel or type(panel.cards)~="table" or #panel.cards<1 or #panel.cards>8 then return end
        counts[row]=#panel.cards
        for _,card in ipairs(panel.cards) do
            -- Do not publish the old face while native Search is flipping it.
            if card.flipped or card.chosen~=nil then return end
            local index
            for i,definition in ipairs(CARDS) do if definition.id==card.id then index=i;break end end
            if not index then return end
            add(indices,index)
        end
    end
    local fingerprint=counts[1]..","..counts[2]..":"..scene_join(indices,",")
    if fingerprint==watch.fingerprint then return end
    watch.fingerprint=fingerprint
    n.draft_serial=(n.draft_serial or 0)+1
    n.draft={id=n.draft_serial,floor=watch.floor,active=true,cards=indices,counts=counts,suggestion=0}
    _log("[ONLINE DRAFT] open="..n.draft_serial.." actual="..fingerprint)
end
function onlinecoop_scenes_tick()
    local n=mode.net
    if n.role~="host" or not n.peer_ok then return end
    onlinecoop_observe_draft(n)
    local d=n.draft
    if d then
        local counts=d.counts or {2,2}
        local msg="C2,"..scene_join({d.id,d.floor,d.active and 1 or 0,d.suggestion,counts[1],counts[2]},",")..","..scene_join(d.cards,",")
        if msg~=n.draft_sent and onlinecoop_lan.send("data",msg) then n.draft_sent=msg end
    end
    if time()>=(n.boss_send_at or 0) then
        local frame=n.boss_frame or ("B1,"..(mode.lvl or 0)..",0,0,0:-")
        if frame~=n.boss_sent and (not onlinecoop_lan.can_send_visual or onlinecoop_lan.can_send_visual())
            and onlinecoop_lan.send("data",frame) then n.boss_sent=frame end
        n.boss_send_at=time()+1/15
    end
end
function onlinecoop_scenes_receive(payload)
    local n=mode.net
    if n.role=="host" and sub(payload,1,3)=="K1," then
        local a=onlinecoop_net_numbers(sub(payload,4),3,1000000); local d=n.draft
        if not a or not d or not d.active or a[1]~=d.id or a[2]~=d.floor or a[3]<1 or a[3]>2 then return false end
        if time()<(n.suggest_at or 0) then return false end
        local changed=d.suggestion~=a[3]
        n.suggest_at=time()+.2; d.suggestion=a[3]
        if changed and time()>=(n.suggestion_sound_at or 0) then
            onlinecoop_signal_sound("suggestion"); n.suggestion_sound_at=time()+1
        end
        _log("[ONLINE DRAFT] suggestion="..a[3].." round="..d.id)
        return true
    elseif n.role=="client" and sub(payload,1,3)=="C2," then
        local fields=scene_split(sub(payload,4),",")
        if #fields<8 or #fields>22 then return false end
        local a=onlinecoop_net_numbers(sub(payload,4),#fields,1000000)
        if not a or a[1]<1 or a[3]>1 or a[4]>2 or a[5]<1 or a[5]>8 or a[6]<1 or a[6]>8
            or #a~=6+a[5]+a[6] or (n.draft and a[1]<n.draft.id) then return false end
        local indices={}
        for i=7,#a do if not CARDS[a[i]] then return false end;add(indices,a[i]) end
        local old=n.draft
        n.draft={id=a[1],floor=a[2],active=a[3]==1,cards=indices,counts={a[5],a[6]},suggestion=a[4],
            started=old and old.id==a[1] and old.started or time()}
        return true
    elseif n.role=="client" and sub(payload,1,3)=="C1," then
        local a=onlinecoop_net_numbers(sub(payload,4),8,1000000)
        if not a or a[1]<1 or a[3]>1 or a[8]>2 or (n.draft and a[1]<n.draft.id) then return false end
        for i=4,7 do if not CARDS[a[i]] then return false end end
        local old=n.draft
        n.draft={id=a[1],floor=a[2],active=a[3]==1,cards={a[4],a[5],a[6],a[7]},suggestion=a[8],
            started=old and old.id==a[1] and old.started or time()}
        return true
    elseif n.role=="client" and sub(payload,1,3)=="B1," then
        if #payload>14000 then return false end
        local fields=scene_split(sub(payload,4),":")
        if #fields~=2 then return false end
        local h=onlinecoop_net_numbers(fields[1],4,1000000)
        if not h or h[3]>1024 or h[4]>1024 then return false end
        if n.snapshot and h[1]<n.snapshot.floor then return false end
        if h[2]==0 then n.boss_visual=nil; return true end
        local rows=scene_split(fields[2],"_"); if #rows>160 then return false end
        local commands={}
        for _,row in ipairs(rows) do
            local values=scene_split(row,","); local op=tonum(values[1]); local count=#values-1
            if not ((op==1 and count==6) or (op==2 and (count==4 or count==5))
                or (op==3 and (count==0 or count==2 or count==3))) then return false end
            local a={}
            for i=2,#values do
                if not match(values[i],"^%-?%d+$") then return false end
                local v=tonum(values[i]); if not v or abs(v)>4096000 then return false end
                a[#a+1]=v/1000
            end
            if op==1 and (a[1]<0 or a[2]<0 or a[3]<=0 or a[4]<=0 or a[1]+a[3]>1024 or a[2]+a[4]>1024
                or (#a>=8 and (abs(a[7])>512 or abs(a[8])>512))) then return false end
            if op==2 and #a==5 and (a[5]<0 or a[5]>255 or a[5]%1~=0) then return false end
            if op==3 and #a>0 and (a[1]<0 or a[1]>255 or a[1]%1~=0 or a[2]<0 or a[2]>255 or a[2]%1~=0 or (#a==3 and a[3]~=0 and a[3]~=1)) then return false end
            add(commands,{op=op,args=a})
        end
        n.boss_visual={floor=h[1],id=h[2],x=h[3],y=h[4],commands=commands}
        return true
    end
    return false
end
function onlinecoop_suggest_choice(row)
    local n=mode.net; local d=n.draft
    if n.role~="client" or not d or not d.active or not n.peer_ok or onlinecoop_lan.status~="connected"
        or row<1 or row>2 or time()<(n.suggest_at or 0) then return false end
    if onlinecoop_lan.send("data","K1,"..d.id..","..d.floor..","..row) then n.suggest_at=time()+.25; return true end
    return false
end
function onlinecoop_draw_boss(s,left)
    local b=mode.net.boss_visual
    if not b or b.floor~=s.floor then return end
    local alive=false; for _,p in ipairs(s.units) do if p[1]==b.id then alive=true break end end
    if not alive then return end
    local dx,dy=left-b.x,30-b.y
    spritesheet("gfx"); sprgrid(16,16); pal(); clip(left-24,4,176,157)
    for _,c in ipairs(b.commands) do
        local a=c.args
        if c.op==1 then sspr(a[1],a[2],a[3],a[4],a[5]+dx,a[6]+dy)
        elseif c.op==2 then line(a[1]+dx,a[2]+dy,a[3]+dx,a[4]+dy,a[5])
        elseif #a==0 then pal() else pal(a[1],a[2],a[3]) end
    end
    pal(); clip()
end
-- Shared by drawing and input, with room for owned cards on both sides.
function onlinecoop_draft_bounds(row)
    local d=mode and mode.net and mode.net.draft
    local count=d and d.counts and max(d.counts[1],d.counts[2]) or 2
    local width=min(max(96,count*28+8),MCW-176)
    return MCW/2-width/2,42+(row-1)*58,width,52
end
function onlinecoop_draw_draft()
    local n=mode.net; local d=n.draft
    if not d or not d.active then return false end
    if n.role=="host" then
        if d.suggestion>0 then lprint(scene_text("黑骑士建议：","Knight suggests: ")..scene_text(d.suggestion==1 and "上组选项" or "下组选项",d.suggestion==1 and "upper pair" or "lower pair"),MCW/2,172,5,1) end
        return false
    end
    local hovered
    local mx,my=n.mouse_x or 0,n.mouse_y or 0
    local ready=onlinecoop_lan.status=="connected" and n.peer_ok
    lprint(scene_text("选择建议，由黑王确认","Suggest a pair; King confirms"),MCW/2,10,4,1)
    for row=1,2 do
        local x,y,w,h=onlinecoop_draft_bounds(row)
        local t=min(1,max(0,(time()-d.started-(row-1)*.08)/.3))
        y=y+(1-t)*(1-t)*20
        local selected=d.suggestion==row
        rectfill(x,y,x+w,y+h,2); rect(x,y,x+w,y+h,selected and 5 or 3)
        local counts=d.counts or {2,2}
        local count=counts[row]
        for col=1,count do
            local c=CARDS[d.cards[(row==1 and 0 or counts[1])+col]]
            local cx=x+w*(col-.5)/count-12
            if mx>=cx and mx<cx+24 and my>=y+4 and my<y+36 then hovered=c end
            spritesheet(c.spsheet or "cards"); sprgrid(24,32,10); spr(c.gid,cx,y+4)
            spritesheet("gfx"); sprgrid(16,16)
            lprint(lang[c.id] or c.name or c.id,cx+12,y+38,4,1)
        end
        if selected then lprint(scene_text("已建议","Suggested"),MCW/2,y+46,5,1) end
    end
    spritesheet("gfx"); sprgrid(16,16)
    lprint(ready and scene_text("点击上组或下组发送建议","Click upper or lower pair") or scene_text("连接中断，请双方重启","Disconnected: restart both"),MCW/2,166,3,1)
    return true,hovered
end
