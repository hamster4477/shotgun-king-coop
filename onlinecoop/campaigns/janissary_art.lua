-- Source rectangles in the artist's unmodified 128x103 janissary2.png.
local janissary_ready=false
local janissary_key=0
function coop_load_janissary_art()
 janissary_ready=false
 if not isfile("assets/gfx/janissary_runtime.png") then return end
 newsrf("coop_janissary","assets/gfx/janissary_runtime.png")
 -- PNG alpha is imported as palette index 0; never sample outside its size.
 janissary_key=0
 mode.coop_draw_janissary=coop_draw_janissary
 mode.coop_draw_janissary_move=coop_draw_janissary_move
 mode.coop_draw_marshal_art=coop_draw_marshal_art
 _log("[COOP ART] janissary2 loaded")
 janissary_ready=true
end
local function begin_art()
 if not janissary_ready then return false end
 spritesheet("coop_janissary")
 palt(janissary_key,true)
 return true
end
local function end_art()
 palt();spritesheet("gfx")
end
-- A per-piece cosmetic clock: no game RNG, scheduled actions or damage calls.
local function janissary_idle_gun(e,x,y,now)
 if not e or e.dead or not e.sq then return end
 if not e.coop_gun_idle then
  local seed=(e.sq.px or 0)*3+(e.sq.py or 0)*7
  e.coop_gun_idle={clock=now,elapsed=0,delay=5+seed%4,period=10+seed%5}
 end
 local idle=e.coop_gun_idle
 local dt=max(0,min(.1,now-idle.clock));idle.clock=now
 if not (mode and mode.coop_pause_menu_open) then idle.elapsed=idle.elapsed+dt end
 if e.coop_janissary_shot then
  idle.elapsed=0;idle.delay=idle.period
  return
 end
 local age=idle.elapsed-idle.delay
 if age<0 then return end
 if age>=2 then idle.elapsed=0;idle.delay=idle.period;return end
 -- Draw, briefly hold, then lower the pistol. No muzzle flash or gunshot.
 local lift=max(0,min(1,age/.22,(2-age)/.28))
 lift=lift*lift*(3-2*lift)
 local a=.13-.10*lift
 asspr(1,23,12,6,x+5+cos(a)*3,y+11+sin(a)*3+(1-lift)*3,a,1,1,3,4)
end
function coop_draw_janissary(e,x,y)
 if not begin_art() then return false end
 -- 14x21 standing sprite, feet aligned with the native 16px Knight.
 sspr(0,0,14,21,x+1,y-5)
 local fx=e and e.coop_janissary_shot
 janissary_idle_gun(e,x,y,time())
 if fx then
  local age=time()-fx.started
  if age>=0 and age<.48 then
   local rise=min(1,age/.10)
   local recoil=age>=.12 and age<.24 and (1-(age-.12)/.12)*2 or 0
   local a=fx.angle
   asspr(1,23,12,6,x+5+cos(a)*(3-recoil),y+11+sin(a)*3+(1-rise)*4,a,1,1,3,4)
  else e.coop_janissary_shot=nil end
 end
 end_art();return true
end
function coop_draw_janissary_move(x,y)
 return coop_draw_janissary(nil,x,y)
end
-- Animation owns only rendering data. It never advances a turn, queues an
-- action, changes a square or changes the already advertised attack lane.
local function ease(u)
 u=max(0,min(1,u));return u*u*(3-2*u)
end
local function round_pixel(n) return n-n%1 end
local function active_age(now,started,duration)
 if not started then return nil end
 local age=now-started
 if age<0 or age>=duration then return nil end
 return age
end

