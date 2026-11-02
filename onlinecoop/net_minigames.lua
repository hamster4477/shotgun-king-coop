-- Guest-only waiting toys. Scores and obstacles stay local; rhythm presses use
-- the existing bell signal. Never touches gameplay RNG or chess entities.
local function label(zh,en) return current_lang=="simplified_chinese" and zh or en end
local function inside(mx,my,x,y,w,h) return mx>=x and mx<x+w and my>=y and my<y+h end
local RHYTHM_TARGET=59
local RHYTHM_EARLY=4
local RHYTHM_LATE=3
local function rhythm_lane_bounds(x,w,lane)
    return x+2+flr(lane*(w-4)/3),x+2+flr((lane+1)*(w-4)/3)-1
end
local function context()
    if mode and mode.coop_stats_screen then return end
    local n=mode and mode.net
    if not n or n.role~="client" or not n.peer_ok or not onlinecoop_lan
        or onlinecoop_lan.status~="connected" or n.cg_active or n.cg_returned then return end
    local s=n.snapshot
    if not s or (s.floor<1 and (s.board or 0)==0) or (n.campaign_scene and n.campaign_scene.kind~=0) then return end
    if n.clip_client then return "runner",n.clip_client.floor end
    if n.draft and n.draft.active then return "rhythm",n.draft.floor,n.draft.id end
    if s.phase==1 or s.phase==2 or s.phase==3 or s.phase==4 then return "runner",s.floor end
end
local function random(g)
    g.seed=(g.seed*16807)%2147483647
    return (g.seed-1)/2147483646
end
function onlinecoop_minigame_bounds(kind)
    if kind=="rhythm" then
        local x,y,w,h=onlinecoop_bell_bounds(mode.net,true)
        return x,41,w,78
    end
    return MCW/2-64,88,128,66
end
local function begin(kind,floor,offer)
    local n=mode.net
    local g={kind=kind,floor=floor,offer=offer,seed=flr(time()*1000000)%2147483646+1,
        last=time(),elapsed=0,score=0,notes={},obstacles={},next_spawn=.5,jump=0,velocity=0}
    n.wait_game=g; n.signal_armed=nil
    _log("[WAIT GAME] open="..kind)
    return g
end
local function feedback(g,text,color)
    g.message=text;g.message_color=color;g.message_until=g.elapsed+.3
end
local function jump(g)
    if g.jump<=0 then g.velocity=95;sfx("menu_in",.12) end
end
local function update(g)
    local dt=min(.05,max(0,time()-g.last));g.last=time()
    g.elapsed=g.elapsed+dt
    if g.kind=="rhythm" then
        if g.elapsed>=g.next_spawn then
            if #g.notes<10 then add(g.notes,{lane=flr(random(g)*3),y=0,speed=32+random(g)*8}) end
            g.next_spawn=g.elapsed+.55+random(g)*.35
        end
        local live={}
        for _,note in ipairs(g.notes) do
            if note.hit then
                if g.elapsed-note.hit<.2 then add(live,note) end
            else
                note.y=note.y+note.speed*dt
                if note.y<RHYTHM_TARGET+16 then add(live,note) end
            end
        end
        g.notes=live
    elseif not g.dead then
        if g.jump>0 or g.velocity>0 then
            g.jump=max(0,g.jump+g.velocity*dt-125*dt*dt)
            g.velocity=g.velocity-250*dt
            if g.jump==0 then g.velocity=0 end
        end
        if g.elapsed>=g.next_spawn then
            if #g.obstacles<6 then add(g.obstacles,{x=125,w=4+flr(random(g)*3),h=7+flr(random(g)*4)}) end
            g.next_spawn=g.elapsed+1.15+random(g)*.5
        end
        local live={};local speed=min(76,42+g.score*1.2)
        for _,o in ipairs(g.obstacles) do
            o.x=o.x-speed*dt
            if o.x<29 and o.x+o.w>19 and g.jump<o.h-1 then g.dead=true end
            if not o.scored and o.x+o.w<19 and not g.dead then o.scored=true;g.score=g.score+1 end
            if o.x+o.w>0 then add(live,o) end
        end
        g.obstacles=live
        mode.net.runner_best=max(mode.net.runner_best or 0,g.score)
        if g.dead then g.dead_at=g.elapsed;sfx("menu_out",.18) end
    end
