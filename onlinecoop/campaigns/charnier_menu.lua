local function trig_achievement() end
-- Native Charnier menu adapted to co-op; progress is separate from vanilla.
setup={
	slots_max={10,10},
}

base={
	pawn_global_promote=1, surrender=1,
	gain={0,0,0,1,5,2},
	ai_lvl=0,
	
	chamber_max=2,
	firepower=4,
	firerange=3,
	spread=55,
	ammo_max=6,
	
}

BURDENS={

	-- HEALTH
	{ n=2, pawn_hp=1, cinders=1  	},
	{ n=2, knight_hp=1  		},
	{ n=2, bishop_hp=1  		},
	{ n=2, rook_hp=1  			},
	{ n=2, queen_hp=2  			},
	{ n=2, king_hp=2  			},
	
	-- ARMY
	{ n=3, gain={0,0,0}  },
	{ n=2, gain={1}  },
	{ n=2, gain={2}  },
	{ n=2, gain={3}, cinders=1  },
	{ n=1, gain={4}, final=1  },
	
	-- BACKUP
	{ n=2, gain={1,0,0,0},			delay=15 },
	{ n=2, gain={1,2},					delay=15 },
	{ n=2, gain={2,2},					delay=15 },
	{ n=2, gain={3},							delay=15 },
	{ n=1, gain={4},	cinders=1,	delay=15 },
	
	-- DUNGEON
	{ n=2, extra_white_choice=1  },
	{ n=5, extra_floor=1 },
	{ n=1, gain={12,12}, 	final=1 },
	{ n=2, gain={13}, 		final=1 },
	{ n=1, gain={1,1,1}, 	final=1 },
	{ n=2, gain={12}  },
	{ n=2, ai_lvl=1  },
	
}

AUGMENTS={
	{ price=1, ammo_max=2 	},
	{ price=1, n=3, ammo_max=1 	},
	{ price=1, n=3, search=1 		},
	{ price=1, n=3, blade=1 	},
	
	{ price=2, n=2, hop=1 	},
	{ price=2, spread=-15 	},
	{ price=2, n=1, soul_slot=1 	},
	{ price=2, n=2, firerange=1 	},
	{ price=2, n=2, grenades_max=1, special="grenade" 	},
	{ price=2, n=1, chamber_max=1 	},
	
	{ price=3, n=2, ammo_regen=1 	},	
	{ price=4, firepower=1 	},

}

CHARNIER_ACH={
	6,	"KINDLED_ATROCITY",	
	10,	"ARCHITECT_OF_RUIN",
	15,	"SOVEREIGN_OF_THE_MASS_GRAVE",
}

-- GAMEPLAY
HOUSE_MAX=3

-- DEV
--INFINITE_CINDERS=1
--CHARNIER_RESET=1
-- REST=true

function initialize()
	newsrf("charnier", "assets/gfx/charnier.png")
	if not SAVE.coop_charnier or CHARNIER_RESET then 
		SAVE.coop_charnier={best_rank=0}
		init_charnier()
	end
	if SAVE.coop_charnier and not SAVE.coop_charnier.ext then
		SAVE.coop_charnier.ext = 0
	end
	mode.burdens=SAVE.coop_charnier.burdens
	
	



	--mode.hide_turn=1
	
end
function init_charnier()	
	local ch=SAVE.coop_charnier
	ch.burdens={}
	ch.cinders=0
	ch.ext=0
	ch.augments={}
    mode.coop_raid_skills={}
    mode.coop_raid_blade_bonus=0
    mode.ban={}
	for i=0,2 do
		if ch.best_rank>=CHARNIER_ACH[i*2+1] then
			ch.ext=ch.ext+1
		end	
	end	
	ch.ingame,ch.defeat,ch.success=nil
end

