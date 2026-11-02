-- Campaign menus are input waits, never combat animation clips. Only bounded
-- presentation data crosses the wire; purchases and saves belong to the host.
local function label(zh,en) return current_lang=="simplified_chinese" and zh or en end
local function set_scene(kind,decay)
    local n=mode.net
    n.campaign_serial=(n.campaign_serial or 0)+1
    n.campaign_scene={id=n.campaign_serial,kind=kind,floor=max(0,mode.lvl or 0),decay=decay or 0,started=time()}
end

if coop_variant=="charnier" then
    local menu,raid=charnier_menu,next_raid
    function charnier_menu()
        local n=mode.net
        if not n or n.role~="host" then return end
        onlinecoop_results_restart()
        set_scene(1)
        menu()
    end
    function next_raid()
        local n=mode.net
        if not n or n.role~="host" or not n.peer_ok or onlinecoop_lan.status~="connected"
            or onlinecoop_playback_busy() then return end
        set_scene(0)
        raid()
    end
end

function onlinecoop_campaign_initialize()
    local n=mode.net
    if n.role~="host" then return end
    append("decay_up",function()
        if mode.net~=n or mode.coop_variant~="endless" then return end
        local upgrade=upgrades and upgrades[#upgrades]
        -- 0 = Blood Bowl, 1..6 = native piece type + 1.
        local kind=upgrade and upgrade.gain and upgrade.gain[1]
        set_scene(2,kind and kind+1 or 0)
    end,"online_endless_reveal")
    prepend("new_level",function()
        if mode.net==n and n.campaign_scene and n.campaign_scene.kind~=0 then set_scene(0) end
    end,"online_campaign_new_level")
end

function onlinecoop_campaign_tick()
    local n=mode.net
    if n.role~="host" or not n.peer_ok or not n.campaign_scene then return end
    local c=n.campaign_scene
    local ch=c.kind==1 and SAVE.coop_charnier or nil
    local owned=ch and ch.augments or {}
    local packet="W1,"..c.id..","..c.kind..","..c.floor..","..(ch and ch.cinders or 0)
        ..","..(ch and #ch.burdens or 0)..","..c.decay..","..#owned
    for _,index in ipairs(owned) do packet=packet..","..index end
    if packet~=n.campaign_sent and onlinecoop_lan.send("data",packet) then n.campaign_sent=packet end
end

function onlinecoop_campaign_receive(payload)
    local n=mode.net
    if n.role~="client" or #payload>600 or sub(payload,1,3)~="W1," then return false end
    local count=0
    for i=4,#payload do if sub(payload,i,i)=="," then count=count+1 end end
    local a=onlinecoop_net_numbers(sub(payload,4),count+1,1000000)
    if not a or #a<7 or a[1]<1 or a[1]<(n.campaign_received or 0) or a[2]>2
        or a[6]>6 or a[7]>64 or #a~=7+a[7] then return false end
    if (a[2]==1 and mode.coop_variant~="charnier") or (a[2]==2 and mode.coop_variant~="endless") then return false end
    local owned={}
    for i=8,#a do
        if not AUGMENTS or not AUGMENTS[a[i]+1] then return false end
        add(owned,a[i])
    end
    local old=n.campaign_scene
    local started=old and old.id==a[1] and old.started or time()
    n.campaign_received=a[1]
    n.campaign_scene={id=a[1],kind=a[2],floor=a[3],cinders=a[4],rank=a[5],decay=a[6],owned=owned,started=started}
    if a[2]==0 and old and old.kind==1 then
        n.runner_best=nil;n.rhythm_best=nil;n.wait_game=nil
        n.board_native=nil;n.snapshot=nil;n.owned_deck=nil
        onlinecoop_events_clear(n)
    end
    return true
end

function onlinecoop_campaign_draw()
    local n=mode.net;local c=n.campaign_scene
    if not c or c.kind==0 or n.clip_client then return false end
    local x=MCW/2
    if c.kind==1 then
        lprint(label("剿灭 · 局外准备","Charnier · Between raids"),x,16,4,1)
        lprint(label("房主正在准备／选购烙印","Host preparing / choosing brands"),x,35,3,1)
        lprint(label("等级：","Rank: ")..c.rank,x-48,56,4)
        lprint(label("余烬：","Cinders: ")..c.cinders,x+12,56,4)
        lprint(label("已拥有的烙印","Owned brands"),x,78,3,1)
        local owned=c.owned or {}
        for i,index in ipairs(owned) do
            local px=x-70+((i-1)%10)*14
            local py=92+flr((i-1)/10)*14
            coop_raid_draw_brand(index,px,py)
        end
        spritesheet("gfx")
        lprint(label("房主开始下一次剿灭后自动进入","The next raid starts when the host is ready"),x,172,3,1)
    else
        lprint(label("无尽 · 增援","Endless · Reinforcements"),x,26,4,1)
        local age=time()-c.started
        local y=82+max(0,1-age)*12
        spritesheet("gfx")
        if c.decay==0 then sspr(176,80,16,16,x-8,y)
        else
            local tp=c.decay-1
            if tp==0 then sspr(0,432,16,16,x-14,y);sspr(0,432,16,16,x-2,y)
            else sspr(tp*16,432,16,16,x-8,y) end
        end
        local text=c.decay==0 and lang.blood_bowl
            or get_lang(c.decay==1 and "pawns_join" or "piece_join",get_piece_name(c.decay-1))
        pprint(text,x,110,110,3,1)
        lprint(label("等待房主点击继续","Waiting for host to continue"),x,165,4,1)
    end
    return true
end
