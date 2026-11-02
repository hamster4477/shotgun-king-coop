-- Presentation-only communication. Never touches pieces, turns or native buttons.
local function signal_context()
    if not mode or mode.id~="coop" or not mode.net then return end
    local n=mode.net
    if not n.peer_ok or onlinecoop_lan.status~="connected" or n.cg_active or n.cg_returned or onlinecoop_playback_busy() then return end
    local s=n.snapshot
    local floor=n.role=="host" and mode.lvl or (s and s.floor)
    if n.campaign_scene and n.campaign_scene.kind==1 then return n,n.campaign_scene.floor,false,true end
    if not floor or floor<0 then return end
    if n.draft and n.draft.active then return n,floor,false,true end
    local phase=n.role=="host" and onlinecoop_net_phase() or (s and s.phase)
    if phase~=1 and phase~=2 and phase~=3 then return end
    return n,floor,true,false
end
local function signal_geometry(n)
    if n.role=="host" then return coop_get_board_geometry() end
    return (MCW-128)/2,30
end
local function signal_inside(mx,my,x,y,w,h)
    return mx>=x and mx<x+w and my>=y and my<y+h
end
-- A per-run reward; the existing runner record survives floors and is reset
-- by fresh mode entry / the shared results restart. Draft bell stays available.
function onlinecoop_bell_available(n,draft)
    return n and n.role=="client" and (draft or (n.runner_best or 0)>=31) or false
end
function onlinecoop_bell_bounds(n,draft)
    if n.campaign_scene and n.campaign_scene.kind==1 then return MCW-56,112,50,48 end
    if draft then
        -- Lower-right gap between the compact choices and the owned white cards.
        local dx,dy,dw=onlinecoop_draft_bounds(1)
        local left,right=dx+dw+2,MCW-60
        local scale=right-left>=50 and 2 or 1
        local w,h=25*scale,24*scale
        local y=n.wait_game and n.wait_game.kind=="rhythm" and 119 or 116
        return flr(left+(right-left-w)/2),y,w,h
    end
    local left,top=signal_geometry(n)
    return left+18,top+131,14,14
end
-- Separate audio PRNG: ringing must not consume the gameplay RNG sequence.
local bell_random_state
local function choose_bell()
    if not bell_random_state then bell_random_state=flr(time()*1000000)%2147483646+1 end
    bell_random_state=(bell_random_state*16807)%2147483647
    local roll=bell_random_state%100
    return roll<5 and 3 or (roll%2==0 and 1 or 2)
end
function onlinecoop_signal_sound(kind,variant)
    if kind=="bell" then
        local suffix=({"a","b","c"})[variant or choose_bell()]
        if not suffix then return end
        sfx("onlinecoop_bell_"..suffix,.9)
        _log("[ONLINE BELL] variant="..suffix)
    elseif kind=="ping" then sfx("onlinecoop_ping",1)
    elseif kind=="suggestion" then sfx("onlinecoop_suggestion",.7) end
end
local function signal_show(n,who,kind,floor,x,y)
    if kind==1 then
        n.signals=n.signals or {}
        n.signals[who]={floor=floor,x=x,y=y,started=time()}
        onlinecoop_signal_sound("ping")
    elseif who=="client" then
        if n.role=="host" then n.bell_received_at=time() end
        onlinecoop_signal_sound("bell",x)
    end
end
function onlinecoop_signal_send(kind,x,y)
    local n,floor,board,draft=signal_context()
    if not n or (kind~=1 and kind~=2) or time()<(n.signal_send_at or 0) then return false end
    if kind==1 then
        if not board or type(x)~="number" or type(y)~="number" or x%1~=0 or y%1~=0
            or x<0 or x>7 or y<0 or y>7 then return false end
    else
        if not onlinecoop_bell_available(n,draft) or not (board or draft) then return false end
        -- Choose once at the source: both peers hear the same ordinary or
        -- rare bell. The sender plays immediately after a successful send.
        x,y=choose_bell(),0
    end
    local serial=(n.signal_sent or 0)+1
    if not onlinecoop_lan.send("data","Q1,"..serial..","..floor..","..kind..","..x..","..y) then return false end
    n.signal_sent=serial; n.signal_send_at=time()+(kind==2 and .3 or 1)
    if kind==2 then n.bell_pressed_at=time() end
    signal_show(n,n.role,kind,floor,x,y)
    _log("[ONLINE SIGNAL] send kind="..kind.." floor="..floor.." cell="..x..","..y)
    return true
end
function onlinecoop_signals_receive(payload)
    local n,floor,board,draft=signal_context()
    if not n or sub(payload,1,3)~="Q1," then return false end
    local a=onlinecoop_net_numbers(sub(payload,4),5,1000000)
    if not a or a[1]<1 or a[1]<=(n.signal_received or 0) or a[2]~=floor
        or time()<(n.signal_receive_at or 0) then return false end
    if a[3]==1 then
        if not board or a[4]>7 or a[5]>7 then return false end
    elseif a[3]==2 then
        if n.role~="host" or not (board or draft) or a[4]<1 or a[4]>3 or a[5]~=0 then return false end
    else return false end
    n.signal_received=a[1]; n.signal_receive_at=time()+(a[3]==2 and .2 or .75)
    signal_show(n,n.role=="host" and "client" or "host",a[3],floor,a[4],a[5])
    _log("[ONLINE SIGNAL] receive kind="..a[3].." floor="..floor.." cell="..a[4]..","..a[5])
    return true