-- MENU
function charnier_menu()
	reset()
	--music("charnier_A",0.1)
	
	-- AUDIO
	local shop_vol=0
	lockaudio()
	for i=0,1 do
		local id=i==0 and "charnier_" or "charnier_shop_"
		_music(id.."A",i,false,.1)
		nxtmusic(id.."B",i,true)
		chnlfx(	i, "volume", 1-i )		
	end
	unlockaudio()
	local function switch_music()
		shop_vol=1-shop_vol
		local tempo=60	
		local function f(ev)		
			local c=ev.t/tempo
			local sv=(1-c)*(1-shop_vol)+c*shop_vol
			chnlfx(0, "volume", 1 - sv)
			chnlfx(1, "volume", sv)
		end
		loop(f,tempo)		
	end
	
	
	--
	local ui={}
	fast_tracker(false)
	
	-- SHORTCUTS
	local ch=SAVE.coop_charnier
	local function lay(par,x,y)
		local e=mke(0,x,y)
		add_child(par,e)
		return e
	end	
	local function gply(inc)
		local n=get_pile_lvl(#ch.burdens+(inc or 0))
		return MCH-n*22-14-min(n,1)*14
	end
	
	-- DEV FORCE
	if DEV then
		--local a=ch.burdens
		--a[1]=17
		--ch.cinders=8
		--ch.augments={8,9,10,11}
		--ch.burdens={9,20,9,0,0} --,0,0,0,1,2,3,4,5,5
		--ch.success=1
		--ch.burdens={22,16,17,10,irnd(22),}
		--ch.burdens={17}
		--ch.cinders=0
		--ch.defeat=1
	end
		
	-- GRAPHICS
	local bg=mke()
	bg.dr=function()
		cls(1)
	end
	
	local scene=mke(0)	
	local ground_bg=lay(scene,0,MCH-16)
	ground_bg.dr=function(e,x,y)
		spritesheet("charnier")
		sspr(0,336,320,16,x,y)
		spritesheet("gfx")
	end
	
	-- PILE
	local pile=lay(scene,0,gply())
	local pile_bg=lay(pile)
	pile.cinders={}
	local function add_cinder(x,y)
		local e=mke(0,x or 155,y or -10)
		e.st=irnd(11)
		e.dr=function(e,x,y)
			local fr=flr(e.t/4+e.st)%11		
			spritesheet("charnier")
			sspr(246+fr*6,0,6,12,x,y)
			spritesheet("gfx")
			
			if e.c_new and cyc(2,3)==0 then
			
				circ(x+3,y+10,5,4)
			end
			
		end
		add(pile.cinders,e)
		add_child(pile,e)	
		return e
	end	
	for i=1,ch.cinders do add_cinder() end
	
	local king=lay(pile,155,-10)
	king.upd=function(e)
		local r=16
		srand(33)
		for i=0,#pile.cinders-1 do
			local cin=pile.cinders[i+1]
			local c=.5+i/#pile.cinders
			e.a=c+(e.t/160)+cos(rnd(1)+e.t/(120+rnd(340)))*.16
			local da=rnd(1)+e.t/(120+rnd(240))
			local tx=e.x+3+cos(e.a)*r+cos(da)*4
			local ty=e.y+sin(e.a)*r+sin(da)*4-2
			cin.dx=(tx-cin.x)*.15
			cin.dy=(ty-cin.y)*.15
			cin.x=cin.x+cin.dx
			cin.y=cin.y+cin.dy
		end		
		srand()
	end
	king.dr=function(e,x,y)
	
		if e.c_shake then
			x=x+irnd(5)-2
		end
	
		spritesheet("charnier")
		sspr(0,0,16,17,x,y)
		spritesheet("gfx")
		--pset(x,y,5)
	end

	local mass=lay(pile)
	mass.dr=function(e,x,y)		
		--if ch.rank==0 then return end
		--if pile.twc then x=x+cyc(2,8)  end
		
		-- PILE
		spritesheet("charnier")
		local dh=32
		sspr(0,dh,320,320-dh,x,y+dh)
		sspr(112,0,96,dh,x+112,y)

		-- BURDENS
		for i=1,#ch.burdens do
			local dx,dy=get_burden_pos(i-1)
			local x,y=x+dx,y+dy
			if i<#ch.burdens or not e.c_new or cyc(2,3)==0 then
				sspr(208,0,38,20,x,y)
				local n=ch.burdens[i]
				local px,py=(n%8)*38,360+flr(n/8)*20
				apal(1)
				sspr(px,py,38,20,x+1,y+1)
				pal()
				sspr(px,py,38,20,x,y)
				if BURDENS[n+1].cinders then
					local fr=i<#ch.burdens and 1 or 0
					if fr==0 and ((mass.c_cind and cyc(2,3)==0) or not mass.new_burd ) then
						fr=1
					end
					
					sspr(246,12+fr*4,4,4,x+2,y+2)
				end
				

			end
			
		end
		
		spritesheet("gfx")
		
		
	end	
	
	local ground=lay(scene,0,MCH-16)
	ground.dr=function(e,x,y)
		spritesheet("charnier")
		sspr(0,320,320,16,x,y)
		spritesheet("gfx")
	end

	-- FUNCS
	local init_ui
	local function open_shop()
		switch_music()
		mode.track_but=1
		--_music("charnier_shop_2_A",0,true,nil,0)
	
		local w,h,r=188,128,6
		local th,bh=22,16
		local pan=mke(0,(MCW-w)/2,(MCH-h)/2-MCH)
		local sel,msg,buy
		local orbs={}

		

		--local msg="select an orb"
		pan.upd=function(e)
			local r=r+2
			for i=1,#orbs do for j=i+1,#orbs do				
				local a,b=orbs[i],orbs[j] 
				local dx=a.x-b.x
				local dy=a.y-b.y
				local d=2*r-sqrt(dx*dx+dy*dy)
				if d>0 then
					local an=atan2(dx,dy)
					local dx=cos(an)*d/2
					local dy=sin(an)*d/2
					a.x=a.x+dx
					a.y=a.y+dy
					b.x=b.x-dx
					b.y=b.y-dy
				end				
			end end
		end
		pan.dr=function(e,x,y)
			rectfill(x,y,x+w-1,y+h-1,1)
			rect(x,y,x+w-1,y+h-1,4)
		
			-- hint
			local s=lang.cinders_lefts
			lprint(s,x+w/2,y+3,3,1)
			
			-- cinders
			srand(33)
			spritesheet("charnier")
			for i=0,ch.cinders-1 do
				local x=x+w/2+(i-ch.cinders/2)*12
				local y=y+10.5+cos(t/60+rnd(1))
				local t=t+rnd(50)
				sspr(246+cyc(11,4,t)*6,0,6,12,x,y)
			end
			srand()
			spritesheet("gfx")
			
			-- msg
			--if msg then	lprint(msg,x+w/2,y+h-12,3,1) end

		end
		mv(pan,0,MCH,16)
		pan.twcv=ease_out_back
		
		-- ORBS
		for i=1,#AUGMENTS do
			local ag=AUGMENTS[i]
			for j=1,(ag.n or 1) do
				local orb=mke(0,r+rnd(w-2*r),th+r+rnd(h-th-bh-2*r))
				add_child(pan,orb)
				add(orbs,orb)
				orb.ag=ag
				orb.n=i-1
				orb.a=rnd(1)
				local spd=.2
				orb.upd=function(e)
					e.a=e.a+hrnd(.02)
					e.vx=cos(e.a)*spd
					e.vy=sin(e.a)*spd
					local r=r+2
					if e.x>w-r or e.x<r or e.y>h-r-bh or e.y<th+r then
						e.a=atan2(w/2-e.x,h/2-e.y)
					end
					
				end
				orb.dr=function(e,x,y)
					--x,y=flr(x),flr(y)
					if orb.ag.price>ch.cinders then 
						for i=0,5 do
							pal(i,sget(i,11))
						end
					end
				
					spritesheet("charnier")
					
					-- LIGHT
					local light=orb==sel and cyc(2,3)==0
					if light then
						sspr(272,16,16,16,x-8,y-8)
					end
					
					-- ICON
					coop_raid_draw_brand(e.n,x-6,y-6)
					
					-- LIGHT
					if light then
						sspr(96,8,12,12,x-6,y-6)
					end
					
					-- price
					if orb==sel then
						for i=1,ag.price do
							local r=9
							local a=.25+(i-1-(ag.price-1)/2)*.1
							local x=flr(x)+cos(a)*r
							local y=flr(y)+sin(a)*r
							sspr(253+irnd(2),16,2,3,x-1,y-2)
						end
					end
					
					
					spritesheet("gfx")
					pal()
				end
				--
				local s=coop_raid_brand_desc(i-1)
				local b=mk_hint_but(-6,-6,12,12,s)
				b.track=0
				b.pad_cursor=1
				b.left_clic=function()
					if orb.ag.price>ch.cinders then
						return
					end
					if sel==orb then 
						sel=nil
						buy.but.locked=1 
						sfx("charnier_orb_in")
						return
					end
					sel=orb
					buy.but.locked=nil
					sfx("charnier_orb_out")
					
				end				
				add_child(orb,b)
			end
		end
		for n in all(coop_raid_owned_brands()) do
			for orb in all(orbs) do
				if orb.n==n then 
					del(orbs,orb)
					kl(orb) 
					break
				end
			end
		end
				
		-- BUTS
		local a={
			"claim",
			"back"
		}
		local function act(id)
		
			local function out()
						
				local function f()
					switch_music()
					kl(pan)
					init_ui()
				end
				mv(pan,0,-MCH,8,f)
				pan.twcv=ease_in
			end
		
			if id=="back" then
				sfx("menu_out",.7)
				remove_buts()		
				out()
			end
			if id=="claim" then
				if not sel then
					sfx("wrong")
					return
				end
				if not coop_raid_buy_brand(sel.n) then
                    sfx("wrong")
                    return
                end
				
				for i=1,sel.ag.price do
					local e=pile.cinders[#pile.cinders]
					kl(e)
					del(pile.cinders,e)
				end

				
				kl(sel)
				sel=nil
				buy.but.locked=1
				sfx("charnier_buy")
				if ch.cinders==0 then
					remove_buts()		
					wait(30,out)
				end
				
			end
		
		end
		for i=1,2 do
			local bw,ec=48,2
			local id=a[i]
			local x=(w-bw*#a-(ec*#a-1))/2+(i-1)*(bw+ec)
			local b=mk_text_but(flr(x),h-14,bw,get_lang(id),bind(act,id))
			b.but.track=0
			add_child(pan,b)
			if id=="claim" then buy=b end
			
			if id=="back" then
				b.upd=function()
					if b.t>10 and btnp("cancel") then
						if pad_cursor then
							pad_cursor.sel={b=b.but,x=b.x,y=b.y}
						end
						mx,my=b.x,b.y
						b.ov=true
						b.upd=nil
						b.but.clicked=true
						-- doesn't become red
						act(id,b)
					end
				end
			end
		end
		buy.but.locked=1
		
	end
	local function reset_pile()
		local function f()
			init_charnier()
			init_menu()
		end
		fade_to(-4,16,f)	
	end	
	local function rmv_ui()		
		for e in all(ui) do
			kl(e)
		end
	end
	function init_ui()

		local ec=max(32-#ch.burdens,3)
		local function slide_in(e,s,t)
			add(ui,e)
			e.x=e.x+MCW/2*s
			local function f()
				mv(e,-s*MCW/2,0,16)
				e.twcv=ease_out_back
			end
			wait(t or 1,f)
		end
		local function act(id,but)
			if id=="next raid" then
					remove_buts()
					sfx("menu_in")
					ch.ingame=1
					fade_to(-5,32,next_raid)			
			end
			if id=="back" then
				remove_buts()
				sfx("menu_out")
				music(nil,1)
				music()
				fade_to(-5,32,init_menu)
			end
			if id=="brands" then
				sfx("menu_in")
				remove_buts()
				rmv_ui()
				open_shop()
			end

			if id=="resign" then
				sfx("menu_out")
				if but.chk_done then
					remove_buts()
					reset_pile()
				else					
					but.chk_done=1
					but.txt=get_lang("sure")
				end
			
			end			

			
		end

		-- RANKS + CINDERS
		for i=1,2 do
			local pan=mke(0,ec,ec+(i-1)*14)
			local w,h=64,11
			pan.dr=function(e,x,y)
				rectfill(x,y,x+w-1,y+h-1,2)
				rect(x,y,x+w-1,y+h-1,3)
				
				local s,cl=lang.rank..": "..#ch.burdens,4
				if i==2 then
					local n=ch.cinders
					if scene.c_cinder_lost then
						n=ch.cinders+1
						cl=4+cyc(2,3)
					end
					s=lang.cinders..": "..n
				end				
				lprint(s,x+w/2,y+3,cl,1)
			end
			slide_in(pan,-1,i*4-3)
		end
		
		-- AUGMENTS
		local ax=ec
		for n in all(coop_raid_owned_brands()) do
			local e=mke(0,ax,ec+28)
			e.dr=function(e,x,y)
				spritesheet("charnier")
				coop_raid_draw_brand(n,x,y)
				spritesheet("gfx")
			end
			slide_in(e,-1,9)
			ax=ax+14
			
			-- HINT
			local s=coop_raid_brand_desc(n)
			local b=mk_hint_but(0,0,12,12,s)
			b.track=0
			b.pad_cursor=1
			add_child(e,b)			
			
		end
		
		-- BUTTONS
		local a={
			"next raid",			
			"back",
		}
		if ch.cinders>0 then add(a,"brands",2) end
		if #ch.burdens>0 then add(a,"resign") end
		for i=1,#a do
			local id,b=a[i]
			local function f() act(id,b) end
			b=mk_text_but(MCW-64-ec,ec+(i-1)*14,64,get_lang(id),f)
			b.but.track=0
			slide_in(b,1,i*4-3)
			
			if id=="back" then
				b.upd=function()
					if b.t>10 and btnp("cancel") then
						if pad_cursor then
							pad_cursor.sel={b=b.but,x=b.x,y=b.y}
						end
						mx,my=b.x,b.y
						b.ov=true
						b.upd=nil
						b.but.clicked=true
						act(id,b)
					end
				end
			end
			
			-- need to start on play button
			
			if i==1 and not MOUSE then
				mode.track_but=0
				track_but_ctrl()
				pad_cursor.sel={b=b.but,x=b.x,y=b.y}
				mx,my=b.x,b.y
			end
		end
		

		-- HINTS
		for i=1,#ch.burdens do
			local x,y=get_burden_pos(i-1)
			local s=get_desc(BURDENS[ch.burdens[i]+1])
			local b=mk_hint_but(x,y,38,20,s)
			b.track=0
			b.pad_cursor=1
			add_child(mass,b)
		end

		-- CHK ACH
		if ch.cinders>=5 then trig_achievement("CINDERLORD") end

		--					
		mode.track_but=1

	end

	local function new_burden()
		mass.new_burd=1
		local free={}
		for i=1,#BURDENS do
			for n=1,(BURDENS[i].n or 1) do add(free,i-1) end
		end
		for n in all(ch.burdens) do del(free,n) end
		local n=steal(free)
		
		
		-- NEW CINDER
		function new_cinder()
			if not BURDENS[n+1].cinders then
				init_ui()
				return
			end
			local function ad()
				ch.cinders=ch.cinders+1
				sfx("cinder_new")
				mass.new_burd=nil				
				mass.cind_add=nil				
				x,y=get_burden_pos(#ch.burdens-1)				
				local p=add_cinder(x,y-6)				
				
				local function f()
					
					p.c_new=60
					init_ui()
				end
				wait(16,f)
			end
			local function blink()				
				mass.c_cind=60
				wait(mass.c_cind,ad)
				sfx("give_cinder")
			end
			
			wait(30,blink)
			
		end

		-- ADD
		sfx("burden_new")
		local a=clone(ch.burdens)
		add(a,n)
		ch.burdens=a
		ch.best_rank=max(#a,ch.best_rank or 0)
		mass.c_new=32
		wait(32,new_cinder)
		
		-- ACH
		for i=0,2 do
			if #ch.burdens==CHARNIER_ACH[i*2+1] then 
				trig_achievement(CHARNIER_ACH[i*2+2]) 
			end
		end
		
		--[[
		if #ch.burdens==6 then trig_achievement("KINDLED_ATROCITY") end
		if #ch.burdens==10 then trig_achievement("ARCHITECT_OF_RUIN") end
		if #ch.burdens==15 then trig_achievement("SOVEREIGN_OF_THE_MASS_GRAVE") end
		--]]
		
		
	end
	local function climb()

		-- CLIMB
		local ty=gply(1)
		if ty<pile.y then
			local function new_cinder()
				ch.cinders=ch.cinders+1
				sfx("cinder_new")
				local p=add_cinder()		
				p.c_new=60
				wait(60,new_burden)
			end
		
		
			mvt(pile,0,ty,80,new_cinder)
			pile.twcv=ease_in_out
		else
			new_burden()
		end	
	end
	local function launch()
		function bounce_pile(e,smx,smy)
			local dx=e.x-smx
			local dy=e.y-smy	
			local avy=abs(e.vy)
			if abs(dx)<dy then
				e.vy=-avy*.75
				e.x=smx+sgn(dx)*dy				
				e.vx=(.15+avy)*.25*sgn(dx)		
				_sfx("pile_bounce",nil,min(avy,.5+rnd(.5)),nil, 1+hrnd(.4) )
			end	
		end
		
		
		-- SUCCESS
		if ch.success then
			for i=0,15 do
				local function pop()
					sfx("piece_fall",rnd(.45) )
					local r=32+get_pile_lvl()*16
					local p=lay(bg,160+hrnd(r),-16)
					local n,a,va=1+irnd(5),rnd(1),hrnd(.05)
					p.dp=-irnd(3)
					p.we=.1+rnd(.1)+p.dp/80
					p.frict=.98
					p.upd=function(e)
						a=a+va
						smx,smy=160,pile.y
						bounce_pile(e,smx,smy)
						
						if p.y>MCH then
							kl(p)
							if ch.success then
								ch.success=nil
								climb()
							end
						end
						
						
					end				
					p.dr=function(e,x,y)
						pal_inc(p.dp)
						spritesheet("charnier")
						sprgrid(16,16)
						aspr(n,x,y,a)
						spritesheet("gfx")
						pal()
					end	
				end
				wait(i*6+irnd(3),pop)
			end
				
		-- DEFEAT
		elseif ch.ingame or ch.defeat then
			ch.ingame,ch.defeat=nil
			sfx("cinder_red")
			-- LOOSE LIFE || LOOSE GAME
			if ch.cinders>0 then	
				if INFINITE_CINDERS then
					init_ui()
					return
				end
			
				scene.c_cinder_lost=60
				ch.cinders=ch.cinders-1
				local function f()
					sfx("cinder_vanish")
					local e=pile.cinders[#pile.cinders]
					for i=0,7 do
						local p=lay(pile_bg,e.x+3+hrnd(2),e.y+4+rnd(6))
						p.life=36+rnd(30)
						p.blink=16
						p.we=-rnd(1)/40
						p.vx=e.dx*rnd(1)
						p.vy=e.dy*rnd(1)
						p.frict=.98
						p.dr=function(e,x,y)
							pset(x,y,5)
						end
						
					end
					
					del(pile.cinders,e)
					kl(e)
				end
				wait(60,f)
				init_ui()
			else
				local function debrief()
					local pan=lay(pile_bg,MCW/2,8)
					pan.upd=function(e)
						if mcl then
							pan.upd=nil
							reset_pile()
						end
					end
					pan.dr=function(e,x,y)
						rectfill(x-32,y-3,x+32,y+16,1)
						lprint(get_lang("game_over"),x,y,5,1)	
						lprint(get_lang("rank")..": "..#ch.burdens,x,y+8,3,1)
					end					
					if #ch.burdens>=16 then
						add_child(scene,pan)
						pan.y=-16
						mv(pan,0,24,64)
					else
						mv(pan,0,-32,64)
					end	
					
				
				end
				local function xpl()
					sfx("charnier_xpl")
					kl(king)
					local cx,cy=king.x+4,king.y+4
					-- BALL
					local b=lay(pile_bg,cx,cy)
					b.life=16
					b.dr=function(e,x,y)
						local r=pow(b.life/16,.5)*12
						circfill(x,y,r,min(4+e.t/4,5))
						circ(x,y,r+e.t^2,5)
					end
					-- PARTS
					local smx,smy=160,0
					for i=0,12 do
						local p=lay(irnd(2)==0 and pile or pile_bg,cx+hrnd(8),cy+hrnd(8))
						local px,py=24+(i%7)*8,48
						p.vx=hrnd(1.5)
						p.vy=-1-rnd(3)
						p.we=.1+rnd(.1)
						p.frict=.99
						p.life=60+rnd(120)
						p.blink=30
						p.upd=function(e)
							bounce_pile(e,smx,smy)
						end
						p.dr=function(e,x,y)
							--circfill(x,y,5,5)
							--line(smx,smy,smx+100,smy+100,5)
							--line(smx,smy,smx-100,smy+100,5)
							--pset(smx,smy,5)
							colorize_piece(e)
							sspr(px,py,8,8,x-4,y-4)
							pal()
						end
					end
					for i=0,15 do
						local a=i/16
						local pw=rnd(1)
						local vx,vy=cos(a)*pw*8,sin(a)*pw*8
						local p=lay(pile_bg,cx+vx,cy+vy)
						p.vx=vx
						p.vy=vy
						p.life=60+rnd(60)
						p.frict=.92
						p.we=rnd(1)/20
						local lim=16+rnd(16)
						p.dr=function(e,x,y)
							if cyc(2,3)==0 then
								pset(x,y,5)
							end
							if e.t<lim then pset(x,y,4) end
						end
						
						
						
					end
					
					
					-- 
					wait(60,debrief)
				end
				sfx("charnier_will_xpl")
				king.c_shake=32
				wait(32,xpl)
			
			end
		
		-- EXTRA CINDER
		elseif ch.ext>0 then

			ch.ext=ch.ext-1
			local p=add_cinder()
			p.c_new=120
			ch.cinders=ch.cinders+1
			sfx("cinder_new")		
			wait(120,launch)
			
			local p=lay(king,8,-24)
			p.life=60
			p.blink=20
			p.dr=function(e,x,y)
				local s=get_lang("ach_"..CHARNIER_ACH[ch.cinders*2] ) -- crash if ...
				lprint(s,x,y-p.t/10,4,1)
			end

			
			
		else
			init_ui()	
		end
	end
	
	-- LAUNCH
	fade_to(0,DEV and 4 or 32,launch,-4)
	
	
end
function get_pile_lvl(rank)
	local pile_lvl=0
	local lim=0
	rank=rank or #SAVE.coop_charnier.burdens
	while rank>lim do
		pile_lvl=pile_lvl+1
		rank=rank-lim
		lim=lim+1
	end
	return pile_lvl
end
function get_burden_pos(index, w, h, ec)

	w,h,ec=38,20,2
	local mr=7

	local row,count=0,0
	while count+min(row,mr)+1 <= index do
		row=row+1
		count=count+1+min(row-1,mr)
	end

	-- Position dans la ligne
	local col=index-count
	local lw=(min(row,mr)+1)*w+min(row,mr)*ec

	local x = 160-lw/2+col*(w+ec)
	local y = 20+row*(h+ec)	
	return x, y
end

