-- Co-op story uses the native vignette timing, typography and skip controls.
-- Frame numbers are zero-based 128x64 rows in assets/gfx/coop_cg.png.
local COOP_CG_SCENES = {
    [20]={frame=3, zh="踏进末日这一行，黑王连最后一个同伴也没有留下。黑骑士一路替他扫清障碍，最终却也被算作了障碍。没有告别，更没有赏赐。黑王对自己的新差事十分满意：再也不必考虑手下会不会辞职了。", en="On entering the apocalypse business, the King spared not even his last companion. The Black Knight had cleared every obstacle in his path, only to be counted among them. There was no farewell, and certainly no reward. The King was delighted with his new position. No more worrying about staff resignations."},
    [34]={frame=17, zh="有人捡起王冠，递到革命骑士面前。他没有接。人群安静下来——他们已经习惯了等一个戴王冠的人开口。骑士收起兵刃，退到他们中间。这一次，没有国王替他们决定下一步。", en="Someone picked up the crown and offered it to the Revolutionary Knight. He did not take it. The crowd fell quiet. They were used to waiting for someone in a crown to speak. The Knight put away his weapon and joined them. This time, no king would decide their next move."},
    [35]={frame=18, zh="王座空了，争论却很快填满了大厅。土地归谁，薪酬多少，城堡又该由谁修缮？这些问题从前只需要国王一句话，如今每个人都有话要说。革命骑士坐在人群中，兵刃搁在一旁。至少这一次，谁都不必先躲过一发霰弹，才能把话说完。", en="The throne was empty, but arguments soon filled the hall. Who owned the land? What wages were fair? Who would repair the castle? Once, the King's word had settled everything. Now everyone had something to say. The Revolutionary Knight sat among them, his weapon set aside. At least this time, nobody had to dodge a shotgun blast to finish a sentence."},
    [36]={frame=19, zh="多年苦心经营才招揽到的新子民……好不容易才让他们感到安全和被接纳……就因为一个端着霰弹枪的王室混蛋，让他们全被轰成了玻璃渣。而那个替疯王开路的黑骑士，竟又让追捕的开销翻了一番。白王终于受够了：为了逮住一个骑士，难道要把整个国库都赔进去？他带上新军兵团，决心亲自结束这笔赔本买卖。", en="So many years' worth of new subjects... So much work to make them feel welcome and safe... All reduced to glass shards by one royal psycho with a shotgun. And the Black Knight clearing his path had doubled the cost of the manhunt yet again. The White King had had enough. Must catching one knight cost him his entire treasury? He assembled his new corps, determined to settle this ruinous business himself."},
    [32]={frame=15, zh="反叛骑士倒下了，失去首领的民众四散逃去。黑王踢开脚边的碎片，仿佛刚刚处理完一份格外麻烦的辞呈。“想换个国王？”他举起霰弹枪，“下次记得先问问它！”王座保住了，臣民们的日子依然照旧。", en="The Rebel Knight fell, and the leaderless crowd scattered. The King kicked aside the fragments at his feet as though disposing of a particularly troublesome resignation. \"Want a different king?\" He raised his shotgun. \"Next time, ask my shotgun first!\" The throne was safe. For his subjects, life would go on much as before."},
    [33]={frame=16, zh="这一次，臣民们没有给黑王让路。在他们的帮助下，革命骑士挥出了最后一击。王冠落地，命令声终于停了。原来，国王也不过是一枚可以被击碎的棋子。", en="This time, the Black King's subjects refused to step aside. With their help, the Revolutionary Knight struck the final blow. The crown fell, and the orders finally ceased. A king, it seemed, was only another piece that could be broken."},
    [29]={frame=12, zh="红色圣书还没来得及飞远，黑骑士便将它一把攥住，撕成两半。书页纷纷飘落，书中的神圣教诲再也拼不完整。“干得好！”黑王大笑起来，“本王早就受够了那些劝诫！”骑士替他撕掉了一本书，也替臣民们撕掉了最后一点指望。", en="Before the Red Book could drift away, the Black Knight seized it and tore it in two. Pages fluttered down, its holy teachings scattered beyond repair. \"Well done!\" the King laughed. \"I've had quite enough of being lectured!\" The Knight had torn up a book for his king, and the last scraps of hope for his subjects."},
    [30]={frame=13, zh="黑骑士没有摧毁圣书，也没有把它交给国王。他将红书抱入臂中，转身离开战场，消失于棋盘的边界之外。黑王起初并不在意。一本书罢了，哪有他的城堡和霰弹枪重要？", en="The Black Knight neither destroyed the book nor delivered it to his king. He tucked it under his arm and left the battlefield, disappearing beyond the edge of the board. At first, the King paid it little mind. It was only a book. What was that compared to his castles and his shotgun?"},
    [31]={frame=14, zh="时隔许久，远方传来消息：黑骑士凭借圣书的神圣力量，被加冕为新的白王。“连他也敢背叛本王！”黑王怒吼。那个最后才离开的人，终究成了新的对手。背叛，原来甚至会发生在这最后一个不曾逃走的人身上。", en="Some time later, word arrived: through the holy power of the Red Book, the Black Knight had been crowned the new White King. \"Even he dares betray me!\" the Black King roared. The last to leave had become his next rival. Betrayal, it seemed, could come even from the last one who had stayed."},
    [27]={frame=10, zh="悬赏元帅轰然倒下，再也没法领取那笔赏金。黑王捡起一张印着黑骑士模样的通缉令，盯着上面的数目看了好一会儿。“这么多钱，宁可拿来悬赏，也不肯交给本王！”他骂道。可惜，开价的人已经死了，来领赏的人也刚刚碎在了他脚下。", en="The Bounty Marshal fell with a crash. He would never collect that bounty now. The Black King picked up a wanted poster bearing the Black Knight's likeness and stared at the sum. \"All that money! They'd spend it on a bounty rather than give it to me!\" he snarled. Pity the one who had offered it was dead, and the one who had come to collect lay shattered at his feet."},
    [28]={frame=11, zh="黑骑士没能活到看见这场胜利。通缉令上许诺的赏金，如今也无人兑现。“本王的人，倒让别人先估了价。”黑王哼了一声，把纸踩进了碎屑里。随后独自收起战利品，不再提什么论功行赏。", en="The Black Knight had not lived to see the victory. No one remained to pay the reward promised on the wanted poster. \"My own man, and someone else put a price on him before I did.\" The King snorted and ground the paper into the rubble. Then he gathered the spoils alone, with no further talk of rewards for service."},
    [26]={frame=9, zh="黑王又想起了那句“自取灭亡”。主教已经死了，骑士也没有回来，可他还站着。在黑王看来，这足以证明那番预言错得离谱。至于一路上替他倒下的那些人，自然不在他的考虑之内。", en="The King remembered that warning about his own undoing. The bishop was dead, the Knight had not returned, and yet here he stood. To the King, that was ample proof the prophecy had been nonsense. Those who had fallen for him along the way did not enter into his calculations."},
    [25]={frame=8, zh="王后倒下了，黑骑士也没有回来。黑王望着身旁空出的位置，低声骂了一句。“一个个都走得倒快。”他把霰弹枪抱得更紧了些。至少这位老伙伴还肯听话，只要记得给它上弹。", en="The Queen had fallen, and the Black Knight had not returned. The King glanced at the empty place beside him and muttered a curse. \"Always in such a hurry to leave, all of them.\" He held his shotgun a little tighter. At least this old companion still obeyed, provided he remembered to load it."},
    [23]={frame=6, zh="黑王重夺王座时，黑骑士依旧立在他身侧，兵刃上还沾着碎棋的尘埃。臣民很快明白，他们不但迎回了旧暴君，还得面对一个替他扫清道路的死士。国王倒是十分满意：总算有个不嫌这份工作的人。", en="When the Black King reclaimed his throne, the Black Knight still stood beside him, his weapon coated in the dust of shattered pieces. The subjects soon understood: their old tyrant had returned with a ruthless, devoted follower to clear his path. The King, at least, was delighted. At last, someone who didn't mind the job."},
    [24]={frame=7, zh="胜利已然到手，黑骑士却没有回来。黑王独自登上王座，清点起自己的战利品。“少一个分赏赐的，倒也不错。”他说。随后他习惯性地向身侧下令，却只听见自己的声音在空厅里回荡。", en="Victory was his, but the Black Knight did not return. The Black King took his throne alone and counted his spoils. \"One less reward to pay. Suits me fine,\" he said. Then, out of habit, he turned to give an order to the Knight who was no longer there. Only his own voice echoed through the empty hall."},
    [19]={frame=2, zh="号令已经完成，骑士之墓的幻影终于得以安息。那些古老的身影缓缓淡去，连同骑上它们的天启骑士，一并消失在棋盘之外。黑王望着空下来的格子，颇为满意：末日也该知道，什么时候轮到自己退场。", en="The command had been fulfilled. At last, the phantoms of the knights' tomb could rest. Those ancient figures slowly faded beyond the board, carrying the Horsemen of the Apocalypse with them. The Black King surveyed the empty squares with satisfaction. Even the end of the world ought to know when to leave."},
    [21]={frame=4, zh="黑王骑上了最后一匹幻影坐骑。他本以为这又是一件理应归自己的战利品，直到坐骑开始消散，连他的身影也随之变淡。“站住！本王还没下令！”可惜，这道号令并不听他的。幻影离去时，也带走了它们的新乘客。", en="The Black King mounted the last phantom steed, certain it was another prize rightfully his. Then his mount began to fade, and his own shape faded with it. \"Halt! I gave no such order!\" Unfortunately, this command was not his to give. As the phantoms departed, they took their newest passenger along."},
    [22]={frame=5, zh="棋盘上再也看不见黑王，臣民们却迟迟不敢庆祝。偶尔，有人声称在城堡的阴影里看见一顶王冠，或听见远处传来霰弹枪上膛的声音。也许只是风声。毕竟，谁也不想亲自去问问。", en="The King was nowhere to be seen, but his subjects were slow to celebrate. Now and then, someone claimed to glimpse a crown in the castle shadows, or hear a shotgun being loaded in the distance. Perhaps it was only the wind. Nobody cared to go and ask."},
    [17]={frame=0, zh="就在臣民纷纷离去之际，一个黑骑士仍留在黑王身边。他没有递上辞呈，也没有跟着主教迈出城门。不论前方等着的是毁灭还是凯旋，他都将追随自己的国王。这一次，黑王不再孤身一人。", en="As the Black King's subjects departed, one Black Knight remained at his side. He neither handed in his resignation nor followed the bishop through the castle gates. Whether ruin or triumph lay ahead, he would follow his king. This time, the Black King would not walk alone."},
    [18]={frame=1, zh="一路上倒下了多少棋子，黑骑士已经记不清了。他只知道，自己始终没有成为其中一个。战场满目疮痍，他的铠甲却未添一道伤痕。黑王打量着这身完好的盔甲，十分欣慰——连修缮费都省了。", en="The Black Knight had lost count of the pieces that fell along the way. He only knew he had never been one of them. The battlefield lay in ruins, yet his armour bore not a scratch. The King surveyed the pristine suit with great satisfaction. Not even a repair bill to pay."},
}
local coop_story_frames=20
local vbg

