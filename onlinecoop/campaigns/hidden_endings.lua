-- Native throne.lua branch order and native boss cinematics. Keep campaign
-- progress in the co-op save bank; do not write vanilla DEN or achievements.
function coop_native_ending_sequence()
    if mode.coop_ending_kind=="duel_king" then return COOP_DUEL_ENDINGS.king end
    if mode.coop_ending_kind=="duel_knight" then return COOP_DUEL_ENDINGS.knight end
    if mode.coop_ending_kind=="book_torn" then return {29,6,7} end
    if mode.coop_ending_kind=="book_kept" then return {6,7,30,31} end
    if boss and boss.name=="bounty_marshal" then return {27,6,7} end
    if mode.coop_ending_kind == "phantom_king" then return {21,22} end
    if mode.coop_ending_kind == "phantom" then return {19,6,7} end
    if hero and hero.apo then
        if mode.coop_new_job_knight then return {14,20} end
        return {14}
    end
    if boss and boss.book then
        if chamber > 0 then return {8,9,10,6,12} end
        return {8,6,11}
    end
    if boss and boss.type == 10 then return {13,6,7} end
    if boss and boss.type == 11 then return {15,6,7} end
    return {6,7}
end

function coop_pause_for_boss_story()
    mode.coop_surrender_input_locked = true
    coop_lock_surrender_controls()
    mode.coop_run_active = false
    mode.coop_auto_select_knight_pending = nil
    mode.coop_select_king_pending = nil
    mode.coop_cursor_refresh_pending = false
    mode.coop_king_kill_pending_floor = nil
    mode.coop_king_kill_pending_frames = nil
    mode.coop_force_king_kill_turn = nil
    if mode.coop_knight then mode.coop_knight.ready = false end
end

function coop_try_hidden_boss()
    if mode.coop_variant then return false end
    -- Ignore repeated completion notifications while a transformation runs.
    if mode.coop_hidden_boss_pending or mode.coop_throne_finishing then return true end
    if not boss or boss.type ~= 6 or boss.dark then return false end
    local knight=mode.coop_knight
    if not mode.coop_duel and knight and knight.sq and not knight.dead and (knight.hp or 0)>0
        and has_card("Guillotine") and has_card("Revolution") then
        mode.coop_hidden_boss_pending="duel"
        coop_pause_for_boss_story()
        coop_begin_duel()
        return true
    end
    local marshal_candidate=coop_marshal_candidate()
    if not mode.coop_marshal_triggered and marshal_candidate
        and has_card("Co-op Warrant") and has_card("Co-op Bounty Cavalry") then
        mode.coop_marshal_triggered=true
        mode.coop_hidden_boss_pending="marshal"
        coop_pause_for_boss_story()
        coop_begin_bounty_marshal(marshal_candidate)
        return true
    end
    local selected, spawn, branch
    local bishops = get_pieces(2)
    if has_card("The Red Book") and stack.torn_theo and #bishops == 1 then
        selected, spawn, branch = bishops[1], spawn_dark_bishop, "bishop"
    else
        local queens = get_pieces(4)
        if #queens == 1 and queens[1].iron then
            selected, spawn, branch = queens[1], spawn_mother_queen, "queen"
        else
            -- Native get_pieces enumerates white bads, not black allies.
            -- Phantom and 2P Knight variants are deliberately not added here.
            local phantoms = coop_ending_phantoms()
            if #phantoms >= 4 then
                mode.coop_hidden_boss_pending = "phantom"
                coop_pause_for_boss_story()
                coop_begin_phantom_ending(phantoms)
                return true
            end
            local knights = get_pieces(1)
            if #phantoms>0 and #phantoms<4 and #knights+#phantoms==4 then
                mode.coop_hidden_boss_pending="mixed_horsemen"
                coop_pause_for_boss_story()
                coop_begin_mixed_horsemen(phantoms,knights)
                return true
            end
            if #knights == 4 then
                -- Capture before the native storm/mounting sequence clears
                -- actors. Extend only the living-Knight taking-office branch.
                mode.coop_new_job_knight = hero.disguised==0 and knight~=nil
                    and not knight.dead and (knight.hp or 0)>0
                knights.list = 1
                selected, spawn, branch = knights, spawn_horsemen, "horsemen"
                if mode.coop_new_job_knight then spawn=coop_spawn_new_job_horsemen end
            end
        end
    end
    if not selected then return false end
    mode.coop_hidden_boss_pending = branch
    coop_pause_for_boss_story()
    if _log then _log("[COOP ENDING] hidden boss=" .. branch) end
    storm_all_but(selected, spawn)
    return true
end

function coop_resume_hidden_boss()
    if not mode or mode.id ~= "coop" or mode.coop_variant
        or not mode.coop_hidden_boss_pending then return end
    -- Resume from native play after clean_up/refill_ammo, or from a new
    -- turn. Hidden-boss refill does not necessarily call init_new_turn.
    if hero and hero.apo then return end
    mode.coop_hidden_boss_pending = nil
    mode.coop_hidden_boss_refilling = nil
    if hero then hero.ready=true end
    mode.coop_surrender_input_locked = false
    mode.coop_floor_transition = false
    mode.coop_force_king_kill_turn = nil
    mode.coop_king_move_input_locked = nil
    mode.coop_manual_king_turn_pending = nil
    mode.coop_manual_king_enemy_turn_pending = nil
    mode.coop_extra_king_action_pending = nil
    mode.coop_spawn_wait_for_turn = false
    mode.coop_run_active = true
    mode.coop_opening_king_turn = true
    mode.black_actions = 1
    if _log then _log("[COOP ENDING] hidden boss ready; King acts first") end
end

function coop_freeze_throne_result()
    -- Snapshot once before the ending destroys board entities. A revived
    -- Knight counts as alive here, even though the deathless CG stays locked.
    if mode.coop_ending_knight_alive == nil then
        local knight=mode.coop_knight
        mode.coop_ending_knight_alive = knight ~= nil and knight.dead ~= true
            and type(knight.hp)=="number" and knight.hp>0
    end
    mode.coop_ending_sequence = coop_native_ending_sequence()
    mode.coop_hidden_boss_pending = nil
    mode.coop_throne_finishing = true
    if mode.coop_stats then mode.coop_stats.running = false end
    coop_pause_for_boss_story()
end

function coop_finish_throne_story()
    coop_freeze_throne_result()
    music("ending_A", 0)
    fade_to(-4, 30, outro)
end
