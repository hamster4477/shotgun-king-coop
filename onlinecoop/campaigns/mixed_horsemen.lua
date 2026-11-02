-- Keep native spawn_horsemen in charge of mounting/corners and clearing boss.
function coop_begin_mixed_horsemen(phantoms,knights)
    local run=mode
    local disguised=hero.disguised==0
    local knight=run.coop_knight
    run.coop_new_job_knight=disguised and knight~=nil
        and not knight.dead and (knight.hp or 0)>0
    mode.coop_phantoms={}
    mode.coop_phantom_pending=nil
    coop_flash_mechanism_card(function()
        if mode~=run or run.coop_hidden_boss_pending~="mixed_horsemen" then return end
        coop_phantom_lightning(phantoms,knights,function(ghosts)
            if mode~=run or run.coop_hidden_boss_pending~="mixed_horsemen" then return end
            if disguised then
                -- The native disguised branch kills every other rider. Remove
                -- phantom mounts from that queue only after all four mount.
                coop_spawn_new_job_horsemen(ghosts)
            else
                mode.coop_mixed_horsemen=ghosts
                spawn_horsemen()
            end
        end)
    end)
end

function coop_depart_mixed_horsemen()
    if not mode or mode.id~="coop" or mode.coop_variant
        or mode.coop_hidden_boss_pending~="mixed_horsemen"
        or not mode.coop_mixed_horsemen then return end
    -- Native clean_up is reached after all four mounts/corner moves finish.
    local ghosts=mode.coop_mixed_horsemen
    mode.coop_mixed_horsemen=nil
    for _,e in ipairs(ghosts) do
        del(bads,e)
        coop_story_ascend(e)
    end
    local remaining=get_pieces(11)
    if #remaining==1 then
        -- Native xpl promotes the last team boss, but ascension is not a kill.
        -- Recreate that one survivor through the native constructor with the
        -- boss flag so the engine's private boss reference is set as well.
        local old=remaining[1]
        local sq=old.sq
        local ind=clone(old.ind,true)
        local hp=old.hp
        local definition=PIECES[12]
        local saved=definition.boss
        leave_sq(old)
        del(bads,old)
        kl(old)
        definition.boss=true
        local e=new_piece(11,true,sq)
        definition.boss=saved
        e.ind=ind
        e.dr_skin=old.dr_skin
        e.turn_move=old.turn_move
        setup_piece(e)
        e.hp=hp
    end
    if _log then _log("[COOP MIXED] departed="..#ghosts.." remaining="..#remaining) end
end
