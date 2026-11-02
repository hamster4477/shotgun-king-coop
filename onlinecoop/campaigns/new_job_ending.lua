-- A scoped version of native spawn_horsemen's disguised-King branch.
-- Its private kill queue cannot be extended by append(). Normal horsemen and
-- full-phantom branches continue to use their existing implementations.
-- Mixed disguised endings pass the transformed phantom mounts explicitly.
function coop_spawn_new_job_horsemen(ghosts)
    local run=mode
    if run.coop_new_job_scene then return end
    local riders=get_pieces(11)
    local knight=run.coop_knight
    local mixed=ghosts~=nil
    if #riders~=4 or hero.disguised~=0 or (not mixed and
        (not knight or knight.dead or (knight.hp or 0)<=0)) then
        run.coop_new_job_knight=false
        spawn_horsemen()
        return
    end
    local scene={}
    run.coop_new_job_scene=scene
    local pending=mixed and "mixed_horsemen" or "horsemen"
    local function current()
        return mode==run and run.coop_new_job_scene==scene
            and run.coop_hidden_boss_pending==pending and not scene.finished
    end
    fast_tracker(false)
    shuffle(riders)
    if mixed then
        -- Always seat the King on a real white Knight, so his mount survives
        -- the phantom departure. Retain the shuffled order of the other roles.
        for i=4,1,-1 do
            local phantom=false
            for _,e in ipairs(ghosts) do if e==riders[i] then phantom=true end end
            if not phantom then
                riders[i],riders[4]=riders[4],riders[i]
                break
            end
        end
    end
    local names={lang.apo_name_0,lang.apo_name_1,lang.apo_name_2,lang.apo_name_3}
    for i,e in ipairs(riders) do
        if i==4 then e.pawn=hero
        else
            local free=get_zone(e.sq,2,function(sq) return is_free(sq) end)
            local sq=steal(free) or get_nearest_free_square(e.sq)
            e.pawn=new_piece(0,true,sq)
            e.pawn.c_raise=60
        end
    end
    local king=riders[4]
    local function talk(text,nxt)
        if not current() then return end
        _sfx("king_talk",-1,1,nil,1+rnd(.1))
        king.ta=.25
        fx_emote(king,text,60,function() if current() then nxt() end end)
    end
    local function depart()
        if not current() then return end
        local center=gsq(3,3)
        king.ta=atan2(center.x-king.x,center.y-king.y)
        goto_sq(king,center,60,function()
            if not current() then return end
            wait(30,function()
                talk(lang.apo_threat_4,function()
                    king.ta=0;king.c_smoke=80
                    _sfx("charge",-1,1,nil,.6)
                    mv(king,80,0,80,function()
                        if not current() then return end
                        kl(king)
                        scene.finished=true
                        coop_finish_throne_story()
                    end)
                    king.twcv=ease_in_back
                end)
            end)
        end)
    end
    local function rebound(nxt)
        loop(function(ev)
            if not current() then return end
            local c=ev.t/30
            king.z=(c-1)*10-sin(c/2)*12
        end,30,function()
            if not current() then return end
            king.z=0;nxt()
        end)
    end
    local function execute_knight()
        if not current() then return end
        if not knight or run.coop_knight~=knight or knight.dead or (knight.hp or 0)<=0 or not knight.sq then
            run.coop_new_job_knight=false
            depart();return
        end
        -- A visible pause after the three original victims, then the same
        -- windup, crushing arc and rebound. Move only the cinematic actor:
        -- goto_sq here would capture the ally and run native on-move effects.
        king.ta=atan2(knight.x-king.x,knight.y-king.y)
        wait(45,function()
            if not current() then return end
            king.crusher=true
            wait(16,function()
                if not current() then return end
                local start_z=king.z or 0
                mvt(king,knight.x,knight.y,TEMPO,function()
                    if not current() then return end
                    king.z=-10;king.crusher=nil
                    sfx("xpl");screen_shake(3)
                    for i=0,6 do fx_crumb(knight,i) end
                    leave_sq(knight);del(bads,knight)
                    coop_mark_knight_dead(knight)
                    knight.dead=true;kl(knight)
                    run.coop_ending_knight_alive=false
                    scene.executed=true
                    if _log then _log("[COOP NEW JOB] King executed Black Knight") end
                    rebound(function()
                        wait(45,function() if current() then depart() end end)
                    end)
                end)
                loop(function(ev)
                    if not current() then return end
                    local c=ev.t/TEMPO
                    if c<1 then king.z=start_z*(1-c)-sin(c/2)*8-10*c end
                end,TEMPO)
            end)
        end)
    end
    local threat_index=0
    local kill_next
    local function threat()
        if not current() then return end
        local text=get_lang("apo_threat_"..threat_index)
        threat_index=threat_index+1
        talk(text,kill_next)
    end
    kill_next=function()
        if not current() then return end
        if #riders==0 then execute_knight();return end
        local victim=steal(riders)
        victim.fast_soul=1
        king.ta=atan2(victim.x-king.x,victim.y-king.y)
        king.crusher=true
        wait(16,function()
            if not current() then return end
            goto_sq(king,victim.sq,TEMPO,function()
                if not current() then return end
                xpl(victim)
                rebound(threat)
            end)
        end)
    end
    local function after_mounts()
        del(riders,king)
        if not mixed then wait(60,threat);return end
        -- Ascension is not a kill: no souls, death statistics or combat hooks.
        -- Keep input locked until all departing riders and their pawns vanish.
        local remaining=#ghosts
        if remaining==0 then wait(60,threat);return end
        sfx("ascend")
        for _,e in ipairs(ghosts) do
            del(riders,e)
            del(bads,e)
            coop_story_ascend(e,function()
                if not current() then return end
                remaining=remaining-1
                if remaining==0 then
                    if _log then _log("[COOP MIXED] disguised departed="..#ghosts.." rivals="..#riders) end
                    wait(60,threat)
                end
            end)
        end
    end
    local index=1
    local function mount_next()
        if not current() then return end
        if index>4 then
            after_mounts()
            return
        end
        local e=riders[index]
        if not e.pawn.named then
            sfx("apo_talk");e.pawn.named=true;e.pawn.c_detect=60
            local text=names[1];del(names,text)
            fx_emote(e.pawn,text,60,mount_next)
            return
        end
        sfx("apo_jump")
        local sq=e.sq
        leave_sq(e)
        goto_sq(e.pawn,sq,TEMPO,function()
            if not current() then return end
            sfx("apo_sit");e.give_role()
            kl(e.pawn);del(bads,e.pawn)
            goto_sq(e,sq,0)
            if e.pawn==hero then
                e.an=hero.an;e.ta=hero.an
                hero.sq=hero.wsq;hero.disguised=nil;hero.apo=1;e.black_king=1
            end
            index=index+1
            wait(30,mount_next)
        end)
    end
    wait(60,mount_next)
end
