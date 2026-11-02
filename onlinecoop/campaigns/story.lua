-- Co-op story uses the native vignette timing, typography and skip controls.
-- Frame numbers are zero-based 128x64 rows in assets/gfx/coop_cg.png.
local COOP_CG_SCENES = {
    [20]={frame=3, zh="走马上任：黑王连黑骑士也一并杀死。专属结局文案待补充。", en="Taking office, the Black King kills even his Black Knight. Ending text placeholder."},
    [34]={frame=17, zh="黑骑士胜利结局第二幕，文案待补充。", en="The Knight's victory, part two. Text placeholder."},
    [35]={frame=18, zh="黑骑士胜利结局第三幕，文案待补充。", en="The Knight's victory, part three. Text placeholder."},
    [36]={frame=19, zh="悬赏骑兵路线：进入最终楼层。过场文案待补充。", en="The bounty cavalry route: entering the final floor. Text placeholder."},
    [32]={frame=15, zh="黑王赢得了这场对决。专属结局文案待补充。", en="The Black King wins the duel. Ending text placeholder."},
    [33]={frame=16, zh="黑骑士推翻了黑王。专属结局文案待补充。", en="The Black Knight overthrows the King. Ending text placeholder."},
    [29]={frame=12, zh="黑骑士撕毁了红色圣书。专属结局文案待补充。", en="The Black Knight tears the Red Book apart. Ending text placeholder."},
    [30]={frame=13, zh="黑骑士携圣书离去。专属结局文案待补充。", en="The Black Knight leaves with the Red Book. Ending text placeholder."},
    [31]={frame=14, zh="黑骑士被册封为新的白王。专属结局文案待补充。", en="The Black Knight is crowned the new White King. Ending text placeholder."},
    [27]={frame=10, zh="悬赏元帅败北，专属结局字幕待补充。", en="The champion is defeated. Ending text placeholder."},
    [28]={frame=11, zh="悬赏元帅结局：黑骑士已经死亡，专属字幕待补充。", en="The Marshal falls, but the Black Knight has fallen too. Text placeholder."},
    [26]={frame=9, zh="黑主教结局：黑骑士已经死亡，专属字幕待补充。", en="The Black Bishop ending: the Black Knight has fallen. Text placeholder."},
    [25]={frame=8, zh="铁王后结局：黑骑士已经死亡，专属字幕待补充。", en="The Iron Queen ending: the Black Knight has fallen. Text placeholder."},
    [23]={frame=6, zh="通关时黑骑士仍然存活，结局字幕待补充。", en="The Black Knight survives. Ending text placeholder."},
    [24]={frame=7, zh="通关时黑骑士已经死亡，结局字幕待补充。", en="The Black Knight has fallen. Ending text placeholder."},
    [19]={frame=2, zh="幻影四骑士离去结局字幕占位，待补充。", en="The phantom horsemen depart. Ending text placeholder."},
    [21]={frame=4, zh="黑王随幻影四骑士离去字幕占位，待补充。", en="The King joins the departing horsemen. Text placeholder."},
    [22]={frame=5, zh="幻影黑王结局字幕占位，待补充。", en="Phantom King ending text placeholder."},
    [17]={frame=0, zh="合作开场字幕占位，待补充。", en="Co-op opening subtitle placeholder."},
    [18]={frame=1, zh="黑骑士无死亡通关结局字幕占位，待补充。", en="Deathless Knight ending subtitle placeholder."},
}
local coop_story_frames=20
local vbg

-- Ending text overrides live here instead of modifying the shared lang table.
-- Leave an entry empty to use the original localized text until writing is ready.
local COOP_ENDING_TEXT = {
    [6]={}, [7]={}, [8]={}, [9]={}, [10]={},
    [12]={}, [13]={}, [14]={}, [15]={},
}

function coop_story_caption(id)
    local key=current_lang=="simplified_chinese" and "zh" or "en"
    local custom=COOP_CG_SCENES[id]
    if custom then return custom[key] end
    local override=COOP_ENDING_TEXT[id]
    return (override and override[key]) or lang["vig_"..id]
end

