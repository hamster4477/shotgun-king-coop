"""Lobby routing, cancellation and focus/caret checks using actual Lua UI code."""
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
from lupa.luajit21 import LuaRuntime
lua=LuaRuntime()
lua.execute(r'''
now=1; hooks={}; files={}; keys={}; texts={}; lines={}; clears=0
MODLIST={{name="onlinecoop",active=false},{name="3833493529",active=true}}; current_lang="english"; MCW=320
onlinecoop_lan={status="idle",role="offline"}
match=string.match; sub=string.sub; tonum=tonumber; min=math.min; max=math.max
function file(path,value)
 if value then files[path]=value end
 return files[path]
end
files["lan/lobby-config.txt"]="LB1|"..string.rep("a",32).."|END"
base_test="lan/lobby/"..string.rep("a",32).."/"
function status(state,seq,beat)
 files[base_test.."status.txt"]="LB1|"..state.."|127.0.0.1|-|none|"..seq.."|"..beat.."|END"
end
function append(k,f,id) hooks[id]=f end
prepend=append
function _log() end
function time() return now end
function defbtn() end
held={}; blocked={}
function btnp(k,p,delay,interval)
 if blocked[k] then return false end
 if keys[k] then keys[k]=nil; return true end
 if held[k] and delay and interval and now-held[k].start>=delay and now>=held[k].next then
  held[k].next=now+interval; return true
 end
 return false
end
function btnv(k) return k=="lobby_x" and mx or my end
function controls()
 return "shoot > m:lb\nmove > k:left\nlobby_back > k:backspace\nlobby_left > k:left\nlobby_right > k:right\nlobby_delete > k:delete"
end
function btnclr(name,player)
 clears=clears+1
 if player==1 then return end
 if name then keys[name]=nil; if held[name] then blocked[name]=true end
 else keys={}; for k in pairs(held) do blocked[k]=true end end
end
function catchtxt() local s=typed; typed=nil; return s end
function init_menu() mode=nil; hooks.online_lobby_controls() end
function set_mode(name) selected=name; mode={id=name} end
function clipboard(s) if s then copied=s end; return copied end
function winspec() return nil end
function clip() end
function pal() end
function rectfill() end
function rect(x1,y1,x2,y2) assert(y1>=0 and y2<180,"UI below viewport") end
function lprint(s,x,y) assert(y>=0 and y+8<=180,"Text below viewport"); texts[#texts+1]=s; return x+#s*4 end
function line(...) lines[#lines+1]={...} end
function click(x,y)
 mx,my=x,y; keys={lobby_click=true}; hooks.online_lobby_input()
end
function draw() texts={}; lines={}; hooks.online_lobby_draw() end
''')
# Run the real entry script to select the active Workshop copy. This harness
# supplies the transport and loads the lobby module directly.
lua.execute("require=function() end; newsfx=function() end")
lua.execute((ROOT/'script.lua').read_text(encoding='utf-8'))
lua.execute("assert(coop_mod_index==2 and not MODLIST[1].lan_lobby)")
lua.execute((ROOT/'game_lobby.lua').read_text(encoding='utf-8'))
lua.execute(r'''
-- Heartbeats alone cannot open a lobby or intercept ordinary menu input.
status("ready",0,1); hooks.online_lobby_input()
now=2; status("ready",0,2); hooks.online_lobby_input()
local before=clears; now=3; hooks.online_lobby_input(); draw()
assert(clears==before and #texts==0)
assert(MODLIST[2].lan_lobby.enter())
-- A same-frame draw is valid even before the first mouse update.
draw(); assert(#texts>0 and #lines==0)
click(40,88); draw(); assert(#lines==1 and lines[1][1]==31)
now=3.7; draw(); assert(#lines==0)
typed="123"; hooks.online_lobby_input(); draw()
assert(#lines==1 and lines[1][1]==43)
keys={lobby_left=true}; hooks.online_lobby_input()
typed="9"; hooks.online_lobby_input(); draw()
local found=false; for _,t in ipairs(texts) do if t=="129" then found=true end end
assert(found and lines[1][1]==43)
-- Clicking the port field must not erase the default value.
click(270,65); draw(); found=false
for _,t in ipairs(texts) do if t=="27841" then found=true end end
assert(found and #lines==1)
keys={lobby_home=true}; hooks.online_lobby_input()
keys={lobby_delete=true}; hooks.online_lobby_input(); draw(); found=false
for _,t in ipairs(texts) do if t=="7841" then found=true end end
assert(found)
-- Create a room, then leave with the mouse before its connection completes.
click(50,40)
assert(string.find(files[base_test.."request-1.txt"],"|host|127.0.0.1|7841|",1,true))
click(50,157)
assert(string.find(files[base_test.."request-2.txt"],"|cancel|",1,true))
assert(mode==nil)
-- A late success is unable to auto-enter a mode after leaving.
now=4; status("connected",1,4); onlinecoop_lan.status="connected"
hooks.online_lobby_input(); draw(); assert(not selected and #texts==0)
now=4.5; status("ready",2,5); onlinecoop_lan.status="idle"; hooks.online_lobby_input()
assert(MODLIST[2].lan_lobby.enter()); draw(); assert(#texts>0)
keys={lobby_escape=true}; hooks.online_lobby_input(); draw(); assert(#texts==0)
-- A normal Steam launch without a helper must explain the available launchers
-- in the selected language, without routing the player to single-core only.
now=20; onlinecoop_lan.status="idle"
assert(MODLIST[2].lan_lobby.enter())
for _,language in ipairs({"english","simplified_chinese","english"}) do
 current_lang=language; draw()
 local combined=table.concat(texts,"\n")
 if language=="english" then
  assert(string.find(combined,"Online Co-op launcher",1,true))
  assert(string.find(combined,"README.md",1,true))
  assert(not string.find(combined,"局域网",1,true))
 else
  assert(string.find(combined,"助手未启动",1,true))
  assert(string.find(combined,"Steam 设置",1,true))
 end
 assert(not string.find(combined,"Start Online Co-op.vbs",1,true))
end
''')
print('PASS: lobby routing, focus/caret, cancellation, reopen, and bilingual missing-helper guidance')

