-- Data-only LAN mailbox. Game actions are validated in net_mode.lua.
local prefix = "[ONLINECOOP] "
local run_marker = file("lan/run-marker.txt")
if run_marker then _log(prefix .. "RUN " .. run_marker) end
_log(prefix .. "capabilities file=" .. type(file) .. " socket=" .. type(socket)
    .. " io=" .. type(io) .. " ffi=" .. type(ffi) .. " isfile=" .. type(isfile))
if type(file) ~= "function" or type(append) ~= "function" or type(match) ~= "function"
    or type(find) ~= "function" or type(tonum) ~= "function" then
    _log(prefix .. "UNSUPPORTED: required SUGAR functions missing")
    return
end
local session,role,base=nil,"offline",nil
local last_config,next_config=nil,0
local tx, rx, next_poll, next_status = 0, 0, 0, 0
local status, previous_status = "waiting", nil
local probe = file("lan/probe.txt") == "PING100"
local probe_started, probe_done, pong_count = false, false, 0
local ping_time = 0
local total_rtt, max_rtt = 0, 0
local data_queue, data_head, data_tail = {}, 1, 0
local batch_enabled=false
local batch_first,batch_count,batch_body=0,0,""
local out_groups,out_head,out_tail,out_retired={},1,0,0

local function track_out(first,last)
    out_tail=out_tail+1;out_groups[out_tail]={first=first,last=last}
end
local function flush_animation()
    if batch_count==0 or not base then return end
    local packet=batch_body
    if batch_count>1 then
        packet="OCB1|"..session.."|"..batch_first.."|"..batch_count.."|END\n"..packet
    end
    file(base.."out/"..batch_first..".msg",packet)
    track_out(batch_first,batch_first+batch_count-1)
    batch_first,batch_count,batch_body=0,0,""
end

-- Expose received data; this layer never evaluates code or changes the board.
onlinecoop_lan = {session=session, role=role, status="idle"}
local function configure(text)
    last_config=text
    local version,sid,who
    if text then version,sid,who=match(text,"^OC([23])|([a-f0-9]+)|([a-z]+)|END$") end
    if sid and #sid==32 and (who=="host" or who=="client") then
        session,role,base=sid,who,"lan/"..sid.."/"; status="waiting"
    else session,role,base=nil,"offline",nil; status="idle" end
    tx,rx=0,0;next_poll,next_status=0,0;data_queue,data_head,data_tail={},1,0
    batch_enabled=version=="3"
    batch_first,batch_count,batch_body=0,0,""
    out_groups,out_head,out_tail,out_retired={},1,0,0
    previous_status=nil; probe_started,probe_done,pong_count=false,false,0
    onlinecoop_lan.session=session; onlinecoop_lan.role=role; onlinecoop_lan.status=status
end
configure(file("lan/config.txt"))
-- MODLIST is engine-owned and shared with the separate mode environment.
if coop_mod_index then MODLIST[coop_mod_index].lan_transport=onlinecoop_lan end
function onlinecoop_lan.receive()
    if data_head > data_tail then return nil end
    local data = data_queue[data_head]
    data_queue[data_head] = nil
    data_head = data_head + 1
    return data
end
function onlinecoop_lan.can_send_visual()
    if status~="connected" then return false end
    if type(isfile)~="function" then return true end
    -- A batch file represents several sequence numbers. Count its logical
    -- records until the bridge retires the complete group, not missing middle
    -- filenames (which would incorrectly treat a queued batch as delivered).
    while out_head<=out_tail do
        local group=out_groups[out_head]
        if isfile(base.."out/"..group.first..".msg") then break end
        out_retired=group.last;out_groups[out_head]=nil;out_head=out_head+1
    end
    if out_head>out_tail then out_groups,out_head,out_tail={},1,0 end
    return tx-out_retired<4