function coop_marshal_art_pose(e,x,y,now)
 local dt=e.coop_art_clock and max(0,min(.05,now-e.coop_art_clock)) or 0
 e.coop_art_clock=now
 local hp=e.hp or 0
 if e.coop_art_hp and hp<e.coop_art_hp then e.coop_art_hurt_started=now end
 e.coop_art_hp=hp
 local hurt=active_age(now,e.coop_art_hurt_started,.26)
 local shot=e.coop_art_shot
 local shot_age=shot and active_age(now,shot.started,.60)
 local dx,dy=0,1
 if hero and hero.sq and e.sq then
  dx=hero.sq.px-e.sq.px-.5;dy=hero.sq.py-e.sq.py-.5
 end
 local aiming=e.coop_marshal_phase=="fire" and not e.coop_ray_spent
 if shot_age then dx,dy=shot.dx,shot.dy
 elseif aiming then dx,dy=e.coop_aim_dx or 0,e.coop_aim_dy or 1 end
 if dx==0 and dy==0 then dy=1 end
 local target=atan2(dx,dy)
 local a=e.coop_art_angle or target
 -- Shortest arc; speed is based on elapsed time, not number of draw calls.
 local delta=(target-a+.5)%1-.5
 a=a+max(-dt*.8,min(dt*.8,delta*min(1,dt*12)))
 e.coop_art_angle=a
 local recoil=0
 if shot_age and shot_age<.32 then
  recoil=shot_age<.045 and ease(shot_age/.045) or 1-ease((shot_age-.045)/.275)
 end
 local moving=e.coop_art_move_started~=nil
 local stride=moving and sin((now-e.coop_art_move_started)*3) or 0
 local land=active_age(now,e.coop_art_land_started,.26)
 local landing=land and sin(land/.52)*(1-land/.26)*2 or 0
 local breath=sin(now*.65)*.45
 local flinch=hurt and sin(hurt*14)*(1-hurt/.26)*1.3 or 0
 local ux,uy=cos(a),sin(a)
 local body_x=x-ux*recoil*1.3+stride*.7+flinch
 local body_y=y+breath+landing-(moving and abs(stride)*1.2 or 0)
 local ready=e.coop_aim_started and ease((now-e.coop_aim_started)/.28) or 1
 local lift=aiming and (1-ready)*2 or 0
 -- On the move, lower the muzzle slightly, then settle back into the aim.
 local ga=a-recoil*.018*(ux<0 and -1 or 1)+(moving and stride*.012 or 0)
 local gx=body_x+16+ux*(7-recoil*3)
 local gy=body_y+15+uy*6+lift
 -- Retain a side profile through vertical aim; there is no rear-head art.
 -- Hysteresis avoids alternating left/right from tiny changes near straight up.
 local face_x,face_y=cos(ga),sin(ga)
 if face_x>.30 then e.coop_art_face_side=0
 elseif face_x<-.30 then e.coop_art_face_side=52 end
 local head_row=face_x>.48 and 0 or (face_x<-.48 and 52 or 25)
 if face_y<-.35 then head_row=e.coop_art_face_side or 0 end
 return {x=body_x,y=body_y,a=ga,ux=face_x,uy=face_y,
  gx=gx,gy=gy,front=sin(ga)>=0,flip=cos(ga)<0 and -1 or 1,
  recoil=recoil,shot_age=shot_age,hurt=hurt,
  head_x=body_x+5+flinch*.5,head_y=body_y-16-recoil*.4,
  head_row=head_row,
  eye_lift=sin(ga)<-.65 and -1 or 0}
end

-- Two equal links solve the elbow while both hands stay attached to the gun.
-- A minimum extension keeps sqrt defined; coincident joints use a folded pose.
function coop_marshal_elbow(sx,sy,wx,wy,bend)
 local dx,dy=wx-sx,wy-sy
 local length=sqrt(dx*dx+dy*dy)
 if length<.001 then return sx+bend*5,sy+7 end
 -- Compact resting arms; extend only as far as the fixed gun grips need.
 local link=max(8,length*.5+.3)
 local height=sqrt(max(0,link*link-length*length*.25))
 return (sx+wx)*.5-dy/length*height*bend,
        (sy+wy)*.5+dx/length*height*bend
end
local function limb_segment(ax,ay,bx,by)
 ax=round_pixel(ax);ay=round_pixel(ay);bx=round_pixel(bx);by=round_pixel(by)
 -- One pixel thicker, with a purple underside and the original dark outline.
 for d=-1,2 do
  line(ax+d,ay,bx+d,by,1);line(ax,ay+d,bx,by+d,1)
 end
 line(ax,ay,bx,by,4)
 if abs(bx-ax)>=abs(by-ay) then line(ax,ay+1,bx,by+1,3)
 else line(ax+1,ay,bx+1,by,3) end
end
local function joint(x,y,r)
 x=round_pixel(x);y=round_pixel(y)
 circfill(x,y,r,1);circfill(x,y,r-1,3)
 if r>1 then pset(x-1,y-1,4) end
