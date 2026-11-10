"""Complete native clips survive backpressure/bursts and gate gameplay/scenes."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
from lupa.luajit21 import LuaRuntime
lua=LuaRuntime()
lua.execute('''
sub=string.sub; match=string.match; flr=math.floor; min=math.min; max=math.max; tostr=tostring
add=table.insert; now=0; active=true; phase=3; logs={}; wire={}; available=false
function time() return now end
function _log(s) add(logs,s) end
function is_coop_active() return active end
function onlinecoop_presentation_active() return active end
function onlinecoop_net_phase() return phase end
function onlinecoop_net_numbers(s,count,limit)
 local a={}; for v in string.gmatch(s,"[^,]+") do
  if not string.match(v,"^%d+$") then return end
  local n=tonumber(v); if n>limit then return end; add(a,n)
 end
 if #a==count then return a end
end
onlinecoop_lan={can_send_visual=function() return available end,
 send=function(k,p) add(wire,p);return true end}
scenes={}; function onlinecoop_scenes_receive(p) add(scenes,p) end
function onlinecoop_receive_cg(p) add(scenes,p) end
function onlinecoop_events_clear(n) n.seen_units={};n.motion={};n.effects={};n.board_visible=false end
hooks={}; function append(k,f,id) hooks[id]=f end
prepend=append
function coop_get_board_geometry() return 96,30 end
function gsq(x,y) return {} end
function coop_piece_on_square(sq) return {} end
function pget(x,y) return flr(now*30)%6 end
function pal() end;function clip() end;draws=0;function rectfill() draws=draws+1 end
host={lvl=1,turns=2,net={role="host",peer_ok=true}}
client={net={role="client",snapshot={floor=1,turn=1,board=1,units={{1}}}}}
mode=host
''')
for name in ('net_board_frame.lua','net_playback.lua'):
    lua.execute((ROOT/name).read_text(encoding='utf-8'))
lua.execute('''
onlinecoop_board_frame_initialize()
onlinecoop_playback_host_tick();assert(not onlinecoop_playback_busy() and #wire==0)
onlinecoop_playback_setting_tick();assert(wire[#wire]=="M2,0")
mode=client;assert(onlinecoop_playback_setting_receive(wire[#wire]) and client.net.playback_mode==0)
mode=host;phase=1;keys={online_playback=true};function btnp(k) return keys[k] end
onlinecoop_playback_input();assert(host.net.playback_pending==1)
onlinecoop_playback_setting_tick();assert(host.net.playback_mode==1)
wire={};keys={};phase=3
onlinecoop_playback_host_tick()
assert(onlinecoop_playback_busy() and #wire==1)
-- Capture continues at the selected rate even when the network cannot send.
for i=1,60 do now=i/60;onlinecoop_playback_host_tick();hooks.online_board_background_reset();hooks.online_native_board_pixels() end
local c=host.net.clip_host
assert(#c.frames>=29 and #c.frames<=31,#c.frames)
local count=#c.frames
phase=1;now=1.1;onlinecoop_playback_host_tick()
now=1.25;onlinecoop_playback_host_tick()
assert(c.closed and not c.ended and #c.frames==count)
-- Deliver BEGIN alone; waiting cannot expire the last native picture.
mode=client;assert(onlinecoop_playback_receive(wire[1]))
client.net.board_native={floor=1,turn=1,received=-100,runs={{0,0,128,1}}}
assert(onlinecoop_draw_board_frame(client.net.snapshot,96) and draws==1)
onlinecoop_playback_client_tick();assert(client.net.clip_client.index==nil)
assert(onlinecoop_playback_defer("C1,1,1,1:cards"))
assert(onlinecoop_playback_defer("G3,1,2,0"))
assert(#scenes==0)
-- Even delivering the whole burst instantly starts paced local playback only
-- after its complete frame count and final duration have been checked.
available=true;mode=host
for i=1,100 do onlinecoop_playback_host_tick() end
assert(c.ended and onlinecoop_playback_busy())
mode=client
for i=2,#wire do assert(onlinecoop_playback_receive(wire[i]),wire[i]:sub(1,60)) end
assert(client.net.clip_client.complete and #client.net.clip_client.frames==count)
local clip=client.net.clip_client; local first=clip.due;local presented={}
for i=1,count do
 now=clip.due+.1 -- render lag must not discard intermediate frames
 onlinecoop_playback_client_tick()
 assert(clip.index==i and onlinecoop_playback_busy())
 add(presented,client.net.board_native.runs[1][4])
end
assert(#scenes==0)
now=clip.due;onlinecoop_playback_client_tick()
assert(not onlinecoop_playback_busy() and #scenes==2 and client.net.board_visible)
assert(client.net.seen_units[1] and #wire==count+3)
mode=host;assert(onlinecoop_playback_receive(wire[#wire]))
assert(not onlinecoop_playback_busy())
-- Draft/CG/returned menu do not create endless clips. An existing clip can
-- finish sending there, otherwise the last death animation would deadlock.
host.net.draft={active=true};phase=4;onlinecoop_playback_host_tick();assert(not host.net.clip_host)
host.net.draft=nil;phase=3;now=5;onlinecoop_playback_host_tick()
onlinecoop_playback_capture(string.rep("8001",161),1,2)
host.net.cg_returned=true;onlinecoop_playback_host_tick()
assert(host.net.clip_host.closed and host.net.clip_host.ended)
mode=client
assert(not onlinecoop_playback_receive("T2,9,1"))
assert(onlinecoop_playback_receive("T2,2,1"))
assert(not onlinecoop_playback_receive("F2,2,1,1,2,0,2,2:8001"))
assert(not onlinecoop_playback_receive("F2,2,1,1,2,0,1,1:0001"))
assert(not onlinecoop_playback_receive("F2,2,1,1,2,0,1,1:8001"))
assert(onlinecoop_playback_receive("F2,2,1,1,2,10,1,1:"..string.rep("8001",161)))
assert(not onlinecoop_playback_receive("J2,2,2,50,0"))
assert(not onlinecoop_playback_receive("J2,2,1,5,0"))
assert(onlinecoop_playback_receive("J2,2,1,50,0"))
assert(not onlinecoop_playback_receive("J2,2,1,50,0"))
assert(not onlinecoop_decode_board_pixels(string.rep("80zz",161),false))
assert(onlinecoop_decode_board_pixels(string.rep("8001",161),false)==true)
-- F7 changes both peers, waits for an active clip, and supports returning to
-- full playback after a live action finishes. No mid-animation capture switch.
host.net.clip_host=nil;host.net.cg_returned=nil;mode=host;phase=1
assert(not onlinecoop_playback_setting_receive("M1,2"))
assert(not onlinecoop_playback_setting_receive("M2,0"))
keys={online_playback=true};function btnp(k) return keys[k] end
now=20;onlinecoop_playback_input();assert(host.net.playback_pending==0)
onlinecoop_playback_setting_tick();assert(host.net.playback_mode==0 and host.net.playback_pending==nil)
mode=client;client.net.clip_client=nil
assert(onlinecoop_playback_setting_receive(wire[#wire]) and client.net.playback_mode==0)
client.net.peer_ok=true;now=21;onlinecoop_playback_input();assert(client.net.playback_pending==1)
mode=host;phase=3;assert(onlinecoop_playback_setting_receive(wire[#wire]))
onlinecoop_playback_setting_tick();onlinecoop_playback_host_tick()
assert(host.net.playback_mode==0 and host.net.playback_pending==1 and not host.net.clip_host)
phase=1;onlinecoop_playback_setting_tick();assert(host.net.playback_mode==1)
mode=client;assert(onlinecoop_playback_setting_receive(wire[#wire]))
assert(client.net.playback_mode==1 and client.net.playback_pending==nil)
mode=host;phase=3;onlinecoop_playback_host_tick();assert(host.net.clip_host)
assert(onlinecoop_playback_setting_receive("M1,0"));phase=1
onlinecoop_playback_setting_tick();assert(host.net.playback_mode==1 and host.net.playback_pending==0)
-- At normal 60 Hz rendering, a 30 FPS one-second clip stays one second long,
-- rather than repeatedly rounding 33/34 ms intervals up and slowing the clip.
mode=client;now=100
local paced={id=3,floor=1,frames={},snapshot=client.net.snapshot,deferred={},complete=true,index=0,
 duration=1000,due=100,play_started=100}
for i=1,30 do add(paced.frames,{ms=flr((i-1)*1000/30),turn=2,data=string.rep("8001",161)}) end
client.net.clip_client=paced;client.net.cg_active=1
onlinecoop_playback_client_tick();assert(paced.index==0)
client.net.cg_active=nil
for i=0,61 do
 now=100+i/60;local previous=paced.index
 onlinecoop_playback_client_tick();assert(paced.index-previous<=1)
 if not client.net.clip_client then break end
end
assert(paced.index==30 and not client.net.clip_client and now<=101.017)
''')
for name in ('net_mode.lua','net_choices.lua','net_minigames.lua','net_view.lua'):
    lua.execute((ROOT/name).read_text(encoding='utf-8'))
lua.execute('''
tonum=tonumber;keys={};cleared=0
function onlinecoop_signals_input() return false end
function btnv() return 0 end
function btnclr() cleared=cleared+1 end
mode={id="coop",lvl=1,turns=1,net={role="host",peer_ok=true,clip_host={},
 revision=10,epoch=2,last_command=0,expected_command=1}}
onlinecoop_lan.status="connected"
onlinecoop_net_client_input();assert(cleared==1)
onlinecoop_net_apply_request("R1,1,10,1,1,2,move,1,1")
assert(wire[#wire]=="A1,1,phase")
mode.net={role="client",peer_ok=true,clip_client={},snapshot={floor=1,phase=2}}
onlinecoop_net_client_input();assert(cleared==2)
assert(not onlinecoop_net_request("move",1,1))
-- Waiting diagnostics distinguish native settlement, transfer and guest ACK;
-- they are rate limited and must never release either player's input lock.
function onlinecoop_net_phase() return 3 end
current_lang="english"; now=200
mode={coop_king_move_input_locked=true,net={role="host",clip_host={id=9,frames={},next=1}}}
local before=#logs
onlinecoop_playback_wait_trace();assert(#logs==before)
assert(onlinecoop_playback_hint()=="Resolving action...")
now=203;onlinecoop_playback_wait_trace();assert(#logs==before+1 and logs[#logs]:find("step=native"))
onlinecoop_playback_wait_trace();assert(#logs==before+1)
mode.net.clip_host.closed=true
assert(onlinecoop_playback_hint()=="Sending complete animation...")
mode.net.clip_host.ended=true
assert(onlinecoop_playback_hint()=="Waiting for 2P playback...")
now=208;onlinecoop_playback_wait_trace();assert(logs[#logs]:find("step=ack"))
assert(mode.coop_king_move_input_locked and onlinecoop_playback_busy())
mode={net={role="client",clip_client={id=9,frames={},index=0}}}
onlinecoop_playback_wait_trace();now=211;onlinecoop_playback_wait_trace()
assert(logs[#logs]:find("step=receive"))
mode.net.clip_client.complete=true;now=216;onlinecoop_playback_wait_trace()
assert(logs[#logs]:find("step=play") and onlinecoop_playback_busy())
''')
print('PASS: retained frames, paced burst playback, host/client input locks, scene deferral, bounded decoder, F7 mode switching')
