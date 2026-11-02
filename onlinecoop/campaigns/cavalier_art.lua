-- Original artist atlas: 88x64. Runtime copy only changes PNG palette encoding.
local cavalier_ready=false
-- Source rectangle, neck-center x, bottom row, plume peg x/y.
local heads={front={24,0,9.5,18,9,0},back={24,20,9.5,19,10,1},left={46,0,9.5,18,9,0},right={46,20,8.5,19,8,1}}
-- sx,sy,width,height,optional attachment x,y within the cropped frame.
-- Rear frames attach at their bottom-right stem, unlike the other rows.
local plumes={
 {{69,0,4,10},{73,0,4,10},{77,0,5,10}},
 {{69,12,4,10},{73,12,5,10},{78,12,6,10}},
 {{69,23,4,11},{73,23,3,11},{78,23,3,11}},
 {{69,36,4,10,3,9},{73,36,4,10,3,9},{77,36,5,10,4,9}},
}
function coop_load_cavalier_art()
 cavalier_ready=false
 if not isfile("assets/gfx/cavalier_runtime.png") then return end
 newsrf("coop_cavalier","assets/gfx/cavalier_runtime.png")
 -- Artist spear points left: crop (0,40,36,8), grip on the shaft at (26,43.5).
 local previous=spritesheet();spritesheet("coop_cavalier")
 local pixels={}
 for sy=0,7 do for sx=0,35 do
  local c=sget(sx,40+sy)
  if c and c~=0 then pixels[#pixels+1]={u=26-sx,v=3.5-sy,c=c} end
 end end
 spritesheet(previous)
 if #pixels>0 then mode.coop_duel_spear_pixels=pixels;mode.coop_duel_spear_scale=1 end
 mode.coop_draw_cavalier_art=coop_draw_cavalier_art
 cavalier_ready=true
 if _log then _log("[COOP ART] cavalier body, four heads and twelve plume frames loaded") end
end

function coop_cavalier_pose(e,x,y,now)
 -- A small cosmetic clock freezes on pause without changing combat timing.
 local dt=e.coop_cavalier_clock and max(0,min(.1,now-e.coop_cavalier_clock)) or 0
 e.coop_cavalier_clock=now
 if not mode.coop_pause_menu_open then
  e.coop_cavalier_elapsed=(e.coop_cavalier_elapsed or 0)+dt
 end
 local clock=e.coop_cavalier_elapsed or 0
 local d=mode.coop_duel
 local fx=e.coop_duel_stab_fx or e.coop_duel_charge_fx
 local dx,dy
 if fx then dx,dy=fx.dx,fx.dy
 elseif d and d.boss==e and d.aim then dx,dy=d.aim[1],d.aim[2]
 elseif d and d.boss==e and d.hop and e.sq then
  dx,dy=d.hop.px-e.sq.px,d.hop.py-e.sq.py
 end
 local face=e.coop_cavalier_face or "front"
 if dx and (dx~=0 or dy~=0) then
  if abs(dx)>abs(dy) then face=dx<0 and "left" or "right"
  else face=dy<0 and "back" or "front" end
 end
 e.coop_cavalier_face=face
 local charging=e.coop_duel_charge_fx~=nil
 -- The front idle/jump row is distinct from the rear-facing plume.
 local row
 if face=="front" then row=charging and 3 or 1
 elseif face=="left" or face=="right" then row=2
 elseif face=="back" then row=4 end
 local frame=clock*(charging and 14 or 6);frame=(frame-frame%1)%3+1
 local head=heads[face]
 local bob=sin(clock/2)>.65 and -1 or 0
 if e.c_hit then bob=bob-1 end
 local lean=charging and 2 or 0
 local bx,by=x+4+(dx or 0)*lean,y+2+bob+(dy or 0)*lean
 local hx,hy=bx+11.5-head[3],by+3-head[4]
 return {sx=head[1],sy=head[2],hx=hx,hy=hy,bx=bx,by=by,face=face,
  plume=row and plumes[row][frame] or nil,mirror=row==2 and face=="right",
  -- Rear helmet peg is atlas (34,21), relative (10,1) to its head crop.
  px=hx+head[5],py=hy+head[6],
  free_side=((fx or (d and d.aim)) and (dx or 0)<0 or not fx and not (d and d.aim) and face=="left") and 1 or -1,
  hand_sway=sin(clock/2)>.35 and 1 or (sin(clock/2)<-.35 and -1 or 0),
  row=row,frame=frame}
end

local function draw_free_hand(p,behind)
 if behind~=(p.face=="back") then return end
 local side=p.free_side
 local shoulder=p.bx+(side<0 and 5 or 18)
 local elbow=p.bx+(side<0 and 1 or 22)
 local hx,hy=p.bx+(side<0 and -1 or 24),p.by+14+p.hand_sway
 for offset=-1,1 do
  line(shoulder,p.by+7+offset,elbow,p.by+11+offset,1)
  line(elbow,p.by+11+offset,hx,hy+offset,1)
 end
 line(shoulder,p.by+7,elbow,p.by+11,2)
 line(elbow,p.by+11,hx,hy,2)
 rectfill(hx-2,hy-2,hx+2,hy+2,1)
 rectfill(hx-1,hy-1,hx+1,hy+1,4)
end

function coop_draw_cavalier_art(e,x,y)
 if not cavalier_ready then return false end
 local p=coop_cavalier_pose(e,x,y,time())
 pal_rst()
 coop_duel_draw_charge(e,x,y,true)
 draw_free_hand(p,true)
 spritesheet("coop_cavalier");palt(0,true)
 sspr(0,0,24,30,p.bx,p.by)
 sspr(p.sx,p.sy,22,20,p.hx,p.hy)
 local f=p.plume
 -- Mirror around the attachment, not around the sprite center.
 if f then asspr(f[1],f[2],f[3],f[4],p.px,p.py,0,p.mirror and -1 or 1,1,f[5] or 0,f[6] or f[4]-1) end
 palt();spritesheet("gfx")
 draw_free_hand(p,false)
 coop_duel_draw_charge(e,x,y,false)
 return true
end
