-- Rival Knight: 2P controls a native enemy boss during its alt_move phase.
COOP_DUEL_ENDINGS={king={32,6,7},knight={33,34,35}}
function coop_duel_live()
 local d=mode and mode.coop_duel
 return d and not d.finished and d.boss and d.boss.hp>0 and not d.boss.dead and d.boss or nil
end
function coop_duel_aligned(e,sq)
 if not e or not e.sq or not sq then return end
 local x,y=e.sq.px,e.sq.py
 if sq.px>=x and sq.px<=x+1 then
  if sq.py<y then return 0,-1 elseif sq.py>y+1 then return 0,1 end
 elseif sq.py>=y and sq.py<=y+1 then
  return sq.px<x and -1 or 1,0
 end
end
function coop_duel_footprint(e,x,y,allow_king)
 for dy=0,1 do for dx=0,1 do
  local sq=gsq(x+dx,y+dy)
  if not sq or sq.moat or coop_has_barricade(sq) then return false end
  local p=coop_piece_on_square(sq) or sq.p
  if p and p~=e and not (allow_king and p==hero) then return false end
 end end
 return true
end
function coop_duel_contains(sq,x,y)
 return sq and sq.px>=x and sq.px<=x+1 and sq.py>=y and sq.py<=y+1
end
function coop_duel_hops(e)
 local a={}
 for _,v in ipairs({{4,2},{4,-2},{-4,2},{-4,-2},{2,4},{2,-4},{-2,4},{-2,-4}}) do
  local x,y=e.sq.px+v[1],e.sq.py+v[2]
  if coop_duel_footprint(e,x,y,true) then a[#a+1]=gsq(x,y) end
 end
 return a
end
function coop_duel_path(e,dx,dy)
 local path={}
 for n=1,7 do
  local x,y=e.sq.px+dx*n,e.sq.py+dy*n
  if not coop_duel_footprint(e,x,y,true) then break end
  path[#path+1]=gsq(x,y)
 end
 return path
end
function coop_duel_close(e,sq)
 if not e or not e.sq or not sq then return false end
 local dx=max(max(e.sq.px-sq.px,0),sq.px-e.sq.px-1)
 local dy=max(max(e.sq.py-sq.py,0),sq.py-e.sq.py-1)
 return max(dx,dy)==1
end
function coop_duel_danger()
 local e=coop_duel_live()
 if not e or not is_coop_active() or e.stun or e.fear or e.peace then return end
 local d=mode.coop_duel
 local targets={}
 for _,sq in ipairs(squares) do if coop_duel_close(e,sq) then targets[sq]=true end end
 local a=d.aim and coop_duel_path(e,d.aim[1],d.aim[2]) or {}
 if d.hop and coop_duel_footprint(e,d.hop.px,d.hop.py,true) then a={d.hop} end
 for _,anchor in ipairs(a) do for dy=0,1 do for dx=0,1 do
  targets[gsq(anchor.px+dx,anchor.py+dy)]=true
 end end end
 for sq in pairs(targets) do
  local seen=false
  for _,p in ipairs(sq.danger or {}) do if p==e then seen=true end end
  if not seen then add(sq.danger,e) end
 end
end
function coop_duel_reinforce()
 local count=0
 for _,x in ipairs({3,4,2,5,1,6,0,7}) do
  local sq=gsq(x,0)
  if count<2 and sq and is_free(sq) and not coop_piece_on_square(sq)
   and not sq.moat and not coop_has_barricade(sq) then
   local p=new_piece(0,true,sq);p.ready=false;p.cd=0;fx_spawn(p);count=count+1
  end
 end
end
function coop_duel_finish(winner)
 local d=mode.coop_duel
 if not d or d.finished then return end
 d.finished=true;d.input=false
 if winner=="king" and mode.coop_stats then
  mode.coop_stats.knight_deaths=(mode.coop_stats.knight_deaths or 0)+1
 end
 remove_buts()
 mode.coop_ending_kind="duel_"..winner
 mode.coop_ending_knight_alive=winner=="knight"
 coop_freeze_throne_result()
 local run=mode
 local function ending()
  if mode~=run or mode.coop_duel~=d then return end
  music("ending_A",0)
  fade_to(-4,30,function()
   if mode~=run or mode.coop_duel~=d then return end
   coop_start_story(true,function() coop_show_run_stats(winner=="king") end)
  end)
 end
 if winner=="knight" then wait(60,ending) else ending() end
end
function coop_duel_complete(e)
 local d=mode.coop_duel
 if not d or d.finished or e~=coop_duel_live() then return end
 d.input=false;d.busy=false
 remove_buts()
 mode.coop_run_active=true
 coop_duel_reinforce()
 opp_move()
end
-- The second action is automatic: it consumes the already locked plan.
-- Native alt_move/action_turn owns scheduling; no extra click or timer owns it.
function coop_duel_execute(e)
 local d=mode.coop_duel
 if not d or d.finished or d.busy or e~=coop_duel_live() or not (d.aim or d.hop) then return end
 d.busy=true;d.input=false;mode.coop_run_active=false;remove_buts()
 if d.aim then
  coop_duel_charge(e)
 else
  local target=d.hop;d.hop=nil
  if not coop_duel_footprint(e,target.px,target.py,true) then coop_duel_complete(e);return end
  if coop_duel_contains(hero.sq,target.px,target.py) then
   mode.coop_run_active=true;coop_duel_reinforce();xpl_king(hero)
  else
   move_piece(e,target,function() if mode.coop_duel==d then coop_duel_complete(e) end end)
  end
 end
end
function coop_duel_commit(e,sq,aim)
 local d=mode.coop_duel
 if not d or not d.input or d.busy or d.aim or d.hop
  or mode.coop_pause_menu_open or e~=coop_duel_live() then return end
 d.busy=true;d.input=false;remove_buts()
 if aim then
  local dx,dy=aim[1],aim[2]
  if abs(dx)+abs(dy)~=1 then d.busy=false;coop_duel_offer(e);return end
  d.aim={dx,dy};d.aim_started=time()
  sfx("reload")
  wait(20,function() if mode.coop_duel==d then coop_duel_complete(e) end end)
 elseif sq and coop_duel_footprint(e,sq.px,sq.py,true) then
  local legal=false
  for _,target in ipairs(coop_duel_hops(e)) do if target==sq then legal=true end end
  if not legal then d.busy=false;coop_duel_offer(e);return end
  d.hop=sq
  sfx("reload")
  wait(20,function() if mode.coop_duel==d then coop_duel_complete(e) end end)
 else coop_duel_complete(e) end
end
function coop_duel_tear(e,ca)
 local d=mode.coop_duel
 if not d or not d.input or d.busy or mode.coop_pause_menu_open or e~=coop_duel_live()
  or d.round<(d.tear_ready or 3) or not ca or ca.team~=0 or not ca.sl or ca.sl.ca~=ca then return end
 d.busy=true;d.input=false;d.tear_ready=d.round+3
 remove_buts()
 tear_apart(ca,function()
  if mode.coop_duel~=d or d.finished then return end
  d.busy=false
  coop_duel_offer(e)
 end)
end
function coop_duel_offer(e)
 local d=mode.coop_duel
 if not d or d.finished or e~=coop_duel_live() then return end
 if d.aim or d.hop then coop_duel_execute(e);return end
 remove_buts();d.input=true;d.busy=false
 mode.coop_run_active=false
 local choices=coop_duel_hops(e)
 if coop_controller and coop_controller.begin_choices then
  coop_controller.begin_choices(2,function() return mode.coop_duel==d and d.input and not d.busy and not d.finished end)
 end
 local direction_label=2
 local function button(x,y,w,h,click,label,board_hint)
  if coop_controller and coop_controller.choice_button then
   local code=board_hint and 0 or 7
   if label then direction_label=direction_label+1;code=direction_label end
   coop_controller.choice_button(x,y,w,h,code,click)
   return
  end
  local b=mk_but(x,y,w,h,click);b.dp=DP_INTER+1
  b.dr=function(o,px,py)
   if board_hint then return end
   rect(px+1,py+1,px+w-2,py+h-2,o.ov and 4 or 5)
   if label then lprint(label,px+w/2,py+3,4,1) end
  end
 end
 local bx,by=coop_get_board_geometry()
  for i,v in ipairs({{-1,0,"左","Left"},{0,-1,"上","Up"},{0,1,"下","Down"},{1,0,"右","Right"}}) do
   local direction={v[1],v[2]}
   button(bx+(i-1)*32,by+131,32,15,function() coop_duel_commit(e,nil,direction) end,
    current_lang=="simplified_chinese" and v[3] or v[4])
  end
  for _,sq in ipairs(choices) do
   local target=sq
   button(bx+sq.px*16,by+sq.py*16,32,32,function() coop_duel_commit(e,target,false) end,nil,true)
  end
 if d.round>=(d.tear_ready or 3) then
  for _,sl in ipairs(card_slots) do
   local ca=sl.ca
   if ca and ca.team==0 then
    button(sl.x,sl.y,22,29,function() coop_duel_tear(e,ca) end)
   end
  end
 end
 mouse("show",true)
 if _log then _log("[COOP DUEL] 2P action round="..d.round.." planned="..((d.aim or d.hop) and "yes" or "no")) end
end
function coop_duel_charge(e)
 local d=mode.coop_duel
 local dx,dy=d.aim[1],d.aim[2]
 local path=coop_duel_path(e,d.aim[1],d.aim[2]);d.aim=nil;d.aim_started=nil
 local hit_king=false;local destination
 for _,sq in ipairs(path) do
  if coop_duel_contains(hero.sq,sq.px,sq.py) then hit_king=true;break end
  destination=sq
 end
 sfx("charge")
 local function land()
  e.coop_duel_charge_fx=nil
  if mode.coop_duel~=d or e~=coop_duel_live() then return end
  if hit_king then mode.coop_run_active=true;coop_duel_reinforce();xpl_king(hero)
  else coop_duel_complete(e) end
 end
 if destination then
  e.coop_duel_charge_fx={dx=dx,dy=dy,started=time()}
  goto_sq(e,destination,20,land,0)
 else wait(12,land) end
end

-- Called from the piece's own draw pass, so the spear follows its animation
-- coordinates and cannot float above menus. No extra entities or callbacks.
function coop_duel_draw_charge(e,x,y,behind)
 local fx=e.coop_duel_stab_fx or e.coop_duel_charge_fx
 if e~=coop_duel_live() or mode.coop_pause_menu_open then return end
 local elapsed=fx and max(0,time()-fx.started) or 0
 if fx and fx.stab and elapsed>=.48 then fx=nil end
 local idle=not fx
 local aim=mode.coop_duel.aim
 local resting=idle and not aim
 local dx,dy=0,-1
 if fx then dx,dy=fx.dx,fx.dy
 elseif aim then dx,dy=aim[1],aim[2] end
 local rear=resting and e.coop_cavalier_face=="back" or not resting and dy<0
 if behind~=rear then return end
 if not mode.coop_duel_spear_pixels then
  local pixels={};local previous=spritesheet();spritesheet("gfx")
  local colors={[1]=4,[4]=2,[3]=3,[2]=1}
  for sy=0,18 do for sx=0,4 do
   local c=sget(106+sx,72+sy)
   if c and c~=0 then
    pixels[#pixels+1]={u=14-sy,v=sx-2,c=(sx==2 and sy==7) and 5 or (colors[c] or c)}
   end
  end end
  spritesheet(previous);mode.coop_duel_spear_pixels=pixels
 end
 local extension=0
 if fx and fx.stab then
  -- Draw back, thrust, then withdraw; the hit lands at frame 14.
  if elapsed<.12 then extension=-5*elapsed/.12
  elseif elapsed<.24 then extension=-5+15*(elapsed-.12)/.12
  else extension=10*(1-(elapsed-.24)/.24) end
 end
 local hx,hy=x+16+dx*(9+extension),y+18+dy*(8+extension)
 if resting then
  hx=x+(e.coop_cavalier_face=="left" and 4 or 27);hy=y+14
 end
 -- A short forearm connects the shoulder to the grip instead of a floating fist.
 local shoulder=x+(hx<x+16 and 10 or 22)
 for offset=-1,1 do line(shoulder,y+9+offset,hx,hy+offset,1) end
 line(shoulder,y+9,hx,hy,2)
 local scale=mode.coop_duel_spear_scale or 2
 for _,p in ipairs(mode.coop_duel_spear_pixels) do
  local px,py=hx+scale*(dx*p.u-dy*p.v),hy+scale*(dy*p.u+dx*p.v)
  px=px+.5;py=py+.5;px=px-px%1;py=py-py%1
  rectfill(px,py,px+scale-1,py+scale-1,p.c)
 end
 -- The spear remains in the piece pass; ground sparks use the board underlay.
 rectfill(hx-2,hy-2,hx+2,hy+2,1)
 rectfill(hx-1,hy-1,hx+1,hy+1,4)
end
function coop_duel_draw_sparks(e,x,y)
 local fx=e.coop_duel_charge_fx
 if not fx or e~=coop_duel_live() or mode.coop_pause_menu_open then return end
 local elapsed=max(0,time()-fx.started)
 -- Only the lower two squares of the 2x2 footprint emit ground sparks.
 for side=-1,1,2 do for i=0,2 do
  local travel=(elapsed*80+i*3)%9;travel=travel-travel%1
  local sx=x+16-fx.dx*travel-fx.dy*side*15
  local sy=y+24-fx.dy*travel+fx.dx*side*6
  sy=max(y+16,min(y+31,sy))
  local ey=max(y+16,min(y+31,sy-fx.dy*(3+i)))
  line(sx,sy,sx-fx.dx*(3+i),ey,i==0 and 4 or 5)
 end end
end
function coop_duel_install_underlay(e)
 local run=mode;local d=mode.coop_duel
 if d.underlay then return end
 local p=mke(0,0,0);d.underlay=p;p.dp=DP_PIECES-1
 p.dr=function()
  if mode~=run or mode.coop_duel~=d or e~=coop_duel_live()
   or mode.coop_pause_menu_open or mode.coop_hidden_boss_pending then return end
  coop_duel_draw_board()
  coop_duel_draw_sparks(e,e.x,e.y)
 end
end

function coop_duel_stab(e)
 local d=mode.coop_duel;local run=mode;local target=hero
 local dx=target.sq.px-e.sq.px-.5
 local dy=target.sq.py-e.sq.py-.5
 local length=(dx*dx+dy*dy)^.5
 if length==0 then return end
 d.input=false;d.busy=true;mode.coop_run_active=false;remove_buts()
 local fx={dx=dx/length,dy=dy/length,started=time(),stab=true}
 e.coop_duel_stab_fx=fx
 sfx("charge")
 wait(14,function()
  if mode~=run or mode.coop_duel~=d or e~=coop_duel_live() then return end
  d.busy=false;mode.coop_run_active=true
  coop_duel_reinforce();xpl_king(target)
 end)
 wait(29,function()
  if mode==run and e.coop_duel_stab_fx==fx then e.coop_duel_stab_fx=nil end
 end)
end
function coop_duel_action(e)
 local d=mode.coop_duel
 if not d or d.finished or e~=coop_duel_live() or d.action_turn==mode.turns then return false end
 d.action_turn=mode.turns;d.round=d.round+1
 -- Defer until native opp_move has exhausted this piece.
 wait(1,function()
  if mode.coop_duel~=d or e~=coop_duel_live() then return end
  -- Resolve the previous position's close attack. Never hit on arrival.
  if not e.peace and not hero.cloaked and coop_duel_close(e,hero.sq) then
   coop_duel_stab(e)
  else coop_duel_offer(e) end
 end)
 return true
end
function coop_duel_draw_board()
 local e=coop_duel_live();local d=mode and mode.coop_duel
 if not e or mode.coop_pause_menu_open or mode.coop_hidden_boss_pending then return end
 local bx,by=coop_get_board_geometry()
 if d.aim then
  -- Visual sweep only: the entire locked path remains dangerous immediately.
  local elapsed=max(0,time()-(d.aim_started or time()))
  local shown={}
  for i,sq in ipairs(coop_duel_path(e,d.aim[1],d.aim[2])) do
   local age=elapsed-(i-1)*.07
   if age>=0 then
    for oy=0,1 do for ox=0,1 do
     local cell=gsq(sq.px+ox,sq.py+oy)
     if cell and not shown[cell] and not coop_duel_contains(cell,e.sq.px,e.sq.py) then
      shown[cell]=true
      local x,y=bx+cell.px*16,by+cell.py*16
      rect(x+2,y+2,x+13,y+13,age<.09 and 4 or 5)
     end
    end end
   end
  end
 end
 if d.hop then
  rect(bx+d.hop.px*16+1,by+d.hop.py*16+1,bx+d.hop.px*16+30,by+d.hop.py*16+30,5)
 end
 if d.input then
  for _,sq in ipairs(coop_duel_hops(e)) do
   rect(bx+sq.px*16+1,by+sq.py*16+1,bx+sq.px*16+30,by+sq.py*16+30,5)
  end
 end
end
function coop_duel_draw()
 local e=coop_duel_live();local d=mode and mode.coop_duel
 if not e or mode.coop_pause_menu_open or mode.coop_hidden_boss_pending then return end
 local bx,by=coop_get_board_geometry()
 if d.input then
  lprint(current_lang=="simplified_chinese" and "2P 反叛骑士" or "2P Rebel Knight",bx+64,by-12,5,1)
  local cooldown=max(0,(d.tear_ready or 3)-d.round)
  lprint(current_lang=="simplified_chinese" and (cooldown==0 and "可点击黑卡撕毁" or "撕卡冷却："..cooldown)
   or (cooldown==0 and "Click a black card to tear" or "Tear cooldown: "..cooldown),bx+64,by+150,3,1)
 end
end
function coop_duel_lightning(e)
 -- Same lightning geometry and palette as the native horsemen storm.
 fx_red_flash();screen_shake(4);sfx("xpl")
 local p=mke(0,e.x+8,e.y+10);local a={};local x,y=p.x,p.y;local ec=8
 while y>-32 do
  a[#a+1]={x=x,y=y};x=x+hrnd(ec);y=y-8-rnd(16+ec);ec=ec*1.5
 end
 p.life=10;p.dp=DP_FX
 p.dr=function(o,px,py)
  for _,v in ipairs(a) do line(px,py,v.x,v.y,sget(o.life,1));px,py=v.x,v.y end
 end
end
function coop_begin_duel()
 local run=mode;local knight=mode.coop_knight
 local d={round=0,tear_ready=3};mode.coop_duel=d
 local function current() return mode==run and mode.coop_duel==d and not d.finished end
 local cards={}
 for _,id in ipairs({"Guillotine","Revolution"}) do
  local ca=get_slot_card(id);if ca then cards[#cards+1]={ca=ca,dr=ca.dr,x=ca.x+10,y=ca.y+14} end
 end
 local function transform()
  if not current() then return end
  local origin=knight.sq
  leave_sq(knight);kl(knight)
  mode.coop_knight=nil;mode.coop_selected="king"
  local sq
  if origin and coop_duel_footprint(nil,origin.px,origin.py,false) then sq=origin end
  if not sq then sq=coop_marshal_spawn_square() end
  if not sq then coop_finish_throne_story();return end
  local typ
  for _,def in ipairs(PIECES) do if def.name=="rebel_knight" then typ=def.type end end
  local e=new_piece(typ,true,sq);d.boss=e;e.cd=1;e.ready=true
  coop_duel_install_underlay(e)
  e.alt_move=function() return coop_duel_action(e) end
  fx_spawn(e);inter.bossfight=1;start_music("boss_queen_A")
  wait(60,function() if current() then clean_up(refill_ammo) end end)
 end
 local function speech()
  if not current() then return end
  coop_duel_lightning(knight)
  fx_emote(knight,current_lang=="simplified_chinese" and "打倒独裁" or "Down with tyranny!",75,function()
   if not current() then return end
   coop_duel_lightning(knight)
   fx_emote(knight,current_lang=="simplified_chinese" and "为了公道" or "For justice!",75,transform)
  end)
 end
 local consumed=false
 local function consume_cards()
  if not current() or consumed then return end
  consumed=true
  for _,v in ipairs(cards) do
   v.ca.dr=v.dr;if v.ca.sl and v.ca.sl.ca==v.ca then v.ca.sl.ca=nil end;kl(v.ca)
  end
  build_stack()
 end
 -- Cinematic pawns deliberately do not enter bads or square occupancy. Calling
 -- fire()/xpl() here would run card, soul and turn hooks during the transition.
 local function citizens()
  if not current() then return end
  local actors={};local sites={}
  local function consider(x,y)
   local sq=gsq(x,y)
   if #sites<2 and sq and is_free(sq) and not coop_piece_on_square(sq)
    and not sq.moat and not coop_has_barricade(sq) then sites[#sites+1]=sq end
  end
  -- Prefer either side of the King, then the other adjacent squares.
  for _,v in ipairs({{-1,0},{1,0},{0,-1},{0,1},{-1,-1},{1,-1},{-1,1},{1,1}}) do
   consider(hero.sq.px+v[1],hero.sq.py+v[2])
  end
  if #sites<2 then
   for radius=2,7 do for oy=-radius,radius do for ox=-radius,radius do
    if max(abs(ox),abs(oy))==radius then consider(hero.sq.px+ox,hero.sq.py+oy) end
   end end end
  end
  if #sites<2 then consume_cards();speech();return end
  local king=hero
  local old_aim=aim
  local home_x,home_y,home_z=king.x,king.y,king.z or 0
  -- Reuse spawn_horsemen.kill_next's 16-frame windup, crusher jump,
  -- and 30-frame rebound, without goto_sq's gameplay/on-move hooks.
  local function jump(x,y,crushing,nxt)
   if not current() then return end
   local duration=TEMPO
   local start_z=king.z or 0
   mvt(king,x,y,duration,function()
    if not current() then return end
    king.z=crushing and -10 or 0
    nxt()
   end)
   loop(function(ev)
    if not current() then return end
    local c=ev.t/duration
    -- mvt's completion owns the exact final height and starts the rebound.
    if c>=1 then return end
    king.z=start_z*(1-c)-sin(c/2)*8-(crushing and 10*c or 0)
   end,duration)
  end
  local function crush_next(index)
   if not current() then return end
   local p=actors[index]
   if not p then
    aim=old_aim
    jump(home_x,home_y,false,function()
     king.z=home_z
     -- Let the two executions settle before the Knight's reaction.
     wait(60,function() if current() then speech() end end)
    end)
    return
   end
   aim=p
   wait(16,function()
    if not current() then return end
    jump(p.x,p.y,true,function()
     sfx("xpl");screen_shake(3)
     for i=0,6 do fx_crumb(p,i) end
     kl(p);aim=nil
     loop(function(ev)
      if not current() then return end
      local c=ev.t/30
      king.z=(c-1)*10-sin(c/2)*12
     end,30,function()
      if not current() then return end
      king.z=0
      crush_next(index+1)
     end)
    end)
   end)
  end
  local function talk()
   if not current() then return end
   fx_emote(actors[1],current_lang=="simplified_chinese" and "为了自由" or "For freedom!",75,function()
    if not current() then return end
    fx_emote(actors[2],current_lang=="simplified_chinese" and "为了平等" or "For equality!",75,function() crush_next(1) end)
   end)
  end
  local arrived=0
  for i,sq in ipairs(sites) do
   local target=sq;local index=i;local ca=cards[i]
   local light=mke(0,ca and ca.x or target.x+8,ca and ca.y or target.y+8)
   light.dp=DP_FX
   light.dr=function(o,x,y)
    if current() then circfill(x,y,max(12-o.t/2,1)+rnd(2),5) end
   end
   light.twcv=ease_in_out
   mvt(light,target.x+8,target.y+8,90,function()
    if not current() then return end
    kl(light)
    local p=mke(0,target.x,target.y);p.dp=DP_PIECES or DP_FX
    p.type=0;p.bad=true;p.z=0
    p.dr=function(o,x,y)
     if not current() then return end
     spritesheet("gfx");pal_rst()
     spr(432,x,y-2);pal_rst()
    end
    actors[index]=p;arrived=arrived+1
    if arrived==2 then talk() end
   end)
  end
  sfx("show_book")
  -- The card is still visible beneath the new light for twelve frames.
  wait(12,consume_cards)
 end
 local function blink(n)
  if not current() then return end
  for _,v in ipairs(cards) do v.ca.dr=n%2==0 and v.dr or function() end end
  if n<4 then wait(10,function() blink(n+1) end);return end
  storm_all_but({list=1},citizens)
 end
 blink(1)
end