end
local function arm(sx,sy,wx,wy,bend)
 local ex,ey=coop_marshal_elbow(sx,sy,wx,wy,bend)
 limb_segment(sx,sy,ex,ey);limb_segment(ex,ey,wx,wy)
 joint(sx,sy,2);joint(ex,ey,1)
end
local function hand(x,y)
 x=round_pixel(x);y=round_pixel(y)
 rectfill(x-2,y-2,x+2,y+2,1)
 rectfill(x-1,y-1,x+1,y+1,4)
 line(x-1,y+1,x+1,y+1,3)
end
local function gun_point(p,along,across)
 return p.gx+p.ux*along-p.uy*across*p.flip,
        p.gy+p.uy*along+p.ux*across*p.flip
end
local function rifle_and_arms(p)
 -- Rifle atlas anchor is (7,5). Grip at (7,5), support hand at (16,5).
 local wx,wy=gun_point(p,0,0)
 local pump=0
 if p.shot_age and p.shot_age>.18 and p.shot_age<.52 then
  pump=sin((p.shot_age-.18)/.68)*3
 end
 local fx,fy=gun_point(p,9-pump,0)
 local right=p.ux>=0
 local near_x=p.x+(right and 24 or 8)
 local far_x=p.x+(right and 8 or 24)
 local bend=right and 1 or -1
 arm(far_x,p.y+12,fx,fy,bend)
 arm(near_x,p.y+12,wx,wy,bend)
 asspr(18,74,24,8,p.gx,p.gy,p.a,1,p.flip,7,5)
 hand(fx,fy);hand(wx,wy)
end
local function shot_effect(p)
 if not p.shot_age then return end
 local age=p.shot_age
 local mx,my=gun_point(p,16,-2)
 if age<.09 then
  local extent=age<.045 and 7 or 4
  local ex,ey=mx+p.ux*extent,my+p.uy*extent
  line(mx-p.uy*2,my+p.ux*2,ex,ey,5)
  line(mx+p.uy*2,my-p.ux*2,ex,ey,4)
  line(mx,my,ex,ey,4)
  circfill(mx,my,2,4)
 end
 -- A short ejected casing and two fading smoke pixels, no persistent entities.
 if age>.04 and age<.38 then
  local cx,cy=gun_point(p,2,-3)
  local u=(age-.04)/.34
  cx=cx-p.uy*u*8;cy=cy+p.ux*u*8-u*(1-u)*16
  rectfill(cx,cy,cx+1,cy+1,4)
 end
 if age>.09 and age<.52 then
  local u=(age-.09)/.43
  pset(mx+p.ux*u*6,my+p.uy*u*6-u*5,3)
  if u<.65 then pset(mx+p.ux*u*4+1,my+p.uy*u*4-u*3,2) end
 end
end
function coop_draw_marshal_art(e,x,y)
 if not begin_art() then return false end
 local now=time()
 -- Pause freezes the pose even though the renderer is still called by menus.
 if mode and mode.coop_pause_menu_open and e.coop_art_clock then now=e.coop_art_clock end
 local p=coop_marshal_art_pose(e,x,y,now)
 if not p.front then rifle_and_arms(p) end
 sspr(18,49,24,24,p.x+4,p.y+8)
 local hx,hy=p.head_x,p.head_y
 sspr(69,p.head_row,22,24,hx,hy)
 local eye_y=p.hurt and 43 or ((now*60%180)<7 and 33 or 38)
 if p.head_row==25 then
  sspr(23,eye_y,4,3,hx+6,hy+15+p.eye_lift);sspr(33,eye_y,4,3,hx+13,hy+15+p.eye_lift)
  if (e.c_talk or p.shot_age and p.shot_age<.16) and now*60%12<6 then
   sspr(33,28,4,2,hx+9,hy+19)
  else sspr(24,29,2,1,hx+10,hy+20) end
 elseif p.head_row==0 then sspr(33,eye_y,4,3,hx+14,hy+15+p.eye_lift)
 elseif p.head_row==52 then sspr(23,eye_y,4,3,hx+5,hy+15+p.eye_lift) end
 if p.front then rifle_and_arms(p) end
 shot_effect(p)
 end_art();return true
end