end
function onlinecoop_lan.send(kind, payload)
    if status ~= "connected" or tx >= 300000 then return false end
    if kind ~= "ping" and kind ~= "pong" and kind ~= "data" then return false end
    if type(payload) ~= "string" or #payload > 16384
        or find(payload, "[^A-Za-z0-9_,:.=%-]") then return false end
    local animation=batch_enabled and kind=="data" and sub(payload,1,3)=="F2,"
    -- Commands do not wait for aggregation. Flush all earlier animation
    -- records first so wire order and complete-playback barriers stay exact.
    if not animation then flush_animation() end
    -- Visual frames are disposable. Leave the FIFO room for gameplay traffic.
    if kind=="data" and sub(payload,1,3)=="F1," and not onlinecoop_lan.can_send_visual() then return false end
    local record="OC1|"..session.."|"..(tx+1).."|"..kind.."|"..payload.."|END"
    if animation and (batch_count>=16 or #batch_body+#record+96>65536) then flush_animation() end
    tx = tx + 1
    if animation then
        if batch_count==0 then batch_first=tx;batch_body=record
        else batch_body=batch_body.."\n"..record end
        batch_count=batch_count+1
    else
        file(base .. "out/" .. tx .. ".msg",record)
        track_out(tx,tx)
    end
    return true
end

append("_update", function()
    local now = time()
    if now>=next_config then
        next_config=now+.25
        local config=file("lan/config.txt")
        if config~=last_config then configure(config) end
    end
    if not base then return end
    -- At most one game frame of aggregation. Never wait for more records.
    flush_animation()
    if now < next_poll then return end
    next_poll = next_poll + 1/60
    if next_poll<now-1/60 then next_poll=now+1/60 end
    -- The native file reader logs every open. Poll connection status at 4Hz,
    -- while incoming data stays responsive at 60Hz without idle disk/log churn.
    if now>=next_status then
    next_status=now+.25
    local text = file(base .. "status.txt")
    local sid, state
    if text then sid, state = match(text, "^OC1|([a-f0-9]+)|([a-z]+)|END$") end
    if sid ~= session then return end
    status = state
    onlinecoop_lan.status = status
    if status ~= previous_status then
        _log(prefix .. "STATUS " .. status)
        if status=="error" and type(isfile)=="function" and isfile(base.."error.txt") then
            local detail=file(base.."error.txt")
            if detail then _log(prefix .. "DETAIL " .. sub(detail,1,2048)) end
        end
        previous_status = status
    end
    end
    if status ~= "connected" then return end
    -- Drain a bounded burst so pose updates cannot delay action/state packets.
    for burst=1,16 do
    local incoming = base .. "in/" .. (rx + 1) .. ".msg"
    local packet
    if type(isfile) ~= "function" or isfile(incoming) then packet = file(incoming) end
    if not packet then break end
    if packet then
        local ps, seq, kind, payload = match(packet, "^OC1|([a-f0-9]+)|(%d+)|([a-z]+)|([A-Za-z0-9_,:.=%-]*)|END$")
        if ps == session and tonum(seq) == rx + 1
            and (kind ~= "data" or data_tail - data_head < 63) then
            rx = rx + 1
            -- Write once: native file() can deny sharing even when the bridge
            -- reader permits writes. Never truncate a file a reader may hold.
            file(base .. "ack/" .. rx .. ".msg", "OC1|" .. session .. "|" .. rx .. "|END")
            if kind == "ping" then
                onlinecoop_lan.send("pong", payload)
            elseif kind == "pong" and probe and not probe_done then
                if payload ~= "probe," .. (pong_count + 1) then
                    _log(prefix .. "NETWORK_PROBE_FAIL unexpected pong")
                    probe_done = true
                else
                    local rtt = now - ping_time
                    total_rtt = total_rtt + rtt
                    if rtt > max_rtt then max_rtt = rtt end
                    pong_count = pong_count + 1
                    if pong_count == 100 then
                        probe_done = true
                        _log(prefix .. "NETWORK_PROBE_PASS messages=100 mean_rtt=" .. (total_rtt / 100) .. " max_rtt=" .. max_rtt)
                    end
                end
            elseif kind == "data" then
                -- Delivered as data for a future authority layer; not interpreted.
                data_tail = data_tail + 1
                data_queue[data_tail] = {sequence=rx, payload=payload}
            end
        else break end
    end
    end
    if probe and not probe_done and (not probe_started or pong_count == tx) then
        probe_started = true
        ping_time = now
        onlinecoop_lan.send("ping", "probe," .. (pong_count + 1))
    end
end, "onlinecoop_lan_transport")
