-- Native presentation: board during play, full canvas during hidden stories.
-- The host owns every animation and turn;
-- the guest receives palette pixels, never entities, scripts or callbacks.
local BW,BH,LEFT,TOP=128,161,0,-30
local function outside_board(x,y)
    return x+LEFT<0 or x+LEFT>=128 or y+TOP<0 or y+TOP>=131
end
local HEX="0123456789abcdef"
local function hx(v) return sub(HEX,flr(v/16)+1,flr(v/16)+1)..sub(HEX,v%16+1,v%16+1) end
local function concat(a) local s=""; for _,v in ipairs(a) do s=s..v end; return s end
local digits={}
for i=1,16 do digits[sub(HEX,i,i)]=i-1 end
local function unhex(s,i)
    local a,b=digits[sub(s,i,i)],digits[sub(s,i+1,i+1)]
    if a and b then return a*16+b end
end
local function wordhex(v) return hx(flr(v/256))..hx(v%256) end
local function unword(s,i)
    local a,b=unhex(s,i),unhex(s,i+2)
    if a and b then return a*256+b end
end
local function text_hex(s)
    local out="";for i=1,#s do out=out..hx(ord(s,i)) end;return out
end
local function read_text_hex(s,start,bytes,font_name)
    if bytes<1 or bytes>(font_name and 32 or 192) then return nil end
    local values={}
    for i=0,bytes-1 do
        local v=unhex(s,start+i*2)
        if not v or (v<32 and v~=10) or v==127 then return nil end
        values[#values+1]=v
    end
    -- Reject malformed UTF-8, overlong forms, surrogates and >U+10FFFF.
    local i=1
    while i<=bytes do
        local v=values[i];local n=0
        if v>=194 and v<=223 then n=1
        elseif v>=224 and v<=239 then n=2
        elseif v>=240 and v<=244 then n=3
        elseif v>=128 then return nil end
        if i+n>bytes then return nil end
        for k=1,n do if values[i+k]<128 or values[i+k]>191 then return nil end end
        if (v==224 and values[i+1]<160) or (v==237 and values[i+1]>159)
            or (v==240 and values[i+1]<144) or (v==244 and values[i+1]>143) then return nil end
        i=i+n+1
    end
    local out="";for _,v in ipairs(values) do out=out..chr(v) end
    if font_name and not match(out,"^[A-Za-z0-9_%- ]+$") then return nil end
    return out
end
local function encode_scene_text(commands,layers)
    if not commands or #commands==0 then return "" end
    local body=""
    for _,c in ipairs(commands) do
        local color=layers and layers.palette and layers.palette[c.color] or c.color
        local item=wordhex(#c.text)..wordhex(c.x)..wordhex(c.y)..hx(color)..hx(c.ax)..hx(c.ay)..hx(#c.font)
            ..text_hex(c.text)..text_hex(c.font)
        if #item%4~=0 then item=item.."00" end
        body=body..item
    end
    return "00005458"..wordhex(#body)..wordhex(#commands)..body
end
local function decode_scene_text(data,start)
    if sub(data,start,start+7)~="00005458" then return nil end
    local size,count=unword(data,start+8),unword(data,start+12)
    if not size or size>16384 or size%4~=0 or not count or count<1 or count>32
        or start+16+size-1~=#data then return nil end
    local result={};local i=start+16
    for k=1,count do
        local length,x,y=unword(data,i),unword(data,i+4),unword(data,i+8)
        local color,ax,ay,flen=unhex(data,i+12),unhex(data,i+14),unhex(data,i+16),unhex(data,i+18)
        if not length or not x or not y or not color or not ax or not ay or not flen or ax>2 or ay>2 then return nil end
        local text=read_text_hex(data,i+20,length,false)
        local fname=read_text_hex(data,i+20+length*2,flen,true)
        if not text or not fname then return nil end
        local length_hex=20+(length+flen)*2
        if length_hex%4~=0 then
            if sub(data,i+length_hex,i+length_hex+1)~="00" then return nil end
            length_hex=length_hex+2
        end
        i=i+length_hex
        result[#result+1]={text=text,x=(x-32768)/16,y=(y-32768)/16,color=color,ax=ax,ay=ay,font=fname}
    end
    if i~=#data+1 then return nil end
    return result
end
local function canvas_size(w,h)
    return type(w)=="number" and type(h)=="number" and w%1==0 and h%1==0
        and w>=64 and w<=1024 and h>=64 and h<=512 and w*h<=262144
end
-- These stories move actors and light from side cards beyond the board.
-- Ordinary play (including Rebel Knight combat) keeps the narrow board stream.
function onlinecoop_scene_capture_active()
    if not mode or mode.coop_stats_screen or (mode.net and (mode.net.cg_active or mode.net.cg_returned)) then return false end
    local book=mode.coop_book_scene
    if book and book.choosing and not book.chosen then return false end
    return mode.coop_hidden_boss_pending~=nil or mode.coop_throne_finishing==true
        or book~=nil or (mode.coop_new_job_scene and not mode.coop_new_job_scene.finished) or false
end
local function scene_capture_layers(width,height)
    local layers={}
    -- fd is applied by native _draw *after* draw_game and pget does not see
    -- screen-palette swaps. Bake this small palette into cinematic frames.
    -- Do not change the host's target, drawing palette or screen palette.
    if type(spritesheet)~="function" or type(sget)~="function" then return layers end
    local previous=spritesheet()
    if type(previous)~="string" then return layers end
    layers.previous=previous
    if type(fd)=="number" and fd~=0 then
        spritesheet("gfx")
        if fd==6 and fast then layers.border=sget(17,10)
        else
            local row=min(11,max(1,4+fd));layers.palette={}
            for i=0,9 do layers.palette[i]=sget(16+i,row) end
        end
    end
    layers.palette=layers.palette or {}
    if type(FORCE_DARK)=="number" then layers.palette[FORCE_DARK]=2 end
    if type(FORCE_MEDIUM)=="number" then layers.palette[FORCE_MEDIUM]=3 end
    if type(FORCE_BRIGHT)=="number" then layers.palette[FORCE_BRIGHT]=4 end
    spritesheet(previous)
    return layers
end
local function scene_pixel(layers,x,y,width,height,color)
    if layers.border and (x<4 or y<4 or x>=width-4 or y>=height-4) then color=layers.border end
    return layers.palette and layers.palette[color] or color
end
local function restore_scene_layers(layers)
    if layers and layers.previous then spritesheet(layers.previous) end
end
local function capture_oversize(n,scene,width,height,size)
    local identity=type(onlinecoop_net_board_identity)=="function" and onlinecoop_net_board_identity() or (n.board_serial or 0)
    local key=n.clip_host and ("clip:"..n.clip_host.id) or ("board:"..identity)
    n.board_oversize=(n.board_oversize or 0)+1
    if n.board_oversize_key~=key then
        n.board_oversize_key=key
        _log("[BOARD CAPTURE OVERSIZE] "..key.." floor="..mode.lvl.." turn="..(mode.turns or 0)
            .." scene="..tostr(scene==true).." canvas="..width.."x"..height.." bytes>="..size.." limit=60000")
    end
end
function onlinecoop_decode_board_pixels(pixels,keep)
    if #pixels<4 or #pixels>60000 or #pixels%4~=0 then return false end
    local width,height,start,scene=BW,BH,1,false
    if sub(pixels,1,4)=="0000" then
        if #pixels<16 then return false end
        local a,b,c,d=unhex(pixels,5),unhex(pixels,7),unhex(pixels,9),unhex(pixels,11)
        if not a or not b or not c or not d then return false end
        width,height=a*256+b,c*256+d
        if not canvas_size(width,height) then return false end
        start,scene=13,true
    end
    local runs=keep and {} or nil; local x,y=0,0;local i=start
    while i<=#pixels and y<height do
        local count,color=unhex(pixels,i),unhex(pixels,i+2)
        if not count or not color or count<1 or count>width-x or y>=height then return false end
        if keep then runs[#runs+1]={x,y,count,color} end
        x=x+count
        if x==width then x=0; y=y+1 end
        i=i+4
    end
    if y~=height or x~=0 then return false end
    local texts
    if i<=#pixels then
        if not scene then return false end
        texts=decode_scene_text(pixels,i)
        if not texts then return false end
    end
    if keep then runs.scene=scene;runs.width=width;runs.height=height;runs.texts=texts end
    return keep and runs or true
end

-- A local mailbox being empty does not mean the remote game has caught up.
-- Limit live frames in flight using receipt acknowledgements, independently
-- of the intentional client playback buffer. Complete clips keep every frame.
local function frame_window(n)
    return min(48,max(6,flr((n.board_effective_fps or n.board_fps or 30)
        *((n.board_min_rtt or .12)+.12))+1))
end
function onlinecoop_board_can_capture()
    local n=mode and mode.net
    return n and (n.clip_host or not n.board_flights or #n.board_flights<frame_window(n)) or false
end
function onlinecoop_board_ack_receive(payload)
    local n=mode.net
    local a=onlinecoop_net_numbers(sub(payload,4),1,10000000)
    if n.role~="host" or not a or a[1]<1 or a[1]<=(n.board_acked or 0)
        or a[1]>(n.board_last_sent or 0) then return false end
    local rest={};local sampled=false
    for _,f in ipairs(n.board_flights or {}) do
        if f.id>a[1] then rest[#rest+1]=f
        elseif f.id==a[1] then
            local rtt=max(.001,time()-f.sent)
            n.board_min_rtt=min(n.board_min_rtt or rtt,rtt)
            n.board_rtt_window_min=min(n.board_rtt_window_min or rtt,rtt)
            n.board_rtt_window_at=n.board_rtt_window_at or time()
            if time()-n.board_rtt_window_at>=15 then
                -- A lasting route change is latency, not perpetual congestion.
                n.board_min_rtt=n.board_rtt_window_min
                n.board_rtt_window_min=rtt;n.board_rtt_window_at=time()
            end
            n.board_rtt=(n.board_rtt or rtt)*.75+rtt*.25
            sampled=true
        end
    end
    if not sampled then return false end
    n.board_flights=rest;n.board_acked=a[1];n.board_ack_at=time()
    return true
end
local function tune_live_rate(n)
    local cap=n.board_fps or 30
    n.board_effective_fps=min(cap,n.board_effective_fps or cap)
    if time()<(n.board_tune_at or 0) then return end
    n.board_tune_at=time()+1
    local queued=n.board_rtt and n.board_min_rtt and n.board_rtt-n.board_min_rtt or 0
    if n.board_congested or queued>.18 then
        n.board_effective_fps=max(6,flr(n.board_effective_fps*.75))
        n.board_recover_at=time()+3
    elseif time()>=(n.board_recover_at or 0) then
        n.board_effective_fps=min(cap,n.board_effective_fps+2)
    end
    n.board_congested=nil
end

-- Short, bounded live jitter buffer. Its clock follows source frame times,
-- not TCP packet arrival bursts. First images/new turns remain immediate.
local function show_live(n,f)
    n.board_native={floor=f.floor,turn=f.turn,board=f.board,
        runs=onlinecoop_decode_board_pixels(f.data,true),received=time()}
end
local function queue_live(n,f)
    if n.clip_client then return end
    local q=n.board_live
    if not f.ms or not q or q.floor~=f.floor or q.turn~=f.turn or q.board~=f.board
        or f.ms<q.last_ms or time()-q.arrival>1 then
        n.board_live={floor=f.floor,turn=f.turn,board=f.board,frames={},head=1,tail=0,
            offset=time()-((f.ms or 0)/1000),last_ms=f.ms or 0,arrival=time(),jitter=0,played=f.ms or 0,
            phase=n.snapshot and n.snapshot.phase}
        show_live(n,f);return
    end
    local variation=abs((time()-q.arrival)-(f.ms-q.last_ms)/1000)
    q.jitter=min(.065,q.jitter*.85+variation*.15)
    q.offset=min(q.offset,time()-f.ms/1000)
    q.arrival=time();q.last_ms=f.ms
    q.tail=q.tail+1;q.frames[q.tail]=f
    -- A catch-up stream may drop old images; it never queues seconds of them.
    if q.tail-q.head>=12 then q.frames[q.head]=nil;q.head=q.head+1 end
end
function onlinecoop_board_live_tick()
    local n=mode.net;local q=n.board_live
    if n.role~="client" or not q then return end
    if n.clip_client or n.cg_active or n.cg_returned then n.board_live=nil;return end
    local s=n.snapshot
    if s and q.board and s.board and s.board>q.board then n.board_live=nil;return end
    local due=max(q.played,(time()-q.offset-min(.18,.05+2*q.jitter))*1000)
    -- Legal moves refer to the latest authoritative state. Do not retain an
    -- extra jitter delay when the host has just handed control to a player.
    if s and (s.phase==1 or s.phase==2) then due=q.last_ms end
    q.phase=s and s.phase
    local latest
    while q.head<=q.tail do
        local f=q.frames[q.head]
        if f.ms>due then break end
        latest=f;q.frames[q.head]=nil;q.head=q.head+1
    end
    if latest then q.played=latest.ms;show_live(n,latest) end
    if q.head>q.tail then q.frames={};q.head=1;q.tail=0 end
end

-- Shared session setting; either player may request a supported limit.
local BOARD_RATES={10,15,20,30,45,60}
local function valid_rate(v)
    for _,rate in ipairs(BOARD_RATES) do if v==rate then return true end end
    return false
end
function onlinecoop_board_rate_receive(payload)
    local n=mode.net
    local v=onlinecoop_net_numbers(sub(payload,4),1,60)
    if not v or not valid_rate(v[1]) then return false end
    if n.role=="host" and sub(payload,1,3)=="L1," then
        n.board_fps=v[1]; n.board_capture_at=nil; n.board_rate_sent=nil; return true
    elseif n.role=="client" and sub(payload,1,3)=="L2," then
        n.board_fps=v[1]; n.board_rate_pending=nil; return true
    end
    return false
end
function onlinecoop_board_rate_input()
    local n=mode.net
    if n.cg_active or n.cg_returned or not n.peer_ok or (n.draft and n.draft.active)
        or not is_coop_active() and not n.snapshot then return false end
    if not btnp("online_fps",0) then return false end
    n.board_rate_show_until=time()+3
    if time()>=(n.board_rate_input_at or 0) then
        n.board_rate_input_at=time()+.2
        local next_rate=10
        for i,rate in ipairs(BOARD_RATES) do
            if rate==(n.board_rate_pending or n.board_fps or 30) then next_rate=BOARD_RATES[i%#BOARD_RATES+1] end
        end
        if n.role=="host" then
            n.board_fps=next_rate; n.board_capture_at=nil; n.board_rate_sent=nil
        elseif n.role=="client" and onlinecoop_lan.send("data","L1,"..next_rate) then
            n.board_rate_pending=next_rate
        end
    end
    return false
end
function onlinecoop_draw_board_rate()
    local n=mode and mode.net
    if not n or n.cg_active or n.cg_returned or not n.peer_ok or (n.draft and n.draft.active)
        or not is_coop_active() and not n.snapshot then return end
    if time()>=(n.board_rate_show_until or 0) then return end
    local label=(current_lang=="simplified_chinese" and "同步 " or "Sync ")
        ..(n.board_fps or 30).." FPS [F6]"..(n.board_rate_pending and "..." or "")
    if n.role=="host" and n.playback_mode~=1 and n.board_effective_fps
        and n.board_effective_fps<(n.board_fps or 30) then
        label=label.." / "..n.board_effective_fps.." "..(current_lang=="simplified_chinese" and "自适应" or "adaptive")
    end
    lprint(label,MCW-90,3,3)
end

function onlinecoop_board_frame_initialize()
    local n=mode.net
    if n.role~="host" then return end
    local function capture_due()
        if not mode or mode.net~=n then return false end
        if not onlinecoop_board_can_capture() then n.board_congested=true;return false end
        return mode.net==n and n.peer_ok and not n.cg_active and onlinecoop_presentation_active()
            and (not mode.coop_floor_transition or onlinecoop_scene_capture_active()) and time()+.00001>=(n.board_capture_at or 0)
            and not (n.clip_host and n.clip_host.closed)
            and (n.clip_host or not onlinecoop_lan.can_send_visual or onlinecoop_lan.can_send_visual())
    end
    prepend("draw_game",function()
        n.board_background=nil
        -- Decide once: a deadline crossed during drawing must not capture a
        -- frame whose earlier background pass was skipped.
        n.board_capture_due=capture_due()
        n.board_capture_scene=onlinecoop_scene_capture_active() and canvas_size(MCW,MCH)
        n.scene_text={};n.scene_camera_x=0;n.scene_camera_y=0
        n.scene_recording=n.board_capture_due and n.board_capture_scene
            and type(winspec)=="function" and winspec("overlay")=="hdtext"
        -- Only the final big Boss needs the extended headroom. Ordinary
        -- floors retain the original four-pixel overhang; never sample sides.
        n.board_capture_first_row=(type(boss)=="table" and boss.big) and 0 or 26
    end,"online_board_background_reset")
    -- Observe native text without changing arguments, returns, font or target.
    -- Only the HD layer needs replay; ordinary low-resolution text is already
    -- in pget. Native calls observed in 1.623b use exactly these six arguments.
    prepend("camera",function(x,y)
        if n.scene_recording then n.scene_camera_x=x or 0;n.scene_camera_y=y or 0 end
    end,"online_scene_text_camera")
    prepend("tcamera",function(x,y)
        if n.scene_recording then n.scene_camera_x=n.scene_camera_x+(x or 0);n.scene_camera_y=n.scene_camera_y+(y or 0) end
    end,"online_scene_text_tcamera")
    prepend("lprint",function(text,x,y,color,ax,ay,...)
        if not n.scene_recording or mode.net~=n or #n.scene_text>=32 or #{...}>0 then return end
        if type(text)=="number" then text=tostr(text) end
        if type(text)~="string" or #text<1 or #text>192 or type(x)~="number" or type(y)~="number"
            or x~=x or y~=y or type(color)~="number" or color%1~=0 or color<0 or color>255 then return end
        ax,ay=ax or 0,ay or 0
        if type(ax)~="number" or type(ay)~="number" or ax%1~=0 or ay%1~=0 or ax<0 or ax>2 or ay<0 or ay>2 then return end
        x,y=x-n.scene_camera_x,y-n.scene_camera_y
        if abs(x)>2047 or abs(y)>2047 then return end
        local fname=type(fntspec)=="function" and fntspec("name") or "default"
        if type(fname)~="string" or #fname<1 or #fname>32 or not match(fname,"^[A-Za-z0-9_%- ]+$") then fname="default" end
        if not read_text_hex(text_hex(text),1,#text,false) then return end
        n.scene_text[#n.scene_text+1]={text=text,x=flr(x*16+.5)+32768,y=flr(y*16+.5)+32768,
            color=color,ax=ax,ay=ay,font=fname}
    end,"online_scene_text_observe")
    prepend("dre",function(entity)
        if entity~=board or not n.board_capture_due or n.board_capture_scene then return end
        -- DP_BG already drew HUD/cards; DP_SHADES (board) precedes pieces.
        -- Compare only the overhang against this baseline so the native HUD
        -- is not copied into the guest's independently laid-out side panels.
        local bx,by=coop_get_board_geometry()
        bx,by=flr(bx)+LEFT,flr(by)+TOP
        local background={}
        for y=n.board_capture_first_row,29 do for x=0,BW-1 do
            if outside_board(x,y) then background[y*BW+x+1]=pget(bx+x,by+y) end
        end end
        n.board_background=background
    end,"online_board_background")
    append("draw_game",function()
        n.scene_recording=false
        if not n.board_capture_due then return end
        if not n.clip_host and n.board_tx then
            if time()-n.board_tx.created<.15 then return end
            n.board_tx=nil; n.board_dropped=(n.board_dropped or 0)+1
        end
        local interval=1/(n.clip_host and (n.board_fps or 30) or (n.board_effective_fps or n.board_fps or 30))
        n.board_capture_at=(n.board_capture_at or time())+interval
        if n.board_capture_at<time()-interval then n.board_capture_at=time()+interval end
        n.board_captured=(n.board_captured or 0)+1
        local bx,by=coop_get_board_geometry()
        bx,by=flr(bx)+LEFT,flr(by)+TOP
        local scene=n.board_capture_scene
        local width,height=BW,BH
        if scene then bx,by=0,0;width,height=MCW,MCH end
        local layers=scene and scene_capture_layers(width,height)
        local background=n.board_background
        local rows={}; local size=0
        if scene then rows[1]="0000"..wordhex(width)..wordhex(height);size=12 end
        for y=0,height-1 do
            if not scene and y<n.board_capture_first_row then
                -- Fixed wire envelope, but no pixel reads/loops for unused
                -- headroom. Each transparent row compresses to one run.
                rows[#rows+1]="80ff"; size=size+4
            else
            local row=""; local color,count=nil,0
            for x=0,width-1 do
                local v=pget(bx+x,by+y)
                if layers then v=scene_pixel(layers,x,y,width,height,v) end
                if not scene and outside_board(x,y) and (not background or background[y*BW+x+1]==v) then v=255 end
                if type(v)~="number" or v<0 or v>255 or v%1~=0 then restore_scene_layers(layers);return end
                if (v~=color or count==255) and count>0 then row=row..hx(count)..hx(color); count=0 end
                color=v; count=count+1
            end
            row=row..hx(count)..hx(color); size=size+#row
            -- Bound work/traffic even with a corrupt or unusually noisy surface.
            if size>60000 then
                restore_scene_layers(layers)
                capture_oversize(n,scene,width,height,size)
                return
            end
            rows[#rows+1]=row
            end
        end
        restore_scene_layers(layers)
        local text_data=scene and encode_scene_text(n.scene_text,layers) or ""
        if size+#text_data>60000 then capture_oversize(n,scene,width,height,size+#text_data);return end
        rows[#rows+1]=text_data
        local data=concat(rows)
        if n.clip_host and onlinecoop_playback_capture(data,mode.lvl,mode.turns or 0) then return end
        local serial=type(onlinecoop_net_board_identity)=="function" and onlinecoop_net_board_identity() or (n.board_serial or 0)
        if data==n.board_last_pixels and n.board_last_floor==mode.lvl
            and n.board_last_turn==(mode.turns or 0) and n.board_last_board==serial then return end
        n.board_frame_serial=(n.board_frame_serial or 0)+1
        n.board_clock_start=n.board_clock_start or time()
        local parts=flr((#data+11999)/12000)
        n.board_tx={serial=n.board_frame_serial,floor=mode.lvl,turn=mode.turns or 0,data=data,parts=parts,next=1,
            created=time(),ms=flr((time()-n.board_clock_start)*1000),board=serial}
    end,"online_native_board_pixels")
end

function onlinecoop_board_frame_tick()
    local n=mode.net; local f=n.board_tx
    if n.role=="client" then
        onlinecoop_board_live_tick()
        if n.board_rx_serial and n.board_rx_serial~=(n.board_ack_sent or 0) and time()>=(n.board_ack_due or 0) then
            if onlinecoop_lan.send("data","F3,"..n.board_rx_serial) then
                n.board_ack_sent=n.board_rx_serial;n.board_ack_due=time()+.05
            end
        end
    else tune_live_rate(n) end
    if n.role=="host" and n.peer_ok and n.board_rate_sent~=(n.board_fps or 30) then
        if onlinecoop_lan.send("data","L2,"..(n.board_fps or 30)) then n.board_rate_sent=n.board_fps or 30 end
    end
    if not n.board_perf_at then n.board_perf_at=time() end
    local elapsed=time()-n.board_perf_at
    if elapsed>=5 then
        _log("[BOARD PERF] role="..n.role.." seconds="..elapsed.." captured="..(n.board_captured or 0)
            .." sent="..(n.board_sent or 0).." received="..(n.board_received or 0)
            .." bytes="..(n.board_bytes or 0).." dropped="..(n.board_dropped or 0)
            .." backpressure="..(n.board_blocked or 0).." effective_fps="..(n.board_effective_fps or n.board_fps or 30)
            .." rtt_ms="..flr((n.board_rtt or 0)*1000).." inflight="..#(n.board_flights or {}))
        n.board_perf_at=time(); n.board_captured=0; n.board_sent=0; n.board_received=0
        n.board_bytes=0; n.board_dropped=0; n.board_blocked=0
    end
    if n.role~="host" or not f or not n.peer_ok then return end
    if f.floor~=mode.lvl or n.cg_active or (mode.coop_floor_transition and not onlinecoop_scene_capture_active()) then n.board_tx=nil; return end
    -- At most two chunks per tick, no unbounded animation queue.
    for i=1,2 do
        local part=f.next
        local msg="F1,"..f.serial..","..f.floor..","..f.turn..","..part..","..f.parts..","..f.ms..","..f.board..":"..sub(f.data,(part-1)*12000+1,part*12000)
        if not onlinecoop_lan.send("data",msg) then n.board_congested=true;n.board_blocked=(n.board_blocked or 0)+1; return end
        n.board_bytes=(n.board_bytes or 0)+#msg
        f.next=part+1
        if f.next>f.parts then
            n.board_last_pixels=f.data;n.board_last_floor=f.floor
            n.board_last_turn=f.turn;n.board_last_board=f.board
            n.board_flights=n.board_flights or {};n.board_last_sent=f.serial
            n.board_flights[#n.board_flights+1]={id=f.serial,sent=f.created}
            n.board_sent=(n.board_sent or 0)+1;n.board_tx=nil;return
        end
    end
end

function onlinecoop_board_frame_receive(payload)
    local n=mode.net
    if n.role~="client" or #payload>12100 then return false end
    local split=match(payload,"^F1,([%d,]+):")
    if not split then return false end
    local h=onlinecoop_net_numbers(split,7,2000000000) or onlinecoop_net_numbers(split,5,10000000)
    if not h or h[1]<1 or h[1]>10000000 or h[2]>10000 or h[3]>10000000
        or h[4]<1 or h[5]<1 or h[5]>5 or h[4]>h[5] or (h[7] and h[7]>10000000) then return false end
    if n.board_rx_serial and h[1]<=n.board_rx_serial then return false end
    local data=sub(payload,#split+5)
    if #data==0 or #data>12000 or #data%4~=0 or not match(data,"^[0-9a-f]+$") then return false end
    local f=n.board_rx
    if not f or f.serial~=h[1] then
        if h[4]~=1 or (f and h[1]<f.serial) then return false end
        f={serial=h[1],floor=h[2],turn=h[3],parts=h[5],ms=h[6],board=h[7],next=1,chunks={}}; n.board_rx=f
    end
    if f.floor~=h[2] or f.turn~=h[3] or f.parts~=h[5] or f.next~=h[4] or f.ms~=h[6] or f.board~=h[7] then return false end
    f.chunks[#f.chunks+1]=data; f.next=f.next+1
    if h[4]<h[5] then return true end
    f.data=concat(f.chunks);f.chunks=nil
    if not onlinecoop_decode_board_pixels(f.data,false) then n.board_rx=nil; return false end
    n.board_received=(n.board_received or 0)+1
    n.board_rx_serial=f.serial; n.board_rx=nil
    queue_live(n,f)
    return true
end

function onlinecoop_has_board_frame(s)
    local n=mode.net; local f=n.board_native
    return f and not n.cg_active and (n.clip_client
        or (f.floor==s.floor and f.turn==s.turn and (not f.board or not s.board or f.board==s.board))) or false
end
function onlinecoop_draw_board_frame(s,left)
    if not onlinecoop_has_board_frame(s) then return false end
    local f=mode.net.board_native
    if f.runs.scene then return onlinecoop_draw_scene_frame(s) end
    -- One native image owns both board and overhang. No separately timed
    -- Boss head/arms may be spliced onto a buffered native animation frame.
    pal(); clip(left+LEFT,30+TOP,BW,BH)
    for _,r in ipairs(f.runs) do
        if r[4]~=255 then
            rectfill(left+LEFT+r[1],30+TOP+r[2],left+LEFT+r[1]+r[3]-1,30+TOP+r[2],r[4])
        end
    end
    clip(); return true
end

function onlinecoop_draw_scene_frame(s)
    if not s or not onlinecoop_has_board_frame(s) then return false end
    local runs=mode.net.board_native.runs
    if not runs or not runs.scene then return false end
    -- Preserve aspect ratio across window sizes; integer run edges avoid gaps
    -- when the host and guest use different logical canvas dimensions.
    local scale=min(MCW/runs.width,MCH/runs.height)
    local left=flr((MCW-runs.width*scale)/2)
    local top=flr((MCH-runs.height*scale)/2)
    pal();clip(0,0,MCW,MCH)
    for _,r in ipairs(runs) do
        if r[4]~=255 then
            local x,y=left+flr(r[1]*scale),top+flr(r[2]*scale)
            local right,bottom=left+flr((r[1]+r[3])*scale)-1,top+flr((r[2]+1)*scale)-1
            if right>=x and bottom>=y then rectfill(x,y,right,bottom,r[4]) end
        end
    end
    clip()
    -- Keep the receiver's language/font configuration untouched. Same-font
    -- peers preserve native HD glyphs; other fonts use the receiver's own
    -- glyph coverage, with one diagnostic rather than loading remote fonts.
    local local_font=type(fntspec)=="function" and fntspec("name") or "default"
    for _,c in ipairs(runs.texts or {}) do
        if c.font~=local_font and not mode.net.scene_font_mismatch then
            mode.net.scene_font_mismatch=true
            _log("[SCENE TEXT FONT] source="..c.font.." local="..tostr(local_font).."; replay uses local glyphs")
        end
        lprint(c.text,left+c.x*scale,top+c.y*scale,c.color,c.ax,c.ay)
    end
    return true
end