end
function onlinecoop_signals_input()
    if mode and mode.net and mode.net.wait_game and mode.net.wait_game.kind=="rhythm" then return false end
    local n,floor,board,draft=signal_context()
    if not n then
        if mode and mode.net then mode.net.signal_armed=nil end
        return false
    end
    if n.signal_armed and n.signal_armed~=floor then n.signal_armed=nil end
    if not board then n.signal_armed=nil end
    if btnp("online_pause",0) then n.signal_armed=nil; return false end
    if board and btnp("online_ping",0) then
        n.signal_armed=not n.signal_armed and floor or nil
        btnclr(); return true
    end
    local left,top=signal_geometry(n)
    local x,y=btnv("online_mx",0),btnv("online_my",0)
    local click=btnp("online_lclick",0)
    if board and click and signal_inside(x,y,left,top+131,14,14) then
        n.signal_armed=not n.signal_armed and floor or nil
        btnclr(); return true
    end
    local bx,by,bw,bh=onlinecoop_bell_bounds(n,draft)
    if onlinecoop_bell_available(n,draft) and click and signal_inside(x,y,bx,by,bw,bh) then
        n.signal_armed=nil; onlinecoop_signal_send(2)
        btnclr(); return true
    end
    if n.signal_armed then
        if btnp("online_cancel",0) then n.signal_armed=nil
        elseif click and signal_inside(x,y,left,top,128,128) then
            local col,row=flr((x-left)/16),flr((y-top)/16)
            if onlinecoop_signal_send(1,col,row) then n.signal_armed=nil end
        elseif click then n.signal_armed=nil end
        -- Consume the entire gesture so it cannot also move, shoot or select a soul.
        btnclr(); return true
    end
    return false
end
function onlinecoop_signals_draw()
    if mode and mode.coop_stats_screen then return end
    local n,floor,board,draft=signal_context()
    if not n then return end
    local left,top=signal_geometry(n)
    local mx,my=btnv("online_mx",0),btnv("online_my",0)
    local zh=current_lang=="simplified_chinese"
    clip(); pal(); spritesheet("gfx"); sprgrid(16,16)
    if board then
        for _,who in ipairs({"host","client"}) do
            local p=n.signals and n.signals[who]
            if p and (p.floor~=floor or time()-p.started>=3) then
                n.signals[who]=nil
            elseif p then
                local age=time()-p.started
                if age<.18 then pal(5,4) end
                -- Native red exclamation, gfx (112,272), not a font substitute.
                spr(279,left+p.x*16,top+p.y*16)
                pal()
            end
        end
        local hover=signal_inside(mx,my,left,top+131,14,14)
        rectfill(left,top+131,left+13,top+144,1)
        if hover or n.signal_armed then rect(left,top+131,left+13,top+144,n.signal_armed and 5 or 3) end
        spr(279,left-1,top+130)
        if (n.signal_armed or hover) and n.role=="host" then
            rectfill(left,172,MCW-64,180,1)
            lprint(zh and (n.signal_armed and "点击格子标点 / E或右键取消" or "标记格子 [E]")
                or (n.signal_armed and "Pick cell / E or Right click cancels" or "Mark a cell [E]"),left,174,4)
        end
    end
    if onlinecoop_bell_available(n,draft) then
        local x,y,w,h=onlinecoop_bell_bounds(n,draft)
        local hover=signal_inside(mx,my,x,y,w,h)
        local color=time()<(n.signal_send_at or 0) and 3 or (hover and 5 or 4)
        if draft then
            local age=n.bell_pressed_at and time()-n.bell_pressed_at or 10
            local frame=age<.14 and 1 or 0
            local shake=age>=.14 and age<.42 and (flr((age-.14)/.07)%2==0 and 1 or -1) or 0
            spritesheet("onlinecoop_bell_button")
            sspr(frame*25,0,25,24,x+shake,y,w,h)
            spritesheet("gfx"); sprgrid(16,16)
            if not n.wait_game or n.wait_game.kind~="rhythm" then
                local rhythm=hover and not (n.campaign_scene and n.campaign_scene.kind==1)
                lprint(zh and (rhythm and "右键玩音游" or "提醒黑王") or (rhythm and "RMB: rhythm" or "Ring King"),x+w/2,y+h+5,color,1)
            end
        else
            rectfill(x,y,x+13,y+13,1)
            if hover then rect(x,y,x+13,y+13,3) end
            rectfill(x+6,y+2,x+7,y+3,color); line(x+5,y+4,x+8,y+4,color)
            line(x+4,y+5,x+4,y+9,color); line(x+9,y+5,x+9,y+9,color)
            line(x+3,y+10,x+10,y+10,color); line(x+6,y+12,x+7,y+12,color)
        end
    elseif n.role=="host" and n.bell_received_at and time()-n.bell_received_at<1.5 then
        lprint(zh and "黑骑士提醒你" or "Knight is calling",MCW/2,166,5,1)
    end
    pal()
end
function onlinecoop_signals_hint()
    local n,floor,board,draft=signal_context()
    if not n then return end
    local left,top=signal_geometry(n)
    local x,y=btnv("online_mx",0),btnv("online_my",0)
    local zh=current_lang=="simplified_chinese"
    if board and n.signal_armed then return zh and "点击格子标点 / E或右键取消" or "Pick cell / E or Right click cancels" end
    if board and signal_inside(x,y,left,top+131,14,14) then return zh and "标记格子 [E]" or "Mark a cell [E]" end
    local bx,by,bw,bh=onlinecoop_bell_bounds(n,draft)
    if onlinecoop_bell_available(n,draft) and signal_inside(x,y,bx,by,bw,bh) then return zh and "提醒黑王" or "Ring the King" end
end
function onlinecoop_signals_initialize()
    local n=mode.net
    local function clear()
        if mode and mode.net==n then n.signals={}; n.signal_armed=nil; n.bell_received_at=nil; n.bell_pressed_at=nil end
    end
    prepend("new_level",clear,"online_signals_floor")
    prepend("init_menu",clear,"online_signals_menu")
end