end
function onlinecoop_minigames_input()
    local n=mode and mode.net
    if not n or n.role~="client" then return false end
    local kind,floor,offer=context()
    local g=n.wait_game
    if g and g.kind=="runner" and kind~="runner" then
        -- Keep this run across draft/CG/loading, paused and hidden so those
        -- screens remain usable. Explicitly opening rhythm replaces the toy.
        g.last=time()
        if kind=="rhythm" and btnp("online_cancel",0) then
            local x,y,w,h=onlinecoop_bell_bounds(n,true)
            if inside(btnv("online_mx",0),btnv("online_my",0),x,y,w,h) then
                begin(kind,floor,offer);btnclr();return true
            end
        end
        return false
    end
    if g and g.kind=="rhythm" and (g.kind~=kind or g.floor~=floor or g.offer~=offer) then
        _log("[WAIT GAME] close="..g.kind.." score="..g.score.." reason=scene_or_turn")
        n.wait_game=nil
        -- Consume the transition frame so a last minigame click cannot move a
        -- Knight or select a card underneath the disappearing panel.
        btnclr();return true
    end
    if not kind then return false end
    local mx,my=btnv("online_mx",0),btnv("online_my",0)
    local space=btnp("online_wait_jump",0)
    local right=btnp("online_cancel",0)
    local escape=btnp("online_pause",0)
    if not g then
        if kind=="rhythm" and right then
            local x,y,w,h=onlinecoop_bell_bounds(n,true)
            if inside(mx,my,x,y,w,h) then begin(kind,floor,offer);btnclr();return true end
        elseif kind=="runner" and space then
            g=begin(kind,floor,offer);jump(g)
            local x,y,w,h=onlinecoop_minigame_bounds("runner")
            if btnp("online_lclick",0) and inside(mx,my,x,y,w,h) then btnclr();return true end
            return false
        end
        return false
    end
    update(g)
    local rx,ry,rw,rh=onlinecoop_minigame_bounds("runner")
    if escape or (right and (kind=="rhythm" or inside(mx,my,rx,ry,rw,rh))) then
        _log("[WAIT GAME] close="..g.kind.." score="..g.score.." reason=exit")
        n.wait_game=nil;btnclr();return true
    end
    if kind=="runner" then
        if space then
            if g.dead and g.elapsed-g.dead_at>.3 then g=begin(kind,floor,offer);jump(g)
            elseif not g.dead then jump(g) end
        end
        if btnp("online_lclick",0) and inside(mx,my,rx,ry,rw,rh) then btnclr();return true end
        -- Space has no client chess binding. Pass through mouse/Tab/soul input
        -- outside this panel, even on the same frame as a jump.
        return false
    end
    local x,y,w,h=onlinecoop_minigame_bounds(kind)
    local bx,by,bw,bh=onlinecoop_bell_bounds(n,true)
    if btnp("online_lclick",0) and inside(mx,my,bx,by,bw,bh) then
        -- Every accepted strike rings the host, even if it misses the note.
        -- Reuse the bell's short cooldown and network validation.
        if not onlinecoop_signal_send(2) then btnclr();return true end
        local best,distance=nil,max(RHYTHM_EARLY,RHYTHM_LATE)
        for _,note in ipairs(g.notes) do
            local offset=note.y-RHYTHM_TARGET
            local d=abs(offset)
            if not note.hit and offset>=-RHYTHM_EARLY and offset<=RHYTHM_LATE
                and d<=distance then best=note;distance=d end
        end
        if best then
            best.hit=g.elapsed;g.score=g.score+1
            n.rhythm_best=max(n.rhythm_best or 0,g.score)
            feedback(g,label("命中！","HIT!"),11);sfx("menu_in",.25)
        else feedback(g,label("未命中","MISS"),3) end
        btnclr();return true
    end
    if btnp("online_lclick",0) and inside(mx,my,x,y,w,h) then btnclr();return true end
    -- Card suggestions outside the little music panel still work normally.
    return false