lua.execute(r'''-- Mapped room advertises a domain while binding locally; join keeps the domain.
now=30; status("ready",2,30); hooks.online_lobby_input()
click(210,157); draw()
click(40,48); draw()
clipboard("tcp://test-tunnel.example:45678"); click(240,100); draw(); click(150,158)
click(50,40)
assert(string.find(files[base_test.."request-3.txt"],"|hostmapped|127.0.0.1|7841|",1,true))
assert(files["lan/public-endpoint.txt"]=="test-tunnel.example:45678")
now=31
files[base_test.."status.txt"]="LB1|waiting|127.0.0.1|127.0.0.1:7841:"..string.rep("b",32).."|none|3|31|END"
hooks.online_lobby_input(); draw(); assert(string.find(table.concat(texts,"\n"),"Room created",1,true))
click(50,115)
assert(copied=="SKCOOP1|test-tunnel.example:45678|"..string.rep("b",32))
local invite=copied
click(240,115); now=32; status("ready",4,32); hooks.online_lobby_input()
clipboard(invite); click(240,88); draw()
assert(not files[base_test.."request-5.txt"],"Paste must not connect")
clipboard("changed clipboard must not replace input")
click(240,40)
assert(string.find(files[base_test.."request-5.txt"],"|client|test-tunnel.example|45678|",1,true))
-- Domain-bearing status does not break heartbeat parsing.
now=33
files[base_test.."status.txt"]="LB1|starting|127.0.0.1|test-tunnel.example:45678:"..string.rep("b",32).."|none|5|33|END"
hooks.online_lobby_input()
now=33.5; status("waiting",5,34); hooks.online_lobby_input()
for _,v in ipairs({{"english","Connecting to host..."},{"simplified_chinese","正在连接房主……"}}) do
 current_lang=v[1]; draw(); assert(string.find(table.concat(texts,"\n"),v[2],1,true))
end
click(210,157); draw(); assert(not string.find(table.concat(texts,"\n"),"房间已创建",1,true))
click(150,158); current_lang="english"
click(240,115)
now=34; status("ready",6,34); hooks.online_lobby_input()
for _,bad in ipairs({"http://bad.example:45678","a..b:1234","-bad.example:1234","a.example:0","a.example:65536","999.1.1.1:1234"}) do
 copied="SKCOOP1|"..bad.."|"..string.rep("b",32)
 click(240,88); click(240,40); assert(not files[base_test.."request-7.txt"])
end
''')
print('PASS: tunnel toggle, public address paste/copy, fixed binding request, paste without connecting, Join uses input, domain join/status and invalid addresses')

