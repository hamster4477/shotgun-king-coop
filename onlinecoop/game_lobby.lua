-- Native game UI; the hidden local broker accepts only fixed data commands.
local config=file("lan/lobby-config.txt")
local token=config and match(config,"^LB1|([a-f0-9]+)|END$")
local base=token and #token==32 and "lan/lobby/"..token.."/" or nil
local ui={open=false,poll=0,seq=0,port="27841",text="",external="",mapped=false,addresses={},address=1,state="ready",message="",cursor=0,mx=-100,my=-100}
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
    local ip,port,key=match(text,"^SKCOOP1|([A-Za-z0-9.%-]+):(%d+)|([a-fA-F0-9]+)$")
    if not ip or not port or not key or #key~=32 or #text>310 or not public_endpoint(ip..":"..port) then
        ui.message=label("连接码无效，请复制完整连接码","Invalid invite: copy the complete code"); return
    end
    ui.text=text; ui.hosting=false; request("client",ip,port,key)
end
local function inside(x,y,w,h)
    return ui.mx>=x and ui.mx<x+w and ui.my>=y and ui.my<y+h
end
local function button(text,x,y,w,h)
    rectfill(x,y,x+w,y+h,inside(x,y,w,h) and 3 or 2); rect(x,y,x+w,y+h,3)
    lprint(text,x+w/2,y+5,4,1)
end
local function setup()
    defbtn("lobby_click",0,"m:lb"); defbtn("lobby_x",0,"m:x"); defbtn("lobby_y",0,"m:y")
    defbtn("lobby_back",0,"k:backspace"); defbtn("lobby_enter",0,"k:return")
    defbtn("lobby_escape",0,"k:escape")
    defbtn("lobby_left",0,"k:left"); defbtn("lobby_right",0,"k:right")
    defbtn("lobby_home",0,"k:home"); defbtn("lobby_end",0,"k:end")
    defbtn("lobby_delete",0,"k:delete")
end
local function live() return ui.alive and time()<ui.alive end
local function close_lobby()
    browsing(false)
    if ui.owned and base then request("cancel","127.0.0.1",27841,"-") end
    ui.open=false; ui.focus=nil; ui.entering=false; ui.settings=false
    catchtxt(); btnclr()
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
    ui.open=true; ui.settings=false; ui.focus=nil; ui.message=""; setup(); catchtxt(); btnclr()
    _log("[ONLINE LOBBY] opened from mode menu")
    return true
end
if coop_mod_index then MODLIST[coop_mod_index].lan_lobby={enter=enter} end
append("init_menu",function() close_lobby(); setup() end,"online_lobby_controls")
local function focus(field)
    ui.focus=field; ui.cursor=#ui[field]; ui.blink=time(); catchtxt()