-- Story text overrides live here instead of modifying the shared lang table.
-- Leave an entry empty to use the original localized text until writing is ready.
local COOP_ENDING_TEXT = {
    [3]={zh="然而黑王名下已经连一座城堡都没有了。他仅剩的就只有自己心爱的王室霰弹枪、他仅存的些许尊严、以及那在他的心中越烧越旺的如预言中昭示的熊熊怒火。亦必自取灭亡？灭亡便灭亡！！一意孤行的国王把霰弹枪上膛，前去面对自己最后的将死。", en="But the Black King had not a rook left to his name. All he had left was his prized royal shotgun, the shreds of his dignity, and the growing fires of the prophesized wrath. Ever my undoing was it? Undone!! Just what more exactly could I lose?!? In his dark folly, the king loaded the shotgun and went to meet his final checkmate."},
    [6]={}, [7]={}, [8]={}, [9]={}, [10]={},
    [12]={}, [13]={}, [14]={}, [15]={},
}

function coop_story_caption(id)
    local key=current_lang=="simplified_chinese" and "zh" or "en"
    local custom=COOP_CG_SCENES[id]
    local override=custom or COOP_ENDING_TEXT[id]
    if override and override[key] then
        local suffix=key=="zh" and "（暂用）" or " (Provisional)"
        return override[key]..suffix
    end
    return lang["vig_"..id]
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
