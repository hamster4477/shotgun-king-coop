-- Display-only mirror. Native skins draw plain records; interpolation entities
-- in net_events have no piece/enemy flags, AI, buttons or combat callbacks.
local function net_label(zh,en)
    return current_lang=="simplified_chinese" and zh or en
end
local function connection_label(n)
    local state=onlinecoop_lan and onlinecoop_lan.status or "idle"
    if state=="error" or state=="stopped" then
        return net_label("连接中断，请双方重启","Disconnected: restart both")
    end
    if n.error=="campaign_mismatch" then
        return net_label("模式不同，请双方选择同一种局域网模式","Mode mismatch: select the same LAN campaign")
    end
    if n.error=="version_mismatch" then
        return net_label("版本不同，请双方更新同一版本","Version mismatch: update both copies")
    end
    if state=="connected" and n.peer_ok then return net_label("已连接","Connected") end
    if n.role=="client" then return net_label("等待房主连接与版本确认","Waiting for host / version check") end
    return net_label("等待 2P 进入局域网合作","Waiting for 2P to enter LAN Co-op")
end
local function net_inside(mx,my,x,y,w,h)
    return mx>=x and mx<x+w and my>=y and my<y+h
end
local function draw_draft_shortcuts()
    -- Keep clear of the ten owned cards on the left (x=8..54, y=14..173).
    lprint(net_label("F6：切换帧率 / F7：切换动画模式",
        "F6: Change FPS / F7: Playback mode"),64,156,3)
end
function onlinecoop_net_slot_position(index,count)
    local page=mode.net.soul_page or 0
    local first=page*5+1
    if index<first or index>first+4 then return nil end
    local visible=min(5,count-page*5)
    return (MCW+128)/2+7,94-visible*16+(index-first)*32