end
local repeat_keys={lobby_back=true,lobby_delete=true,lobby_left=true,lobby_right=true}
local function consume_input()
    if not ui.focus then btnclr(); return end
    -- Global btnclr suppresses held keys until release, including key repeat.
    -- Consume game controls while retaining the four editing keys.
    for player=0,1 do
        for name in each_match(controls(nil,player) or "","(%S+)%s*>") do
            if player~=0 or not repeat_keys[name] then btnclr(name,player) end
        end
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
        end
    end
    if not ui.open then return end
    local available=live()
    ui.mx,ui.my=btnv("lobby_x",0),btnv("lobby_y",0)
    if available and ui.state=="connected" and onlinecoop_lan.status=="connected" then
        ui.open=false; ui.entering=true; ui.focus=nil; catchtxt(); btnclr()
        _log("[ONLINE LOBBY] enter role="..onlinecoop_lan.role)
        if coop_mod_index then set_mode(coop_mod_index..". "..(ui.entry or "onlinecoop")) end
        return
    end
    local ready=ui.state=="ready" or ui.state=="error" or ui.state=="stopped"
    if ui.nearby then
        catchtxt()
        local left=MCW/2-132
        if btnp("lobby_escape",0) then browsing(false)
        elseif btnp("lobby_click",0) then
            if inside(left,158,88,18) then browsing(false)
            elseif inside(left,137,80,17) then ui.room_page=max(0,ui.room_page-1)
            elseif inside(left+184,137,80,17) then ui.room_page=min(max(0,room_pages(#ui.rooms)-1),ui.room_page+1)
            elseif available and ready then
                for row=1,5 do
                    local room=ui.visible_rooms[row]
                    if room and inside(left,28+(row-1)*21,264,19) then join_room(room.invite); break end
                end
            end
        end
        btnclr(); return
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
    if btnp("lobby_escape",0) then
        leave(); return
    elseif btnp("lobby_click",0) then
        local left=MCW/2-132
        if inside(left+198,6,66,18) and ready then browsing(true); ui.room_page=0
        elseif inside(left,148,88,18) then leave(); return
        elseif inside(left+100,148,164,18) then ui.settings=true; ui.focus=nil; ui.message=""
        elseif inside(left,31,124,23) and available and ready then
            local port=tonum(ui.port)
            if ui.mapped and not public_endpoint(ui.external) then
                ui.message=label("请填写对外域名或 IP:端口","Enter public hostname or IP:port")
            elseif port and port>=1024 and port<=65535 then
                if ui.mapped then file("lan/public-endpoint.txt",ui.external) end
                ui.hosting=true
                request(ui.mapped and "hostmapped" or "host",ui.addresses[ui.address] or "127.0.0.1",port,"-")
            else ui.message=label("端口需为 1024～65535","Port must be 1024-65535") end
        elseif inside(left+140,31,124,23) and available and ready then join_room(ui.text)
        elseif inside(left,61,192,16) and ready then ui.address=ui.address%max(1,#ui.addresses)+1; ui.focus=nil
        elseif inside(left+199,61,65,16) and ready then focus("port")
        elseif inside(left,82,194,16) and ready then focus("text")
        elseif inside(left+200,82,64,16) and ready then
            local pasted=match(clipboard() or "","^%s*(.-)%s*$") or ""
            if #pasted<=310 then ui.text=pasted; ui.message=""; focus("text")
            else ui.message=label("连接码过长，请复制完整有效的连接码","Invite too long: copy a valid complete code") end
        elseif inside(left,108,124,20) and ui.invite and ui.invite~="-" then
            local ip,port,key=match(ui.invite,"^([A-Za-z0-9.%-]+):(%d+):([a-f0-9]+)$")
            if ui.hosting and ui.mapped then
                ip,port=public_endpoint(ui.external)
                if ip then file("lan/public-endpoint.txt",ui.external)
                else ui.message=label("请填写有效的对外地址:端口","Enter a valid public hostname:port") end
            end
            if ip then clipboard("SKCOOP1|"..ip..":"..port.."|"..key); ui.message=label("连接码已复制，发给朋友即可","Invite copied: send it to your friend") end
        elseif inside(left+140,108,124,20) and available then
            if ready and ui.last_request then
                local r=ui.last_request; ui.hosting=r[1]~="client"; request(r[1],r[2],r[3],r[4])
            else request("cancel","127.0.0.1",27841,"-") end
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
    local left=MCW/2-132
    if ui.nearby then
        lprint(label("附近房间","Nearby rooms"),MCW/2,6,4,1)
        ui.visible_rooms={}
        for row=1,5 do
            local room=ui.rooms[ui.room_page*5+row]
            ui.visible_rooms[row]=room
            if room then button(room.name.."  "..room.address,left,28+(row-1)*21,264,19) end
        end
        if #ui.rooms==0 then
            lprint(label("正在寻找房间，请朋友先创建","Searching: ask your friend to create a room"),MCW/2,55,3,1)
            lprint(label("找不到时可返回，用连接码加入","If none appear, go back and use an invite"),MCW/2,72,3,1)
        end
        button(label("上一页","Previous"),left,137,80,17)
        lprint((ui.room_page+1).."/"..max(1,room_pages(#ui.rooms)),MCW/2,142,3,1)
        button(label("下一页","Next"),left+184,137,80,17)
        button(label("返回","Back"),left,158,88,18)
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
            lprint(label("房间已创建；开关需取消连接后修改","Room active: cancel connection to change the switch"),MCW/2,131,3,1)
        else lprint(ui.message,MCW/2,131,4,1) end
        button(label("返回大厅","Back to lobby"),MCW/2-44,150,88,18)
        return
    end
    local title=ui.entry=="onlinecoop_endless" and label("局域网无尽","LAN Endless")
        or ui.entry=="onlinecoop_charnier" and label("局域网剿灭","LAN Charnier")
        or label("局域网合作","Online Co-op")
    lprint(title,MCW/2-35,10,4,1)
    button(label("附近房间","Nearby"),left+198,6,66,18)
    button(label("创建房间","Create room"),left,31,124,23)
    button(label("加入","Join"),left+140,31,124,23)
    lprint(label("本地：","Local: ")..(ui.addresses[ui.address] or "...").." >",left,64,3)
    local address=ui.addresses[ui.address]
    lprint(ui.adapters[address] or (address=="127.0.0.1" and label("仅本机","This PC only") or ""),left,74,3)
    lprint(label("端口","Port"),left+199,64,3)
    field("port",left+226,60,38,5)
    field("text",left,82,194,45,label("输入或粘贴连接码，再点击加入","Enter / paste invite, then Join"))
    button(label("粘贴","Paste"),left+200,82,64,16)
    button(label("复制连接码","Copy invite"),left,108,124,20)
    local retry=(ui.state=="error" or ui.state=="stopped" or ui.state=="ready") and ui.last_request
    button(retry and label("重试","Retry") or label("取消连接","Cancel"),left+140,108,124,20)
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
            busy=label("连接仍在运行，请先取消","Connection still active: cancel first")
        }
        message=errors[ui.error] or message
    end
    if not live() then message=label("助手未启动，请通过联机启动器运行","Use an Online Co-op launcher to enable networking") end
    lprint(message,MCW/2,136,4,1)
    button(label("返回","Back"),left,148,88,18)
    button(ui.mapped and label("穿透设置：已开启","Tunnel settings: ON") or label("穿透设置（可选）","Tunnel settings (optional)"),left+100,148,164,18)
    local help=live() and label("多网卡可点地址切换；端口默认无需修改","Click address to switch adapter; keep the default port")
        or label("启动方式与 Steam 设置见 README_zh.md","See README.md for launchers and Steam setup")
    if ui.mapped then help=label("TCP 隧道本地地址/端口应与上方一致","TCP tunnel target must match Local address / port") end
    lprint(help,MCW/2,170,3,1)
end,"online_lobby_draw")