function coop_story_sequence(ending, native_only)
    if ending then
        local stats=mode.coop_stats
        local duel=mode.coop_ending_kind=="duel_king" or mode.coop_ending_kind=="duel_knight"
        local seq={}
        for _,id in ipairs(mode.coop_ending_sequence or {6,7}) do
            if not native_only or not COOP_CG_SCENES[id] then seq[#seq+1]=id end
            if id==27 and not native_only and not mode.coop_variant
                and mode.coop_ending_knight_alive == false then
                seq[#seq+1]=28
            end
            -- Image 8 closes the Bishop-specific scene before its optional
            -- chamber sequence (9,10) and the shared ending (6).
            if id==8 and not native_only and not mode.coop_variant
                and mode.coop_ending_knight_alive == false then
                seq[#seq+1]=26
            end
            if id==13 and not native_only and not mode.coop_variant
                and mode.coop_ending_knight_alive == false then
                seq[#seq+1]=25
            end
            if id==6 and not duel and not native_only and not mode.coop_variant
                and mode.coop_ending_knight_alive ~= nil then
                seq[#seq+1]=mode.coop_ending_knight_alive and 23 or 24
            end
            -- Preserve each native branch, including NEW_JOB ({14}).
            -- The deathless extra belongs after native ending image 6 only.
            if id==6 and not duel and not native_only and not mode.coop_variant
                and stats and stats.knight_deaths==0 then
                seq[#seq+1]=18
            end
        end
        if #seq==0 then return {14} end
        return seq
    end
    if native_only then return {1,2,3} end
    return {1,2,17,3}
end

function coop_load_story_art()
    local art=isfile("assets/gfx/coop_cg_runtime.png")
        and "assets/gfx/coop_cg_runtime.png" or "assets/gfx/coop_cg.png"
    newsrf("coop_story_cg",art)
    local w,h=srfsize("coop_story_cg")
    coop_story_frames=max(1,(h-h%64)/64)
end

function coop_floor12_story_sequence()
    -- Floor-entry CG foreshadows the recipe; the living Warrant Knight is
    -- checked later, at the final white King's death.
    if not mode.coop_variant and has_card("Co-op Warrant") and has_card("Co-op Bounty Cavalry") then
        -- The rival branch has priority if its conditions already hold.
        local k=mode.coop_knight
        if not (k and not k.dead and (k.hp or 0)>0
            and has_card("Guillotine") and has_card("Revolution")) then return {36} end
    end
    return {4}
end

function coop_start_boss_story(nxt)
    local seq=coop_floor12_story_sequence()
    if seq[1]==4 or not isfile("assets/gfx/coop_cg.png") then init_vig({4},nxt);return end
    coop_load_story_art()
    coop_play_vig(seq,nxt)
end

function coop_start_story(ending,nxt)
    if mode.coop_variant then
        init_vig(ending and {6,7} or {1,2,3},nxt)
        return
    end
    local available=isfile("assets/gfx/coop_cg.png")
    if available then coop_load_story_art() end
    coop_play_vig(coop_story_sequence(ending,not available),nxt)
end

function coop_play_vig(seq,nxt)
	fast_tracker(false)


	if #seq==0 then
		kl(vbg)
		vbg=nil
		nxt()
		return
	end
	
	if vbg then kl(vbg) end
	vbg=mke()
	vbg.dp=DP_TOP
	vbg.dr=function() 
		cls(1)
		hdclear(0,0,MCW*2,MCH*2)
	end	
	
	local id=seq[1]
	del(seq,id)
	if id==4 and stack.theocracy then id=5 end
	if id==11 then id=7 end -- they were the same, so I'm removing 11 from the language file - Remy
	

	fade_to(0,16,nil,-4)
	local fast=false
	local fasst=false
	local leavin=false
	local slide=16
	local slide_tempo=32
	local typing=true
	local custom = COOP_CG_SCENES[id]
	local desc = coop_story_caption(id)
	if (id==2 or id==3) and mode.id=="tutorial" then desc=lang["vig_"..id.."_tuto"] end
	local len = safesize(desc)
  
	local e=mke(0,0,slide)
	e.dp=DP_TOP
	local tt=0
	e.upd=function()
		if leavin then
			if mcl then
				mcl=false
				if fasst then
					sfx("next_vig_2")
					while #seq>0 do deli(seq,1) end
					e.upd = nil
				end
			end
			return
		end
	
		tt=tt+(fast and 5 or .5)
	
		if mcl then
			mcl=false
			if fast then
				sfx("next_vig_2")
				--e.upd=nil
				leavin=true
				local function f()
					kl(e)					
					coop_play_vig(seq,nxt)
				end
				mv(e,0,-slide,slide_tempo,f)
				fade_to(-4,slide_tempo)
				e.twcv=ease_in
			else
				fast=true
				fasst = true
			end
		end
		
		if typing and tt>slide_tempo/2 then
		
			if e.t%(fast and 3 or 6)==0 then

				_sfx("tic",3,.2,0,.5+hrnd(.02))
			end
		end
	
	end
	e.dr=function(e,px,py)
		tcamera(-px,-py)
		
		-- VIG
		local vw,vh=128,64
		local x=(MCW-vw)/2
		local y=16
		rectfill(x,y,x+vw-1,y+vh-1,5)
		spritesheet(custom and "coop_story_cg" or "intro")
		sspr(0,custom and min(custom.frame,coop_story_frames-1)*vh or id*vh-vh,vw,vh,x,y)
		spritesheet("gfx")

		-- TEXT
		local sw=128+64
		local lim=max(tt-slide_tempo/2,0)
		if lim>len then fast=true typing=false end		
		--local story=slicer(desc,sw,lim)
		local cy=96--e.t/10
		--pprint(desc, (MCW-sw)/2, cy, sw, 4)
		pprint(desc, (MCW-sw)/2, cy, sw, 4, 0, lim)
		
		tcamera(px,py)
	end
	
	mv(e,0,-slide,slide_tempo)


end