end
function onlinecoop_net_client_input()
    if not mode or mode.id~="coop" or not mode.net then return end
    local n=mode.net
    if mode.coop_stats_screen then return end
    onlinecoop_playback_input()
    if onlinecoop_board_rate_input() then return end
    if onlinecoop_minigames_input() then return end
    if n.cg_active or n.cg_returned then return end
    if onlinecoop_choices_input() then return end
    if onlinecoop_signals_input() then return end
    if onlinecoop_playback_busy() then
        if not mode.coop_pause_menu_open and not btnp("online_pause",0) then btnclr() end
        return
    end
    if n.role~="client" then
        if n.draft and n.draft.active then return end
        if is_coop_active() and not mode.coop_pause_menu_open and not btnp("online_pause",0)
            and (not n.peer_ok or onlinecoop_lan.status~="connected" or mode.coop_selected=="knight") then btnclr() end
        return
    end
    local s=n.snapshot
    n.mouse_x,n.mouse_y=btnv("online_mx",0),btnv("online_my",0)
    if n.campaign_scene and n.campaign_scene.kind~=0 then btnclr();return end
    if s and not n.menu_retired and type(remove_buts)=="function" then
        remove_buts()
        n.menu_retired=true
    end
    if btnp("online_cards",0) then n.card_page=(n.card_page or 0)+1 end
    if n.draft and n.draft.active then
        if btnp("online_lclick",0) and time()-n.draft.started>=.4 then
            for row=1,2 do
                local x,y,w,h=onlinecoop_draft_bounds(row)
                if net_inside(n.mouse_x,n.mouse_y,x,y,w,h) then onlinecoop_suggest_choice(row) end
            end
        end
        btnclr(); return
    end
    if btnp("online_soul_page",0) and s then n.soul_page=((n.soul_page or 0)+1)%max(1,ceil(#s.souls/5)) end
    if s and not n.pending then
        if s.phase==2 and time()>=(n.aim_at or 0) then
            n.aim_at=time()+.05
            for _,p in ipairs(s.units) do if p[1]==s.knight then
                local dx=n.mouse_x-((MCW-128)/2+p[2]*16+8)
                local dy=n.mouse_y-(30+p[3]*16+8)
                local angle=(atan2(dx,dy)%1)*128; angle=angle-angle%1
                local x,y=(n.mouse_x-(MCW-128)/2)/16,(n.mouse_y-30)/16
                x=x-x%1; y=y-y%1
                if x<0 or x>7 or y<0 or y>7 then x,y=-1,-1 end
                local aim=angle..","..(x+1)..","..(y+1)
                if aim~=n.last_aim and onlinecoop_lan.send("data","H1,"..aim) then n.last_aim=aim end
                break
            end end
        end
        if btnp("online_cancel",0) and s.phase==2 and s.ui[11]>0 then onlinecoop_net_request("cancel",0,0) end
        if btnp("online_lclick",0) then
            local mx,my=btnv("online_mx",0),btnv("online_my",0)
            local handled=false
            for _,slot in ipairs(s.souls) do
                local x,y=onlinecoop_net_slot_position(slot[1],#s.souls)
                if x and net_inside(mx,my,x,y,24,30) then
                    handled=true
                    if s.ui[12]==1 and slot[2]==1 then onlinecoop_net_request("revive",slot[1],slot[2])
                    elseif s.phase==2 and slot[3]==1 then onlinecoop_net_request("soul",slot[1],slot[2]) end
                    break
                end
            end
            local left=(MCW-128)/2
            if not handled and s.ui[10]==1 and net_inside(mx,my,left-17,161,14,14) then
                handled=onlinecoop_net_request("mechanism",0,0)
            end
            if not handled and s.phase==2 then
                local x,y=(mx-left)/16,(my-30)/16
                x=x-x%1; y=y-y%1
                local kind
                for _,p in ipairs(s.moves) do if p[1]==x and p[2]==y then kind="move" break end end
                for _,p in ipairs(s.attacks) do if p[1]==x and p[2]==y then kind="attack" break end end
                if kind then onlinecoop_net_request(kind,x,y) end
            end
        end
        if btnp("online_skip",0) then onlinecoop_net_request("skip",0,0) end
    end
    -- Native menus underneath the mirror must never receive a remote player's clicks.
    btnclr()
end
local function net_corners(x,y,color,arm)
    arm=arm or 3
    for _,dx in ipairs({0,1}) do for _,dy in ipairs({0,1}) do
        local xx,yy=x+2+dx*11,y+2+dy*11
        rectfill(xx-dx*arm,yy,xx+(1-dx)*arm,yy+1,color)
        rectfill(xx,yy-dy*arm,xx+1,yy+(1-dy)*arm,color)
    end end
end
function onlinecoop_draw_net_piece(p,x,y,s,flash)
    local typ=p[4]
    -- Boss body is replayed from native drawing data, never a pawn portrait.
    if typ==6 then return end
    if p[1]==s.knight or p[10]==1 or typ==s.ui[16] then typ=1 end
    if typ>5 then typ=0 end
    local skin={type=typ,index=typ,team=p[5],bad=p[5]==1,
        hp=p[6],hp_max=p[9],name="",x=x,y=y,z=0,t=0,fr=-1,
        prison_bar=0,dcx=0,dcy=0,hdy=typ==5 and 0 or 1,
        ww=16,hh=16,flx=false,see_hat=false,ready=false,fly=false,
        dr_skin=dr_skin,mark={},dgr={},behavior={},sq={px=p[2],py=p[3]}}
    if p[1]==s.king then
        -- Native mastermind selects the player crown; an selects its direction.
        skin.name="king"; skin.piece=1; skin.still=true; skin.mastermind=1
        skin.an=mode.net.king_aim or -.125; skin.current_an=skin.an
    end
    spritesheet("gfx"); sprgrid(16,16)
    if flash then pal({[1]=5,[2]=5,[3]=4,[4]=4}) end
    dr_piece(skin,x,y)
    pal()
    local body_y=y-2
    if p[4]==s.ui[16] then rectfill(x+11,body_y+1,x+13,body_y+3,5) end
    if p[10]==1 then pset(x+2,body_y+3,11); pset(x+12,body_y+10,11) end
end
local function net_weapon(p,x,y,s,mx,my)
    local n=mode.net
    if n.cg_active or n.cg_returned then return end
    local angle=-.125
    if s.phase==2 then angle=atan2(mx-x-8,my-y-8) end
    local swing=n.swing_started and (time()-n.swing_started)/.24 or 1
    if swing<1 then angle=atan2(s.ui[19]-p[2],s.ui[20]-p[3])-.14+.28*swing end
    local target_x=(mx-(MCW-128)/2)/16; target_x=target_x-target_x%1
    local target_y=(my-30)/16; target_y=target_y-target_y%1
    if swing<1 then target_x,target_y=s.ui[19],s.ui[20] end
    local dx,dy=abs(target_x-p[2]),abs(target_y-p[3])
    local spear=s.ui[15]==1 and s.ui[11]==0 and (s.phase==2 or swing<1)
        and ((dx==2 and (dy==0 or dy==2)) or (dx==0 and dy==2))
    local size=mode.coop_weapon_source_size
    if not mode.coop_weapon_pixels and mode.coop_weapon_sheet_loaded then coop_load_knight_weapon_pixels() end
    local pixels=mode.coop_weapon_pixels
    local anchor=mode.coop_weapon_anchor
    if spear then
        if not mode.coop_spear_pixels and mode.coop_spear_sheet_loaded then coop_load_knight_spear_pixels() end
        if mode.coop_spear_pixels then pixels=mode.coop_spear_pixels; size=48; anchor=23
        else
            local ux,uy=cos(angle),sin(angle)
            line(x+8,y+8,x+8+ux*21,y+8+uy*21,4)
            line(x+8+ux*18-uy*2,y+8+uy*18+ux*2,x+8+ux*23,y+8+uy*23,5)
            line(x+8+ux*18+uy*2,y+8+uy*18-ux*2,x+8+ux*23,y+8+uy*23,5)
            return
        end
    end
    if not pixels or not size then return end
    -- Inverse sampling leaves no forward-mapping holes. Only this view's mouse aims the weapon.
    local c,si=cos(angle+.125),sin(angle+.125)
    local radius=spear and 24 or 16
    for dy=-radius,radius do for dx=-radius,radius do
        local sx=anchor+dx*c+dy*si+.5; sx=sx-sx%1
        local sy=anchor-dx*si+dy*c+.5; sy=sy-sy%1
        local col=sx>=0 and sx<size and sy>=0 and sy<size and pixels[sy*size+sx] or nil
        if col and (abs(dx)>2 or dy < -5 or dy>6) then pset(x+8+dx,y+8+dy,col) end
    end end
end
local function net_king_gun(x,y,s)
    spritesheet("gfx")
    local angle=mode.net.king_aim or -.125
    local recoil=mode.net.shot_track and onlinecoop_effect_progress(mode.net.shot_track) or 1
    local reload=mode.net.reload_track and onlinecoop_effect_progress(mode.net.reload_track) or 1
    if reload<1 and recoil>=1 then
        -- Native gun artwork and tween; short visual tilt, not native refill logic.
        angle=angle+sin(reload/2)*.09
        y=y+sin(reload/2)*2
    end
    if recoil<1 then
        angle=mode.net.shot_angle or angle
        x=x-cos(angle)*3*(1-recoil); y=y-sin(angle)*3*(1-recoil)
    end
    -- Native held-gun cell, pivot and left-facing flip (not the HUD thumbnail).
    local flip=cos(angle)<0 and -1 or 1
    pal({[0]=4,[1]=4,[2]=4,[3]=4,[4]=4,[5]=4,[6]=4})
    for _,d in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do
        asspr(32,0,16,16,x+8+d[1],y+8+d[2],angle,1,flip,4,8)
    end
    pal()
    asspr(32,0,16,16,x+8,y+8,angle,1,flip,4,8)
    spritesheet("gfx")
end
local function net_hit_effect(id)
    local flash,dead=false,false
    for _,fx in ipairs(mode.net.effects or {}) do
        local e=fx.event
        local progress=onlinecoop_effect_progress(fx)
        if e[4]==id and progress<1 then
            if e[3]==3 then flash=(progress*6)%2<1 end
            if e[3]==4 then dead=true end
        end
    end
    return flash,dead
end
local function net_draw_events(s,left)
    local remaining={}
    for _,fx in ipairs(mode.net.effects or {}) do
        local e=fx.event
        local t=onlinecoop_effect_progress(fx)
        if t<1 then
            add(remaining,fx)
            local x,y=left+(fx.x or e[5])*16,30+(fx.y or e[6])*16
            if e[3]==2 then
                local angle=e[13]/128
                local ux,uy=cos(angle),sin(angle)
                local ox,oy=x+8+ux*15,y+9+uy*15
                if t<.45 then
                    line(ox-uy*3,oy+ux*3,ox+ux*7,oy+uy*7,4)
                    line(ox+uy*3,oy-ux*3,ox+ux*7,oy+uy*7,5)
                end
                clip(left,30,128,128)
                for i=-1,1 do
                    local a=angle+i*min(60,s.ui[5])/720
                    local d=16+t*28
                    local vx,vy=cos(a),sin(a)
                    -- Three pixels wide so pellets remain visible at windowed scale.
                    for step=0,6 do
                        local px,py=flr(x+8+vx*(d+step)+.5),flr(y+9+vy*(d+step)+.5)
                        rectfill(px-1,py-1,px+1,py+1,5)
                    end
                end
                clip()
            elseif e[3]==3 then
                lprint("-"..e[12],x+8,y-2-t*7,5,1)
            elseif e[3]==6 then
                -- Read-only feedback; authoritative HP comes from the snapshot.
                lprint("+"..e[12],x+8,y-2-t*9,6,1)
                if t<.7 then
                    local py=flr(y+8-t*12)
                    line(x+2,py-1,x+2,py+1,6)
                    line(x+1,py,x+3,py,6)
                end
            elseif e[3]==4 and e[9]~=6 then
                -- Retained numeric portrait; no resurrected engine entity.
                local p={e[4],e[5],e[6],e[9],e[10],0,0,0,0,0,e[15]}
                local dx,dy=sin(t*.5)*2,-t*5
                for row=-3,13 do
                    if ((row+3)*7+e[4])%17>=t*17 then
                        clip(x+dx,y+dy+row,16,1)
                        onlinecoop_draw_net_piece(p,x+dx,y+dy,s,t<.18)
                    end
                end
                clip()
                for i=0,5 do
                    local a=i/6
                    pset(x+8+cos(a)*(3+t*9),y+8+sin(a)*(3+t*9)-t*5,i%2==0 and 4 or 3)
                end
            end
        end
    end
    mode.net.effects=remaining
end
-- Read-only local tooltip: no native buttons/entities or network hover traffic.
-- Build the native description once per hover, not once per rendered frame.
function onlinecoop_card_tooltip(card,mx,my)
    local n=mode.net
    if not card then n.card_tooltip=nil;return end
    local old=n.card_tooltip
    if not old or old.card~=card or old.language~=current_lang then
        local text=(get_lang(card.id) or card.id).."|"..get_desc(card,true)
        text=sbs(sbs(text,"|","\n"),"%$",lang.degree_symbol)
        local lines={};local first=1
        for i=1,#text do
            if sub(text,i,i)=="\n" then add(lines,sub(text,first,i-1));first=i+1 end
        end
        add(lines,sub(text,first))
        old={card=card,language=current_lang,lines=lines};n.card_tooltip=old
    end
    local w=min(144,MCW-8);local tw=w-12
    local height=0
    for _,line in ipairs(old.lines) do height=pprint(line,0,height-1000,tw,0,0)+1000 end
    local h=height+8
    local x=mx+6
    if x+w>MCW-3 then x=mx-w-6 end
    x=max(3,min(x,MCW-w-3))
    local y=max(3,min(my+6,MCH-h-3))
    clip();pal()
    rectfill(x,y,x+w-1,y+h-1,2)
    hdclear(x,y,x+w-1,y+h-1,2)
    rect(x,y,x+w-1,y+h-1,3)
    local cy=y+4
    for i,line in ipairs(old.lines) do cy=pprint(line,x+4,cy,tw,i==1 and 4 or 3,0) end
    spritesheet("gfx");sprgrid(16,16)
end
local function net_card_panels(s,mx,my)
    local teams={[0]={},[1]={}}
    for _,card in ipairs(s.cards) do add(teams[card[3]],card) end
    local pages=max(1,ceil(max(#teams[0],#teams[1])/10))
    local page=(mode.net.card_page or 0)%pages
    local hovered
    for team=0,1 do
        for i=1,10 do
            local x=(team==0 and 8 or MCW-56)+((i-1)%2)*24
            local y=14+((i-1)-(i-1)%2)/2*32
            local card=teams[team][page*10+i]
            if card then
                spritesheet(CARDS[card[1]].spsheet or "cards"); sprgrid(24,32,10); spr(card[2],x,y)
                if net_inside(mx,my,x,y,22,30) then hovered=CARDS[card[1]] end
            else coop_draw_empty_soul_slot(nil,x,y) end
        end
    end
    if pages>1 then
        local draft=mode.net.draft and mode.net.draft.active
        lprint("C "..(page+1).."/"..pages,draft and MCW-56 or 8,174,3)
    end
    return hovered
end
-- Consume only this frame's hover after bells and waiting-game overlays draw.
function onlinecoop_draw_card_tooltip_overlay()
    local n=mode and mode.net
    if not n or n.role~="client" then return end
    local card=n.card_tooltip_pending
    n.card_tooltip_pending=nil
    onlinecoop_card_tooltip(card,n.mouse_x or 0,n.mouse_y or 0)
end
function onlinecoop_net_draw_client()
    if mode and mode.net then mode.net.card_tooltip_pending=nil end
    if mode and mode.coop_stats_screen then return end
    if not mode or mode.id~="coop" or not mode.net then return end
    local n=mode.net
    if n.cg_active or n.cg_returned then return end
    if n.role~="client" then
        onlinecoop_draw_draft()
        if n.draft and n.draft.active then draw_draft_shortcuts() end
        lprint(onlinecoop_playback_hint() or ("1P / "..connection_label(n)),4,176,4)
        return
    end
    -- Native mode setup draws HD text onto a separate overlay. Clearing the
    -- low-resolution board alone leaves rank/weapon/start labels over souls.
    -- Reset that overlay before drawing this client's own labels each frame.
    -- Native hdtext clears to palette key 255, not the opaque background 0.
    -- winspec's getter returns the surface name only.
    local overlay=winspec("overlay")
    if overlay=="hdtext" and srfname(overlay) then
        local previous_target=srfname()
        target(overlay); cls(255); target(previous_target)
    end
    clip()
    pal(); rectfill(0,0,MCW,240,1)
    if onlinecoop_campaign_draw() then return end
    local s=onlinecoop_playback_snapshot()
    -- Hidden-Boss stories own their side cards, speech and off-board actors.
    -- Their complete canvas must not be covered by independently drawn HUD.
    if onlinecoop_draw_scene_frame(s) then
        local connected=onlinecoop_lan and onlinecoop_lan.status=="connected" and n.peer_ok
        if not connected then
            rectfill(0,MCH-12,MCW-1,MCH-1,1)
            lprint(connection_label(n),MCW/2,MCH-10,4,1)
        elseif n.clip_client and n.clip_client.story_prebuffer then
            rectfill(0,MCH-12,MCW-1,MCH-1,1)
            lprint(net_label("正在缓冲完整剧情…","Buffering complete story..."),MCW/2,MCH-10,4,1)
        elseif n.remote_choices and not onlinecoop_playback_busy() then onlinecoop_choices_draw() end
        return
    end
    if n.draft and n.draft.active and not n.clip_client then
        local hovered=s and net_card_panels(s,n.mouse_x or 0,n.mouse_y or 0)
        local _,draft_hover=onlinecoop_draw_draft()
        draw_draft_shortcuts()
        lprint("2P / "..connection_label(n),4,176,4)
        n.card_tooltip_pending=draft_hover or hovered
        return
    end
    if not s or s.board==0 then
        lprint(n.peer_ok and onlinecoop_lan.status=="connected"
            and net_label("等待房主开始……","Waiting for host...") or connection_label(n),MCW/2,84,4,1)
        return
    end
    local mx,my=n.mouse_x or 0,n.mouse_y or 0
    local phase=onlinecoop_lan.status=="connected" and s.phase or 7
    local zh={[0]="等待房主开始",[1]="黑王行动",[2]="黑骑士行动",[3]="行动结算中",[4]="房主正在结算楼层",[5]="对局结束",[6]="房主已暂停",[7]="连接中断，请双方重启",[8]="正在核对版本"}
    local en={[0]="Waiting for host",[1]="King's action",[2]="Knight's action",[3]="Resolving",[4]="Host resolving floor",[5]="Game over",[6]="Host paused",[7]="Disconnected: restart both",[8]="Checking version"}
    lprint("2P / "..net_label(zh[phase],en[phase]),8,3,phase==2 and 5 or 3)
    local left=(MCW-128)/2
    local hovered_card=net_card_panels(s,mx,my)
    local can_input=phase==2 and not n.pending and not onlinecoop_playback_busy() and not onlinecoop_events_busy() and not (n.await_revision and n.revision<=n.await_revision)
    local hover_piece
    for _,p in ipairs(s.units) do
        if net_inside(mx,my,left+p[2]*16,30+p[3]*16,16,16) and p[1]~=s.knight then hover_piece=p end
    end
    if not onlinecoop_has_board_frame(s) then
    local moat={}
    for _,p in ipairs(s.terrain) do
        if p[3]==2 then moat[p[2]*8+p[1]]=true end
    end
    spritesheet("gfx"); sprgrid(16,16)
    clip(left,30,128,131)
    for y=0,7 do for x=0,7 do
        local progress=onlinecoop_board_tile_progress(x,y)
        if progress>0 then
            local xx,yy=left+x*16,30+y*16+(1-progress)*(1-progress)*40
            -- Native checker tiles include a 3-pixel front face below row 7.
            -- Native Moat replaces the tile with gfx 28/29, preserving parity.
            spr((moat[y*8+x] and 28 or 30)+(x+y)%2,xx,yy,1,y==7 and 1.1875 or 1)
        end
    end end
    clip()
    if onlinecoop_board_ready() then
    for _,p in ipairs(s.terrain) do
        local x,y=left+p[1]*16,30+p[2]*16
        if p[3]==1 then
            -- Same geometry/palette as the authoritative Co-op barricade.
            line(x+2,y+12,x+8,y+4,1); line(x+8,y+4,x+13,y+12,1)
            line(x+2,y+12,x+13,y+12,1)
            line(x+4,y+11,x+8,y+5,7); line(x+8,y+5,x+11,y+11,7)
            rectfill(x+5,y+10,x+10,y+11,3)
        elseif p[3]==3 then
            -- Native square renderer uses gfx tile 14 for Evil Summoning.
            spritesheet("gfx"); sprgrid(16,16); spr(14,x,y)
        end
    end
    end
    if can_input then for _,p in ipairs(s.moves) do
        local x,y=left+p[1]*16,30+p[2]*16
        net_corners(x,y,5,net_inside(mx,my,x,y,16,16) and 5 or 3)
    end end
    if s.ui[13]>0 and s.ui[14]>0 then net_corners(left+(s.ui[13]-1)*16,30+(s.ui[14]-1)*16,5,2) end
    clip(left,26,128,132)
    for _,p in ipairs(s.units) do
        -- dr_piece restores its own clip, so reapply for every board actor.
        clip(left,26,128,132)
        local px,py,lift=onlinecoop_visual_position(p)
        local spawn_lift,visible=onlinecoop_spawn_visual(p)
        lift=lift+spawn_lift
        local x,y=left+px*16,30+py*16-lift
        local flash,dead=net_hit_effect(p[1])
        if lift>0 then line(left+px*16+5,30+py*16+15,left+px*16+10,30+py*16+15,2) end
        if flash then x=x+sin(time()*18) end
        if p[7]==1 and p[5]==1 then x=x+sin(time()*5)*.6 end
        local gun_angle=n.shot_track and onlinecoop_effect_progress(n.shot_track)<1 and n.shot_angle or n.king_aim or -.125
        if not dead and visible and not (n.boss_visual and n.boss_visual.floor==s.floor and n.boss_visual.id==p[1]) then
        if p[1]==s.knight then net_weapon(p,x,y,s,mx,my) end
        if p[1]==s.king and sin(gun_angle)<0 then net_king_gun(x,y,s) end
        onlinecoop_draw_net_piece(p,x,y,s,flash)
        if p[1]==s.king and sin(gun_angle)>=0 then clip(left,26,128,132); net_king_gun(x,y,s) end
        end
        if net_inside(mx,my,left+p[2]*16,30+p[3]*16,16,16) and p[1]~=s.knight then hover_piece=p end
    end
    onlinecoop_draw_boss(s,left)
    net_draw_events(s,left)
    clip()
    end -- fallback scene; native pixels own the entire board and overhang
    local boss_present=n.boss_visual and n.boss_visual.floor==s.floor
    lprint((lang.floor_ or net_label("楼层","Floor")).." "..s.floor,boss_present and left+111 or MCW/2,13,3,1)
    lprint(net_label("回合 ","Turn ")..s.turn,MCW/2,164,3,1)
    local ui=s.ui
    if not hover_piece then
    lprint(net_label("火力","Power"),left-23,56,2,1); lprint(ui[4]-1000,left-23,65,3,1)
    lprint(net_label("射程","Range"),left-23,81,2,1); lprint((ui[6]-1000).."-"..(ui[6]-998),left-23,90,3,1)
    lprint(net_label("散射","Spread"),left-23,106,2,1); lprint(ui[5],left-23,115,3,1)
    lprint(net_label("骑士刀锋","Knight blade"),left-23,131,2,1); lprint(ui[8],left-23,140,3,1)
    end
    for i=1,min(12,ui[2]) do
        rectfill(left+(i-1)*4,18,left+(i-1)*4+2,25,i<=ui[1] and 5 or 2)
        if i<=ui[1] then rectfill(left+(i-1)*4,18,left+(i-1)*4+2,20,4) end
    end
    local reload=n.reload_track and onlinecoop_effect_progress(n.reload_track) or 1
    if reload<1 then
        local lift=sin(reload/2)*3
        local shell=left+max(0,min(11,ui[1]-1))*4
        rectfill(shell,18-lift,shell+2,25-lift,5)
        rectfill(shell,18-lift,shell+2,20-lift,4)
    end
    lprint(net_label("备弹 ","Ammo ")..ui[3],boss_present and left+100 or left+54,21,3)
    local gun=weapons and weapons[ui[17]+1]
    if gun then lprint(lang[gun.name] or gun.name,left,10,4) end
    spritesheet("weapons"); sspr(96,ui[17]*16,24,8,left+14,18); spritesheet("gfx")
    if hover_piece then
        rectfill(left-39,47,left-3,149,1)
        lprint(lang["piece_"..hover_piece[4]] or net_label("棋子","Piece"),left-21,51,4,1)
        onlinecoop_draw_net_piece(hover_piece,left-29,65,s)
        lprint(net_label("血量 ","HP ")..hover_piece[6].."/"..hover_piece[9],left-21,88,5,1)
        lprint(net_label("等待 ","Wait ")..hover_piece[8],left-21,103,3,1)
        if hover_piece[7]==1 then lprint(net_label("准备行动","Ready"),left-21,117,5,1) end
    end
    local hover_soul
    for _,slot in ipairs(s.souls) do
        local x,y=onlinecoop_net_slot_position(slot[1],#s.souls)
        if x then
            local selected=ui[11]==slot[1]
            coop_draw_empty_soul_slot(nil,x,y)
            if slot[2]>0 and not selected then
                spritesheet("gfx"); sprgrid(8,8)
                -- Original soul-card background at (0,72); its glyph is overlaid below.
                sspr(0,72,24,32,x,y)
                rectfill(x+4,y+7,x+17,y+22,3)
                spritesheet("gfx"); sprgrid(16,16); pal({[4]=1,[1]=4})
                spr(432+slot[2],x+3,y+7); pal()
            end
            if net_inside(mx,my,x,y,24,30) then hover_soul=slot end
        end
    end
    if #s.souls>5 then lprint("V "..((n.soul_page or 0)+1),left+137,172,3) end
    if ui[10]>0 then
        local x,y=left-17,161
        rect(x,y,x+13,y+13,ui[10]==1 and 5 or 2)
        for i=0,5 do rectfill(x+3+i%3*3,y+4+(i-i%3)/3*4,x+4+i%3*3,y+5+(i-i%3)/3*4,ui[10]==1 and 4 or 3) end
    end
    local fx=n.soul_fx
    if fx and time()-fx.started<.3 then
        local x,y=onlinecoop_net_slot_position(fx.index,#s.souls)
        if x then local d=(time()-fx.started)*35; pset(x+11-d,y+14-d,5); pset(x+11+d,y+14+d,3) end
    end
    -- The native frame already contains Knight move/charge corners. Drawing
    -- net_corners over them would duplicate their differing pixel geometry.
    -- The earlier local corners remain the fallback when no frame is ready.
    onlinecoop_draw_board_frame(s,left)
    if n.remote_choices then onlinecoop_choices_draw();return end
    if can_input then for _,p in ipairs(s.attacks) do
        local x,y=left+p[1]*16,30+p[2]*16
        if net_inside(mx,my,x,y,16,16) then
            local spear=false
            for _,u in ipairs(s.units) do if u[1]==s.knight then
                spear=s.ui[15]==1 and (abs(u[2]-p[1])==2 or abs(u[3]-p[2])==2)
            end end
            if spear then coop_draw_knight_spear_icon(x,y) else coop_draw_knight_blade_icon(x,y) end
        end
    end end
    local hint=net_label("Tab 跳过  /  右键取消灵魂","Tab: skip  /  Right click: cancel soul")
    if onlinecoop_playback_busy() then hint=onlinecoop_playback_hint()
    elseif n.pending then hint=net_label("等待房主确认……","Waiting for host confirmation...")
    elseif phase==2 and onlinecoop_events_busy() then hint=net_label("等待动作播放完毕……","Finishing animations...")
    elseif n.last_result and n.last_result~="ok" and n.last_result~="duplicate" and time()-(n.result_at or 0)<2 then
        hint=net_label("状态已变化，请按新提示操作","State changed; choose from the new targets")
    elseif hover_soul then
        local names={[0]=net_label("空灵魂槽","Empty soul slot"),[1]=net_label("骑士灵魂","Knight soul"),[2]=net_label("主教灵魂","Bishop soul"),[3]=net_label("城堡灵魂","Rook soul")}
        hint=names[hover_soul[2]] or net_label("灵魂","Soul")
        if ui[12]==1 and hover_soul[2]==1 then hint=hint..net_label("：点击复活黑骑士"," : revive Knight")
        elseif hover_soul[3]==1 and phase==2 then hint=hint..net_label("：选择后点击目标格"," : select, then choose target") end
    elseif hovered_card then hint=lang[hovered_card.id] or hovered_card.id
    elseif hover_piece then
        hint=(lang["piece_"..hover_piece[4]] or net_label("棋子","Piece"))..net_label("  血量 ","  HP ")..hover_piece[6].."/"..hover_piece[9].."  "..net_label("等待 ","Wait ")..hover_piece[8]
    elseif ui[11]>0 then hint=net_label("点击目标格确认，右键取消","Click a target to confirm; right click cancels") end
    lprint(onlinecoop_signals_hint() or hint,MCW/2,174,4,1)
    n.card_tooltip_pending=hovered_card
    if phase==6 or phase==7 then
        rectfill(left,82,left+127,104,1); rect(left,82,left+127,104,3)
        lprint(net_label(zh[phase],en[phase]),MCW/2,90,4,1)
    end
end