end
function onlinecoop_minigames_draw()
    local n=mode and mode.net
    if not n or n.role~="client" then return end
    local kind,floor,offer=context()
    if not kind then return end
    local g=n.wait_game
    if not g then return end
    if kind~=g.kind or (kind=="rhythm" and (floor~=g.floor or offer~=g.offer)) then return end
    local x,y,w,h=onlinecoop_minigame_bounds(kind)
    clip();pal();rectfill(x,y,x+w-1,y+h-1,1);rect(x,y,x+w-1,y+h-1,3)
    if kind=="rhythm" then
        lprint(label("命中 ","HIT ")..g.score,x+w/2,y+3,4,1)
        lprint(label(w<40 and "最高 " or "本局最高 ","Best ")..(n.rhythm_best or 0),x+w/2,y+11,3,1)
        clip(x+1,y+22,w-2,h-23)
        local judge_y=y+14+RHYTHM_TARGET
        rectfill(x+2,judge_y-RHYTHM_EARLY,x+w-3,judge_y+RHYTHM_LATE,2)
        for lane=1,2 do
            local left=rhythm_lane_bounds(x,w,lane)
            line(left,y+22,left,y+h-2,2)
        end
        line(x+2,judge_y,x+w-3,judge_y,5)
        for _,note in ipairs(g.notes) do
            local left,right=rhythm_lane_bounds(x,w,note.lane or 1)
            local yy=flr(y+14+note.y)
            rectfill(left+1,yy,right-1,yy+2,note.hit and 11 or 4)
        end
        clip()
        if g.message_until and g.elapsed<g.message_until then
            rectfill(x+1,y+29,x+w-2,y+39,1)
            lprint(g.message,x+w/2,y+31,g.message_color,1)
        end
        local bx,by,bw,bh=onlinecoop_bell_bounds(n,true)
        if bw<40 then
            lprint(label("按铃","Click"),bx+bw/2,by+bh+5,3,1)
            lprint(label("右键退","RMB"),bx+bw/2,by+bh+13,3,1)
        else
            lprint(label("按铃 / 右键退","Click / RMB"),bx+bw/2,by+bh+5,3,1)
        end
    else
        lprint(label("骑士跑酷","Knight Run"),x+4,y+4,4)
        lprint(label("分数 ","Score ")..g.score,x+w-4,y+4,4,2)
        lprint(label("本局最高 ","Run best ")..(n.runner_best or 0),x+w-4,y+13,3,2)
        clip(x+1,y+15,w-2,38)
        local ground=y+51
        line(x+2,ground,x+w-3,ground,3)
        for i=0,9 do
            local xx=x+((i*16-flr(g.elapsed*42))%(w-4))+2
            line(xx,ground+2,xx+3,ground+2,2)
        end
        spritesheet("gfx");sprgrid(16,16)
        spr(433,x+16,flr(ground-16-g.jump))
        for _,o in ipairs(g.obstacles) do
            local xx=flr(x+o.x)
            rectfill(xx,ground-o.h,xx+o.w-1,ground-1,5)
            line(xx,ground-o.h-2,xx+o.w-1,ground-o.h-2,4)
        end
        clip()
        if g.dead then
            rectfill(x+34,y+23,x+w-4,y+34,1)
            lprint(label("撞到了！空格重来","Oops! Space retries"),x+w/2+14,y+25,5,1)
        end
        lprint(label("空格跳 / 框内右键或Esc退出","Space: jump / RMB or Esc: exit"),x+w/2,y+h-10,3,1)
    end
    clip();pal()
end
