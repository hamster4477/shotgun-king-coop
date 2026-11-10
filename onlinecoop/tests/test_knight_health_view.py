"""Guest HP follows the displayed snapshot and the native heart/bar rules."""
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT.parents[1]/'diagnostics/python_libs'))
from lupa.luajit21 import LuaRuntime
lua=LuaRuntime()
lua.execute('''
min=math.min;max=math.max;ceil=math.ceil;flr=math.floor;add=table.insert
MCW=320;MCH=180;lang={piece_0="Pawn",piece_1="Knight"};current_lang="english"
PIECES={{type=0,name="pawn"},{type=1,name="knight"},{type=6,name="boss",big=true},{type=20,name="rebel_knight",big=true}}
texts={};hearts={};bars={};face="default"
function font(f) local old=face;if f then face=f end;return old end
function spritesheet() end
function lprint(s,x,y,c,a) add(texts,{s,x,y,c,a}) end
function sspr(x,y,w,h,dx,dy) if y==56 and w==3 and h==3 then add(hearts,{x,dx,dy}) end end
function rectfill(...) add(bars,{...}) end
function reset_draw() texts={};hearts={};bars={} end
function noop() end
function coop_draw_turn_indicator(player,active) turn_player=player end
clip=noop;pal=noop;sprgrid=noop;coop_draw_empty_soul_slot=noop
function winspec() end
function onlinecoop_campaign_draw() return false end
function onlinecoop_draw_scene_frame() return false end
function onlinecoop_has_board_frame() return true end
function onlinecoop_playback_busy() return false end
function onlinecoop_events_busy() return false end
function onlinecoop_signals_hint() end
function onlinecoop_draw_board_frame() end
function onlinecoop_playback_hint() end
function time() return 0 end
function onlinecoop_choices_draw() choice_drawn=true end
onlinecoop_lan={status="connected"}
mode={id="coop",net={role="client",peer_ok=true}}
''')
for name in ('campaigns/rebel_knight.lua','net_view.lua','net_playback.lua'):
    lua.execute((ROOT/name).read_text(encoding='utf-8'))
lua.execute('''
assert(coop_duel_name()=="Revolutionary Knight")
mode.net.role="host";assert(coop_duel_name()=="Rebel Knight")
mode.net=nil;assert(coop_duel_name()=="Rebel Knight")
mode.net={role="client",peer_ok=true}
current_lang="simplified_chinese";assert(coop_duel_name()=="革命骑士")
assert(coop_duel_name(false)=="反叛骑士");current_lang="english"
local p={7,2,3,0,1,3,0,2,7,0}
onlinecoop_draw_piece_health(p,75,88)
assert(#hearts==7 and #texts==0 and #bars==0)
for i,h in ipairs(hearts) do assert(h[1]==(i<=3 and 8 or 11)) end
assert(hearts[1][3]==88 and hearts[6][3]==92)
p[6]=10;p[9]=10;reset_draw();onlinecoop_draw_piece_health(p,75,88)
assert(#hearts==10 and #texts==0)
p[6]=7;p[9]=11;reset_draw();onlinecoop_draw_piece_health(p,75,88)
assert(#hearts==0 and #bars==2 and texts[1][1]=="7&" and face=="default")
p[4]=6;p[9]=10;reset_draw();onlinecoop_draw_piece_health(p,75,88)
assert(#hearts==0 and texts[1][1]=="7&")
reset_draw();onlinecoop_draw_piece_health(nil,75,152);assert(#hearts==1 and hearts[1][1]==11)
local original={2,0,6,1,0,1,0,0,1,0}
local rebel={8,2,2,20,1,37,0,0,40,0}
local s={floor=12,turn=4,phase=4,board=1,king=1,knight=2,units={original,rebel},cards={},souls={},moves={},attacks={},ui={}}
for i=1,20 do s.ui[i]=0 end
local own,duel=onlinecoop_net_own_piece(s);assert(own==rebel and duel)
assert(onlinecoop_net_piece_name(rebel)=="Revolutionary Knight")
assert(onlinecoop_net_hover_piece(s,96+3*16+8,30+3*16+8,96)==rebel)
assert(onlinecoop_net_hover_piece(s,96+4*16+8,30+3*16+8,96)==nil)
-- A buffered animation's 37 HP must win over an already-arrived 9 HP snapshot.
local future={floor=12,units={{8,2,2,20,1,9,0,0,40,0}}}
mode.net.snapshot=future;mode.net.clip_client={floor=12,snapshot=s};mode.net.remote_choices={kind=2}
reset_draw();onlinecoop_net_draw_client()
local hp,own_label,name=false,false,false
for _,t in ipairs(texts) do
 if t[1]=="37&" then hp=true;assert(t[3]==153) end
 if t[1]=="Your HP" then own_label=true end
 assert(not string.find(tostring(t[1]),"2P /",1,true))
 assert(t[1]~="9&" and not string.find(tostring(t[1]),"37/40",1,true))
end
assert(hp and own_label and turn_player==nil and choice_drawn)
-- Normal 1-HP Knight shows health only in its hover panel.
s.units={original};s.phase=2;mode.net.snapshot=s;mode.net.clip_client=nil;mode.net.remote_choices=nil
assert(onlinecoop_net_own_piece(s)==original)
mode.net.mouse_x=104;mode.net.mouse_y=30+6*16+8
onlinecoop_draw_net_piece=noop
reset_draw();onlinecoop_net_draw_client();assert(#hearts==1)
for _,t in ipairs(texts) do assert(t[1]~="Your HP") end
mode.net.mouse_x=0;mode.net.mouse_y=0
reset_draw();onlinecoop_net_draw_client();assert(#hearts==0)
-- Retiring the Knight never leaves the former Boss's health on another floor.
s.units={};reset_draw();onlinecoop_net_draw_client();assert(#hearts==0)
''')
print('PASS: perspective names, native 10-heart threshold and bar, own/big-piece hover, buffered HP, choice HUD and death reset')
