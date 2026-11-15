-- Native game UI; the hidden local broker accepts only fixed data commands.
local config=file("lan/lobby-config.txt")
local token=config and match(config,"^LB1|([a-f0-9]+)|END$")
local base=token and #token==32 and "lan/lobby/"..token.."/" or nil
local ui={open=false,poll=0,seq=0,port="27841",text="",external="",mapped=false,steam=false,addresses={},address=1,state="ready",message="",cursor=0,mx=-100,my=-100}
local function label(zh,en) return current_lang=="simplified_chinese" and zh or en end
local function split(s)
    local a={}; local start=1
    for i=1,#s+1 do if i>#s or sub(s,i,i)=="," then a[#a+1]=sub(s,start,i-1); start=i+1 end end
    return a
end
-- The mod sandbox exposes SUGAR's flat helpers (match/sub) but no `string`
-- table, and `find` does not report positions, so string.gmatch is unavailable
-- in mod callbacks. Anchor the pattern, take the whole match as the first
-- capture and continue after it; every pattern here matches at least one
-- character, so the scan always advances.
local function each_match(text, pattern)
    local rest = text or ""
    local anchored = "^(" .. pattern .. ")"
    return function()
        while #rest > 0 do
            local whole, a, b, c, d = match(rest, anchored)
            if whole then
                rest = sub(rest, #whole + 1)
                return a, b, c, d
            end
            rest = sub(rest, 2)
        end
    end
end
-- Five rooms per page. SUGAR exposes flr but no math table, and ceil is not
-- guaranteed for mods, so use floor arithmetic on a positive integer count.
local function room_pages(count) return flr((count + 4) / 5) end
-- Public endpoint is only advertised; never bind a listener to the tunnel server.
local saved=file("lan/public-endpoint.txt")
if saved and #saved<=259 and match(saved,"^[A-Za-z0-9.%-]+:%d+$") then ui.external=saved end
local function public_endpoint(text)
    text=match(text or "","^%s*(.-)%s*$") or ""
    text=match(text,"^tcp://(.+)$") or text
    local host,port=match(text,"^([A-Za-z0-9.%-]+):(%d+)$")
    if not host or #host>253 or not port or #port>5 or tonum(port)<1 or tonum(port)>65535 then return end
    if match(host,"^[0-9.]+$") then
        local a,b,c,d=match(host,"^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
        if not a or #a>3 or #b>3 or #c>3 or #d>3 or tonum(a)>255 or tonum(b)>255 or tonum(c)>255 or tonum(d)>255 then return end
    else
        if sub(host,1,1)=="." or match(host,"%.%.") then return end
        local labels={}; local start=1
        for i=1,#host+1 do if i>#host or sub(host,i,i)=="." then labels[#labels+1]=sub(host,start,i-1); start=i+1 end end
        for i,part in ipairs(labels) do
            if #part==0 or #part>63 or not match(part,"^[A-Za-z0-9]") or not match(part,"[A-Za-z0-9]$") then return end
        end
    end
    return host,port
end
ui.rooms={}; ui.visible_rooms={}; ui.adapters={}; ui.room_page=0
local function browsing(enabled)
    ui.nearby=enabled; ui.focus=nil; ui.message=""; ui.visible_rooms={}
    if base then file(base.."discover.txt",enabled and "ON" or "OFF") end
end
local function request(role,ip,port,key)
    if not base then return end
    browsing(false)
    if role~="cancel" then ui.last_request={role,ip,port,key} end
    ui.seq=ui.seq+1
    file(base.."request-"..ui.seq..".txt","LB1|"..ui.seq.."|"..role.."|"..ip.."|"..port.."|"..key.."|END")
    ui.state="starting"; ui.message=""; ui.requesting=true
    ui.owned=role~="cancel"; ui.focus=nil
end
local function join_room(text)
    text=match(text or "","^%s*(.-)%s*$") or ""
    -- Developer Steam P2P invite: the lobby id replaces the address, and the key
    -- still authenticates the TCP bridge running inside the tunnel.
    local sid,skey=match(text,"^SKCOOPS1|(%d+)|([a-fA-F0-9]+)$")
    if sid and skey then
        if #sid<17 or #sid>20 or #skey~=32 then
            ui.message=label("Steam 连接码无效，请向房主重新获取","Invalid Steam invite: ask the host for a new code")
            return
        end
        -- The broker rejects a new request while a bridge runs, so release ours
        -- first; it consumes the two requests in order.
        if ui.owned and base then request("cancel","127.0.0.1",27841,"-") end
        ui.text=text; ui.steam=true; ui.hosting=false; ui.copy_pending=nil
        request("steamclient",sid,tonum(ui.port) or 27841,skey)
        return
    end
    local ip,port,key=match(text,"^SKCOOP1|([A-Za-z0-9.%-]+):(%d+)|([a-fA-F0-9]+)$")
    if not ip or not port or not key or #key~=32 or #text>310 or not public_endpoint(ip..":"..port) then
        ui.message=label("连接码无效，请复制完整连接码","Invalid invite: copy the complete code"); return
    end
    if ui.owned and base then request("cancel","127.0.0.1",27841,"-") end
    ui.text=text; ui.steam=false; ui.hosting=false; ui.copy_pending=nil
    request("client",ip,port,key)
end
local function inside(x,y,w,h)
    return ui.mx>=x and ui.mx<x+w and ui.my>=y and ui.my<y+h
end
local function button(text,x,y,w,h)
    rectfill(x,y,x+w,y+h,inside(x,y,w,h) and 3 or 2); rect(x,y,x+w,y+h,3)
    lprint(text,x+w/2,y+5,4,1)
end
-- Set once setup() has registered the lobby buttons: btnclr on an unknown
-- button is fatal, and close_lobby can run before the first setup().
local lobby_defined=false
local function setup()
    defbtn("lobby_click",0,"m:lb"); defbtn("lobby_x",0,"m:x"); defbtn("lobby_y",0,"m:y")
    defbtn("lobby_back",0,"k:backspace"); defbtn("lobby_enter",0,"k:return")
    defbtn("lobby_escape",0,"k:escape")
    defbtn("lobby_left",0,"k:left"); defbtn("lobby_right",0,"k:right")
    defbtn("lobby_home",0,"k:home"); defbtn("lobby_end",0,"k:end")
    defbtn("lobby_delete",0,"k:delete")
    -- Developer transport toggle: Ctrl + right-click on the title (see _update).
    defbtn("lobby_rclick",0,"m:rb"); defbtn("lobby_ctrl",0,"k:lctrl, k:rctrl")
    lobby_defined=true
end
local function live() return ui.alive and time()<ui.alive end
-- The experimental Steam tunnel is a separate developer package; the gesture is
-- inert without it so a normal install cannot switch into a broken transport.
local function steam_available()
    if type(isfile)~="function" then return false end
    return isfile("steam-p2p/onlinecoop-steam-tunnel.exe") and isfile("steam-p2p/steam_api64.dll")
end

-- Never call btnclr() with no argument: it walks every player and the lobby
-- buttons exist for player 0 only, so the engine raises "Button ... for player 1
-- doesn't exist" and the game quits. Clear our own buttons for player 0 and the
-- game's controls explicitly instead.
local lobby_buttons={"lobby_click","lobby_enter","lobby_escape","lobby_back",
    "lobby_left","lobby_right","lobby_home","lobby_end","lobby_delete","lobby_rclick"}
local function clear_game_input()
    -- Player 0 only: the lobby is a single-player menu, and controls(nil,1)
    -- returns a scheme whose names are not all defined for player 1, which makes
    -- btnclr report "Button ... for player 1 doesn't exist" and quit the game.
    for name in each_match(controls(nil,0) or "","(%S+)%s*>") do
        if sub(name,1,6)~="lobby_" then btnclr(name,0) end
    end
end
local function clear_lobby_input()
    clear_game_input()
    -- btnclr on an unknown button is fatal, and close_lobby can run before the
    -- first setup(), so only clear the lobby buttons once they are defined.
    if lobby_defined then
        for _,name in ipairs(lobby_buttons) do btnclr(name,0) end
    end
end
local function close_lobby()
    browsing(false)
    if ui.owned and base then request("cancel","127.0.0.1",27841,"-") end
    ui.open=false; ui.focus=nil; ui.entering=false; ui.settings=false
    catchtxt(); clear_lobby_input()
end
local function leave()
    close_lobby()
    init_menu()
end
local function enter(entry)
    if entry=="onlinecoop_endless" or entry=="onlinecoop_charnier" or entry=="onlinecoop" then ui.entry=entry end
    -- The mode's initialize() calls this only after the player selects LAN Co-op.
    -- A successful handshake reloads the same mode once, bypassing this lobby.
    if ui.entering then ui.entering=false; return false end
    -- Keep the existing preconnected command-line/local-test entry usable.
    if not live() and onlinecoop_lan and onlinecoop_lan.status=="connected" then return false end
    ui.open=true; ui.settings=false; ui.focus=nil; ui.message=""; setup(); catchtxt(); clear_lobby_input()
    _log("[ONLINE LOBBY] opened from mode menu; helper="
        ..(live() and "yes" or "no"))
    return true
end
if coop_mod_index then MODLIST[coop_mod_index].lan_lobby={enter=enter} end
append("init_menu",function() setup(); close_lobby() end,"online_lobby_controls")
local function focus(field)
    ui.focus=field; ui.cursor=#ui[field]; ui.blink=time(); catchtxt()
end
local repeat_keys={lobby_back=true,lobby_delete=true,lobby_left=true,lobby_right=true}
local function consume_input()
    if not ui.focus then
        -- Keep the developer gesture's Ctrl readable: btnclr suppresses a cleared
        -- key until it is released, so the modifier check would never be true.
        clear_game_input()
        btnclr("lobby_click",0); btnclr("lobby_enter",0); btnclr("lobby_escape",0)
        return
    end
    -- Global btnclr suppresses held keys until release, including key repeat.
    -- Consume game controls while retaining the four editing keys.
    for name in each_match(controls(nil,0) or "","(%S+)%s*>") do
        if sub(name,1,6)~="lobby_" and not repeat_keys[name] then btnclr(name,0) end
    end
end
local function edit_input(text)
    local field=ui.focus
    if not field then return end
    local value=ui[field]
    local cursor=min(ui.cursor,#value)
    if text and #text>0 then
        local limit=field=="port" and 5 or 310
        local pattern=field=="port" and "^[0-9]+$" or "^[A-Za-z0-9|:./%-]+$"
        if match(text,pattern) then
            text=sub(text,1,max(0,limit-#value))
            value=sub(value,1,cursor)..text..sub(value,cursor+1); cursor=cursor+#text
            ui.blink=time()
        end
    end
    if btnp("lobby_back",0,.4,.05) and cursor>0 then
        value=sub(value,1,cursor-1)..sub(value,cursor+1); cursor=cursor-1; ui.blink=time()
    elseif btnp("lobby_delete",0,.4,.05) then
        value=sub(value,1,cursor)..sub(value,cursor+2); ui.blink=time()
    elseif btnp("lobby_left",0,.4,.05) then cursor=max(0,cursor-1); ui.blink=time()
    elseif btnp("lobby_right",0,.4,.05) then cursor=min(#value,cursor+1); ui.blink=time()
    elseif btnp("lobby_home",0) then cursor=0; ui.blink=time()
    elseif btnp("lobby_end",0) then cursor=#value; ui.blink=time() end
    ui[field]=value; ui.cursor=cursor
end
-- One layout shared by input and drawing, so the hit tests cannot drift from what
-- the player actually sees. Everything is relative to the 264-wide content column.
local function layout()
    local left=MCW/2-132
    return {
        left=left,
        title_y=6,
        create={left,24,88,23},
        nearby={left+96,24,72,23},
        join={left+176,24,88,23},
        hint_y=52,
        local_y=66, adapter_y=76,
        address_strip={left,58,194,18},
        port_label_x=left+199, port_label_y=62,
        port={left+226,58,38,5},
        port_hit={left+222,54,44,24},
        invite={left,92,194,16},
        paste={left+200,92,64,16},
        message_y=112,
        retry={left+88,126,88,16},
        back={left,146,88,18},
        tunnel={left+100,146,164,18},
        help_y=168,
        room_y=28, room_h=19, room_pitch=21,
        page_prev={left,137,80,17},
        page_next={left+184,137,80,17},
        nearby_back={left,158,88,18}
    }
end
local function hit(box) return inside(box[1],box[2],box[3],box[4]) end
local function retryable() return ui.last_request end
-- Copy whatever invite the broker published: a Steam lobby id or a TCP endpoint.
-- Used by the create button and by the automatic copy that follows room creation.
local function copy_invite()
    local invite=ui.invite
    if not invite or invite=="-" then return false end
    local sid,skey=match(invite,"^steam:(%d+):([a-f0-9]+)$")
    if sid and skey then
        clipboard("SKCOOPS1|"..sid.."|"..skey)
        ui.message=label("房间已创建，Steam 连接码已复制","Room created: Steam invite copied")
        return true
    end
    local ip,port,key=match(invite,"^([A-Za-z0-9.%-]+):(%d+):([a-f0-9]+)$")
    if not ip then return false end
    if ui.hosting and ui.mapped then
        local host,public_port=public_endpoint(ui.external)
        if not host then
            ui.message=label("请填写有效的对外地址:端口","Enter a valid public hostname:port")
            return false
        end
        file("lan/public-endpoint.txt",ui.external)
        ip,port=host,public_port
    end
    clipboard("SKCOOP1|"..ip..":"..port.."|"..key)
    ui.message=label("房间已创建，连接码已复制","Room created: invite copied")
    return true
end
prepend("_update",function()
    if not ui.setup then setup(); ui.setup=true end
    local now=time()
    if base and now>=ui.poll then
        ui.poll=now+.2
        local raw=file(base.."status.txt")
        local state,addresses,invite,err,seq,beat
        if raw then state,addresses,invite,err,seq,beat=match(raw,"^LB1|([a-z]+)|([0-9.,]+)|([A-Za-z0-9:.-]+)|([a-z]+)|(%d+)|(%d+)|END$") end
        if state then
            if ui.beat and beat~=ui.beat then ui.alive=now+3 end
            ui.beat=beat
            if not ui.requesting or tonum(seq)>=ui.seq then ui.state=state; ui.requesting=false end
            ui.seq=max(ui.seq,tonum(seq)); ui.addresses=split(addresses); ui.invite=invite; ui.error=err
            ui.adapters={}
            for ip,name in each_match(file(base.."adapters.txt") or "","([0-9.]+)|([^\n]+)") do ui.adapters[ip]=name end
            ui.rooms={}
            for ip,port,key,name in each_match(file(base.."rooms.txt") or "","([0-9.]+):(%d+):([a-f0-9]+)|([A-Za-z0-9 _-]+)") do
                if #key==32 and public_endpoint(ip..":"..port) and #ui.rooms<32 then
                    ui.rooms[#ui.rooms+1]={name=name,address=ip..":"..port,invite="SKCOOP1|"..ip..":"..port.."|"..key}
                end
            end
            ui.room_page=min(ui.room_page,max(0,room_pages(#ui.rooms)-1))
            -- Creating a room also copies its invite; finish that here once the
            -- broker has published one, then never copy again on its own.
            if ui.copy_pending and ui.state=="waiting" and invite and invite~="-" then
                ui.copy_pending=nil
                copy_invite()
            end
        end
    end
    if not ui.open then return end
    local available=live()
    ui.mx,ui.my=btnv("lobby_x",0),btnv("lobby_y",0)
    if available and ui.state=="connected" and onlinecoop_lan.status=="connected" then
        ui.open=false; ui.entering=true; ui.focus=nil; catchtxt(); clear_lobby_input()
        _log("[ONLINE LOBBY] enter role="..onlinecoop_lan.role)
        if coop_mod_index then set_mode(coop_mod_index..". "..(ui.entry or "onlinecoop")) end
        return
    end
    local ready=ui.state=="ready" or ui.state=="error" or ui.state=="stopped"
    if ui.nearby then
        catchtxt()
        local L=layout()
        if btnp("lobby_escape",0) then browsing(false)
        elseif btnp("lobby_click",0) then
            if hit(L.nearby_back) then browsing(false)
            elseif hit(L.page_prev) then ui.room_page=max(0,ui.room_page-1)
            elseif hit(L.page_next) then ui.room_page=min(max(0,room_pages(#ui.rooms)-1),ui.room_page+1)
            elseif available and ready then
                for row=1,5 do
                    local room=ui.visible_rooms[row]
                    if room and inside(L.left,L.room_y+(row-1)*L.room_pitch,264,L.room_h) then join_room(room.invite); break end
                end
            end
        end
        clear_lobby_input(); return
    end
    local text=catchtxt()
    if ready or (ui.state=="waiting" and ui.focus=="external") then edit_input(text) end
    if ui.settings then
        if btnp("lobby_escape",0) then ui.settings=false; ui.focus=nil; ui.message=""
        elseif btnp("lobby_click",0) then
            local left=MCW/2-132
            if inside(MCW/2-44,150,88,18) then ui.settings=false; ui.focus=nil; ui.message=""
        elseif inside(left,40,264,20) and ready then
            ui.mapped=not ui.mapped; ui.focus=nil
            if ui.mapped then
                ui.previous_address=ui.address
                for i,ip in ipairs(ui.addresses) do if ip=="127.0.0.1" then ui.address=i end end
            else ui.address=min(ui.previous_address or 1,max(1,#ui.addresses)) end
        elseif ui.mapped and (ready or ui.state=="waiting") and inside(left,92,194,17) then focus("external")
        elseif ui.mapped and (ready or ui.state=="waiting") and inside(left+200,92,64,17) then
            local host,port=public_endpoint(clipboard())
            if host then ui.external=host..":"..port; file("lan/public-endpoint.txt",ui.external); focus("external")
            else ui.message=label("请复制 TCP 对外地址:端口","Copy TCP public hostname:port") end

            else ui.focus=nil end
        end
        consume_input(); return
    end
    if available and ready and ui.focus=="text" and btnp("lobby_enter",0) then join_room(ui.text) end
    -- Developer transport: Ctrl + right-click on the title switches between the
    -- LAN / virtual-LAN route and the experimental Steam P2P tunnel. It is not
    -- advertised in the player UI; the Steam tunnel binary ships separately.
    if ready and inside(MCW/2-132,4,264,26) and btn("lobby_ctrl",0) and btnp("lobby_rclick",0) then
        -- Refuse the switch when the developer package is absent: the public LAN
        -- build ships the gesture but not the tunnel binary.
        if not steam_available() then
            ui.message=label("缺少 Steam P2P 组件，请使用完整实验包","Steam P2P helper missing: use the full experimental package")
            consume_input(); return
        end
        ui.steam=not ui.steam; ui.focus=nil; ui.message=""
        _log("[ONLINE LOBBY] dev transport steam="..(ui.steam and "on" or "off"))
        consume_input(); return
    end
    if btnp("lobby_escape",0) then
        leave(); return
    elseif btnp("lobby_click",0) then
        local L=layout()
        if hit(L.nearby) and ready then browsing(true); ui.room_page=0
        elseif hit(L.back) then leave(); return
        elseif hit(L.tunnel) and not ui.steam then ui.settings=true; ui.focus=nil; ui.message=""
        elseif hit(L.create) and available and ready then
            -- One button for both steps: a live room only re-copies its invite,
            -- otherwise create the room and copy once the broker publishes it.
            if ui.invite and ui.invite~="-" and ui.state=="waiting" then
                copy_invite()
            else
                local port=tonum(ui.port)
                if ui.mapped and not public_endpoint(ui.external) then
                    ui.message=label("请填写对外域名或 IP:端口","Enter public hostname or IP:port")
                elseif port and port>=1024 and port<=65535 then
                    if ui.mapped then file("lan/public-endpoint.txt",ui.external) end
                    ui.hosting=true; ui.copy_pending=true
                    request(ui.steam and "steamhost" or (ui.mapped and "hostmapped" or "host"),
                        ui.steam and "127.0.0.1" or (ui.addresses[ui.address] or "127.0.0.1"),port,"-")
                else ui.message=label("端口需为 1024～65535","Port must be 1024-65535") end
            end
        elseif hit(L.join) and available and ready then
            if ui.text=="" then
                ui.message=label("先粘贴朋友的连接码，再点加入","Paste your friend's invite, then Join")
            else join_room(ui.text) end
        elseif hit(L.retry) and available and retryable()
            and (ui.state=="error" or ui.state=="stopped") then
            local r=ui.last_request
            ui.hosting=r[1]~="client" and r[1]~="steamclient"
            request(r[1],r[2],r[3],r[4])
        elseif hit(L.address_strip) and ready and not ui.steam then ui.address=ui.address%max(1,#ui.addresses)+1; ui.focus=nil
        elseif hit(L.port_hit) and ready then focus("port")
        elseif hit(L.invite) and ready then focus("text")
        elseif hit(L.paste) and ready then
            local pasted=match(clipboard() or "","^%s*(.-)%s*$") or ""
            if #pasted<=310 then ui.text=pasted; ui.message=""; focus("text")
            else ui.message=label("连接码过长，请复制完整有效的连接码","Invite too long: copy a valid complete code") end
        else ui.focus=nil end
    end
    consume_input()
end,"online_lobby_input")
local function field(name,x,y,w,limit,placeholder)
    local selected=ui.focus==name
    rectfill(x,y,x+w,y+16,selected and 2 or 1)
    rect(x,y,x+w,y+16,selected and 4 or 3)
    local value=ui[name]
    local start=selected and max(1,ui.cursor-limit+1) or 1
    local shown=sub(value,start,start+limit-1)
    local count=selected and ui.cursor-start+1 or #shown
    local prefix=sub(shown,1,count)
    local cursor_x=lprint(prefix,x+3,y+5,4)
    if type(cursor_x)~="number" then cursor_x=x+3+#prefix*4 end
    lprint(sub(shown,count+1),cursor_x,y+5,4)
    if #value==0 and not selected and placeholder then lprint(placeholder,x+3,y+5,3) end
    if selected and (time()-(ui.blink or 0))%1<.55 then
        line(min(x+w-2,cursor_x),y+3,min(x+w-2,cursor_x),y+12,4)
    end
end
append("_draw",function()
    if not ui.open then return end
    local overlay=winspec("overlay")
    if overlay=="hdtext" and srfname(overlay) then local previous=srfname(); target(overlay); cls(255); target(previous) end
    clip(); pal(); rectfill(0,0,MCW,240,1)
    local L=layout()
    local left=L.left
    if ui.nearby then
        lprint(label("附近房间","Nearby rooms"),MCW/2,L.title_y,4,1)
        ui.visible_rooms={}
        for row=1,5 do
            local room=ui.rooms[ui.room_page*5+row]
            ui.visible_rooms[row]=room
            if room then button(room.name.."  "..room.address,left,L.room_y+(row-1)*L.room_pitch,264,L.room_h) end
        end
        if #ui.rooms==0 then
            lprint(label("正在寻找房间，请朋友先创建","Searching: ask your friend to create a room"),MCW/2,55,3,1)
            lprint(label("找不到时可返回，用连接码加入","If none appear, go back and use an invite"),MCW/2,72,3,1)
        end
        button(label("上一页","Previous"),L.page_prev[1],L.page_prev[2],L.page_prev[3],L.page_prev[4])
        lprint((ui.room_page+1).."/"..max(1,room_pages(#ui.rooms)),MCW/2,142,3,1)
        button(label("下一页","Next"),L.page_next[1],L.page_next[2],L.page_next[3],L.page_next[4])
        button(label("返回","Back"),L.nearby_back[1],L.nearby_back[2],L.nearby_back[3],L.nearby_back[4])
        lprint(label("双方需选同一模式","Use the same game mode"),left+94,164,3)
        return
    end
    if ui.settings then
        lprint(label("内网穿透 / 端口映射","TCP tunnel / port forwarding"),MCW/2,10,4,1)
        lprint(label("仅房主需要；先在穿透工具中建立 TCP 隧道","Host only: configure a TCP tunnel in your tool first"),MCW/2,26,3,1)
        button(ui.mapped and label("[开] 使用对外连接地址","[ON] Use public endpoint") or label("[关] 使用对外连接地址","[OFF] Use public endpoint"),left,40,264,20)
        lprint(label("隧道本地目标：","Tunnel local target: ")..(ui.addresses[ui.address] or "...")..":"..ui.port,left,70,3)
        field("external",left,92,194,45,label("对外域名或 IP:端口","Public hostname or IP:port"))
        button(label("粘贴","Paste"),left+200,92,64,17)
        lprint(label("开启后填写对外地址，返回大厅创建房间并复制连接码","Enable, enter public address; return to create / copy invite"),MCW/2,118,3,1)
        if ui.state=="waiting" and ui.hosting then
            lprint(label("房间已创建；返回大厅即可重新设置","Room active: go back to the lobby to change it"),MCW/2,131,3,1)
        else lprint(ui.message,MCW/2,131,4,1) end
        button(label("返回大厅","Back to lobby"),MCW/2-44,150,88,18)
        return
    end
    local title=ui.entry=="onlinecoop_endless" and label("局域网无尽","LAN Endless")
        or ui.entry=="onlinecoop_charnier" and label("局域网剿灭","LAN Charnier")
        or label("局域网合作","Online Co-op")
    lprint(title,MCW/2,L.title_y,4,1)
    -- Nearby sits in the middle and the two actions shrink outward from it, so the
    -- row reads as create | browse | join instead of a wide pair plus a tag-on.
    -- The create button relabels itself once a room is live: the same click then
    -- only re-copies the invite, so say so instead of pretending to create again.
    local room_live=ui.invite and ui.invite~="-" and ui.state=="waiting"
    button(room_live and label("复制连接码","Copy invite") or label("创建房间","Create room"),
        L.create[1],L.create[2],L.create[3],L.create[4])
    button(label("附近房间","Nearby"),L.nearby[1],L.nearby[2],L.nearby[3],L.nearby[4])
    button(label("加入","Join"),L.join[1],L.join[2],L.join[3],L.join[4])
    lprint(room_live and label("再次点击可重新复制","Click again to copy it again")
        or label("创建后自动复制连接码","Invite is copied for you"),
        L.create[1]+L.create[3]/2,L.hint_y,3,1)
    if ui.steam then
        -- Developer transport: address and tunnel settings do not apply.
        lprint(label("连接方式：Steam P2P（实验）","Connection: Steam P2P (experimental)"),L.left,L.local_y,3)
        lprint(label("Steam 好友联机 / App ID 480","Steam friends / App ID 480"),L.left,L.adapter_y,3)
    else
        lprint(label("本地：","Local: ")..(ui.addresses[ui.address] or "...").." >",L.left,L.local_y,3)
        local address=ui.addresses[ui.address]
        lprint(ui.adapters[address] or (address=="127.0.0.1" and label("仅本机","This PC only") or ""),L.left,L.adapter_y,3)
    end
    lprint(label("端口","Port"),L.port_label_x,L.port_label_y,3)
    field("port",L.port[1],L.port[2],L.port[3],5)
    field("text",L.invite[1],L.invite[2],L.invite[3],45,label("输入或粘贴连接码，再点击加入","Enter / paste invite, then Join"))
    button(label("粘贴","Paste"),L.paste[1],L.paste[2],L.paste[3],L.paste[4])
    local states={ready=label("创建房间，或粘贴连接码后点击加入","Create a room, or paste an invite then Join"),starting=label("正在连接……","Connecting..."),waiting=ui.hosting and label("房间已创建，等待朋友加入","Room created: waiting for friend") or label("正在连接房主……","Connecting to host..."),connected=label("已连接，正在进入准备界面","Connected: opening setup"),error=label("连接失败，请核对地址、组网和防火墙后重试","Connection failed: check address / network / firewall"),stopped=label("已断开，可重新创建或加入","Disconnected: create or join again")}
    local message=ui.message~="" and ui.message or states[ui.state] or ui.state
    if ui.state=="error" then
        local errors={
            port=label("端口占用，请修改本地和隧道端口","Port busy: change local / tunnel port"),
            address=label("网卡地址失效，请重新选择","Adapter unavailable: select another address"),
            invite=label("连接码无效，请向房主重新获取","Invalid invite: ask host for a new code"),
            denied=label("系统阻止连接，请检查防火墙或安全软件","Connection blocked: check firewall / security software"),
            refused=label("连接被拒绝，请房主确认房间已创建","Refused: ask host to check the room is open"),
            timeout=label("连接超时，请检查组网、地址和防火墙","Timed out: check network / address / firewall"),
            mismatch=label("密钥或协议不符，请更新并获取新连接码","Key / protocol mismatch: update and get a new invite"),
            dns=label("域名无法解析，请检查穿透地址","Cannot resolve hostname: check tunnel address"),
            disconnected=label("对方已断开，请双方重新创建和加入","Peer disconnected: create and join a new room"),
            handshake=label("握手超时，请核对端口和双方助手","Handshake timed out: check port and both helpers"),
            busy=label("连接仍在运行，请先取消","Connection still active: cancel first"),
            steammissing=label("缺少 Steam P2P 组件，请使用完整实验包","Steam P2P helper missing: use the full experimental package"),
            steam=label("Steam 连接失败：双方需用不同账号登录并互为好友","Steam link failed: sign in with different accounts and add each other")
        }
        message=errors[ui.error] or message
    end
    if not live() then message=label("助手未启动，请通过联机启动器运行","Use an Online Co-op launcher to enable networking") end
    lprint(message,MCW/2,L.message_y,4,1)
    -- Retry only appears after a failed or dropped attempt: leaving the lobby
    -- already releases the connection, so a permanent cancel button was noise.
    if retryable() and (ui.state=="error" or ui.state=="stopped") then
        button(label("重试","Retry"),L.retry[1],L.retry[2],L.retry[3],L.retry[4])
    end
    button(label("返回","Back"),L.back[1],L.back[2],L.back[3],L.back[4])
    button(ui.steam and label("穿透设置：不适用","Tunnel settings: n/a")
        or ui.mapped and label("穿透设置：已开启","Tunnel settings: ON")
        or label("穿透设置（可选）","Tunnel settings (optional)"),L.tunnel[1],L.tunnel[2],L.tunnel[3],L.tunnel[4])
    local help=live() and label("多网卡可点地址切换；端口默认无需修改","Click address to switch adapter; keep the default port")
        or label("启动方式与 Steam 设置见 README_zh.md","See README.md for launchers and Steam setup")
    if ui.mapped then help=label("TCP 隧道本地地址/端口应与上方一致","TCP tunnel target must match Local address / port") end
    if ui.steam then help=label("双方登录 Steam 并互加好友；保留原有连接方式","Sign in to Steam and add each other; LAN remains available") end
    lprint(help,MCW/2,L.help_y,3,1)
end,"online_lobby_draw")