lua.execute(r'''-- Connected lobby must reopen the requested campaign, not Throne.
keys={lobby_escape=true}; hooks.online_lobby_input()
now=40;status("ready",7,40);onlinecoop_lan.status="idle";hooks.online_lobby_input()
assert(MODLIST[2].lan_lobby.enter("onlinecoop_charnier"));draw()
assert(string.find(table.concat(texts,"\n"),"LAN Charnier",1,true))
click(50,40)
now=41;status("connected",8,41);onlinecoop_lan.status="connected"
hooks.online_lobby_input()
assert(selected=="2. onlinecoop_charnier")
assert(not MODLIST[2].lan_lobby.enter("onlinecoop_charnier"))
''')
print('PASS: selected LAN campaign survives the lobby connection / one-time reentry')

lua.execute(r'''
now=50;status("ready",8,50);onlinecoop_lan.status="idle";hooks.online_lobby_input()
assert(MODLIST[2].lan_lobby.enter())
local invite="SKCOOP1|192.168.1.9:27841|"..string.rep("c",32)
files[base_test.."rooms.txt"]="192.168.1.9:27841:"..string.rep("c",32).."|Test-PC"
files[base_test.."adapters.txt"]="127.0.0.1|Loopback"
now=51;status("ready",8,51);hooks.online_lobby_input()
click(240,12);draw()
assert(files[base_test.."discover.txt"]=="ON")
assert(string.find(table.concat(texts,"\n"),"Test-PC",1,true))
click(60,36)
assert(files[base_test.."discover.txt"]=="OFF")
assert(string.find(files[base_test.."request-9.txt"],"|client|192.168.1.9|27841|",1,true))
now=52
files[base_test.."status.txt"]="LB1|error|127.0.0.1|-|refused|9|52|END"
hooks.online_lobby_input();draw()
assert(string.find(table.concat(texts,"\n"),"Refused",1,true))
click(240,115)
assert(string.find(files[base_test.."request-10.txt"],"|client|192.168.1.9|27841|",1,true))
now=53;status("error",10,53);hooks.online_lobby_input()
clipboard("1234567890");click(240,88)
keys={lobby_back=true};held.lobby_back={start=now,next=now+.4};hooks.online_lobby_input()
draw(); assert(string.find(table.concat(texts,"\n"),"123456789",1,true))
now=53.2;hooks.online_lobby_input();draw()
assert(string.find(table.concat(texts,"\n"),"123456789",1,true))
now=53.41;hooks.online_lobby_input()
now=53.47;hooks.online_lobby_input()
held={};blocked={};draw()
local found=false; for _,t in ipairs(texts) do if t=="1234567" then found=true end end
assert(found,"Held Backspace must continue past its initial press")
now=54
keys={lobby_left=true};held.lobby_left={start=now,next=now+.4};hooks.online_lobby_input()
now=54.41;hooks.online_lobby_input();held={};blocked={}
keys={lobby_delete=true};held.lobby_delete={start=now,next=now+.4};hooks.online_lobby_input()
now=54.82;hooks.online_lobby_input();held={};blocked={}
draw();found=false;for _,t in ipairs(texts) do if t=="12345" then found=true end end
assert(found,"Held Left/Delete must edit at the caret")
click(240,12);keys={lobby_escape=true};hooks.online_lobby_input()
assert(files[base_test.."discover.txt"]=="OFF")
''')
print('PASS: nearby selection, discovery stop, classified failure/retry and held editing keys')
