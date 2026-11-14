id = "coop"
coop_controller = nil -- each mode entry starts with local input ownership
require("shared/actions.lua")
require("shared/turn_indicator.lua")
require("shared/royal_cards.lua")
require("campaigns/story.lua")
require("campaigns/hidden_endings.lua")
require("campaigns/new_job_ending.lua")
require("campaigns/phantom_ending.lua")
require("campaigns/phantom_art.lua")
require("campaigns/mixed_horsemen.lua")
require("campaigns/bounty_marshal.lua")
require("campaigns/bishop_book_choice.lua")
require("campaigns/rebel_knight.lua")
require("campaigns/janissary_art.lua")
require("campaigns/cavalier_art.lua")

-- Optional shortcut: 10 starts on floor 11, 11 starts on floor 12.
-- Keep normal co-op runs on floor 1 unless explicitly debugging a transition.
local COOP_START_LVL = nil

-- Floor transitions can expose a table named `flr` in this mode's lookup
-- scope. Keep pixel rounding independent of that changing game state.
local function coop_floor_int(value)
    return value - (value % 1)
end

setup = {
    slots_max = {10, 10},
}

weapons = {
    { gid = 0, name = "Solomon", chamber_max = 2, firepower = 4, spread = 55, ammo_max = 6 },
    { gid = 1, name = "Victoria", chamber_max = 1, firepower = 5, firerange = 1, spread = 45, ammo_max = 3 },
    { gid = 2, name = "Ramesses II", chamber_max = 2, firepower = 4, spread = 65, ammo_max = 5, knockback = 50 },
    { gid = 3, name = "Richard III", chamber_max = 3, firepower = 3, firerange = 2, spread = 75, ammo_max = 8, pierce = 40 },
    { gid = 4, name = "Makeda", chamber_max = 2, firepower = 3, spread = 50, ammo_max = 6, blade = 2, butcher = 1 },
    { gid = 5, name = "Alexander", chamber_max = 2, firepower = 4, spread = 65, ammo_max = 8, search = 1 },
    { gid = 6, name = "Yvan IV", chamber_max = 1, firepower = 4, firerange = -1, spread = 50, ammo_max = 6, all_freereload = 1 },
    { gid = 7, name = "Attila", chamber_max = 1, firepower = 4, spread = 65, ammo_max = 5, grenades_max = 1, special = "grenade", reload_grenade = 1, grenade_dmg = -1 },
    { gid = 8, name = "Montezuma", chamber_max = 3, firepower = 3, spread = 65, ammo_max = 6, sheath = 1 },
}

ranks = {
    { nothing = 1 },
    { gain = {0,0} },
    { gain = {3} },
    { ai_lvl = 1 },
    { gain = {1} },
    { royal_promote = 1 },
    { king_hp = 1 },
    { gain = {2} },
    { rook_hp = 1 },
    { ai_lvl = 1 },
    { boss_hprc = 200 },
    { spread = 15 },
    { rook_hp = 1 },
    { king_hp = 1 },
    { bishop_hp = 1 },
    { knight_hp = 1 },
    { queen_hp = 1 },
    { king_hp = 1 },
    { rook_hp = 1 },
    { pawn_hp = 1, ammo_max = 1 },
}

base = {
    pawn_global_promote = 1,
    surrender = 1,
    gain = {0,0,0,1,5,2,0},
    ai_lvl = 0,
    firerange = 3,
}

intro = true

-- ==================== helper functions ====================
function get_coop_knight_type()
    for _, p in ipairs(PIECES) do
        if p.name == "coop_knight" then return p.type end
    end
    return nil
end

function get_coop_warrant_type()
    for _, p in ipairs(PIECES) do
        if p.name == "warrant_knight" then return p.type end
    end
    return nil
end

function is_coop_active()
    return mode and mode.id == "coop" and mode.coop_run_active and hero and hero.sq
end

function coop_set_selected(selection)
    if not mode or mode.id ~= "coop" then return end
    if selection == "knight" then
        if mode.coop_selected ~= "knight" and mode.coop_knight and hero ~= mode.coop_knight then
            mode.coop_king_hero = hero
        end
    elseif mode.coop_king_hero then
        hero = mode.coop_king_hero
        mode.coop_king_hero = nil
    end
    if selection == "king" then
        mode.coop_knight_selected_soul = nil
        mode.coop_knight_move_soul_to_spend = nil
        mode.coop_soul_selection_fx = nil
    end
    -- Keep the 2P unit out of native black-piece movement/capture in both
    -- selections. Its legal jumps and blade damage come from the co-op input.
    if mode.coop_knight then
        mode.coop_knight.custom_range = coop_no_soul_moves
        mode.coop_knight.custom_atk = coop_no_soul_moves
        mode.coop_knight.nocarry = 1
    end
    mode.coop_selected = selection
    coop_sync_knight_soul_hover()
    if mouse then mouse("show", true) end
    -- Selection can happen during the update/input dispatch. Rebuilding the
    -- native cursor here and again in the pending update hook creates two
    -- button maps in one frame; leave the rebuild to that single hook.
    mode.coop_cursor_refresh_pending = true
    if selection == "king" then
        coop_refresh_king_danger()
        coop_mute_king_button_on_knight_square()
    end
end

function coop_finish_knight_move(knight, destination)
    if not mode or mode.id ~= "coop" or mode.coop_selected ~= "knight"
        or knight ~= mode.coop_knight or not destination or knight.sq ~= destination
        or mode.coop_select_king_pending then
        return false
    end
    local origin = mode.coop_knight_move_origin_sq
    if origin and origin ~= destination then
        mode.coop_last_knight_origin_sq = origin
        mode.coop_last_knight_destination_sq = destination
        if _log then
            _log("[COOP OCCUPANCY] after native move origin=" .. coop_trace_value(origin)
                .. " destination=" .. coop_trace_value(destination)
                .. " free_origin=" .. coop_string(is_free(origin))
                .. " free_destination=" .. coop_string(is_free(destination)))
        end
        mode.coop_pickup_cleanup_pending = true
    end
    if mode.coop_knight_move_soul_to_spend then
        coop_spend_knight_soul(mode.coop_knight_move_soul_to_spend)
        mode.coop_knight_move_soul_to_spend = nil
    else
        mode.coop_knight_selected_soul = nil
    end
    knight.ready = false
    coop_queue_warrant_knight_check(knight)
    mode.coop_knight_move_origin_sq = nil
    mode.coop_auto_select_knight_pending = nil
    -- Finish the current mouse click before exposing the King's native
    -- controls. Otherwise that same click can start a King move as well.
    mode.coop_select_king_pending = true
    if _log then _log("[COOP INPUT] Knight jump completed; King selection queued") end
    return true
end

function coop_get_board_geometry()
    local board_left = (MCW - 128) / 2
    -- board_y is the screen-space top edge of the board in this build.
    -- Earlier adding 72 offset the click by several ranks and inverted the
    -- Knight's vertical movement relative to the actual pointer location.
    local board_top = board_y
    return board_left, board_top
end

function coop_get_square_at_mouse(x, y)
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    local board_left, board_top = coop_get_board_geometry()
    local file = coop_floor_int((x - board_left) / 16)
    local row = coop_floor_int((y - board_top) / 16)
    if file < 0 or file > 7 or row < 0 or row > 7 then return nil end
    -- In this build the board's py coordinate follows screen rows from top
    -- to bottom, so do not invert the row.
    return gsq(file, row)
end

function coop_as_square(value)
    if type(value) ~= "table" then return nil end
    local square = value
    if square.px == nil or square.py == nil then square = value.sq end
    if type(square) ~= "table" or square.px == nil or square.py == nil then return nil end
    local board_square = gsq(square.px, square.py)
    if board_square == square then return square end
    return nil
end

function coop_find_mouse_target(move_targets)
    -- `get_hero_trg()` is the firing target helper and can resolve to the
    -- current hero square when the Knight has no gun. Probe the game-level
    -- mouse target helper instead. Its signature is undocumented, so guard
    -- both known query shapes and accept only an actual board square.
    if type(get_mouse_target) ~= "function" or type(pcall) ~= "function" then
        return nil, "unavailable"
    end
    local ok, value = pcall(get_mouse_target)
    if ok then
        local square = coop_as_square(value)
        if square then return square, "get_mouse_target()" end
    end
    if move_targets then
        ok, value = pcall(get_mouse_target, move_targets)
        if ok then
            local square = coop_as_square(value)
            if square then return square, "get_mouse_target(targets)" end
        end
    end
    return nil, ok and "no_square" or "query_error"
end

function coop_has_barricade(sq)
    return sq and mode and mode.coop_barricades
        and mode.coop_barricades[sq] == true or false
end

function coop_get_knight_move_targets(knight)
    if not knight or not knight.sq then return {} end
    local offsets = {
        {2,-1}, {2,1}, {1,2}, {-1,2},
        {-2,-1}, {-2,1}, {-1,-2}, {1,-2}
    }
    local targets = {}
    for _, offset in ipairs(offsets) do
        local sq = gsq(knight.sq.px + offset[1], knight.sq.py + offset[2])
        if sq and not sq.piece and not sq.moat
            and not coop_has_barricade(sq) and is_free(sq) then
            add(targets, sq)
        end
    end
    return targets
end

function coop_knight_soul_move_targets(knight, soul_id)
    local targets = {}
    if not knight or not knight.sq or (soul_id ~= 2 and soul_id ~= 3) then return targets end
    local directions = soul_id == 2
        and {{1,1}, {1,-1}, {-1,1}, {-1,-1}}
        or {{1,0}, {-1,0}, {0,1}, {0,-1}}
    for _, direction in ipairs(directions) do
        for distance = 1, 7 do
            local sq = gsq(knight.sq.px + direction[1] * distance,
                knight.sq.py + direction[2] * distance)
            if not sq or sq.moat or coop_has_barricade(sq)
                or not is_free(sq) or coop_piece_on_square(sq) then break end
            add(targets, sq)
        end
    end
    return targets
end

function coop_knight_charge_targets(knight)
    local targets = {}
    if not knight or not knight.sq then return targets end
    for _, direction in ipairs({{1,0}, {-1,0}, {0,1}, {0,-1}}) do
        for distance = 1, 7 do
            local sq = gsq(knight.sq.px + direction[1] * distance,
                knight.sq.py + direction[2] * distance)
            if not sq or coop_has_barricade(sq) then break end
            add(targets, sq)
        end
    end
    return targets
end

-- Permanent raid skills share the same targeting/consumption paths as cards.
function coop_has_knight_skill(card_id)
    if mode and mode.coop_variant == "charnier"
        and mode.coop_raid_skills and mode.coop_raid_skills[card_id] then return true end
    return has_card and has_card(card_id)
end

function coop_knight_soul_ready(knight)
    local soul = mode and mode.coop_knight_selected_soul
    return knight and knight.ready ~= false and soul and soul.id
        and ((soul.id == 1 and has_card and coop_has_knight_skill("Co-op Knight Spirit"))
            or ((soul.id == 2 or soul.id == 3)
                and has_card and coop_has_knight_skill("Co-op In-Law")))
end

function coop_knight_blade_damage(knight)
    return max(1, coop_floor_int((knight and knight.blade or 3) + coop_saddle_bonus(knight)
        + ((mode and mode.coop_variant == "charnier" and mode.coop_raid_blade_bonus) or 0)
        + ((has_card and has_card("Nightbane")) and 1 or 0)
        + ((has_card and has_card("The Moat") and stack
            and type(stack.moat) == "number" and knight and knight.sq
            and knight.sq.py > stack.moat) and 1 or 0)
        + ((has_card and has_card("Bushido")
            and type(chamber) == "number" and chamber <= 0) and 1 or 0)))
end

function coop_duet_knight_bonus(target)
    if not is_coop_active() or not (has_card and has_card("Co-op Gun Knight Duet"))
        or type(target) ~= "table" or target.team ~= 1 then return 0 end
    local bonus = target.coop_duet_king_floor == mode.lvl and 1 or 0
    target.coop_duet_knight_floor = mode.lvl
    if bonus > 0 and _log then
        _log("[COOP DUET] Knight followed King on " .. coop_trace_value(target))
    end
    return bonus
end

function coop_duet_begin_king_action(square)
    if not square or not is_coop_active() or mode.coop_selected ~= "king"
        or not (has_card and has_card("Co-op Gun Knight Duet")) then return end
    mode.coop_duet_king_action_id = (mode.coop_duet_king_action_id or 0) + 1
    mode.coop_duet_king_window = {
        floor=mode.lvl, turn=mode.turns, id=mode.coop_duet_king_action_id
    }
end

function coop_duet_king_hit(piece)
    if not is_coop_active() or mode.coop_duet_extra_hit
        or mode.coop_selected ~= "king"
        or not (has_card and has_card("Co-op Gun Knight Duet"))
        or type(piece) ~= "table" or piece.team ~= 1 then return end
    local action = mode.coop_duet_king_window
    if not action or action.floor ~= mode.lvl or action.turn ~= mode.turns then
        return
    end
    local knight_attacked = piece.coop_duet_knight_floor == mode.lvl
    piece.coop_duet_king_floor = mode.lvl
    -- One gunshot may hit the same piece with several pellets. Add the duet
    -- damage only once for that King action, after the native hit completes.
    if not knight_attacked or piece.coop_duet_king_bonus_action == action.id
        or piece.dead == true or type(piece.hp) ~= "number" or piece.hp <= 0
        or coop_floor_is_ending() then return end
    piece.coop_duet_king_bonus_action = action.id
    mode.coop_duet_extra_hit = true
    hit(piece, 1)
    mode.coop_duet_extra_hit = nil
    if _log then _log("[COOP DUET] King followed Knight on " .. coop_trace_value(piece)) end
end

function coop_knight_pawn_damage_bonus(target)
    if is_coop_active() and target and target.team == 1 and target.type == 0
        and has_card and has_card("Small Fry Harvest") then return 1 end
    return 0
end

function coop_knight_attack_damage(knight, multiplier, target, base_damage)
    local ritual_bonus = mode and mode.coop_ritual_dagger_pending and 1 or 0
    local damage = ((base_damage or coop_knight_blade_damage(knight)) + ritual_bonus)
        * (multiplier or 1) + coop_duet_knight_bonus(target)
        + coop_knight_pawn_damage_bonus(target)
    if ritual_bonus > 0 then
        mode.coop_ritual_dagger_pending = false
        if _log then _log("[COOP RITUAL DAGGER] Knight attack consumed blade +1") end
    end
    if mode and mode.coop_rally_pending then
        if knight then knight.blade = max(1, (knight.blade or 3) - 1) end
        mode.coop_rally_pending = false
        if _log then _log("[COOP RALLY] temporary blade consumed by Knight attack") end
    end
    return damage
end

function coop_note_ritual_dagger_click(x, y)
    if not is_coop_active() or mode.coop_selected ~= "king"
        or not (has_card and has_card("Ritual Dagger"))
        or not hero or not hero.sq then return end
    -- Only the King's adjacent blade execution earns the Knight's bonus.
    -- Keep the target reference until the native hit callback confirms death.
    mode.coop_ritual_dagger_target = nil
    local sq = coop_get_square_at_mouse(x, y)
    local victim = sq and coop_piece_on_square(sq)
    if not victim or victim.team ~= 1 or not victim.sq
        or type(victim.hp) ~= "number" or type(stack) ~= "table"
        or type(stack.blade) ~= "number" or victim.hp > stack.blade then return end
    local dx = abs(victim.sq.px - hero.sq.px)
    local dy = abs(victim.sq.py - hero.sq.py)
    if dx <= 1 and dy <= 1 and (dx > 0 or dy > 0) then
        mode.coop_ritual_dagger_target = victim
    end
end

function coop_prepare_redemption_knight_death(piece, damage)
    if not is_coop_active() or piece ~= mode.coop_knight
        or not (has_card and has_card("Redemption"))
        or type(piece.hp) ~= "number" or type(damage) ~= "number"
        or damage < piece.hp then return end
    -- Native Redemption copies the dying piece's type. Present the custom
    -- co-op Knight as the ordinary Knight only during native death handling.
    mode.coop_redemption_native_knight_type = piece.type
    mode.coop_redemption_native_knight = piece
    piece.type = 1
end

function coop_award_ritual_dagger_kill(piece, native_kill)
    if not mode or mode.id ~= "coop"
        or piece ~= mode.coop_ritual_dagger_target then return end
    if native_kill or piece.dead == true
        or (type(piece.hp) == "number" and piece.hp <= 0) then
        mode.coop_ritual_dagger_pending = true
        if _log then _log("[COOP RITUAL DAGGER] King blade kill; Knight blade +1 queued") end
    end
    mode.coop_ritual_dagger_target = nil
end

function coop_try_rally_reload(source)
    if _log and mode and mode.id == "coop"
        and has_card and has_card("Co-op Rally Order") then
        _log("[COOP RALLY PROBE] source=" .. source
            .. " selected=" .. coop_string(mode.coop_selected)
            .. " chamber=" .. coop_string(chamber)
            .. " active=" .. coop_string(mode.coop_run_active)
            .. " floor_transition=" .. coop_string(mode.coop_floor_transition))
    end
    if not is_coop_active() or mode.coop_floor_transition
        or mode.coop_spawn_wait_for_turn or not mode.coop_knight
        or mode.coop_pause_menu_open or mode.coop_selected ~= "king"
        or mode.coop_surrender_input_locked
        or not (has_card and has_card("Co-op Rally Order")) then return end
    local loaded = type(chamber) == "number" and chamber or nil
    if not loaded or loaded <= 0 or mode.coop_rally_pending then return end
    mode.coop_rally_pending = true
    if mode.coop_knight then
        mode.coop_knight.blade = (mode.coop_knight.blade or 3) + 1
    end
    if _log then
        _log("[COOP RALLY] " .. source .. " with chamber=" .. coop_string(loaded)
            .. "; temporary Knight blade +1")
    end
end

function coop_finish_grindstone_turn()
    if not is_coop_active() or mode.coop_surrender_input_locked
        or not mode.coop_knight
        or not (has_card and has_card("Grindstone")) then return end
    -- Both native and manual King movement can reach the end-of-turn path.
    -- Count a given floor/turn only once, even if the engine re-enters it.
    local turn_key = coop_string(mode.lvl) .. ":" .. coop_string(mode.turns)
    if mode.coop_grindstone_last_turn == turn_key then return end
    mode.coop_grindstone_last_turn = turn_key
    mode.coop_grindstone_turns = (mode.coop_grindstone_turns or 0) + 1
    if mode.coop_grindstone_turns % 12 ~= 0 then return end
    mode.coop_grindstone_bonus = (mode.coop_grindstone_bonus or 0) + 1
    if mode.coop_knight then
        mode.coop_knight.blade = (mode.coop_knight.blade or 3) + 1
    end
    if _log then
        _log("[COOP GRINDSTONE] turns=" .. coop_string(mode.coop_grindstone_turns)
            .. " knight_bonus=" .. coop_string(mode.coop_grindstone_bonus))
    end
end

function coop_watch_bishop_preparation()
    if not is_coop_active() or mode.coop_floor_transition then return end
    local knight = mode.coop_knight
    if not knight or not knight.sq or knight.dead == true
        or (knight.hp ~= nil and knight.hp <= 0) then return end

    local bishop_ready = false
    if has_card and has_card("Co-op Excommunication")
        and type(get_pieces) == "function" then
        local bishops = get_pieces(2)
        if type(bishops) == "table" then
            for _, bishop in ipairs(bishops) do
                if bishop and bishop.team == 1 and bishop.type == 2
                    and bishop.sq and bishop.dead ~= true
                    and (bishop.hp == nil or bishop.hp > 0)
                    and bishop.ready == true then
                    bishop_ready = true
                    break
                end
            end
        end
    end

    -- Record the actual point removed, so leaving ready restores the exact
    -- value even when the Knight was already at the minimum of 1 blade.
    local penalty = knight.coop_excommunication_penalty or 0
    if bishop_ready and penalty == 0 then
        local before = knight.blade or 3
        penalty = before > 1 and 1 or 0
        if penalty > 0 then
            knight.blade = before - penalty
            knight.coop_excommunication_penalty = penalty
            if _log then
                _log("[COOP EXCOMMUNICATION] ready blade="
                    .. coop_string(before) .. "->" .. coop_string(knight.blade))
            end
        end
    elseif not bishop_ready and penalty > 0 then
        knight.blade = (knight.blade or 3) + penalty
        knight.coop_excommunication_penalty = nil
        if _log then
            _log("[COOP EXCOMMUNICATION] ended blade=" .. coop_string(knight.blade))
        end
    end
end

function coop_divisive_edict_state()
    if not is_coop_active() or mode.coop_floor_transition
        or not (has_card and has_card("Co-op Divisive Edict",true)) then return nil end
    local king = mode.coop_king_hero and mode.coop_king_hero.sq
        and mode.coop_king_hero or hero
    local knight = mode.coop_knight
    if not king or not king.sq or not knight or not knight.sq
        or knight.dead == true or (knight.hp ~= nil and knight.hp <= 0) then
        return "apart"
    end
    local dx = abs(king.sq.px - knight.sq.px)
    local dy = abs(king.sq.py - knight.sq.py)
    return (dx <= 1 and dy <= 1 and (dx ~= 0 or dy ~= 0))
        and "adjacent" or "apart"
end

function coop_refresh_divisive_edict()
    if not mode or mode.id ~= "coop" or type(stack) ~= "table"
        or mode.coop_floor_transition or mode.coop_spawn_wait_for_turn then return end
    local state = coop_divisive_edict_state()
    local previous = mode.coop_divisive_edict_applied_state
    if state == previous then return end
    -- Rebuilding the entire native weapon stack during the first update of a
    -- new board can race the engine's own floor setup. Only undo our prior
    -- modifier and apply the new one; native build_stack still handles card
    -- additions through the hook below.
    if previous == "adjacent" then
        stack.spread = (stack.spread or 0) - 15
    elseif previous == "apart" then
        stack.firepower = (stack.firepower or 0) + 1
    end
    if state == "adjacent" then
        stack.spread = (stack.spread or 0) + 15
    elseif state == "apart" then
        stack.firepower = (stack.firepower or 0) - 1
    end
    mode.coop_divisive_edict_applied_state = state
    if _log then
        _log("[COOP DIVISIVE EDICT] state=" .. coop_string(state)
            .. " spread=" .. coop_string(stack.spread)
            .. " firepower=" .. coop_string(stack.firepower))
    end
end

function coop_get_knight_input_targets(knight)
    if not knight or not knight.sq then return {} end
    if coop_knight_soul_ready(knight) then
        local soul_id = mode.coop_knight_selected_soul.id
        if soul_id == 1 then return coop_knight_charge_targets(knight) end
        return coop_knight_soul_move_targets(knight, soul_id)
    end
    local targets = coop_get_knight_move_targets(knight)
    local reach = (has_card and coop_has_knight_skill("Co-op Timar Cavalry Pact")) and 2 or 1
    for y = max(0, knight.sq.py - reach), min(7, knight.sq.py + reach) do
        for x = max(0, knight.sq.px - reach), min(7, knight.sq.px + reach) do
            local sq = gsq(x, y)
            if coop_knight_can_attack_target(knight, sq) then add(targets, sq) end
        end
    end
    return targets
end

function coop_piece_on_square(sq)
    if not sq then return nil end
    local function matches(piece)
        if type(piece) ~= "table" or not piece.sq
            or piece.team == nil or piece.type == nil or piece.dead == true
            or (piece.hp ~= nil and piece.hp <= 0) then return false end
        if piece.sq.px == sq.px and piece.sq.py == sq.py then return true end
        -- Native big pieces occupy gsq_zone(anchor), with sq.p pointing to
        -- the same entity in every body square. Do not accept stale caches
        -- outside that footprint, or restore the old Knight-square bug.
        if piece.big and type(gsq_zone) == "function" then
            for _, occupied in ipairs(gsq_zone(piece.sq)) do
                if occupied and occupied.px == sq.px and occupied.py == sq.py then
                    return true
                end
            end
        end
        return false
    end
    if matches(sq.p) then return sq.p end
    if matches(sq.piece) then return sq.piece end
    -- In this build gsq(x,y).piece can be nil even while a live piece has
    -- piece.sq at that coordinate. Look up the entity, not the square cache.
    for _, value in pairs(sq) do
        if matches(value) then return value end
    end
    local function from_collection(collection)
        if type(collection) ~= "table" then return nil end
        for _, value in pairs(collection) do
            if matches(value) then return value end
            if type(value) == "table" and value.sq == nil then
                for _, nested in pairs(value) do
                    if matches(nested) then return nested end
                end
            end
        end
        return nil
    end
    local found = from_collection(all_pieces)
        or from_collection(pieces)
        or from_collection(mode and mode.pieces)
    if found then return found end
    if type(get_pieces) == "function" and type(pcall) == "function" then
        local ok, collection = pcall(get_pieces)
        if ok then return from_collection(collection) end
    end
    return nil
end

function coop_mechanism_icon_bounds()
    local board_left, board_top = coop_get_board_geometry()
    return board_left - 17, board_top + 131, 14, 14
end

function coop_reset_phantom_state()
    mode.coop_mechanism_used_floor = nil
    mode.coop_phantoms = {}
    mode.coop_phantom_spawn_turn = nil
    mode.coop_phantom_pending = nil
end

function coop_mechanism_icon_at(x, y)
    if type(x) ~= "number" or type(y) ~= "number" then return false end
    local bx, by, w, h = coop_mechanism_icon_bounds()
    return x >= bx and x < bx + w and y >= by and y < by + h
end

function coop_can_activate_mechanism_order()
    local knight = mode and mode.coop_knight
    return is_coop_active() and not coop_floor_is_ending()
        and not mode.coop_floor_transition and not mode.coop_spawn_wait_for_turn
        and not mode.coop_native_turn_in_progress
        and not mode.coop_pause_menu_open
        and (mode.coop_menu_click_grace or 0) <= 0
        and not coop_white_move_animation_pending()
        and (type(events) ~= "table" or #events == 0)
        and not (hero and hero.in_move)
        and mode.coop_mechanism_used_floor ~= mode.lvl
        and knight and knight.sq and knight.hp and knight.hp > 0
        and not knight.in_move
        and type(has_card) == "function" and has_card("Co-op Mechanism Order")
        and type(new_piece) == "function" and type(fx_ascend) == "function"
end

function coop_draw_mechanism_order_icon()
    if not is_coop_active() or mode.coop_floor_transition
        or mode.coop_pause_menu_open or mode.coop_spawn_wait_for_turn
        or not (has_card and has_card("Co-op Mechanism Order")) then return end
    local x, y, w, h = coop_mechanism_icon_bounds()
    local active = coop_can_activate_mechanism_order()
    local hovered = coop_mechanism_icon_at(
        btnv("coop_mouse_x_probe", 0), btnv("coop_mouse_y_probe", 0))
    rectfill(x, y, x + w - 1, y + h - 1, 1)
    rect(x, y, x + w - 1, y + h - 1,
        active and (hovered and 7 or 5) or 3)
    for i = 0, 5 do
        local color = active and 11 or 3
        rectfill(x + 3 + (i % 3) * 3, y + 4 + coop_floor_int(i / 3) * 4,
            x + 4 + (i % 3) * 3, y + 5 + coop_floor_int(i / 3) * 4, color)
    end
    if not active then line(x + 2, y + 11, x + 11, y + 2, 3) end
end

function coop_spawn_barricades()
    if not is_coop_active() or mode.coop_floor_transition
        or mode.coop_spawn_wait_for_turn or not mode.coop_barricades_pending
        or mode.coop_native_turn_in_progress or coop_floor_is_ending()
        or coop_white_move_animation_pending()
        or (type(events) == "table" and #events > 0)
        or not (has_card and has_card("Co-op Cheval de Frise")) then return end
    if mode.coop_barricade_floor == mode.lvl then
        mode.coop_barricades_pending = nil
        return
    end
    local candidates = {}
    for y = 0, 7 do
        for x = 0, 7 do
            local sq = gsq(x, y)
            if sq and not sq.moat and not sq.penta and not sq.pentagram
                and not coop_piece_on_square(sq) and is_free(sq) then
                candidates[#candidates + 1] = sq
            end
        end
    end
    if #candidates < 3 then return end
    mode.coop_barricades = {}
    mode.coop_barricade_squares = {}
    for i = 1, 3 do
        local index = irnd(#candidates) + 1
        local sq = candidates[index]
        candidates[index] = candidates[#candidates]
        candidates[#candidates] = nil
        mode.coop_barricades[sq] = true
        mode.coop_barricade_squares[#mode.coop_barricade_squares + 1] = sq
    end
    mode.coop_barricade_floor = mode.lvl
    mode.coop_barricades_pending = nil
    if _log then
        _log("[COOP BARRICADE] spawned=" .. coop_string(#mode.coop_barricade_squares)
            .. " floor=" .. coop_string(mode.lvl))
    end
end

function coop_break_king_barricade()
    if not is_coop_active() or not hero or not coop_has_barricade(hero.sq) then return end
    mode.coop_barricades[hero.sq] = nil
    if type(sfx) == "function" then sfx("blade") end
    if _log then
        _log("[COOP BARRICADE] King dismantled " .. coop_trace_value(hero.sq))
    end
end

function coop_draw_barricades()
    if not is_coop_active() or mode.coop_floor_transition
        or mode.coop_pause_menu_open then return end
    local board_left, board_top = coop_get_board_geometry()
    local hovered = coop_get_square_at_mouse(
        btnv("coop_mouse_x_probe", 0), btnv("coop_mouse_y_probe", 0))
    for _, sq in ipairs(mode.coop_barricade_squares or {}) do
        if coop_has_barricade(sq) and not sq.piece then
            local x, y = board_left + sq.px * 16, board_top + sq.py * 16
            local tip = hovered == sq and mode.coop_selected == "king" and 5 or 7
            line(x+2, y+12, x+8, y+4, 1)
            line(x+8, y+4, x+13, y+12, 1)
            line(x+2, y+12, x+13, y+12, 1)
            line(x+4, y+11, x+8, y+5, tip)
            line(x+8, y+5, x+11, y+11, tip)
            rectfill(x+5, y+10, x+10, y+11, 3)
        end
    end
end

function coop_find_phantom_spawn_squares()
    local result, used = {}, {}
    local lanes = {{0, 1, 2}, {3, 4}, {7, 6, 5}}
    local function free_square(x, y)
        local sq = gsq(x, y)
        return sq and not sq.moat and not coop_has_barricade(sq) and not used[sq]
            and not coop_piece_on_square(sq) and is_free(sq) and sq or nil
    end
    -- Each pair enters from a separate left, centre or right section of the
    -- lower edge. Search upward within that lane when the bottom rank is busy.
    for group, columns in ipairs(lanes) do
        for y = 7, 5, -1 do
            for _, x in ipairs(columns) do
                if not result[(group - 1) * 2 + 2] then
                    local sq = free_square(x, y)
                    if sq then
                        result[#result + 1] = {sq = sq, group = group}
                        used[sq] = true
                    end
                end
            end
            if result[(group - 1) * 2 + 2] then break end
        end
    end
    return #result == 6 and result or nil
end

function coop_phantom_is_live(piece)
    if type(piece) ~= "table" or not piece.sq or piece.dead == true
        or (piece.hp ~= nil and piece.hp <= 0) then return false end
    local occupant = coop_piece_on_square(piece.sq)
    return occupant == nil or occupant == piece
end

function coop_expire_phantoms()
    for _, entry in ipairs(mode.coop_phantoms or {}) do
        local piece = entry.piece
        if coop_phantom_is_live(piece) then fx_ascend(piece) end
    end
    mode.coop_phantoms = {}
    if _log then _log("[COOP PHANTOM] all remaining phantoms vanished after nine turns") end
end

function coop_queue_phantom_turn()
    local entries = mode and mode.coop_phantoms
    if not entries or #entries == 0 or mode.coop_floor_transition then return end
    local age = (mode.turns or 0) - (mode.coop_phantom_spawn_turn or 0) + 1
    if age >= 10 then
        coop_expire_phantoms()
        return
    end
    if _log then
        _log("[COOP PHANTOM] turn=" .. coop_string(mode.turns)
            .. " age=" .. coop_string(age))
        if age == 1 then
            for _, entry in ipairs(entries) do
                _log("[COOP PHANTOM] post-init group=" .. coop_string(entry.group)
                    .. " cd=" .. coop_string(entry.piece.cd)
                    .. " ready=" .. coop_string(entry.piece.ready))
            end
        end
    end
end

function coop_spawn_pending_phantoms()
    local pending = mode and mode.coop_phantom_pending
    if not pending or mode.id ~= "coop" or not mode.coop_run_active
        or mode.coop_floor_transition or pending.floor ~= mode.lvl
        or (mode.turns or 0) + 1 < pending.turn then return end
    local spawn = coop_find_phantom_spawn_squares()
    if not spawn then
        if _log then _log("[COOP PHANTOM] next-turn spawn delayed: six free lanes unavailable") end
        return
    end
    local summoned = {}
    for _, candidate in ipairs(spawn) do
        -- Type 1 is the original black Knight. Its native three-turn tempo,
        -- player selection, movement and attack paths remain in charge.
        -- Only the individual skin changes; ordinary Knights keep their art.
        local piece = new_piece(1, false, candidate.sq)
        if piece then
            piece.coop_phantom = true
            piece.dr_skin = coop_draw_phantom_knight
            piece.give_soul = false
            summoned[#summoned + 1] = {
                piece = piece, group = candidate.group,
            }
        end
    end
    if #summoned ~= 6 then
        for _, entry in ipairs(summoned) do fx_ascend(entry.piece) end
        if _log then _log("[COOP PHANTOM] next-turn spawn delayed: creation failed") end
        return
    end
    mode.coop_phantoms = summoned
    mode.coop_phantom_spawn_turn = (mode.turns or 0) + 1
    mode.coop_phantom_pending = nil
    for _, entry in ipairs(summoned) do
        local piece = entry.piece
        if type(fx_spawn) == "function" then fx_spawn(piece) end
        -- This runs before the native turn initializes its piece buttons.
        -- Stagger only the first wait; subsequent moves use Knight tempo.
        piece.cd = entry.group - 1
        piece.ready = entry.group == 1
        if _log then
            _log("[COOP PHANTOM] spawn group=" .. coop_string(entry.group)
                .. " cd=" .. coop_string(piece.cd)
                .. " ready=" .. coop_string(piece.ready)
                .. " npc=" .. coop_string(piece.npc))
        end
    end
    if _log then
        _log("[COOP PHANTOM] spawned on next turn floor=" .. coop_string(mode.lvl)
            .. " spawned=" .. coop_string(#mode.coop_phantoms))
    end
end

function coop_activate_mechanism_order()
    if not coop_can_activate_mechanism_order() then return false end
    if not coop_find_phantom_spawn_squares() then
        if _log then _log("[COOP PHANTOM] activation deferred: six free lanes unavailable") end
        return false
    end
    local knight = mode.coop_knight
    mode.coop_mechanism_used_floor = mode.lvl
    mode.coop_phantom_pending = {
        floor = mode.lvl, turn = (mode.turns or 0) + 1,
    }
    knight.ready = false
    fx_ascend(knight)
    coop_mark_knight_dead(knight)
    sfx("blade")
    if _log then
        _log("[COOP PHANTOM] sacrifice floor=" .. coop_string(mode.lvl)
            .. " turn=" .. coop_string(mode.turns)
            .. " spawn_turn=" .. coop_string(mode.coop_phantom_pending.turn))
    end
    return true
end

function coop_king_destination_in_range(sq)
    if not sq or not hero or not hero.sq or type(get_range) ~= "function" then return false end
    local range = get_range(hero)
    if type(range) ~= "table" then return false end
    for _, entry in ipairs(range) do
        if coop_as_square(entry) == sq then return true end
    end
    return false
end

function coop_king_can_enter_killed_square(sq)
    if not sq or sq.moat or not hero or not hero.sq
        or coop_piece_on_square(sq) then return false end
    if coop_king_destination_in_range(sq) then return true end
    -- The native range can still count the victim as occupying its square
    -- until the next full turn. A normal adjacent King step remains legal.
    local dx = abs(sq.px - hero.sq.px)
    local dy = abs(sq.py - hero.sq.py)
    return dx <= 1 and dy <= 1 and (dx ~= 0 or dy ~= 0)
end

function coop_live_white_attacks_square(sq)
    -- A different living attacker must keep the native Folly Shield check.
    -- The base game's get_range(..., {atk=1}) is also used by other mods to
    -- query attack squares without advancing the turn.
    if not sq or type(bads) ~= "table" or type(get_range) ~= "function" then return true end
    for bad in all(bads) do
        if type(bad) == "table" and bad.team == 1 and bad.sq
            and bad.dead ~= true
            and (bad.hp == nil or bad.hp > 0) then
            local attacks = get_range(bad, {atk=1,scan=1})
            if type(attacks) == "table" then
                for _, target in ipairs(attacks) do
                    if coop_as_square(target) == sq then return true end
                end
            end
        end
    end
    return false
end

function coop_prune_dead_attackers(sq)
    if not sq or type(sq.danger) ~= "table" then return 0 end
    local removed = 0
    for index = #sq.danger, 1, -1 do
        local attacker = sq.danger[index]
        if type(attacker) == "table" and attacker.team == 1
            and (attacker.dead == true
                or (attacker.hp ~= nil and attacker.hp <= 0)) then
            deli(sq.danger, index)
            removed = removed + 1
        end
    end
    return removed
end

function coop_refresh_king_danger()
    if not is_coop_active() or mode.coop_selected ~= "king"
        or mode.coop_floor_transition or not hero or not hero.sq
        or type(init_safe_mode) ~= "function" then return end
    -- Independent Knight actions do not call native play(), which normally
    -- rebuilds danger. Vacating a bishop/rook ray must expose its danger before
    -- the King's next click, including Inquisition's uncover through cloak.
    -- Keep the native cloak, scan, projectile and special-attack rules intact.
    init_safe_mode()
    for _, sq in ipairs(squares) do coop_prune_dead_attackers(sq) end
end

function coop_record_knight_kill_ui(victim, victim_square, attacks)
    if not victim or victim.type == 5 or not victim_square then return end
    mode.coop_knight_killed_square = victim_square
    mode.coop_knight_killed_squares = mode.coop_knight_killed_squares or {}
    mode.coop_knight_killed_squares[victim_square] = true
    mode.coop_knight_killed_attack_squares = mode.coop_knight_killed_attack_squares or {}
    local attack_count = 0
    local pruned_count = 0
    if type(attacks) == "table" then
        for _, target in ipairs(attacks) do
            local sq = coop_as_square(target)
            if sq then
                mode.coop_knight_killed_attack_squares[sq] = true
                attack_count = attack_count + 1
                pruned_count = pruned_count + coop_prune_dead_attackers(sq)
            end
        end
    end
    pruned_count = pruned_count + coop_prune_dead_attackers(victim_square)
    mode.coop_killed_button_refresh_pending = true
    if _log then
        _log("[COOP KILL UI] recorded victim=" .. coop_trace_value(victim)
            .. " square=" .. coop_trace_value(victim_square)
            .. " attack_squares=" .. coop_string(attack_count)
            .. " stale_danger_removed=" .. coop_string(pruned_count))
    end
end

function coop_knight_can_blade_target(knight, target_sq)
    if not knight or not knight.sq or not target_sq then return false end
    local target = coop_piece_on_square(target_sq)
    if not target then return false end
    if target.team ~= 1 then return false end
    local dx = abs(target_sq.px - knight.sq.px)
    local dy = abs(target_sq.py - knight.sq.py)
    return (dx > 0 or dy > 0) and dx <= 1 and dy <= 1
end

function coop_knight_can_spear_square(knight, target_sq)
    if not knight or not knight.sq or not target_sq
        or not (has_card and coop_has_knight_skill("Co-op Timar Cavalry Pact")) then return false end
    local dx = abs(target_sq.px - knight.sq.px)
    local dy = abs(target_sq.py - knight.sq.py)
    -- The target is exactly two squares away on a rank, file, or diagonal.
    -- The intervening square does not obstruct this card's thrust.
    return (dx == 2 and (dy == 0 or dy == 2)) or (dx == 0 and dy == 2)
end

function coop_knight_can_spear_target(knight, target_sq)
    if not coop_knight_can_spear_square(knight, target_sq) then return false end
    local target = coop_piece_on_square(target_sq)
    return target and target.team == 1 or false
end

function coop_knight_can_attack_target(knight, target_sq)
    return coop_knight_can_blade_target(knight, target_sq)
        or coop_knight_can_spear_target(knight, target_sq)
end

function coop_string(value)
    if value == nil then return "nil" end
    local value_type = type(value)
    if value_type == "table" then return "table" end
    if value_type == "boolean" then return value and "true" or "false" end
    if value_type == "number" or value_type == "string" then return "" .. value end
    return value_type
end

function coop_adjacent_warrant_hunter(knight)
    local warrant_type = get_coop_warrant_type()
    if not warrant_type or not knight or not knight.sq then return nil end
    for y = 0, 7 do
        for x = 0, 7 do
            local sq = gsq(x, y)
            local hunter = sq and coop_piece_on_square(sq)
            if hunter and hunter.team == 1 and hunter.type == warrant_type
                and hunter.dead ~= true and (hunter.hp == nil or hunter.hp > 0) then
                local dx = abs(knight.sq.px - x)
                local dy = abs(knight.sq.py - y)
                if dx <= 1 and dy <= 1 and (dx ~= 0 or dy ~= 0) then
                    return hunter
                end
            end
        end
    end
    return nil
end

function coop_joust_blocks_shot()
    if not is_coop_active() or mode.coop_floor_transition
        or mode.coop_pause_menu_open or mode.coop_selected ~= "king"
        or not (has_card and has_card("Co-op Joust Compact")) then return false end
    local knight = mode.coop_knight
    if not knight or not knight.sq or knight.dead == true
        or (knight.hp ~= nil and knight.hp <= 0) then return false end
    for dy = -1, 1 do
        for dx = -1, 1 do
            if abs(dx) + abs(dy) == 1 then
                local sq = gsq(knight.sq.px + dx, knight.sq.py + dy)
                local piece = sq and coop_piece_on_square(sq)
                if piece and piece.team == 1 and piece.type == 1 then
                    return true
                end
            end
        end
    end
    return false
end

function coop_joust_allows_king_action(target)
    if not target or not hero or not hero.sq then return false end
    local occupant = coop_piece_on_square(target)
    if occupant then
        -- A legal blade strike uses the same board click as shooting. Keep
        -- that native action available while Joust Compact forbids gunfire.
        local dx = abs(target.px - hero.sq.px)
        local dy = abs(target.py - hero.sq.py)
        return occupant.team == 1 and dx <= 1 and dy <= 1
            and (dx ~= 0 or dy ~= 0) and stack and type(stack.blade) == "number"
            and stack.blade > 0 and (occupant.hp or 1) <= stack.blade
    end
    if not is_free(target) or type(get_range) ~= "function" then return false end
    local range = get_range(hero)
    if type(range) ~= "table" then return false end
    for _, square in ipairs(range) do
        if coop_as_square(square) == target then return true end
    end
    return false
end

function coop_award_warrant_knight_soul(piece)
    if not mode or mode.id ~= "coop" or not mode.coop_run_active
        or type(piece) ~= "table" or piece.team ~= 1
        or piece.type ~= get_coop_warrant_type()
        or piece.coop_warrant_soul_awarded then return end
    local dead = piece.dead == true or (piece.hp ~= nil and piece.hp <= 0)
        or not piece.sq or coop_piece_on_square(piece.sq) ~= piece
    if not dead then return end
    if type(add_soul) == "function" then
        -- This is a real capture, not the delayed refund from a soul used to
        -- revive 2P. Otherwise the add_soul hook can consume the new soul.
        mode.coop_soul_refund_watch = false
        mode.coop_soul_revival_descriptor = nil
        mode.coop_soul_refund_origin_px = nil
        mode.coop_soul_refund_origin_py = nil
        piece.coop_warrant_soul_awarded = true
        add_soul(1)
        if _log then _log("[COOP WARRANT] awarded Knight soul") end
    end
end

function coop_assign_warrant_hunter()
    if not is_coop_active() or mode.coop_floor_transition
        or mode.coop_spawn_wait_for_turn
        or mode.coop_warrant_assigned_floor == mode.lvl
        or not (has_card and has_card("Co-op Warrant")) then return end
    local warrant_type = get_coop_warrant_type()
    if not warrant_type then return end
    for y = 0, 7 do
        for x = 0, 7 do
            local sq = gsq(x, y)
            local piece = sq and coop_piece_on_square(sq)
            if piece and piece.team == 1 and piece.type == warrant_type then
                piece.coop_warrant_hunter = true
                mode.coop_warrant_hunter = piece
                mode.coop_warrant_assigned_floor = mode.lvl
                if _log then
                    _log("[COOP WARRANT] 缉骑官 assigned on floor "
                        .. coop_string(mode.lvl) .. " at " .. coop_trace_value(sq))
                end
                return
            end
        end
    end
    -- The card's custom piece cannot be passed through the native card gain
    -- parser. Spawn it only after init_new_turn has prepared the new board.
    local spawn_sq = coop_bounty_spawn_square()
    if not spawn_sq or type(new_piece) ~= "function" then return end
    local piece = new_piece(warrant_type, true, spawn_sq)
    if not piece then return end
    piece.coop_warrant_hunter = true
    mode.coop_warrant_hunter = piece
    mode.coop_warrant_assigned_floor = mode.lvl
    if type(fx_spawn) == "function" then fx_spawn(piece) end
    if _log then
        _log("[COOP WARRANT] spawned on floor " .. coop_string(mode.lvl)
            .. " at " .. coop_trace_value(spawn_sq))
    end
end

function coop_record_bounty_kill(piece, hp_before)
    if not is_coop_active() or not (has_card and has_card("Co-op Bounty Cavalry"))
        or type(piece) ~= "table" or piece.team ~= 1
        or piece.coop_bounty_counted or (hp_before ~= nil and hp_before <= 0) then return end
    local dead = piece.dead == true or (piece.hp ~= nil and piece.hp <= 0)
        or not piece.sq or coop_piece_on_square(piece.sq) ~= piece
    if not dead then return end
    piece.coop_bounty_counted = true
    mode.coop_bounty_kills = (mode.coop_bounty_kills or 0) + 1
    local kills = mode.coop_bounty_kills
    local reinforcement_type
    if has_card("Co-op Warrant") then
        if kills >= 3 then
            reinforcement_type = get_coop_warrant_type()
            mode.coop_bounty_kills = 0
        end
    elseif kills == 3 then
        reinforcement_type = 1
    elseif kills >= 6 then
        reinforcement_type = get_coop_warrant_type()
        mode.coop_bounty_kills = 0
    end
    if reinforcement_type then
        mode.coop_bounty_pending = mode.coop_bounty_pending or {}
        add(mode.coop_bounty_pending, reinforcement_type)
    end
    if _log then
        _log("[COOP BOUNTY] Knight kill count=" .. coop_string(mode.coop_bounty_kills)
            .. " queued=" .. coop_string(reinforcement_type))
    end
end

function coop_bounty_spawn_square()
    local files = {3, 4, 2, 5, 1, 6, 0, 7}
    for y = 0, 7 do
        for _, x in ipairs(files) do
            local sq = gsq(x, y)
            if sq and not sq.moat and not coop_has_barricade(sq)
                and not coop_piece_on_square(sq)
                and is_free(sq) then return sq end
        end
    end
    return nil
end

function coop_queue_royal_vigil(piece)
    if not is_coop_active() or mode.coop_floor_transition
        or not (has_card and has_card("Co-op Royal Vigil"))
        or not piece or piece.team ~= 1 or piece.type ~= 5
        or piece.dead == true or not piece.hp or piece.hp <= 0 then return end
    mode.coop_royal_vigil_pending = (mode.coop_royal_vigil_pending or 0) + 1
    if _log then
        _log("[COOP ROYAL VIGIL] queued Warden for next turn")
    end
end

function coop_knight_guarded_blade_damage(target, damage)
    if not target or target.team ~= 1 or target.type ~= 5
        or type(target.hp) ~= "number" or type(get_pieces) ~= "function" then
        return damage
    end
    local wardens = get_pieces(13)
    if type(wardens) ~= "table" then return damage end
    for _, warden in ipairs(wardens) do
        if warden and warden.team == 1 and warden.type == 13
            and warden.sq and warden.dead ~= true
            and (warden.hp == nil or warden.hp > 0) then
            local guarded_damage = min(damage, max(0, target.hp - 1))
            if _log and guarded_damage < damage then
                _log("[COOP ROYAL VIGIL] Warden prevents lethal Knight hit")
            end
            return guarded_damage
        end
    end
    return damage
end

function coop_grand_phalanx_blade_damage(target, damage)
    if not is_coop_active() or not (has_card and has_card("Co-op Grand Phalanx"))
        or not target or target.team ~= 1 or target.type ~= 0
        or not target.sq then return damage end
    for dy = -1, 1 do
        for dx = -1, 1 do
            if abs(dx) + abs(dy) == 1 then
                local sq = gsq(target.sq.px + dx, target.sq.py + dy)
                local neighbor = coop_piece_on_square(sq)
                if neighbor and neighbor ~= target
                    and neighbor.team == 1 and neighbor.type == 0 then
                    if _log then
                        _log("[COOP GRAND PHALANX] adjacent white pawn; blade "
                            .. coop_string(damage) .. "->" .. coop_string(max(0, damage - 1)))
                    end
                    return max(0, damage - 1)
                end
            end
        end
    end
    return damage
end

function coop_apply_blade_revenge(piece)
    if not is_coop_active() or mode.coop_floor_transition
        or not (has_card and has_card("Co-op Blade Revenge"))
        or not piece or piece.team ~= 1 or piece.dead == true
        or not piece.sq or (piece.hp ~= nil and piece.hp <= 0)
        or piece.ready == true or type(piece.cd) ~= "number" then return end
    local before = piece.cd
    if type(piece.tempo) == "number" then
        if piece.cd < piece.tempo then piece.cd = piece.cd + 1 end
    else
        piece.cd = piece.cd + 1
    end
    if _log then
        _log("[COOP BLADE REVENGE] type=" .. coop_string(piece.type)
            .. " cd=" .. coop_string(before) .. "->" .. coop_string(piece.cd)
            .. " tempo=" .. coop_string(piece.tempo))
    end
end

function coop_knight_sweep_targets(knight_square, target_square)
    local targets = {}
    if not knight_square or not target_square
        or not (has_card and has_card("Co-op Sweeping Blade")) then
        return targets
    end
    local dx = target_square.px - knight_square.px
    local dy = target_square.py - knight_square.py
    -- Rotate the adjacent attack vector 90 degrees for both side squares.
    -- Diagonal hits therefore splash diagonally; ranged spear hits do not.
    if max(abs(dx), abs(dy)) ~= 1 then return targets end
    local white_king_target
    local seen = {}
    local primary = coop_piece_on_square(target_square)
    if primary then seen[primary] = true end
    for _, side in ipairs({-1, 1}) do
        local square = gsq(target_square.px - dy * side,
            target_square.py + dx * side)
        local piece = coop_piece_on_square(square)
        if piece and piece.team == 1 and not seen[piece] then
            seen[piece] = true
            local entry = {piece=piece, square=square}
            if coop_is_white_king(piece) then
                white_king_target = entry
            else
                targets[#targets + 1] = entry
            end
        end
    end
    -- The white King can end the floor immediately, so damage it last.
    if white_king_target then targets[#targets + 1] = white_king_target end
    return targets
end

function coop_apply_knight_sweep(targets)
    local king_killed = false
    for _, entry in ipairs(targets) do
        if coop_floor_is_ending() then break end
        local piece, square = entry.piece, entry.square
        if piece and square and coop_piece_on_square(square) == piece then
            local was_white_king = coop_is_white_king(piece)
            local damage = coop_grand_phalanx_blade_damage(piece,
                coop_knight_guarded_blade_damage(piece,
                    1 + coop_duet_knight_bonus(piece) + coop_knight_pawn_damage_bonus(piece)))
            if damage > 0 then
                local hp_before = piece.hp
                local attacks = type(get_range) == "function"
                    and get_range(piece, {atk=1}) or nil
                hit(piece, damage, {coop_stats_owner=2})
                if piece.dead == true or (piece.hp ~= nil and piece.hp <= 0) then
                    coop_record_knight_kill_ui(piece, square, attacks)
                    if was_white_king then king_killed = true end
                end
                coop_record_bounty_kill(piece, hp_before)
                coop_queue_royal_vigil(piece)
                coop_apply_blade_revenge(piece)
                if _log then
                    _log("[COOP SWEEP] target=" .. coop_trace_value(piece)
                        .. " damage=" .. coop_string(damage))
                end
            end
        end
    end
    return king_killed
end

function coop_spawn_bounty_reinforcement()
    local pending = mode and mode.coop_bounty_pending
    local royal_pending = mode and mode.coop_royal_vigil_pending or 0
    if not is_coop_active() or mode.coop_floor_transition
        or mode.coop_force_king_kill_turn or mode.coop_surrender_input_locked
        or mode.coop_spawn_wait_for_turn or mode.coop_opening_king_turn
        or (royal_pending <= 0 and (not pending or #pending == 0))
        or type(new_piece) ~= "function" then return end
    local sq = coop_bounty_spawn_square()
    if not sq then return end
    local piece_type = royal_pending > 0 and 13 or pending[1]
    local piece = new_piece(piece_type, true, sq)
    if not piece then return end
    if royal_pending > 0 then
        mode.coop_royal_vigil_pending = royal_pending - 1
    else
        deli(pending, 1)
    end
    if type(fx_spawn) == "function" then fx_spawn(piece) end
    mode.coop_bounty_notice = {
        piece_type = piece_type, floor = mode.lvl, started = time(),
    }
    if _log then
        _log("[COOP REINFORCEMENT] spawned type=" .. coop_string(piece_type)
            .. " at " .. coop_trace_value(sq))
    end
end

function coop_spawn_revival_bishops()
    local pending = mode and mode.coop_revival_bishops_pending or 0
    if not is_coop_active() or mode.coop_floor_transition
        or mode.coop_force_king_kill_turn or mode.coop_surrender_input_locked
        or mode.coop_spawn_wait_for_turn or mode.coop_opening_king_turn
        or pending <= 0 or type(new_piece) ~= "function" then return end
    local spawned = 0
    for _ = 1, pending do
        local sq = coop_bounty_spawn_square()
        if not sq then break end
        local bishop = new_piece(2, true, sq)
        if not bishop then break end
        spawned = spawned + 1
        if type(fx_spawn) == "function" then fx_spawn(bishop) end
        if _log then
            _log("[COOP REVENANT BELL] spawned Bishop at " .. coop_trace_value(sq))
        end
    end
    mode.coop_revival_bishops_pending = pending - spawned
    if spawned > 0 then
        mode.coop_bounty_notice = {
            piece_type = 2, count = spawned, floor = mode.lvl, started = time(),
        }
    end
end

function coop_draw_bounty_notice()
    local notice = mode and mode.coop_bounty_notice
    if not notice then return end
    if not is_coop_active() or notice.floor ~= mode.lvl
        or time() - notice.started >= 1.5 then
        mode.coop_bounty_notice = nil
        return
    end
    if mode.coop_pause_menu_open then return end
    local label = get_lang("backup") .. ": "
        .. get_lang("piece_" .. notice.piece_type)
    if notice.count and notice.count > 1 then
        label = label .. " x" .. notice.count
    end
    local x = coop_floor_int(MCW / 2)
    lprint(label, x, board_y - 10, 5, 1)
end

function coop_queue_warrant_knight_check(knight)
    if mode and mode.id == "coop" and knight == mode.coop_knight then
        mode.coop_warrant_check_pending = knight
    end
end

function coop_resolve_warrant_knight_check()
    local knight = mode and mode.coop_warrant_check_pending
    if not knight then return end
    mode.coop_warrant_check_pending = nil
    if not is_coop_active() or mode.coop_floor_transition
        or knight ~= mode.coop_knight or not knight.sq then return end
    local hunter = coop_adjacent_warrant_hunter(knight)
    if not hunter then return end
    if _log then _log("[COOP WARRANT] 缉骑官 executes adjacent Black Knight") end
    mode.coop_warrant_execution_fx = {
        floor = mode.lvl, started = time(),
        hunter_x = hunter.sq.px, hunter_y = hunter.sq.py,
        knight_x = knight.sq.px, knight_y = knight.sq.py,
    }
    hunter.coop_janissary_shot={started=time(),angle=atan2(
        knight.sq.px-hunter.sq.px,knight.sq.py-hunter.sq.py)}
    local shot_run=mode
    wait(7,function() if mode==shot_run and is_coop_active() then sfx("shoot") end end)
    -- kill_piece is a nil-backed mod hook in this game build. Damage the
    -- Knight through the same hit path used by ordinary white attacks.
    if type(hit) == "function" then
        hit(knight, max(1, knight.hp or 1))
    end
    if mode.coop_knight == knight then coop_mark_knight_dead(knight) end
end

function coop_join(values, separator)
    local result = ""
    for i = 1, #values do
        if i > 1 then result = result .. separator end
        result = result .. values[i]
    end
    return result
end

function coop_copy_table(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[coop_copy_table(key, seen)] = coop_copy_table(child, seen)
    end
    return copy
end

function coop_no_soul_moves(e, max_range, flying, add_sq)
    -- Keep native target generation empty for the 2P piece and while
    -- resolving a Knight soul used for revival. Co-op input owns 2P actions.
end

function coop_get_knight_soul_piece()
    for _, piece in ipairs(PIECES) do
        if piece.type == 1 then return piece end
    end
    return nil
end

function coop_is_white_king(value)
    if type(value) ~= "table" then return false end
    -- A native piece may itself have a `piece` field. Check it first rather
    -- than treating that field as a wrapper around the actual piece.
    if value.team == 1 and (value.type == 5 or value.boss) then return true end
    local piece = value.piece
    if type(piece) == "table" and piece.team == 1
        and (piece.type == 5 or piece.boss) then return true end
    piece = value.p
    return type(piece) == "table" and piece.team == 1
        and (piece.type == 5 or piece.boss) or false
end

function coop_floor_is_ending()
    if not mode or mode.id ~= "coop" then return false end
    if mode.coop_floor_transition or mode.coop_surrender_input_locked
        or mode.coop_force_king_kill_turn or mode.coop_king_kill_pending_floor then
        return true
    end
    if mode.coop_spawn_wait_for_turn then return false end
    -- The King's gun can kill the white King without going through the
    -- Knight's blade lock. Detect that death before the surrender event has
    -- finished, so init_new_turn cannot grant another Knight action.
    return type(boss) == "table" and coop_is_white_king(boss)
        and (boss.dead == true or (type(boss.hp) == "number" and boss.hp <= 0))
end

function coop_resume_after_heir()
    if not mode or mode.id~="coop" or not mode.coop_heir_reveal_floor then return end
    if mode.coop_heir_reveal_floor~=mode.lvl or mode.coop_floor_transition then
        mode.coop_heir_reveal_floor=nil
        return
    end
    -- Called by native play after the reveal's continuation. Do not unlock
    -- when the heir was absent/killed and native surrender is still pending.
    if not hero or hero.win or hero.dead or #events>0 then return end
    local alive=false
    for _,p in ipairs(get_pieces(5)) do
        if p.sq and not p.dead and p.hp>0 then alive=true;break end
    end
    if not alive then return end
    mode.coop_heir_reveal_floor=nil
    mode.coop_surrender_input_locked=false
    mode.coop_force_king_kill_turn=nil
    mode.coop_king_kill_pending_floor=nil
    mode.coop_king_kill_pending_frames=nil
    mode.coop_king_move_input_locked=nil
    mode.coop_auto_select_knight_pending=nil
    mode.coop_select_king_pending=nil
    mode.black_actions=1
    hero.ready=true
    coop_set_selected("king")
    _log("[COOP HEIR] native reveal completed; restore King action floor="..mode.lvl)
end

function coop_white_move_animation_pending()
    return mode and (mode.coop_white_move_grace_frames or 0) > 0
end

function coop_is_knight(value)
    local knight_type = get_coop_knight_type()
    if type(value) == "number" then
        return knight_type ~= nil and value == knight_type
    end
    if type(value) ~= "table" then return false end
    local piece = value.piece or value.entity or value.target or value
    if type(piece) ~= "table" then return false end
    return piece == mode.coop_knight
        or piece.name == "coop_knight"
        or (knight_type ~= nil and piece.type == knight_type)
end

function coop_event_has_knight(...)
    local values = {...}
    for i = 1, #values do
        if coop_is_knight(values[i]) then return true end
    end
    return false
end

function coop_mark_knight_dead(piece)
    if not mode or mode.id ~= "coop" or not mode.coop_knight then return false end
    if piece ~= mode.coop_knight and not coop_is_knight(piece) then return false end
    local knight = mode.coop_knight
    local stats = mode.coop_stats
    if stats and stats.running then stats.knight_deaths = stats.knight_deaths + 1 end
    knight.hp = 0
    knight.ready = false
    mode.coop_knight = nil
    for _,slot in ipairs(card_slots or {}) do
        local ca=slot.ca
        if ca and ca.id=="Co-op Divisive Edict" and not ca.flipped then
            flip_card(ca)
        end
    end
    coop_refresh_divisive_edict()
    mode.coop_knight_charge = nil
    mode.coop_rally_pending = false
    mode.coop_ritual_dagger_pending = false
    mode.coop_ritual_dagger_target = nil
    mode.coop_warrant_check_pending = nil
    mode.coop_knight_selected_soul = nil
    -- A replacement Knight starts with its own blade and turn count.
    mode.coop_grindstone_turns = 0
    mode.coop_grindstone_bonus = 0
    mode.coop_grindstone_last_turn = nil
    mode.coop_spawning = false
    mode.knight_ever_died = true
    mode.coop_block_knight_soul_range = true
    mode.coop_soul_range_block_turn = nil
    mode.coop_knight_missing_frames = 0
    mode.coop_knight_seen_on_board = false
    mode.coop_knight_move_origin_sq = nil
    -- The old jump squares belong to this Knight instance. Keeping them
    -- after death can intercept King clicks even after a replacement spawns.
    mode.coop_last_knight_origin_sq = nil
    mode.coop_last_knight_destination_sq = nil
    mode.coop_auto_select_knight_pending = nil
    mode.coop_dead_knight_cursor_refresh_pending = true
    -- Enemy captures usually happen with the King already selected. Avoid
    -- rebuilding the native cursor while the remaining white pieces move.
    if mode.coop_selected ~= "king" or mode.coop_king_hero then
        coop_set_selected("king")
    end
    print("[COOP] knight death recorded")
    if _log then _log("[COOP] knight death recorded at floor " .. coop_string(mode.lvl)) end
    return true
end

function coop_log_knight_state(label)
    if not _log or not mode or mode.id ~= "coop" then return end
    local knight = mode.coop_knight
    local square = knight and knight.sq
    local occupant = square and square.piece
    _log("[COOP] " .. label
        .. " floor=" .. coop_string(mode.lvl)
        .. " died=" .. coop_string(mode.knight_ever_died)
        .. " knight=" .. coop_string(knight ~= nil)
        .. " hp=" .. coop_string(knight and knight.hp)
        .. " sq=" .. coop_string(square and (coop_string(square.px) .. "," .. coop_string(square.py)))
        .. " occupant=" .. coop_string(occupant and (occupant.name or occupant.type))
        .. " seen=" .. coop_string(mode.coop_knight_seen_on_board)
        .. " missing=" .. coop_string(mode.coop_knight_missing_frames))
end

function coop_refresh_knight_death()
    local knight = mode and mode.coop_knight
    if not knight then return end
    if knight.dead == true or (knight.hp ~= nil and knight.hp <= 0) then
        coop_mark_knight_dead(knight)
    end
end

function coop_knight_is_on_board(knight)
    if not knight or knight.dead == true
        or (knight.hp ~= nil and knight.hp <= 0) then return false end
    local current_sq = knight.sq
    if current_sq and coop_piece_on_square(current_sq) == knight then return true end
    for y = 0, 7 do
        for x = 0, 7 do
            local sq = gsq(x, y)
            if sq and coop_piece_on_square(sq) == knight then return true end
        end
    end
    return false
end

function coop_track_knight_presence()
    local knight = mode and mode.coop_knight
    if not knight or mode.coop_floor_transition or mode.coop_spawning then return end
    if knight.dead == true then
        coop_mark_knight_dead(knight)
        return
    end

    -- An enemy occupying the Knight's current square is a completed capture,
    -- even if this game build leaves the removed piece's `sq` reference set.
    if knight.sq and knight.sq.piece and knight.sq.piece ~= knight then
        if _log then
            _log("[COOP GUARD] Knight square occupied by "
                .. coop_trace_value(knight.sq.piece)
                .. " at " .. coop_trace_value(knight.sq))
        end
        coop_mark_knight_dead(knight)
        return
    end

    if coop_knight_is_on_board(knight) then
        mode.coop_knight_seen_on_board = true
        mode.coop_knight_missing_frames = 0
        return
    end

    -- Do not infer death during spawn or before this floor has shown the
    -- knight on the board. A short grace period also covers move animations.
    if not mode.coop_knight_seen_on_board then return end
    mode.coop_knight_missing_frames = (mode.coop_knight_missing_frames or 0) + 1
    if mode.coop_knight_missing_frames == 1 and _log then
        _log("[COOP GUARD] Knight missing from board hp=" .. coop_string(knight.hp)
            .. " dead=" .. coop_string(knight.dead)
            .. " sq=" .. coop_trace_value(knight.sq))
    end
    if mode.coop_knight_missing_frames >= 12 then
        coop_mark_knight_dead(knight)
    end
end

function coop_record_knight_state_before_floor_change()
    if not mode or mode.id ~= "coop" or not mode.coop_knight then return end
    local knight = mode.coop_knight
    -- Do not infer death from board-wide occupancy here: the engine can clear
    -- or rebuild it before on_empty. A missing piece square or zero HP is safe.
    if knight.dead == true or (knight.hp ~= nil and knight.hp <= 0)
        or knight.sq == nil then
        coop_mark_knight_dead(knight)
    end
end

function coop_trace_value(value)
    if type(value) ~= "table" then return type(value) .. ":" .. coop_string(value) end
    if value.px ~= nil and value.py ~= nil then
        -- The native board stores its occupant in `p`. `piece` is only used
        -- by some UI paths, so logging that field alone hid occupied squares.
        local occupant = value.p or value.piece
        if type(occupant) ~= "table" then occupant = nil end
        local label = occupant and (occupant.name or ("type" .. coop_string(occupant.type))) or "empty"
        return "square(" .. coop_string(value.px) .. "," .. coop_string(value.py) .. "," .. label .. ")"
    end
    if value.name or value.type ~= nil then
        local ranges = {}
        if value.name == "coop_knight" then
            for key, child in pairs(value) do
                if type(child) == "table" and #child > 0 then
                    local king_count = 0
                    for _, target in ipairs(child) do
                        if coop_is_white_king(target) then king_count = king_count + 1 end
                    end
                    add(ranges, coop_string(key) .. "[" .. coop_string(#child) .. ";king=" .. coop_string(king_count) .. "]")
                end
            end
        end
        local range_info = #ranges > 0 and (",lists=" .. coop_join(ranges, "/")) or ""
        return "piece(" .. coop_string(value.name or "?") .. ",type=" .. coop_string(value.type)
            .. ",team=" .. coop_string(value.team) .. ",sq=" .. coop_string(value.sq and value.sq.px)
            .. "," .. coop_string(value.sq and value.sq.py) .. range_info .. ")"
    end
    return "table"
end

function coop_ignore_stale_button() end

function coop_safe_all_buttons(allow_surrender_lock)
    -- The native button tree is rebuilt between floors and while entering
    -- menus or processing a move. Do not traverse it until the board and
    -- native event queue are stable again.
    if not is_coop_active() or mode.coop_floor_transition
        or mode.coop_spawn_wait_for_turn
        or mode.coop_pause_menu_open
        or coop_white_move_animation_pending()
        or (not allow_surrender_lock and mode.coop_auto_select_knight_pending)
        or (not allow_surrender_lock and mode.coop_native_turn_in_progress)
        or (not allow_surrender_lock and hero and hero.in_move)
        or (not allow_surrender_lock
            and type(events) == "table" and #events > 0) then return nil end
    if type(get_all_buts) ~= "function" then return nil end
    -- This game's Lua environment normally has no pcall. Keep native button
    -- traversal available for input while avoiding an unsupported call.
    if type(pcall) ~= "function" then return get_all_buts() end
    -- Other Lua hosts may support catching a transient UI rebuild error.
    local ok, buttons = pcall(get_all_buts)
    if not ok then
        if mode and not mode.coop_button_scan_error_logged and _log then
            _log("[COOP UI] skipped invalid button tree: " .. tostring(buttons))
            mode.coop_button_scan_error_logged = true
        end
        return nil
    end
    if mode then mode.coop_button_scan_error_logged = false end
    if type(buttons) == "table" then return buttons end
    return nil
end

function coop_native_menu_button_at(x, y)
    -- Undercover Mission can put a choice button over the board while the
    -- King's post-move click guard is active. Leave that button's click for
    -- the native UI; only square buttons represent board actions here.
    local buttons = coop_safe_all_buttons()
    if type(buttons) ~= "table" then return false end
    for _, button in ipairs(buttons) do
        if type(button) == "table" and not button.issq
            and type(button.left_clic) == "function"
            and button.left_clic ~= coop_ignore_stale_button
            and type(button.x) == "number" and type(button.y) == "number"
            and type(button.w) == "number" and type(button.h) == "number"
            and x >= button.x and x < button.x + button.w
            and y >= button.y and y < button.y + button.h then
            return true
        end
    end
    return false
end

function coop_draw_empty_soul_slot(soul, x, y)
    -- The native scene skips the exhausted soul entity entirely, so this is
    -- called from draw_game for empty guarded slots instead of soul.dr.
    if type(x) ~= "number" or type(y) ~= "number" then
        x = soul and soul.x
        y = soul and soul.y
    end
    if type(x) ~= "number" or type(y) ~= "number" then return end
    -- Match the native empty soul slot: its outline starts one pixel right of
    -- the soul descriptor and on the descriptor's y, with a four-pixel break
    -- halfway down each side.
    local left, top = x + 1, y
    local right, bottom = left + 20, top + 28
    local color = 2
    rectfill(left + 1, top, left + 8, top, color)
    rectfill(right - 8, top, right - 1, top, color)
    rectfill(left, top + 1, left + 1, top + 1, color)
    rectfill(right - 1, top + 1, right, top + 1, color)
    rectfill(left, top + 2, left, top + 11, color)
    rectfill(right, top + 2, right, top + 11, color)
    rectfill(left, top + 16, left, bottom - 2, color)
    rectfill(right, top + 16, right, bottom - 2, color)
    rectfill(left, bottom - 1, left + 1, bottom - 1, color)
    rectfill(right - 1, bottom - 1, right, bottom - 1, color)
    rectfill(left + 1, bottom, left + 8, bottom, color)
    rectfill(right - 8, bottom, right - 1, bottom, color)
end

function coop_draw_soul_vanish()
    local fx = mode and mode.coop_soul_vanish_fx
    if not fx or mode.coop_pause_menu_open then return end
    fx.frame = (fx.frame or 0) + 1
    if fx.frame > 8 then
        mode.coop_soul_vanish_fx = nil
        return
    end
    local x, y = fx.x + 11, fx.y + 14
    local spread = fx.frame + 1
    pset(x - spread, y - spread, 5)
    pset(x + spread, y - spread, 3)
    pset(x - spread, y + spread, 3)
    pset(x + spread, y + spread, 5)
end

function coop_draw_selected_soul_dissolve()
    local fx = mode and mode.coop_soul_selection_fx
    if not fx or mode.coop_selected ~= "knight"
        or not mode.coop_knight_selected_soul
        or mode.coop_pause_menu_open then return end
    local x, y = fx.x, fx.y
    if type(x) ~= "number" or type(y) ~= "number" then return end

    -- This covers only the card pixels; the live soul is not modified until
    -- a destination is chosen. A right-click stops the overlay and restores it.
    fx.frame = min(8, (fx.frame or 0) + 1)
    local visible_height = 32 - fx.frame * 4
    rectfill(x, y + visible_height, x + 23, y + 31, 1)
    if visible_height == 0 then
        coop_draw_empty_soul_slot(nil, x, y)
    else
        local edge = y + visible_height - 1
        pset(x + 4, edge, 5)
        pset(x + 12, edge, 3)
        pset(x + 20, edge, 5)
    end
end

function coop_mute_spent_soul_buttons(guard)
    if not guard or not guard.soul or guard.soul.id ~= nil
        or type(get_all_buts) ~= "function" then return end
    local buttons = coop_safe_all_buttons()
    if type(buttons) ~= "table" then return end
    guard.buttons = guard.buttons or {}
    for _, button in ipairs(buttons) do
        if type(button) == "table" and not button.issq
            and button.x == guard.soul.x and button.y == guard.soul.y
            and type(button.left_clic) == "function"
            and button.left_clic ~= coop_ignore_stale_button then
            -- get_all_buts returns the live button objects. The native soul
            -- button is 24x32 although its icon is only 16x16, so muting its
            -- callback covers the whole clickable area without guessing at
            -- mouse coordinates or interfering with the other soul slot.
            guard.buttons[#guard.buttons + 1] = {
                button = button,
                left_clic = button.left_clic,
                right_clic = button.right_clic,
                over = (mode.coop_knight_soul_hover_guards
                    and mode.coop_knight_soul_hover_guards[button]
                    and mode.coop_knight_soul_hover_guards[button].over)
                    or button.over,
            }
            guard.saved_button_callbacks = guard.saved_button_callbacks or {
                left_clic = button.left_clic,
                right_clic = button.right_clic,
                over = guard.buttons[#guard.buttons].over,
            }
            button.left_clic = coop_ignore_stale_button
            button.right_clic = coop_ignore_stale_button
            button.over = coop_ignore_stale_button
            if _log then
                _log("[COOP SOUL] muted exhausted slot button x="
                    .. coop_string(button.x) .. " y=" .. coop_string(button.y)
                    .. " w=" .. coop_string(button.w)
                    .. " h=" .. coop_string(button.h))
            end
        end
    end
end

function coop_hide_spent_soul(guard)
    if not guard or not guard.soul or guard.soul.id ~= nil then return end
    -- The native draw callback can still run on an exhausted descriptor and
    -- expects a numeric id. Mute it until the slot is refilled; the guard is
    -- kept across floors so its original callback can then be restored.
    guard.soul.dr = coop_ignore_stale_button
    guard.soul.oid = nil
    guard.soul.ov = false
    coop_mute_spent_soul_buttons(guard)
end

function coop_restore_spent_soul_buttons(guard)
    -- Knight mode intentionally mutes native soul hover callbacks. Restore
    -- exhausted-slot buttons only after switching back to the King, otherwise
    -- the saved hover callback can re-enable the King's range preview there.
    if not mode or mode.coop_selected ~= "king" then return nil end
    local buttons = coop_safe_all_buttons()
    -- A refill can happen during a kill animation. At that point the native
    -- button tree is temporarily unsafe to scan; keep the guard for an idle
    -- frame instead of discarding its saved callback.
    if type(buttons) ~= "table" then
        if not guard.restore_retry_logged and _log then
            _log("[COOP SOUL] defer button restore until UI is stable")
            guard.restore_retry_logged = true
        end
        return nil
    end
    local live = {}
    for _, button in ipairs(buttons) do live[button] = true end
    local restored = 0
    local matching_button = nil
    for _, button in ipairs(buttons) do
        if type(button) == "table" and not button.issq
            and guard.soul and button.x == guard.soul.x
            and button.y == guard.soul.y
            and button.w == 24 and button.h == 32 then
            matching_button = button
            break
        end
    end
    if not matching_button then
        if not guard.restore_retry_logged and _log then
            _log("[COOP SOUL] defer button restore until slot button exists")
            guard.restore_retry_logged = true
        end
        return nil
    end
    for _, entry in ipairs(guard.buttons or {}) do
        local button = entry.button
        if live[button] and button.left_clic == coop_ignore_stale_button then
            button.left_clic = entry.left_clic
            button.right_clic = entry.right_clic
            button.over = entry.over
            restored = restored + 1
        end
    end
    local saved = guard.saved_button_callbacks
    if saved and guard.soul then
        for _, button in ipairs(buttons) do
            if type(button) == "table" and not button.issq
                and button.x == guard.soul.x and button.y == guard.soul.y
                and button.w == 24 and button.h == 32
                and (button.left_clic == coop_ignore_stale_button
                    or (guard.soul.id ~= nil
                        and button.left_clic ~= saved.left_clic)) then
                -- The refilled slot can get a replacement button while its
                -- original descriptor remains alive. Reattach the callback
                -- captured before exhaustion to that exact slot.
                button.left_clic = saved.left_clic
                button.right_clic = saved.right_clic
                button.over = saved.over
                restored = restored + 1
            end
        end
    end
    if restored > 0 and _log then
        _log("[COOP SOUL] restored live button callbacks=" .. coop_string(restored)
            .. " x=" .. coop_string(guard.soul and guard.soul.x)
            .. " y=" .. coop_string(guard.soul and guard.soul.y))
    end
    return restored
end

function coop_restore_spent_soul(guard)
    if not guard or not guard.soul or guard.soul.id == nil then return false end
    if not guard.descriptor_restored then
        -- Repair descriptors hidden by older versions of this hook, while
        -- keeping a fresh draw callback installed by native add_soul intact.
        if guard.soul.dr == coop_ignore_stale_button then
            guard.soul.dr = guard.draw
        end
        -- Preserve native oid timing. A freshly filled soul normally has
        -- oid=nil; forcing oid=id can suppress its normal entry drawing.
        if guard.oid ~= nil and guard.soul.oid == nil then
            guard.soul.oid = guard.oid
        end
        -- Hiding an exhausted slot also clears its hover/overlay state. The
        -- native add_soul path reuses the descriptor without resetting ov.
        guard.soul.ov = guard.ov
        guard.descriptor_restored = true
        if _log then
            _log("[COOP SOUL] restored filled slot x=" .. coop_string(guard.soul.x)
                .. " y=" .. coop_string(guard.soul.y)
                .. " id=" .. coop_string(guard.soul.id)
                .. " oid=" .. coop_string(guard.soul.oid)
                .. " draw=" .. type(guard.soul.dr)
                .. " ov=" .. coop_string(guard.soul.ov))
        end
    end
    return coop_restore_spent_soul_buttons(guard) ~= nil
end

function coop_release_spent_soul_slot(slot)
    if type(slot) ~= "table" or slot.id == nil
        or type(slot.x) ~= "number" or type(slot.y) ~= "number" then return end
    local guards = mode and mode.coop_spent_soul_click_guards
    if type(guards) ~= "table" then return end
    for index = #guards, 1, -1 do
        local guard = guards[index]
        local old = guard.soul
        if old and (old == slot or (old.x == slot.x and old.y == slot.y)) then
            local ready
            if old == slot then
                ready = coop_restore_spent_soul(guard)
            else
                -- A replacement descriptor now owns this coordinate. The old
                -- empty descriptor stays hidden, but its button must no longer
                -- intercept the newly filled slot.
                guard.refilled_slot = slot
                ready = coop_restore_spent_soul_buttons(guard) ~= nil
            end
            if ready then deli(guards, index) end
        end
    end
    mode.coop_spent_soul_click_guard = guards[#guards]
end

function coop_track_spent_soul(soul)
    local native_draw = soul.dr
    if native_draw == coop_ignore_stale_button then
        native_draw = soul.coop_native_draw
    end
    local guard = {soul=soul, draw=native_draw, ov=soul.ov, oid=soul.oid}
    -- The slot descriptor can survive a floor change after the run-local
    -- guard list is reset. Keep its native draw callback on that descriptor.
    soul.coop_native_draw = native_draw
    soul.coop_native_ov = soul.ov
    soul.coop_native_oid = soul.oid
    mode.coop_spent_soul_click_guards = mode.coop_spent_soul_click_guards or {}
    add(mode.coop_spent_soul_click_guards, guard)
    mode.coop_spent_soul_click_guard = guard
    return guard
end

function coop_restore_refilled_soul(slot)
    if type(slot) ~= "table" or slot.id == nil
        or slot.dr ~= coop_ignore_stale_button then return end
    if type(slot.coop_native_draw) == "function" then
        slot.dr = slot.coop_native_draw
        slot.ov = slot.coop_native_ov
        if slot.oid == nil then slot.oid = slot.coop_native_oid end
        if _log then
            _log("[COOP SOUL] restored persistent slot draw x="
                .. coop_string(slot.x) .. " y=" .. coop_string(slot.y)
                .. " id=" .. coop_string(slot.id))
        end
    end
end

function coop_refresh_spent_souls()
    local guards = mode and mode.coop_spent_soul_click_guards
    if type(guards) ~= "table" then return end
    for index = #guards, 1, -1 do
        local guard = guards[index]
        if guard.refilled_slot and guard.refilled_slot.id ~= nil then
            if coop_restore_spent_soul_buttons(guard) ~= nil then
                deli(guards, index)
            end
        elseif coop_restore_spent_soul(guard) then
            deli(guards, index)
        else
            coop_hide_spent_soul(guard)
        end
    end
    mode.coop_spent_soul_click_guard = guards[#guards]
end

function coop_spend_knight_soul(soul)
    if not soul or soul.id == nil or type(exhaust_soul) ~= "function" then return false end
    local guard = coop_track_spent_soul(soul)
    if type(soul.x) == "number" and type(soul.y) == "number" then
        mode.coop_soul_vanish_fx = {x=soul.x, y=soul.y, frame=0}
    end
    mode.coop_stats_soul_owner = 2
    exhaust_soul(soul)
    mode.coop_stats_soul_owner = nil
    coop_hide_spent_soul(guard)
    mode.coop_knight_selected_soul = nil
    mode.coop_soul_selection_fx = nil
    sfx("menu_out", .6)
    return true
end

function coop_get_soul_button_at(x, y)
    if type(get_all_buts) ~= "function" then return nil end
    local buttons = coop_safe_all_buttons()
    if type(buttons) ~= "table" then return nil end
    local board_left = coop_get_board_geometry()
    for _, button in ipairs(buttons) do
        if type(button) == "table" and not button.issq
            and type(button.left_clic) == "function"
            and button.left_clic ~= coop_ignore_stale_button
            and type(button.x) == "number" and type(button.y) == "number"
            and button.x >= board_left + 128
            and button.w == 24 and button.h == 32
            and x >= button.x and x < button.x + button.w
            and y >= button.y and y < button.y + button.h then
            return button
        end
    end
    return nil
end

function coop_get_known_soul_at(x, y)
    -- Draw callbacks must not traverse the live native button tree.
    for _, soul in ipairs(mode.coop_known_soul_slots or {}) do
        if type(soul) == "table" and soul.id ~= nil
            and type(soul.x) == "number" and type(soul.y) == "number"
            and x >= soul.x and x < soul.x + 24
            and y >= soul.y and y < soul.y + 32 then
            return soul
        end
    end
    return nil
end

function coop_is_soul_button_at(x, y)
    return coop_get_soul_button_at(x, y) ~= nil
end

function coop_find_soul_for_button(button)
    if not button then return nil end
    local function matches(value)
        return type(value) == "table" and type(value.id) == "number"
            and value.id >= 1 and value.id <= 3
            and value.x == button.x and value.y == button.y
            and (type(value.dr) == "function" or value.oid ~= nil)
    end
    for _, collection in pairs({known=mode and mode.coop_known_soul_slots,
        entities=ents, souls=souls, soul_slots=soul_slots,
        hero_souls=hero and hero.souls,
        hero_soul_slots=hero and hero.soul_slots,
        mode_souls=mode and mode.souls}) do
        if type(collection) == "table" then
            for _, value in pairs(collection) do
                if matches(value) then return value end
            end
        end
    end
    for _, value in pairs(button) do
        if matches(value) then return value end
    end
    -- The native soul button may hold its descriptor as a Lua closure
    -- upvalue rather than an entity. Read it only when that API is present.
    local getupvalue = type(debug) == "table" and debug.getupvalue
    if type(getupvalue) == "function" and type(pcall) == "function" then
        for index = 1, 20 do
            local ok, name, value = pcall(getupvalue, button.left_clic, index)
            if not ok or name == nil then break end
            if matches(value) then return value end
        end
    end
    return nil
end

function coop_sync_knight_soul_hover()
    local guards = mode and mode.coop_knight_soul_hover_guards or {}
    -- A selection change may occur while white pieces are still moving.
    -- Restoring callbacks on an old button at that point can race the native
    -- UI rebuild just as much as scanning for new buttons can.
    if not mode or mode.coop_floor_transition or mode.coop_pause_menu_open
        or mode.coop_auto_select_knight_pending
        or coop_white_move_animation_pending()
        or mode.coop_native_turn_in_progress or (hero and hero.in_move)
        or (type(events) == "table" and #events > 0) then return end
    if mode and mode.coop_selected == "knight" and is_coop_active()
        and not mode.coop_pause_menu_open and type(get_all_buts) == "function" then
        -- Nothing needs a hover override while every known soul slot is empty.
        -- In particular, avoid walking the native button tree every idle frame
        -- after a Knight soul has been exhausted.
        local has_live_soul = false
        for _, soul in ipairs(mode.coop_known_soul_slots or {}) do
            if soul and soul.id ~= nil then
                has_live_soul = true
                break
            end
        end
        if not has_live_soul then return end
        local buttons = coop_safe_all_buttons()
        if type(buttons) == "table" then
            local board_left = coop_get_board_geometry()
            for _, button in ipairs(buttons) do
                if type(button) == "table" and not button.issq
                    and type(button.x) == "number"
                    and button.x >= board_left + 128
                    and button.w == 24 and button.h == 32
                    and type(button.left_clic) == "function"
                    and button.left_clic ~= coop_ignore_stale_button
                    and type(button.over) == "function"
                    and button.over ~= coop_ignore_stale_button then
                    if not guards[button] then
                        guards[button] = {over=button.over,
                            left_clic=button.left_clic}
                    end
                    -- Native soul hover previews the King's range. Knight
                    -- movement previews are drawn by coop_draw_knight_move_hints.
                    button.over = coop_ignore_stale_button
                end
            end
        end
        mode.coop_knight_soul_hover_guards = guards
        return
    end
    local has_guards = false
    for _ in pairs(guards) do has_guards = true break end
    if not has_guards then return end
    local buttons = coop_safe_all_buttons()
    if type(buttons) ~= "table" then return end
    local live_buttons = {}
    for _, button in ipairs(buttons) do live_buttons[button] = true end
    for button, guard in pairs(guards) do
        if live_buttons[button] and button.left_clic == guard.left_clic
            and button.over == coop_ignore_stale_button then
            button.over = guard.over
        end
    end
    if mode then mode.coop_knight_soul_hover_guards = {} end
end

function coop_lock_surrender_controls()
    if not mode or mode.id ~= "coop" or not mode.coop_surrender_input_locked then return end
    -- The blade kill starts a native surrender animation. Keep the King's
    -- board controls inactive, but leave the mouse click itself untouched so
    -- the native animation can still be fast-forwarded.
    if mode.coop_selected ~= "king" then coop_set_selected("king") end
    mode.coop_select_king_pending = nil
    mode.coop_auto_select_knight_pending = nil
    mode.coop_cursor_refresh_pending = false
    if hero then hero.ready = false end
    if type(get_all_buts) ~= "function" then return end
    local buttons = coop_safe_all_buttons(true)
    if type(buttons) ~= "table" then return end
    for _, button in ipairs(buttons) do
        if type(button) == "table" and button.issq then
            button.dr = coop_ignore_stale_button
            button.over = coop_ignore_stale_button
            button.left_clic = coop_ignore_stale_button
            -- An invisible square button would still capture a click intended
            -- to skip surrender, so move its hit area off the screen too.
            button.x = -1000
            button.y = -1000
        end
    end
end

function coop_mute_king_button_on_knight_square()
    if not mode or mode.id ~= "coop" or mode.coop_selected ~= "king"
        or not mode.coop_knight or not mode.coop_knight.sq
        or type(get_all_buts) ~= "function" then return end
    local knight_sq = mode.coop_knight.sq
    local board_left, board_top = coop_get_board_geometry()
    local x = board_left + knight_sq.px * 16
    local y = board_top + knight_sq.py * 16
    local buttons = coop_safe_all_buttons()
    if type(buttons) ~= "table" then return end
    for _, button in ipairs(buttons) do
        if type(button) == "table" and button.issq
            and button.x == x and button.y == y then
            -- Revival can happen after the King move buttons were built.
            -- Hide any now-stale move arrow over the occupied Knight square.
            button.dr = coop_ignore_stale_button
            button.over = coop_ignore_stale_button
            button.left_clic = coop_ignore_stale_button
        end
    end
end

function coop_mute_stale_knight_pickup(rebuild_arrow)
    if not mode or mode.id ~= "coop" or not mode.coop_last_knight_origin_sq
        or type(get_all_buts) ~= "function" then return end
    local buttons = coop_safe_all_buttons()
    if type(buttons) ~= "table" then return end
    local old_square = mode.coop_last_knight_origin_sq
    local board_left, board_top = coop_get_board_geometry()
    local old_x = board_left + old_square.px * 16
    local old_y = board_top + old_square.py * 16
    local muted = 0
    for _, button in ipairs(buttons) do
        if type(button) == "table" and button.issq
            and button.x == old_x and button.y == old_y
            and type(button.left_clic) == "function" then
            -- The returned list is a copy, but its buttons are the live
            -- objects. Only the old pickup control has a click callback here.
            button.dr = coop_ignore_stale_button
            button.over = coop_ignore_stale_button
            button.left_clic = coop_ignore_stale_button
            muted = muted + 1
        end
    end
    if _log then _log("[COOP PICKUP] muted stale old-square buttons=" .. muted) end

    -- The old square is empty after the jump, but the native movement
    -- buttons were built while the Knight still occupied it. Add the same
    -- square button the King would receive on a fresh turn when that square
    -- is currently in the King's legal movement range. Click handling stays
    -- with the co-op controller's existing old-square path.
    if rebuild_arrow and muted > 0 and mode.coop_selected == "king" and hero and hero.sq
        and is_free(old_square) and type(get_range) == "function"
        and type(mk_sq_but) == "function" then
        local king_range = get_range(hero)
        if type(king_range) == "table" then
            local dx = old_square.px - hero.sq.px
            local dy = old_square.py - hero.sq.py
            if dx > 0 then dx = 1 elseif dx < 0 then dx = -1 end
            if dy > 0 then dy = 1 elseif dy < 0 then dy = -1 end
            -- Native mk_sq_but uses compass directions, not the position of
            -- the square in get_range's filtered result list.
            local directions = {
                ["1,0"] = 0, ["0,1"] = 1, ["-1,0"] = 2, ["0,-1"] = 3,
                ["1,1"] = 4, ["-1,1"] = 5, ["-1,-1"] = 6, ["1,-1"] = 7,
            }
            local direction = directions[dx .. "," .. dy]
            for _, entry in ipairs(king_range) do
                if coop_as_square(entry) == old_square then
                    if direction ~= nil then
                        mk_sq_but(old_square, coop_ignore_stale_button, direction)
                    end
                    if _log then
                        _log("[COOP PICKUP] rebuilt King move arrow at old Knight square direction="
                            .. coop_string(direction))
                    end
                    break
                end
            end
        end
    end
end

function coop_mute_dead_victim_button()
    if not is_coop_active() or mode.coop_selected ~= "king"
        or not mode.coop_knight_killed_square then return false end
    local buttons = coop_safe_all_buttons()
    if type(buttons) ~= "table" then return false end
    local board_left, board_top = coop_get_board_geometry()
    local muted = 0
    local killed_squares = mode.coop_knight_killed_squares
        or {[mode.coop_knight_killed_square]=true}
    for sq in pairs(killed_squares) do
        if not coop_piece_on_square(sq) then
            -- A dead victim can remain in the square cache after removal.
            local cached_piece = sq.piece
            if cached_piece and (cached_piece.dead == true
                or (cached_piece.hp ~= nil and cached_piece.hp <= 0)) then
                sq.piece = nil
            end
            local x, y = board_left + sq.px * 16, board_top + sq.py * 16
            for _, button in ipairs(buttons) do
                if type(button) == "table" and button.issq
                    and button.x == x and button.y == y then
                    button.dr = coop_ignore_stale_button
                    button.over = coop_ignore_stale_button
                    button.left_clic = coop_ignore_stale_button
                    muted = muted + 1
                end
            end
            if coop_king_can_enter_killed_square(sq)
                and type(mk_sq_but) == "function" then
                local dx = sq.px - hero.sq.px
                local dy = sq.py - hero.sq.py
                if dx > 0 then dx = 1 elseif dx < 0 then dx = -1 end
                if dy > 0 then dy = 1 elseif dy < 0 then dy = -1 end
                local directions = {
                    ["1,0"] = 0, ["0,1"] = 1, ["-1,0"] = 2, ["0,-1"] = 3,
                    ["1,1"] = 4, ["-1,1"] = 5, ["-1,-1"] = 6, ["1,-1"] = 7,
                }
                local direction = directions[dx .. "," .. dy]
                if direction ~= nil then
                    mk_sq_but(sq, coop_ignore_stale_button, direction)
                end
            end
        end
    end
    if _log then _log("[COOP CURSOR] replaced dead victim button count=" .. coop_string(muted)) end
    return true
end

function coop_call_targets_white_king(...)
    local values = {...}
    local mover, destination = values[1], values[2]
    if not coop_is_knight(mover) or not destination then return false end
    return coop_is_white_king(destination)
        or coop_is_white_king(coop_piece_on_square(destination))
end

function coop_find_knight_spawn_square()
    if not hero or not hero.sq then return nil end
    local hx, hy = hero.sq.px, hero.sq.py
    local function safe_square(x, y)
        if x < 0 or x > 7 or y < 0 or y > 7 then return nil end
        local sq = gsq(x, y)
        if not sq or sq.moat or coop_has_barricade(sq)
            or (x == hx and y == hy) then return nil end
        -- The square cache can lag behind a piece's actual position. Check
        -- both the engine's free-square rule and live piece coordinates.
        if not is_free(sq) or coop_piece_on_square(sq) then return nil end
        return sq
    end

    -- Side by side is the normal start and revival position. Try the other
    -- side before allowing a fallback above or below the King.
    local side = safe_square(hx - 1, hy) or safe_square(hx + 1, hy)
    if side then return side end

    -- If both side squares are blocked or off-board, use the nearest other
    -- legal square. Never place the Knight on an occupied square.
    local best, best_dist = nil, nil
    for y = 0, 7 do
        for x = 0, 7 do
            local sq = safe_square(x, y)
            if sq then
                local dist = abs(x - hx) + abs(y - hy)
                if not best_dist or dist < best_dist then
                    best, best_dist = sq, dist
                end
            end
        end
    end
    return best
end

function spawn_coop_knight(force_revive)
    if mode.coop_duel then return end
    -- Treat the saved instance reference as the spawn guard. Some game objects
    -- do not keep `sq.piece` synchronized during their creation animation.
    if mode.coop_knight or mode.coop_spawning then return end
    if mode.knight_ever_died and not force_revive then return end
    if not hero or not hero.sq then return end
    mode.coop_spawning = true

    local knight_type = get_coop_knight_type()
    if not knight_type then
        print("[COOP] ERROR: coop_knight not found in PIECES")
        mode.coop_spawning = false
        return
    end

    local spawn_sq = coop_find_knight_spawn_square()

    if spawn_sq then
        if _log then
            _log("[COOP SPAWN] creating Knight floor=" .. coop_string(mode.lvl)
                .. " turn=" .. coop_string(mode.turns)
                .. " king=" .. coop_trace_value(hero.sq)
                .. " square=" .. coop_trace_value(spawn_sq)
                .. " opening=" .. coop_string(mode.coop_opening_king_turn))
        end
        mode.coop_knight = new_piece(knight_type, false, spawn_sq)
        if mode.coop_knight then
            -- Native target lists must stay empty; co-op input owns both
            -- jumping and blade damage.
            mode.coop_knight.behavior = {}
            mode.coop_knight.custom_range = coop_no_soul_moves
            mode.coop_knight.custom_atk = coop_no_soul_moves
            mode.coop_knight_seen_on_board = false
            mode.coop_knight_missing_frames = 0
            mode.coop_knight.team = 0
            -- new_piece does not reliably copy custom template fields.
            -- Preserve the tutorial's NPC-ally classification after spawn.
            mode.coop_knight.npc = 1
            mode.coop_knight.seek = nil
            mode.coop_knight.hp = 1
            mode.coop_knight.max_hp = 1
            mode.coop_knight.danger = 0
            mode.coop_knight.coop_ally = true
            mode.coop_knight.give_soul = false
            -- The piece template declares nocarry, but new_piece does not
            -- reliably leave every custom property on the spawned instance.
            mode.coop_knight.nocarry = 1
            mode.coop_knight.blade = 3 + (mode.coop_grindstone_bonus or 0)
                + (mode.coop_rally_pending and 1 or 0)
            -- Revival and the opening King-only round grant no 2P action.
            -- init_new_turn restores normal Knight actions on later rounds.
            mode.coop_knight.ready = not force_revive and not mode.coop_opening_king_turn
            if force_revive then mode.coop_revive_locked_turn = mode.turns end
            mode.coop_knight.delay = 0
            mode.coop_knight.coop_weapon_angle = -0.125
            mode.coop_knight.coop_swing_started = nil
            mode.knight_spawned = true
            if not force_revive and not mode.coop_opening_king_turn then
                mode.coop_auto_select_knight_pending = true
            end
            fx_spawn(mode.coop_knight)
        end
    elseif _log then
        _log("[COOP SPAWN] no unoccupied square; Knight remains absent")
    end
    mode.coop_spawning = false
end

function revive_coop_knight()
    if mode.coop_knight then return end
    mode.coop_last_knight_origin_sq = nil
    mode.coop_last_knight_destination_sq = nil
    spawn_coop_knight(true)
    if mode.coop_knight then
        mode.knight_ever_died = false
        sfx("healing")
        if has_card and has_card("Co-op Revenant Bell") then
            mode.coop_revival_bishops_pending =
                (mode.coop_revival_bishops_pending or 0) + 2
            if _log then _log("[COOP REVENANT BELL] queued two Bishops") end
        end
    end
end

function coop_clear_soul_revival_state(restore_hero)
    if restore_hero and hero then
        hero.soul = mode.coop_hero_soul_before
        hero.c_soul = mode.coop_hero_c_soul_before
        hero.behavior = mode.coop_hero_behavior_before
    end
    mode.coop_soul_revival_pending = false
    mode.coop_hero_soul_before = nil
    mode.coop_hero_c_soul_before = nil
    mode.coop_hero_behavior_before = nil
    mode.coop_hero_sq_before = nil
    mode.coop_hero_px_before = nil
    mode.coop_hero_py_before = nil
end

function coop_complete_soul_revival()
    if not mode or mode.id ~= "coop" or not mode.coop_soul_revival_pending then return end
    if not mode.knight_ever_died or mode.coop_knight then
        coop_clear_soul_revival_state(false)
        return
    end

    revive_coop_knight()
    if not mode.coop_knight then
        -- Do not spend the soul if the Knight could not be spawned.
        coop_clear_soul_revival_state(false)
        return
    end
    -- Revival takes the Knight's action immediately. Account for it before
    -- the King's move so the newly spawned piece cannot make that move look
    -- like the first half of another shared round.
    mode.black_actions = 1

    -- Native Knight soul activation only exhausts the card after the King
    -- completes a Knight move. Coop revival replaces that move, so spend the
    -- selected soul explicitly once the 2P Knight has actually spawned.
    local revival_soul = mode.coop_soul_revival_descriptor
    if revival_soul and exhaust_soul then
        -- A second slot leaves the consumed soul's native button active even
        -- after exhaust_soul clears its id. Keep that button muted until this
        -- descriptor receives a new soul or the floor's UI is rebuilt.
        mode.coop_spent_soul_click_guard = coop_track_spent_soul(revival_soul)
        if _log then
            _log("[COOP SOUL] spend Knight soul for 2P revive; empty_slot_before="
                .. coop_string(get_empty_soul_slot and get_empty_soul_slot()))
        end
        mode.coop_stats_soul_owner = 1
        exhaust_soul(revival_soul)
        mode.coop_stats_soul_owner = nil
        coop_hide_spent_soul(mode.coop_spent_soul_click_guard)
        if _log then
            _log("[COOP SOUL] spent Knight soul for 2P revive; empty_slot_after="
                .. coop_string(get_empty_soul_slot and get_empty_soul_slot())
                .. " id=" .. coop_string(revival_soul.id)
                .. " oid=" .. coop_string(revival_soul.oid))
        end
    end
    -- Clear the king's visible temporary soul fields after activation. This
    -- does not cancel the native soul-selection transaction; the right-click
    -- refund and cached Knight targets must be handled at the input layer.
    mode.coop_force_clear_hero_soul = 3
    mode.coop_block_knight_soul_range = true
    mode.coop_soul_range_block_turn = mode.turns
    mode.coop_soul_refund_watch = true
    mode.coop_soul_refund_origin_px = hero and hero.sq and hero.sq.px
    mode.coop_soul_refund_origin_py = hero and hero.sq and hero.sq.py
    mode.coop_hero_soul_cleanup = mode.coop_hero_soul_before
    mode.coop_hero_c_soul_cleanup = mode.coop_hero_c_soul_before
    mode.coop_hero_behavior_cleanup = mode.coop_hero_behavior_before
    coop_clear_soul_revival_state(true)
    -- Native Knight-soul activation may leave its move buttons on the board
    -- after the descriptor is spent. Rebuild the King's ordinary move buttons
    -- once the activation callback has returned to the update loop; otherwise
    -- a stale soul target can bypass normal King move warnings and the enemy
    -- phase on the revival turn.
    mode.coop_cursor_refresh_pending = true
    if _log then
        _log("[COOP SOUL] immediate revive result knight=" .. coop_string(mode.coop_knight ~= nil)
            .. " died=" .. coop_string(mode.knight_ever_died)
            .. " hero.soul=" .. coop_string(hero and hero.soul)
            .. " hero.c_soul=" .. coop_string(hero and hero.c_soul)
            .. " empty_slot=" .. coop_string(get_empty_soul_slot and get_empty_soul_slot()))
    end
end

function coop_anchor_knight_charge(knight, target)
    if not coop_knight_soul_ready(knight) or mode.coop_knight_selected_soul.id ~= 1
        or not target or target == knight.sq then return false end
    local dx = target.px - knight.sq.px
    local dy = target.py - knight.sq.py
    -- A charge is chosen by left-clicking a square on the same rank or file.
    if dx ~= 0 and dy ~= 0 then return false end
    dx = dx > 0 and 1 or (dx < 0 and -1 or 0)
    dy = dy > 0 and 1 or (dy < 0 and -1 or 0)
    if dx == 0 and dy == 0 then return false end
    if not coop_spend_knight_soul(mode.coop_knight_selected_soul) then return false end
    mode.coop_knight_charge = {
        dx=dx, dy=dy, floor=mode.lvl,
        target_px=target.px, target_py=target.py
    }
    if _log then
        _log("[COOP CHARGE] anchored floor=" .. coop_string(mode.lvl)
            .. " turn=" .. coop_string(mode.turns)
            .. " from=" .. coop_trace_value(knight.sq)
            .. " target=" .. coop_trace_value(target)
            .. " direction=" .. coop_string(dx) .. "," .. coop_string(dy))
    end
    knight.ready = false
    coop_queue_warrant_knight_check(knight)
    mode.coop_auto_select_knight_pending = nil
    mode.coop_select_king_pending = true
    return true
end

function coop_resolve_knight_charge()
    local charge = mode and mode.coop_knight_charge
    if not charge then return end
    mode.coop_knight_charge = nil
    local knight = mode.coop_knight
    if not is_coop_active() or mode.coop_floor_transition
        or charge.floor ~= mode.lvl or not knight
        or not knight.sq or knight.dead == true or (knight.hp and knight.hp <= 0) then
        if _log then _log("[COOP CHARGE] cancelled before resolution") end
        return
    end
    local landing = knight.sq
    local enemy
    for distance = 1, 7 do
        local sq = gsq(knight.sq.px + charge.dx * distance,
            knight.sq.py + charge.dy * distance)
        if not sq or sq.moat or coop_has_barricade(sq) then break end
        local occupant = coop_piece_on_square(sq)
        if occupant then
            if occupant.team == 1 then enemy = occupant end
            break
        end
        if not is_free(sq) then break end
        landing = sq
    end
    if _log then
        _log("[COOP CHARGE] resolving floor=" .. coop_string(mode.lvl)
            .. " turn=" .. coop_string(mode.turns)
            .. " from=" .. coop_trace_value(knight.sq)
            .. " landing=" .. coop_trace_value(landing)
            .. " enemy=" .. coop_trace_value(enemy))
    end
    if landing ~= knight.sq then move_piece(knight, landing) end
    if enemy and type(hit) == "function" then
        local enemy_was_white_king = coop_is_white_king(enemy)
        local sweep_targets = coop_knight_sweep_targets(knight.sq, enemy.sq)
        sfx("blade")
        coop_start_knight_swing(knight, enemy.sq)
        local hp_before = enemy.hp
        local sweep_killed_king = false
        if enemy_was_white_king then
            sweep_killed_king = coop_apply_knight_sweep(sweep_targets)
        end
        local damage = coop_grand_phalanx_blade_damage(enemy,
            coop_knight_guarded_blade_damage(enemy,
                coop_knight_attack_damage(knight, 2, enemy)))
        if damage > 0 then
            local victim_square = enemy.sq
            local victim_attacks = type(get_range) == "function"
                and get_range(enemy, {atk=1}) or nil
            hit(enemy, damage, {coop_stats_owner=2})
            if enemy.dead == true or (enemy.hp ~= nil and enemy.hp <= 0) then
                coop_record_knight_kill_ui(enemy, victim_square, victim_attacks)
            end
            coop_record_bounty_kill(enemy, hp_before)
            coop_queue_royal_vigil(enemy)
            coop_apply_blade_revenge(enemy)
        end
        if not enemy_was_white_king then
            sweep_killed_king = coop_apply_knight_sweep(sweep_targets)
        end
        if sweep_killed_king or (enemy_was_white_king
            and (enemy.dead == true or (enemy.hp and enemy.hp <= 0))) then
            -- The King's move is already advancing this native turn.
            mode.coop_surrender_input_locked = true
            coop_lock_surrender_controls()
        end
    end
    -- opp_turn consumes the board's existing danger lists immediately after
    -- this hook. hit() clears a killed piece's sq, so remove its old attack
    -- references before native attack/movement callbacks can capture it.
    -- Scan the small board because cached attacks can differ from get_range
    -- after the King's move; retain every living attacker in the same lists.
    local removed = 0
    for py = 0, 7 do
        for px = 0, 7 do
            removed = removed + coop_prune_dead_attackers(gsq(px, py))
        end
    end
    if _log then
        _log("[COOP CHARGE] removed stale danger before opp_turn=" .. coop_string(removed))
    end
    if has_card("Co-op High Cantle Saddle") then
        knight.coop_saddle_floor=mode.lvl;knight.coop_saddle_turn=(mode.turns or 0)+1
    end
    coop_queue_warrant_knight_check(knight)
    if _log then
        _log("[COOP CHARGE] resolved knight=" .. coop_trace_value(knight)
            .. " enemy=" .. coop_trace_value(enemy))
    end
end

-- ==================== 初始化 ====================
function initialize()
    coop_install_royal_cards()
    coop_load_janissary_art()
    coop_load_cavalier_art()
    coop_load_turn_indicator()
    -- The mod sandbox cannot access the base game's DEN progress object.
    -- Keep co-op preferences and weapon unlocks in its own save bank.
    newbnk(128, 64, 4)
    local knight_died_this_run = mode.knight_ever_died
    mode.sel = 1
    mode.weapon_sel = 1
    mode.rank_sel = 1

    -- Mode selection opens the setup screen before start() runs. The previous
    -- game's hero can still have a square here; never treat it as a new board.
    mode.coop_run_active = false
    mode.coop_knight = nil
    mode.coop_spawning = false
    mode.knight_spawned = false
    mode.knight_ever_died = knight_died_this_run or false
    mode.coop_floor_transition = false
    mode.coop_surrender_input_locked = false
    mode.coop_knight_seen_on_board = false
    mode.coop_knight_missing_frames = 0
    mode.coop_soul_revival_pending = false
    mode.coop_soul_refund_watch = false
    mode.coop_soul_revival_descriptor = nil
    mode.coop_grindstone_turns = 0
    mode.coop_grindstone_bonus = 0
    mode.coop_grindstone_last_turn = nil
    mode.coop_rally_pending = false
    mode.coop_ritual_dagger_pending = false
    mode.coop_ritual_dagger_target = nil
    mode.coop_redemption_native_knight = nil
    mode.coop_redemption_native_knight_type = nil
    coop_reset_phantom_state()
    mode.coop_divisive_edict_applied_state = nil
    mode.coop_bounty_marshal = nil
    mode.coop_marshal_triggered = nil
    mode.coop_warrant_hunter = nil
    mode.coop_warrant_assigned_floor = nil
    mode.coop_warrant_check_pending = nil
    mode.coop_warrant_execution_fx = nil
    mode.coop_bounty_kills = 0
    mode.coop_bounty_pending = {}
    mode.coop_royal_vigil_pending = 0
    mode.coop_revival_bishops_pending = 0
    mode.coop_spent_soul_click_guard = nil
    mode.coop_spent_soul_click_guards = {}
    mode.coop_pending_soul_fill_slot = nil
    mode.coop_knight_soul_hover_guards = {}
    mode.coop_known_soul_slots = {}
    mode.coop_knight_selected_soul = nil
    mode.coop_knight_move_soul_to_spend = nil
    mode.coop_knight_charge = nil
    mode.coop_knight_soul_king_state = nil
    mode.coop_soul_refund_origin_px = nil
    mode.coop_soul_refund_origin_py = nil
    mode.coop_force_clear_hero_soul = false
    mode.coop_hero_soul_cleanup = nil
    mode.coop_hero_c_soul_cleanup = nil
    mode.coop_hero_behavior_cleanup = nil
    mode.coop_block_knight_soul_range = false
    mode.coop_soul_range_block_turn = nil
    mode.coop_hero_soul_before = nil
    mode.coop_hero_c_soul_before = nil
    mode.coop_hero_behavior_before = nil
    mode.coop_hero_sq_before = nil
    mode.coop_hero_px_before = nil
    mode.coop_hero_py_before = nil
    mode.black_actions = 0
    mode.coop_opening_king_turn = false
    mode.coop_auto_select_knight_pending = nil
    mode.coop_white_move_grace_frames = 0
    mode.coop_white_move_tracking = nil
    mode.coop_barricades = {}
    mode.coop_barricade_squares = {}
    mode.coop_barricade_floor = nil
    mode.coop_barricades_pending = false
    mode.coop_revive_locked_turn = nil
    mode.coop_king_hero = nil
    mode.coop_selected = "king"
    mode.coop_cursor_refresh_pending = nil
    mode.coop_pause_menu_open = false
    mode.coop_menu_click_grace = 0
    if mouse then mouse("show", true) end
    defbtn("coop_switch", 0, "k:tab")
    defbtn("coop_mouse_probe", 0, "m:lb")
    defbtn("coop_right_probe", 0, "m:rb")
    defbtn("coop_mouse_x_probe", 0, "m:x")
    defbtn("coop_mouse_y_probe", 0, "m:y")
    defbtn("coop_revive", 0, "k:r")
    defbtn("coop_rally_space", 0, "k:space")

    -- Like Karma, this card changes the King's built weapon stats. Rebuild
    -- only when the King/Knight adjacency changes, never once per frame.
    append("build_stack", function()
        if not mode or mode.id ~= "coop" then return end
        local state = coop_divisive_edict_state()
        if type(stack) ~= "table" then
            mode.coop_divisive_edict_applied_state = nil
            return
        end
        if state == "adjacent" then
            stack.spread = (stack.spread or 0) + 15
        elseif state == "apart" then
            stack.firepower = (stack.firepower or 0) - 1
        end
        mode.coop_divisive_edict_applied_state = state
    end, "coop_divisive_edict_stack")

    -- Controller fire has a separate input binding from mouse movement.
    prepend("_update", function()
        if coop_joust_blocks_shot() then btnclr("shoot", 0) end
    end, "coop_joust_block_controller_shoot")

    -- King movement can leave hero.ready=false even while King controls are
    -- usable. Watch the input and the native refill entry without that flag.
    -- The pending flag keeps the two paths from stacking the bonus.
    prepend("_update", function()
        if btnp("reload", 0) or btnp("coop_rally_space", 0) then
            coop_try_rally_reload("reload input")
        end
    end, "coop_rally_manual_reload_start")
    prepend("clean_up", function()
        if mode and mode.id=="coop" and mode.coop_hidden_boss_pending then
            mode.coop_hidden_boss_refilling=true
        end
        coop_depart_mixed_horsemen()
    end, "coop_mixed_horsemen_depart")
    prepend("ev_reveal_heir",function()
        if mode and mode.id=="coop" and seek_role("heir") then
            mode.coop_heir_reveal_floor=mode.lvl
        end
    end,"coop_heir_reveal_begin")
    prepend("play",coop_resume_after_heir,"coop_heir_reveal_resume")
    append("play", function()
        if mode and mode.id=="coop" and mode.coop_hidden_boss_refilling
            and playing and hero and not hero.win
            and not (inter and inter.storming) then
            coop_resume_hidden_boss()
        end
    end, "coop_hidden_boss_play_ready")
    prepend("refill_ammo", function()
        coop_try_rally_reload("native refill")
    end, "coop_rally_native_refill")
    -- The art is optional while it is being drawn. A pixel sword is drawn
    -- below when this file has not yet been added to the mod directory.
    mode.coop_weapon_sheet_loaded = false
    mode.coop_weapon_sheet_name = nil
    mode.coop_weapon_source_size = nil
    mode.coop_weapon_anchor = nil
    mode.coop_weapon_uses_key = false
    mode.coop_weapon_pixels = nil
    mode.coop_weapon_rotated_cache = nil
    mode.coop_spear_sheet_loaded = false
    mode.coop_spear_pixels = nil
    mode.coop_spear_rotated_cache = nil
    if type(file) == "function" and type(newsrf) == "function" then
        -- This game's mod wrapper takes (surface_name, filename), unlike
        -- the raw SUGAR manual's (filename, surface_name) overload.
        if file("knight_weapon_hi.png") then
            local loaded_name = newsrf("coop_knight_weapon_hi", "knight_weapon_hi.png")
            if loaded_name ~= nil and loaded_name ~= false then
                mode.coop_weapon_sheet_loaded = true
                mode.coop_weapon_sheet_name = "coop_knight_weapon_hi"
                mode.coop_weapon_source_size = 48
                mode.coop_weapon_anchor = 23
                mode.coop_weapon_uses_key = true
            end
        end
        if not mode.coop_weapon_sheet_loaded and file("knight_weapon.png") then
            local loaded_name = newsrf("coop_knight_weapon", "knight_weapon.png")
            if loaded_name ~= nil and loaded_name ~= false then
                mode.coop_weapon_sheet_loaded = true
                mode.coop_weapon_sheet_name = "coop_knight_weapon"
                mode.coop_weapon_source_size = 24
                mode.coop_weapon_anchor = 11
            end
        end
        if file("knight_spear_hi.png") then
            local loaded_name = newsrf("coop_knight_spear_hi", "knight_spear_hi.png")
            if loaded_name ~= nil and loaded_name ~= false then
                mode.coop_spear_sheet_loaded = true
            end
        end
    end
    if _log then
        _log("[COOP ATTACK API] all_pieces=" .. type(all_pieces)
            .. " pieces=" .. type(pieces)
            .. " mode.pieces=" .. type(mode.pieces)
            .. " get_pieces=" .. type(get_pieces)
            .. " pcall=" .. type(pcall)
            .. " hit=" .. type(hit))
    end

    prepend("xpl_boss",coop_book_snapshot,"coop_book_distance_snapshot")
    prepend("dark_bishop_up",coop_book_capture_before,"coop_book_capture_before")
    append("dark_bishop_up",coop_book_capture_after,"coop_book_capture_after")
    append("init_safe_mode",coop_marshal_danger,"coop_marshal_native_folly")
    append("init_safe_mode",coop_duel_danger,"coop_duel_native_folly")
    -- Recheck at the action boundary as well: a delayed Knight hit or an
    -- independent allied move may change blockers after control was restored.
    -- This rebuild does not spend shields or advance turns. The original
    -- check_folly_shields still owns charges, overrides and extra-turn safety.
    prepend("check_folly_shields",coop_refresh_king_danger,"coop_fresh_folly_danger")
    mode.coop_duel_draw_charge=coop_duel_draw_charge
    -- Draw role-specific HUD after the board capture, so the host's Rebel
    -- Knight label is not baked into the client's Revolutionary Knight view.
    append("_draw",coop_duel_draw,"coop_duel_overlay")


    -- Draw the weapon at the Knight's own draw call. The base piece is then
    -- drawn over its grip, and the game's menus are drawn over both.
    prepend("dr_piece", function(piece, x, y)
        if not mode.coop_floor_transition
            and piece == mode.coop_knight and type(x) == "number"
            and type(y) == "number" then
            coop_draw_knight_weapon(x + 8, y + 8)
        end
    end, "coop_knight_weapon_behind_piece")

    -- A charge target may contain a piece. Draw that square's corner marks
    -- just before its piece, so the sprite stays above the movement hint.
    prepend("dr_piece", function(piece)
        if not mode.coop_floor_transition and piece and piece.sq then
            coop_draw_knight_move_hints(piece)
        end
    end, "coop_knight_occupied_hints_behind_piece")

    -- draw_inter runs before the board in this build, so board squares cover
    -- marks placed there. Draw Knight destinations after the game scene.
    append("draw_game", function()
        if not mode.coop_run_active or mode.coop_floor_transition then return end
        coop_marshal_draw()
        coop_draw_barricades()
        coop_draw_mechanism_order_icon()
        coop_draw_knight_move_hints(nil)
        coop_draw_warrant_execution()
        coop_draw_bounty_notice()
        if is_coop_active() and not mode.coop_pause_menu_open then
            local charge = mode.coop_knight_charge
            if charge and charge.floor == mode.lvl
                and charge.target_px and charge.target_py then
                local board_left, board_top = coop_get_board_geometry()
                local tx = board_left + charge.target_px * 16 + 8
                local ty = board_top + charge.target_py * 16 + 8
                -- Mark only the chosen square; the direction line stays hidden.
                rectfill(tx-1, ty-5, tx+1, ty-4, 5)
                rectfill(tx-1, ty+4, tx+1, ty+5, 5)
                rectfill(tx-5, ty-1, tx-4, ty+1, 5)
                rectfill(tx+4, ty-1, tx+5, ty+1, 5)
                rectfill(tx-1, ty-1, tx+1, ty+1, 3)
            end
            for _, guard in ipairs(mode.coop_spent_soul_click_guards or {}) do
                local soul = guard.soul
                if soul and soul.id == nil
                    and type(soul.x) == "number" and type(soul.y) == "number" then
                    coop_draw_empty_soul_slot(soul)
                    if _log and not guard.empty_frame_logged then
                        _log("[COOP SOUL] drew empty slot frame x="
                            .. coop_string(soul.x) .. " y=" .. coop_string(soul.y))
                        guard.empty_frame_logged = true
                    end
                end
            end
        end
        if is_coop_active() then
            coop_draw_selected_soul_dissolve()
            coop_draw_soul_vanish()
        end
    end, "coop_knight_move_hints_after_game")

    -- The Knight's board-click handler clears mouse input for destinations on
    -- the board. The pause menu can overlap that area, so leave all input to
    -- the native UI while a menu is open. Track the menu through the engine's
    -- exposed lifecycle functions; these hooks only update our local flag.
    prepend("open_menu", function()
        if mode and mode.id == "coop" then
            mode.coop_pause_menu_open = true
            mode.coop_menu_click_grace = 2
            if _log then _log("[COOP UI] menu opened") end
        end
    end, "coop_menu_open_state")
    prepend("init_menu", function()
        if mode and mode.id == "coop" then
            mode.coop_duel = nil
            mode.coop_run_active = false
            mode.coop_opening_king_turn = false
            mode.coop_auto_select_knight_pending = nil
            mode.coop_select_king_pending = nil
            mode.coop_cursor_refresh_pending = nil
            mode.coop_surrender_input_locked = false
            mode.coop_spent_soul_click_guard = nil
            mode.coop_spent_soul_click_guards = {}
            mode.coop_pending_soul_fill_slot = nil
            -- The old board is about to be discarded. Do not write callbacks
            -- back to its buttons while the native UI is being torn down.
            mode.coop_knight_soul_hover_guards = {}
            mode.coop_known_soul_slots = {}
            mode.coop_knight_selected_soul = nil
            mode.coop_knight_charge = nil
            mode.coop_knight_soul_king_state = nil
        end
    end, "coop_stop_on_main_menu")
    prepend("close_menu", function()
        if mode and mode.id == "coop" then
            -- This callback can run during menu input dispatch, before the
            -- selected menu action has completed. Leave the open state alone;
            -- Escape/resume/unpause owns the actual transition.
            mode.coop_menu_click_grace = 2
            if _log then _log("[COOP UI] menu closed") end
        end
    end, "coop_menu_close_state")
    prepend("unpause", function()
        if mode and mode.id == "coop" then
            mode.coop_pause_menu_open = false
            mode.coop_menu_click_grace = 2
            if _log then _log("[COOP UI] unpaused") end
        end
    end, "coop_menu_unpause_state")
    prepend("resume", function()
        if mode and mode.id == "coop" then
            mode.coop_pause_menu_open = false
            mode.coop_menu_click_grace = 2
            if _log then _log("[COOP UI] resumed") end
        end
    end, "coop_menu_resume_state")

    mode.ranks_index = ranks and mid(0, bget(0,4), #ranks-1) or nil
    mode.weapons_index = weapons and mid(0, bget(1,4), #weapons-1) or nil

    append("add_card", function(card)
        if not mode or mode.id ~= "coop" then return end
        local card_id = type(card) == "table" and (card.id or card.name or card.gid) or card
        if card_id == "Grindstone" then
            mode.coop_grindstone_turns = 0
            mode.coop_grindstone_last_turn = nil
        end
        if card_id == "Co-op Warrant" then coop_assign_warrant_hunter() end
        if card_id == "Co-op Cheval de Frise" then
            mode.coop_barricades_pending = true
        end
        if card_id == "Co-op Bounty Cavalry"
            or (card_id == "Co-op Warrant" and has_card
                and has_card("Co-op Bounty Cavalry")) then
            mode.coop_bounty_kills = 0
        end
        if _log then
            _log("[COOP CARD] added=" .. coop_string(card_id)
                .. " floor=" .. coop_string(mode.lvl)
                .. " turn=" .. coop_string(mode.turns))
        end
    end, "coop_card_choice_trace")

    -- Add earned reinforcements before the native turn builds white actions.
    prepend("init_new_turn", coop_spawn_bounty_reinforcement,
        "coop_bounty_reinforcement_before_turn")
    prepend("init_new_turn", coop_spawn_revival_bishops,
        "coop_revival_bishops_before_turn")
    prepend("init_new_turn", coop_spawn_pending_phantoms,
        "coop_phantoms_before_turn")

    prepend("init_new_turn", function()
        if is_coop_active() and _log then
            _log("[COOP TURN TRACE] init_new_turn enter floor="
                .. coop_string(mode.lvl) .. " turn=" .. coop_string(mode.turns)
                .. " selected=" .. coop_string(mode.coop_selected))
        end
        if mode and mode.id == "coop" then
            mode.coop_native_turn_in_progress = true
        end
    end, "coop_init_new_turn_enter_trace")

    -- new_turn
    append("init_new_turn", function()
        coop_resume_hidden_boss()
        if mode and mode.id == "coop" then
            mode.coop_native_turn_in_progress = false
            mode.coop_duet_king_window = nil
            if mode.coop_manual_king_enemy_turn_pending and _log then
                _log("[COOP KING GHOST MOVE] native completion advanced turn="
                    .. coop_string(mode.coop_manual_king_enemy_turn_pending.turn)
                    .. "->" .. coop_string(mode.turns))
            end
            mode.coop_manual_king_enemy_turn_pending = nil
            mode.coop_extra_king_action_pending = nil
            mode.coop_locked_new_turn_origin = nil
        end
        if not is_coop_active() then return end
        mode.coop_knight_killed_square = nil
        mode.coop_knight_killed_squares = nil
        mode.coop_knight_killed_attack_squares = nil
        mode.coop_killed_button_refresh_pending = nil
        -- A completed native turn consumes any pending pentagram bonus. The
        -- pentagram path itself grants one more King action without calling
        -- init_new_turn here.
        mode.coop_penta_bonus_pending = nil
        if _log then
            _log("[COOP TURN TRACE] init_new_turn returned floor="
                .. coop_string(mode.lvl) .. " turn=" .. coop_string(mode.turns))
        end
        if coop_floor_is_ending() then
            -- A surrender turn must not refresh the old board or grant the
            -- Knight another action while the execution is still playing.
            mode.coop_surrender_input_locked = true
            mode.black_actions = 0
            if mode.coop_knight then mode.coop_knight.ready = false end
            mode.coop_auto_select_knight_pending = nil
            if mode.coop_selected ~= "king" then coop_set_selected("king") end
            if not mode.coop_floor_transition then coop_lock_surrender_controls() end
            return
        end
        -- new_level can expose hero.sq to _update before the engine has built
        -- its path-distance data. Spawn only once the first turn is initialized.
        mode.coop_spawn_wait_for_turn = false
        coop_refresh_knight_death()
        coop_queue_phantom_turn()
        -- Each turn builds a fresh native button map. Jump-square overrides
        -- from the previous turn must not handle clicks on this board state.
        mode.coop_last_knight_origin_sq = nil
        mode.coop_last_knight_destination_sq = nil
        mode.coop_knight_move_origin_sq = nil
        if not mode.coop_knight and not mode.knight_ever_died then
            spawn_coop_knight()
        end
        if mode.coop_opening_king_turn then
            -- Each floor's first playable round belongs to the King. Keep its
            -- native new_turn interception accounted for, so the King's
            -- action advances the round instead of being suppressed.
            mode.black_actions = 1
            if mode.coop_knight then mode.coop_knight.ready = false end
            mode.coop_auto_select_knight_pending = nil
            if mode.coop_selected ~= "king" then coop_set_selected("king") end
            mode.coop_king_move_input_locked = nil
            if _log then _log("[COOP ROUND] opening round: King acts first") end
            coop_mute_king_button_on_knight_square()
            return
        end
        mode.black_actions = 0
        if mode.coop_knight then
            local revived_this_turn = mode.coop_revive_locked_turn ~= nil
                and mode.coop_revive_locked_turn == mode.turns
            -- The revived Knight cannot act this round, so the King's move
            -- must be counted as the second and final black action.
            if revived_this_turn then mode.black_actions = 1 end
            mode.coop_knight.ready = not revived_this_turn
            mode.coop_knight.delay = 0
            mode.coop_auto_select_knight_pending = not revived_this_turn
            if mode.coop_auto_select_knight_pending then
                mode.coop_king_move_input_locked = true
            end
            if not revived_this_turn then mode.coop_revive_locked_turn = nil end
        else
            mode.coop_auto_select_knight_pending = nil
            if mode.coop_selected ~= "king" then coop_set_selected("king") end
        end
        coop_mute_king_button_on_knight_square()
        if not mode.coop_auto_select_knight_pending then
            mode.coop_king_move_input_locked = nil
        end
        if mode.coop_dead_knight_cursor_refresh_pending then
            -- Rebuild the King's controls on the next frame, after native
            -- enemy movement and init_new_turn have both returned.
            mode.coop_dead_knight_cursor_refresh_pending = nil
            mode.coop_cursor_refresh_pending = true
        end
    end, "coop_new_turn")

    -- new_level
    prepend("new_level", function(...)
        if mode and mode.id == "coop" then
            coop_log_knight_state("new_level:before")
            -- The engine clears a living piece's sq reference while preparing
            -- the next board. A dead custom knight can retain its old square
            -- reference even though that square no longer contains it. Detect
            -- that transition before the append hook drops the old instance.
            local knight = mode.coop_knight
            if mode.coop_floor_transition and knight and knight.sq
                and not coop_is_knight(knight.sq.piece) then
                if _log then
                    _log("[COOP] stale knight square at floor transition; recording death")
                end
                coop_mark_knight_dead(knight)
            end
        end
    end, "coop_record_knight_before_new_level")

    append("new_level", function()
        if not mode or mode.id ~= "coop" then return end
        mode.coop_heir_reveal_floor=nil
        if mode.coop_surrender_input_locked and hero then hero.ready = true end
        mode.knight_spawned = false
        -- The board is being replaced. Drop the old entity reference while
        -- keeping `knight_ever_died` so a dead 2P does not return automatically.
        mode.coop_knight = nil
        mode.coop_selected = "king"
        mode.coop_duet_king_window = nil
        mode.coop_king_hero = nil
        mode.coop_select_king_pending = nil
        mode.coop_auto_select_knight_pending = nil
        mode.coop_white_move_grace_frames = 0
        mode.coop_white_move_tracking = nil
        mode.coop_barricades = {}
        mode.coop_barricade_squares = {}
        mode.coop_barricade_floor = nil
        mode.coop_barricades_pending = has_card
            and has_card("Co-op Cheval de Frise") or false
        mode.coop_auto_select_wait_logged = nil
        mode.coop_force_king_kill_turn = nil
        mode.coop_surrender_input_locked = false
        mode.coop_revive_locked_turn = nil
        mode.coop_knight_move_origin_sq = nil
        mode.coop_last_knight_origin_sq = nil
        mode.coop_last_knight_destination_sq = nil
        mode.coop_knight_killed_square = nil
        mode.coop_knight_killed_squares = nil
        mode.coop_knight_killed_attack_squares = nil
        mode.coop_killed_button_refresh_pending = nil
        mode.coop_manual_king_turn_pending = nil
        mode.coop_manual_king_turn_frames = nil
        mode.coop_manual_king_origin_sq = nil
        mode.coop_manual_king_enemy_turn_pending = nil
        mode.coop_extra_king_action_pending = nil
        mode.coop_penta_move_target = nil
        mode.coop_penta_bonus_pending = nil
        mode.coop_pickup_cleanup_pending = nil
        mode.coop_spawning = false
        mode.coop_floor_transition = false
        mode.coop_spawn_wait_for_turn = true
        mode.coop_knight_seen_on_board = false
        mode.coop_knight_missing_frames = 0
        mode.coop_soul_revival_pending = false
        mode.coop_soul_refund_watch = false
        mode.coop_soul_revival_descriptor = nil
        -- Grindstone's delayed blade bonus starts over on each floor.
        mode.coop_grindstone_turns = 0
        mode.coop_grindstone_bonus = 0
        mode.coop_grindstone_last_turn = nil
        mode.coop_rally_pending = false
        mode.coop_ritual_dagger_pending = false
        mode.coop_ritual_dagger_target = nil
        mode.coop_redemption_native_knight = nil
        mode.coop_redemption_native_knight_type = nil
        coop_reset_phantom_state()
        mode.coop_divisive_edict_applied_state = nil
        mode.coop_warrant_hunter = nil
        mode.coop_warrant_assigned_floor = nil
        mode.coop_warrant_check_pending = nil
        mode.coop_warrant_execution_fx = nil
        -- Bounty progress and unspawned rewards belong to the finished floor.
        mode.coop_bounty_kills = 0
        mode.coop_bounty_pending = {}
        mode.coop_bounty_notice = nil
        mode.coop_royal_vigil_pending = 0
        mode.coop_revival_bishops_pending = 0
        -- Soul descriptors and even their button objects can survive a floor
        -- change. Keep callback functions but drop references to the old UI;
        -- restoration finds the live button when the slot is refilled.
        mode.coop_spent_soul_click_guards = mode.coop_spent_soul_click_guards or {}
        for _, guard in ipairs(mode.coop_spent_soul_click_guards) do
            guard.buttons = {}
        end
        mode.coop_spent_soul_click_guard = mode.coop_spent_soul_click_guards[#mode.coop_spent_soul_click_guards]
        mode.coop_native_turn_in_progress = false
        mode.coop_king_move_input_locked = nil
        mode.coop_extra_king_action_pending = nil
        mode.coop_locked_new_turn_origin = nil
        mode.coop_dead_knight_cursor_refresh_pending = nil
        mode.coop_pending_soul_fill_slot = nil
        -- The previous floor's button objects are being retired. Restoring
        -- callbacks on them here can touch a stale native UI tree.
        mode.coop_knight_soul_hover_guards = {}
        mode.coop_knight_selected_soul = nil
        mode.coop_knight_move_soul_to_spend = nil
        mode.coop_knight_charge = nil
        mode.coop_knight_soul_king_state = nil
        mode.coop_soul_refund_origin_px = nil
        mode.coop_soul_refund_origin_py = nil
        mode.coop_force_clear_hero_soul = false
        mode.coop_hero_soul_cleanup = nil
        mode.coop_hero_c_soul_cleanup = nil
        mode.coop_hero_behavior_cleanup = nil
        mode.coop_block_knight_soul_range = false
        mode.coop_soul_range_block_turn = nil
        mode.coop_hero_soul_before = nil
        mode.coop_hero_c_soul_before = nil
        mode.coop_hero_behavior_before = nil
        mode.coop_hero_sq_before = nil
        mode.coop_hero_px_before = nil
        mode.coop_hero_py_before = nil
        coop_log_knight_state("new_level:after_reset")
    end, "coop_new_level")

    -- Block king captures at the engine's target-validation point. The range
    -- filter in script.lua remains as an additional guard for displayed moves.
    prepend("is_valid_target", function(...)
        if mode and mode.id == "coop" and mode.coop_knight and coop_call_targets_white_king(...) then
            return false
        end
    end, "coop_no_white_king_target")

    -- Log unexpected native moves. A prepend callback cannot cancel the
    -- original move_piece call, so occupancy is enforced in the manual input
    -- path and by keeping this piece's native target lists empty.
    prepend("move_piece", function(piece, destination, ...)
        if is_coop_active() and piece and piece.team == 1 and _log then
            _log("[COOP WHITE MOVE] enter type=" .. coop_string(piece.type)
                .. " from=" .. coop_trace_value(piece.sq)
                .. " to=" .. coop_trace_value(destination)
                .. " knight=" .. coop_trace_value(mode.coop_knight and mode.coop_knight.sq)
                .. " source_occupant=" .. coop_trace_value(piece.sq and piece.sq.p)
                .. " target_occupant=" .. coop_trace_value(destination and destination.p)
                .. " source_is_piece=" .. coop_string(piece.sq and piece.sq.p == piece)
                .. " target_is_board_sq=" .. coop_string(destination and destination.px ~= nil
                    and destination.py ~= nil))
        end
        if is_coop_active() and piece == hero and _log then
            _log("[COOP KING PIECE MOVE] enter destination=" .. coop_trace_value(destination)
                .. " origin=" .. coop_trace_value(hero.sq))
        end
        if mode and mode.id == "coop" and piece == mode.coop_knight
            and destination and destination.piece then
            if _log then
                _log("[COOP GUARD] rejected Knight move onto occupied square="
                    .. coop_trace_value(destination)
                    .. " occupant=" .. coop_trace_value(destination.piece))
            end
            return true
        end
        if mode and mode.id == "coop" and coop_call_targets_white_king(piece, destination, ...) then
            return true
        end
        if mode and mode.id == "coop" and piece and piece.team == 1
            and mode.coop_knight and destination == mode.coop_knight.sq then
            -- Remember the victim before the native capture clears its square.
            mode.coop_knight_capture_square = destination
        end
    end, "coop_no_white_king_move")

    -- A white King move has occasionally failed inside the native move
    -- wrapper. Mark whether it reached the lower-level square transition.
    prepend("goto_sq", function(piece, destination)
        if is_coop_active() and coop_is_white_king(piece) and _log then
            _log("[COOP WHITE GOTO] enter from=" .. coop_trace_value(piece.sq)
                .. " to=" .. coop_trace_value(destination)
                .. " source_occupant=" .. coop_trace_value(piece.sq and piece.sq.p)
                .. " target_occupant=" .. coop_trace_value(destination and destination.p))
        end
    end, "coop_white_king_goto_trace_enter")

    append("goto_sq", function(piece, destination)
        if is_coop_active() and coop_is_white_king(piece) and _log then
            _log("[COOP WHITE GOTO] returned current=" .. coop_trace_value(piece.sq)
                .. " target=" .. coop_trace_value(destination))
        end
    end, "coop_white_king_goto_trace_return")

    -- Guard explicit move_hero calls. Board clicks are validated and consumed
    -- in the _update hook below because a prepend return value cannot cancel
    -- the game's original input handler.
    prepend("move_hero", function(destination)
        if is_coop_active() and mode.coop_selected == "king"
            and destination and not coop_piece_on_square(destination) then
            mode.coop_duet_king_window = nil
        end
        if is_coop_active() and mode.coop_selected == "king" and _log then
            _log("[COOP KING MOVE] enter destination=" .. coop_trace_value(destination)
                .. " origin=" .. coop_trace_value(hero and hero.sq)
                .. " penta=" .. coop_string(destination and destination.penta)
                .. " pentagram=" .. coop_string(destination and destination.pentagram)
                .. " extra_turn=" .. coop_string(mode.extra_turn)
                .. " turn=" .. coop_string(mode.turns)
                .. " black_actions=" .. coop_string(mode.black_actions))
        end
        if is_coop_active() and mode.coop_selected == "king" then
            mode.coop_penta_move_target = destination and destination.penta == true
                and destination or nil
        end
        if not mode or mode.id ~= "coop" or mode.coop_selected ~= "knight"
            or not mode.coop_knight then return end
        local knight = mode.coop_knight
        for _, sq in ipairs(coop_get_knight_move_targets(knight)) do
            if sq == destination and knight.ready ~= false then
                mode.coop_knight_move_origin_sq = knight.sq
                return
            end
        end
        if _log then
            _log("[COOP INPUT] blocked non-move Knight target=" .. coop_trace_value(destination))
        end
        return true
    end, "coop_knight_validate_native_move")

    append("move_hero", function(destination)
        if is_coop_active() and mode.coop_selected == "king" then
            if destination and hero.sq == destination then
                coop_break_king_barricade()
            end
            mode.coop_penta_bonus_pending = mode.coop_penta_move_target == destination
                and hero.sq == destination
            mode.coop_penta_move_target = nil
            -- The native movement button can accept another click while the
            -- enemy phase and next-turn UI are still being assembled.
            if destination and hero.sq == destination then
                mode.coop_king_move_input_locked = true
                mode.coop_extra_king_action_pending = nil
                mode.coop_king_post_move_idle_frames = 0
            end
        end
        if is_coop_active() and mode.coop_selected == "king" and _log then
            _log("[COOP KING MOVE] returned destination=" .. coop_trace_value(destination)
                .. " current=" .. coop_trace_value(hero and hero.sq)
                .. " turn=" .. coop_string(mode.turns)
                .. " black_actions=" .. coop_string(mode.black_actions))
        end
        if not mode or mode.id ~= "coop" or mode.coop_selected ~= "knight"
            or not mode.coop_knight then return end
        local knight = mode.coop_knight
        local origin = mode.coop_knight_move_origin_sq
        if origin and knight.sq ~= origin and knight.sq == destination then
            coop_finish_knight_move(knight, destination)
        end
    end, "coop_knight_finish_native_move")

    append("move_piece", function(piece, destination)
        if not is_coop_active() then return end
        if piece and piece.team == 1 then
            -- Native move_piece updates sq before the white piece finishes
            -- tweening on screen. Track the actual movement when the engine
            -- exposes in_move; the frame limit remains a fallback.
            mode.coop_white_move_grace_frames = 30
            mode.coop_white_move_tracking = mode.coop_white_move_tracking or {}
            mode.coop_white_move_tracking[#mode.coop_white_move_tracking + 1] = {
                piece = piece, seen_in_move = not not piece.in_move,
            }
        end
        if piece and piece.team == 1 and _log then
            _log("[COOP WHITE MOVE] returned type=" .. coop_string(piece.type)
                .. " current=" .. coop_trace_value(piece.sq)
                .. " destination=" .. coop_trace_value(destination)
                .. " knight=" .. coop_trace_value(mode.coop_knight and mode.coop_knight.sq))
        end
        if piece == hero and _log then
            _log("[COOP KING PIECE MOVE] returned destination=" .. coop_trace_value(destination)
                .. " current=" .. coop_trace_value(hero.sq))
        end
        local knight = mode.coop_knight
        if piece and piece.team == 1 and knight and destination
            and (destination == knight.sq or destination == mode.coop_knight_capture_square) then
            if _log then
                _log("[COOP GUARD] enemy captured Knight on " .. coop_trace_value(destination))
            end
            coop_mark_knight_dead(knight)
        end
        mode.coop_knight_capture_square = nil
        if piece == mode.coop_knight then
            if destination and destination.piece and destination.piece ~= piece then
                if _log then
                    _log("[COOP GUARD] Knight move ended on occupied square="
                        .. coop_trace_value(destination)
                        .. " occupant=" .. coop_trace_value(destination.piece))
                end
                coop_mark_knight_dead(piece)
            end
        elseif piece ~= hero and piece ~= mode.coop_king_hero then
            return
        end
        if piece == knight and mode.coop_selected == "knight"
            and destination == knight.sq then
            if coop_finish_knight_move(knight, destination) and _log then
                _log("[COOP INPUT] native Knight move committed; selected=king")
            end
        end
    end, "coop_move_piece_after")

    -- Resolve the charge before opp_turn snapshots attackers and queues their
    -- callbacks. opp_move is later: pruning danger there cannot cancel an
    -- attack that opp_turn has already scheduled against the King.
    prepend("opp_turn", function()
        if not is_coop_active() then return end
        if mode.coop_selected == "knight" then coop_set_selected("king") end
        if mode.coop_knight_charge and _log then
            _log("[COOP CHARGE] resolve before native enemy attack scheduling")
        end
        coop_resolve_knight_charge()
    end, "coop_charge_before_enemy_attacks")

    -- The engine's enemy turn assumes `hero` is the real King. Restore it
    -- before enemy targeting/damage code runs, even if the Knight was selected
    -- but did not finish an action before the phase advanced.
    prepend("opp_move", function()
        if mode and mode.id == "coop" then mode.coop_duet_king_window = nil end
        if is_coop_active() and _log then
            _log("[COOP WHITE PHASE] enter floor=" .. coop_string(mode.lvl)
                .. " turn=" .. coop_string(mode.turns)
                .. " events=" .. coop_string(type(events) == "table" and #events or nil)
                .. " knight=" .. coop_trace_value(mode.coop_knight and mode.coop_knight.sq))
        end
        -- Resolve the warrant only when the King's action ends the shared
        -- round, alongside the enemy damage phase, never on the Knight click.
        if mode and mode.id == "coop" then coop_resolve_warrant_knight_check() end
        if mode and mode.id == "coop" then coop_finish_grindstone_turn() end
        if mode and mode.id == "coop" and mode.coop_selected == "knight" then
            coop_set_selected("king")
            if _log then _log("[COOP INPUT] restored King before enemy phase") end
        end
    end, "coop_restore_king_before_enemy_phase")

    append("opp_move", function()
        if is_coop_active() and _log then
            _log("[COOP WHITE PHASE] returned floor=" .. coop_string(mode.lvl)
                .. " turn=" .. coop_string(mode.turns)
                .. " events=" .. coop_string(type(events) == "table" and #events or nil))
        end
    end, "coop_white_phase_return_trace")

    -- 双动拦截
    prepend("new_turn", function()
        if not mode or mode.id ~= "coop" then return end
        -- The coop interceptor can skip the first native new_turn call. The
        -- base mode normally initializes ai_lvl there, but during a floor
        -- transition the king may not have a square yet. Seed it before the
        -- native new_turn arithmetic even in that short inactive window.
        if mode.ai_lvl == nil then mode.ai_lvl = mode.lvl or 0 end
        if not is_coop_active() then return end
        if mode.coop_king_move_input_locked and mode.coop_selected == "king" then
            mode.coop_locked_new_turn_origin = mode.turns
        else
            mode.coop_locked_new_turn_origin = nil
        end
        if _log then
            _log("[COOP ROUND PROBE] new_turn before knight="
                .. coop_string(mode.coop_knight ~= nil)
                .. " selected=" .. coop_string(mode.coop_selected)
                .. " turns=" .. coop_string(mode.turns)
                .. " black_actions=" .. coop_string(mode.black_actions))
        end
        if coop_floor_is_ending() then
            -- The Knight's blade does not use the King's action controller.
            -- Keep allowing native turns until on_empty completes the floor.
            -- Clearing this after one call made each later surrender turn
            -- look like a fresh 2P action and repeatedly suppressed it.
            mode.coop_surrender_input_locked = true
            mode.black_actions = 0
            return
        end
        if mode.coop_opening_king_turn and mode.black_actions == 1 then
            mode.coop_opening_king_turn = false
            mode.black_actions = mode.coop_penta_bonus_pending and 1 or 0
            mode.coop_penta_bonus_pending = nil
            if _log then _log("[COOP ROUND] opening King action advances native turn") end
            return
        end
        if not mode.coop_knight then
            if _log then _log("[COOP ROUND PROBE] new_turn allow reason=no_knight") end
            return
        end

        mode.black_actions = mode.black_actions + 1
        if mode.black_actions == 1 then
            if _log then _log("[COOP ROUND PROBE] new_turn suppress native advance") end
            return true
        else
            if _log then _log("[COOP ROUND PROBE] new_turn allow native advance") end
            if mode.coop_penta_bonus_pending then
                -- The original game skips the white phase and keeps the King
                -- active after a pentagram move. Its extra King action must
                -- still finish this shared round on the next new_turn call.
                mode.black_actions = 1
                if _log then _log("[COOP ROUND] pentagram granted extra King action") end
            else
                mode.black_actions = 0
            end
            mode.coop_penta_bonus_pending = nil
        end
    end, "coop_new_turn_intercept")

    append("new_turn", function()
        if is_coop_active() and mode.coop_king_move_input_locked
            and mode.coop_selected == "king"
            and not mode.coop_native_turn_in_progress
            and mode.coop_locked_new_turn_origin == mode.turns
            and not coop_floor_is_ending() then
            -- Native bonus actions (including Undercover Mission) return
            -- from new_turn without init_new_turn. The normal turn-start
            -- callback therefore cannot release the rapid-click guard.
            mode.coop_extra_king_action_pending = 2
            -- The Knight and King's regular actions are already complete.
            -- Count the bonus King action as the final action on its next
            -- new_turn call, as the pentagram path does.
            mode.black_actions = 1
            if _log then
                _log("[COOP ROUND] native same-turn King bonus; release click lock when settled")
            end
        end
        if mode and mode.id == "coop" then mode.coop_locked_new_turn_origin = nil end
        if is_coop_active() and _log then
            _log("[COOP ROUND PROBE] new_turn returned floor=" .. coop_string(mode.lvl)
                .. " turn=" .. coop_string(mode.turns)
                .. " events=" .. coop_string(type(events) == "table" and #events or nil))
        end
    end, "coop_new_turn_return_trace")

    -- The base game hides the OS pointer from draw_game() every frame. Keep it
    -- visible while 2P is selected; this does not touch the game's own aim UI.
    append("mouse", function(command, enabled)
        if not is_coop_active() or mode.coop_selected ~= "knight"
            or mode.coop_pause_menu_open or (mode.coop_menu_click_grace or 0) > 0
            or command ~= "show" or enabled ~= false or mode.coop_force_os_cursor then
            return
        end
        mode.coop_force_os_cursor = true
        mouse("show", true)
        mode.coop_force_os_cursor = false
    end, "coop_knight_show_os_cursor")

    -- Do not alter hero or square data for these previews. Restrict the native
    -- cursor renderers to a single pixel while Knight control is active.
    local coop_preview_clip_depth = 0
    local coop_preview_clip_calls = {}
    local coop_movemap_trace_count = 0
    local coop_movemap_exit_trace_count = 0
    local function coop_begin_preview_clip(kind)
        local stack = coop_preview_clip_calls[kind]
        if not stack then
            stack = {}
            coop_preview_clip_calls[kind] = stack
        end
        stack[#stack + 1] = false
        if not mode or not is_coop_active() or mode.coop_selected ~= "knight"
            or type(clip) ~= "function" then
            return
        end
        stack[#stack] = true
        if coop_preview_clip_depth == 0 then clip(0, 0, 1, 1) end
        coop_preview_clip_depth = coop_preview_clip_depth + 1
        if kind == "dr_movemap" and _log and coop_movemap_trace_count < 8 then
            coop_movemap_trace_count = coop_movemap_trace_count + 1
            _log("[COOP CURSOR TRACE] movemap enter floor=" .. coop_string(mode.lvl)
                .. " turn=" .. coop_string(mode.turns)
                .. " depth=" .. coop_string(coop_preview_clip_depth))
        end
        if _log and not mode["coop_logged_clip_" .. kind] then
            mode["coop_logged_clip_" .. kind] = true
            _log("[COOP CURSOR] clipped native " .. kind)
        end
    end

    local function coop_end_preview_clip(kind)
        local stack = coop_preview_clip_calls[kind]
        if not stack or #stack == 0 then return end
        local saved = stack[#stack]
        stack[#stack] = nil
        if not saved then return end
        coop_preview_clip_depth = max(0, coop_preview_clip_depth - 1)
        -- SUGAR clip() resets clipping to the full drawing area. The renderer
        -- runs without a narrower clip here; do not assume clip() returns state.
        if coop_preview_clip_depth == 0 then clip() end
        if kind == "dr_movemap" and _log and coop_movemap_exit_trace_count < 8 then
            coop_movemap_exit_trace_count = coop_movemap_exit_trace_count + 1
            _log("[COOP CURSOR TRACE] movemap exit floor=" .. coop_string(mode and mode.lvl)
                .. " turn=" .. coop_string(mode and mode.turns)
                .. " depth=" .. coop_string(coop_preview_clip_depth))
        end
    end

    local function coop_clip_preview_hook(kind)
        prepend(kind, function()
            coop_begin_preview_clip(kind)
        end, "coop_clip_preview_before_" .. kind)
        append(kind, function()
            coop_end_preview_clip(kind)
        end, "coop_clip_preview_after_" .. kind)
    end
    -- Keep the native crosshair and King movement-map drawing clipped while
    -- 2P Knight is selected. Knight movement is handled by the coop input path.
    coop_clip_preview_hook("dr_crosshair")
    coop_clip_preview_hook("dr_movemap")

    -- The native movement arrow follows the mouse over an empty King move
    -- square. Preserve native coordinates over other occupied squares so the
    -- game's normal piece details panel can still respond to hover in Knight
    -- mode. The co-op Knight itself must not get a native pickup/status hover.
    -- Soul hover must also be handled by the Knight preview: its native hover
    -- callback calculates the King's soul range. Knight controls use separate
    -- m:x/m:y bindings below. Menus retain native coordinates.
    prepend("_update", function()
        if not is_coop_active() then return end
        if not mode.coop_pause_menu_open and btnp("coop_mouse_probe", 0) then
            local mx = btnv("coop_mouse_x_probe", 0)
            local my = btnv("coop_mouse_y_probe", 0)
            if coop_mechanism_icon_at(mx, my)
                and has_card and has_card("Co-op Mechanism Order") then
                btnclr()
                coop_activate_mechanism_order()
                return true
            end
        end
        if mode.coop_selected == "king" and hero and hero.sq
            and mode.coop_knight_killed_attack_squares
            and mode.coop_knight_killed_attack_squares[hero.sq] then
            -- Shooting may still see cached danger from the killed piece
            -- until the next white turn. Keep all living attackers intact.
            local removed = coop_prune_dead_attackers(hero.sq)
            if removed > 0 and _log then
                _log("[COOP KILL UI] pruned dead danger before King input="
                    .. coop_string(removed))
            end
        end
        if coop_floor_is_ending() then
            -- The board can remain clickable during surrender and after
            -- on_empty. Never dispatch a Knight action into that old board.
            if not mode.coop_floor_transition then
                mode.coop_surrender_input_locked = true
                coop_lock_surrender_controls()
            end
            return
        end
        -- Undercover Mission pauses after the King lands and waits for a
        -- disruption choice. Its choices are drawn over the board but are not
        -- all regular buttons, so the post-move board guard must eventually
        -- pass their clicks to the native selector. Ordinary move animations
        -- and queued events keep the guard active.
        local waiting_for_disruption_choice = mode.coop_king_move_input_locked
            and mode.coop_selected == "king"
            and not mode.coop_manual_king_enemy_turn_pending
            and type(has_card) == "function" and has_card("Undercover Mission")
            and not (hero and hero.in_move)
            and not mode.coop_native_turn_in_progress
            and not mode.coop_auto_select_knight_pending
            and not mode.coop_penta_bonus_pending
            and not mode.coop_extra_king_action_pending
            and not mode.coop_pause_menu_open
            and (type(events) ~= "table" or #events == 0)
        if waiting_for_disruption_choice then
            mode.coop_king_post_move_idle_frames =
                (mode.coop_king_post_move_idle_frames or 0) + 1
        else
            mode.coop_king_post_move_idle_frames = 0
        end
        coop_sync_knight_soul_hover()
        if coop_white_move_animation_pending()
            and (mode.coop_auto_select_knight_pending
                or mode.coop_selected == "knight")
            and btnp("coop_mouse_probe", 0) then
            local mx = btnv("coop_mouse_x_probe", 0)
            local my = btnv("coop_mouse_y_probe", 0)
            if coop_get_square_at_mouse(mx, my) then
                btnclr()
                return true
            end
        end
        if mode.coop_selected == "knight" and mode.coop_knight
            and not mode.coop_pause_menu_open
            and (mode.coop_menu_click_grace or 0) <= 0 then
            local mouse_x = btnv("coop_mouse_x_probe", 0)
            local mouse_y = btnv("coop_mouse_y_probe", 0)
            local hover_square = coop_get_square_at_mouse(mouse_x, mouse_y)
            if not (hover_square and hover_square ~= mode.coop_knight.sq
                and coop_piece_on_square(hover_square)) then
                btnclr("mx", 0)
                btnclr("my", 0)
            end
        end
        -- Knight cancellation owns this press. A prepend return value does
        -- not stop native input: consume it before Scope/other King skills
        -- can see the same right-click. btnclr also blocks held bindings
        -- until release, including a press held across a character switch.
        if mode.coop_selected == "knight" and mode.coop_knight
            and not mode.coop_pause_menu_open
            and (mode.coop_menu_click_grace or 0) <= 0
            and btnp("coop_right_probe", 0) then
            coop_cancel_knight_soul()
            btnclr()
            return true
        end
        if not btnp("coop_mouse_probe", 0) then return end
        -- Menu state is set by the native open/resume callbacks above. The
        -- old pause-key toggle drifted while Escape was held and could swallow
        -- the next Knight click after the native menu had already closed.
        local menu_click_grace = (mode.coop_menu_click_grace or 0) > 0
        if mode.coop_pause_menu_open or menu_click_grace then
            if _log then
                _log("[COOP UI] click passed to native menu flag="
                    .. coop_string(mode.coop_pause_menu_open)
                    .. " grace=" .. coop_string(mode.coop_menu_click_grace))
            end
            mode.coop_menu_click_grace = 0
            return
        end
        if coop_controller and not coop_controller.owns_input() then btnclr(); return end
        local click_x = btnv("coop_mouse_x_probe", 0)
        local click_y = btnv("coop_mouse_y_probe", 0)
        -- Native disruption options cover the board; their clicks belong to
        -- the modal even while the King's movement continuation is suspended.
        if disrupt_menu then return end
        if coop_controller and coop_controller.native_choice_waiting
            and coop_controller.native_choice_waiting() then return end
        if waiting_for_disruption_choice
            and mode.coop_king_post_move_idle_frames >= 15 then
            if _log then _log("[COOP UI] passed waiting disruption choice click") end
            return
        end
        if mode.coop_selected == "king"
            and mode.coop_king_move_input_locked
            and coop_native_menu_button_at(click_x, click_y) then
            if _log then _log("[COOP UI] passed native choice button click") end
            return
        end
        if mode.coop_king_move_input_locked
            and coop_get_square_at_mouse(click_x, click_y) then
            btnclr()
            if _log then
                _log("[COOP INPUT] blocked King click during turn transition"
                    .. " mouse=" .. coop_string(click_x) .. "," .. coop_string(click_y)
                    .. " moving=" .. coop_string(hero and hero.in_move)
                    .. " events=" .. coop_string(type(events) == "table" and #events or nil))
            end
            return true
        end
        if mode.coop_selected == "king" and mode.coop_knight_killed_square then
            local clicked = coop_get_square_at_mouse(click_x, click_y)
            local killed_square = clicked and mode.coop_knight_killed_squares
                and mode.coop_knight_killed_squares[clicked]
            local affected = clicked and (killed_square
                or (mode.coop_knight_killed_attack_squares
                    and mode.coop_knight_killed_attack_squares[clicked]))
            local legal_move = killed_square
                and coop_king_can_enter_killed_square(clicked)
                or (clicked and is_free(clicked)
                    and not coop_piece_on_square(clicked)
                    and coop_king_destination_in_range(clicked))
            if affected and legal_move then
                local live_attack = coop_live_white_attacks_square(clicked)
                if killed_square or not live_attack then
                    -- Native buttons may still use the victim's pre-kill map.
                    -- Submit this legal King move once, checking refreshed
                    -- native danger (including projectiles and special attacks).
                    btnclr()
                    if type(check_folly_shields) == "function"
                        and check_folly_shields(clicked) then
                        if _log then _log("[COOP KILL UI] live attack blocked King move") end
                        return true
                    end
                    mode.coop_manual_king_origin_sq = hero.sq
                    mode.coop_manual_king_turn_pending = clicked
                    mode.coop_manual_king_turn_frames = 60
                    if _log then
                        _log("[COOP KILL UI] King move through stale target="
                            .. coop_trace_value(clicked)
                            .. " live_attack=" .. coop_string(live_attack))
                    end
                    move_hero(clicked)
                    return true
                end
            end
            if killed_square and _log then
                _log("[COOP KILL UI] dead square click rejected legal="
                    .. coop_string(legal_move)
                    .. " free=" .. coop_string(is_free(clicked))
                    .. " piece=" .. coop_trace_value(coop_piece_on_square(clicked)))
            end
        end
        coop_refresh_spent_souls()
        if mode.coop_selected == "king" then
            coop_note_ritual_dagger_click(click_x, click_y)
        end
        if coop_joust_blocks_shot() then
            local clicked_square = coop_get_square_at_mouse(click_x, click_y)
            if clicked_square and not coop_joust_allows_king_action(clicked_square) then
                btnclr()
                if _log then
                    _log("[COOP JOUST] blocked King shot at "
                        .. coop_trace_value(clicked_square))
                end
                return true
            end
        end
        if mode.coop_selected == "king" and mode.coop_knight
            and mode.coop_knight.sq
            and coop_get_square_at_mouse(click_x, click_y) == mode.coop_knight.sq then
            -- The King's native range can still contain a square occupied by
            -- a Knight revived after that range was calculated.
            btnclr()
            if _log then _log("[COOP GUARD] King move onto Knight square blocked") end
            return true
        end
        if mode.coop_selected == "king" and mode.coop_knight
            -- activate_soul creates fresh native buttons, including the
            -- vacated square. Preserve their range, shield and landing callback.
            and not (hero and hero.soul ~= nil)
            and mode.coop_last_knight_origin_sq
            and mode.coop_last_knight_destination_sq then
            local clicked_square = coop_get_square_at_mouse(click_x, click_y)
            local old_square = mode.coop_last_knight_origin_sq
            local new_square = mode.coop_last_knight_destination_sq
            if clicked_square == old_square or clicked_square == new_square then
                -- The native click buttons still point at the Knight's old
                -- square after its independent jump. Use the current board
                -- state for these two squares instead of that stale button.
                btnclr()
                local legal_king_move = false
                local range_length = nil
                local range_preview = {}
                if clicked_square == old_square and hero and hero.sq
                    and is_free(old_square) and get_range then
                    local range = get_range(hero)
                    if type(range) == "table" then
                        range_length = #range
                        for index, entry in ipairs(range) do
                            if index <= 8 then add(range_preview, coop_trace_value(entry)) end
                            if coop_as_square(entry) == old_square then
                                legal_king_move = true
                                break
                            end
                        end
                    end
                end
                if _log then
                    _log("[COOP KING GHOST CLICK] square=" .. coop_trace_value(clicked_square)
                        .. " origin=" .. coop_string(clicked_square == old_square)
                        .. " destination=" .. coop_string(clicked_square == new_square)
                        .. " legal_king_move=" .. coop_string(legal_king_move)
                        .. " hero_ready=" .. coop_string(hero and hero.ready)
                        .. " range_length=" .. coop_string(range_length)
                        .. " range_preview=" .. coop_join(range_preview, "/")
                        .. " free=" .. coop_string(is_free(clicked_square)))
                end
                -- The old-square button bypasses the native King's click
                -- handler. Run its Folly Shield check only on an actual move
                -- click, leaving the movement arrow visible as in vanilla.
                if legal_king_move and type(check_folly_shields) == "function"
                    and check_folly_shields(old_square) then
                    if _log then _log("[COOP KING GHOST CLICK] blocked by Folly Shield") end
                    return true
                end
                if legal_king_move and move_hero then
                    mode.coop_manual_king_origin_sq = hero.sq
                    mode.coop_manual_king_turn_pending = old_square
                    mode.coop_manual_king_turn_frames = 60
                    -- Hide the temporary arrow as soon as this move is
                    -- committed. The turn's normal button cleanup follows
                    -- after the movement animation finishes.
                    coop_mute_stale_knight_pickup(false)
                    move_hero(old_square)
                end
                return true
            end
        end
        if mode.coop_selected == "king" then
            coop_duet_begin_king_action(coop_get_square_at_mouse(click_x, click_y))
        end
        if mode.coop_selected == "knight" and mode.coop_knight then
            local knight = mode.coop_knight
            local move_targets = coop_get_knight_input_targets(knight)
            local coordinate_target = coop_get_square_at_mouse(click_x, click_y)
            local native_target, native_target_source = coop_find_mouse_target(move_targets)
            local target = coordinate_target
            local target_is_legal = false
            local blade_available = not coop_knight_soul_ready(knight)
            local coordinate_target_is_actionable = coordinate_target
                and blade_available
                and coop_knight_can_attack_target(knight, coordinate_target) or false
            local native_target_is_actionable = false
            if coordinate_target then
                for _, sq in ipairs(move_targets) do
                    if sq == coordinate_target then
                        coordinate_target_is_actionable = true
                        break
                    end
                end
            end
            if native_target then
                for _, sq in ipairs(move_targets) do
                    if sq == native_target then
                        native_target_is_actionable = true
                        break
                    end
                end
                if blade_available and not native_target_is_actionable
                    and coop_knight_can_attack_target(knight, native_target) then
                    native_target_is_actionable = true
                end
            end
            -- A click on a visible Knight destination or adjacent enemy must
            -- keep that square. The native helper may still resolve a King
            -- button left under the pointer and redirect the Knight's action.
            if native_target_is_actionable and not coordinate_target_is_actionable then
                target = native_target
            end
            for _, sq in ipairs(move_targets) do
                if sq == target then target_is_legal = true break end
            end
            local board_left, board_top = coop_get_board_geometry()
            local board_click = native_target_is_actionable
                or (click_x >= board_left and click_x < board_left + 128
                    and click_y >= board_top and click_y < board_top + 128)

            -- Handle the new cards before the native soul button runs. Native
            -- activation gives the movement pattern to hero (the King), not
            -- to the independently controlled 2P Knight.
            local soul_button = coop_get_soul_button_at(click_x, click_y)
            if soul_button then
                local soul = coop_find_soul_for_button(soul_button)
                if coop_select_knight_soul(soul) then
                    btnclr()
                    if _log then _log("[COOP SOUL] selected for Knight id=" .. coop_string(soul.id)) end
                    return true
                end
                if _log and not soul then
                    _log("[COOP SOUL] could not resolve button descriptor x="
                        .. coop_string(soul_button.x) .. " y=" .. coop_string(soul_button.y))
                end
                return
            end

            -- `prepend` callbacks cannot cancel the base game's handler.
            -- Consume every left click while the Knight is selected: clicks
            -- outside the board still reach the native fire handler otherwise.
            -- Pause/menu clicks have already been passed through above.
            btnclr()

            if board_click and target and coop_knight_soul_ready(knight)
                and mode.coop_knight_selected_soul.id == 1 then
                coop_anchor_knight_charge(knight, target)
                return true
            end

            if coop_perform_knight_action(knight, target, {
                board_click=board_click, target_is_legal=target_is_legal,
                click_x=click_x, click_y=click_y, native_target=native_target,
                native_target_source=native_target_source, coordinate_target=coordinate_target,
                native_target_is_actionable=native_target_is_actionable
            }) then return true end

            if _log then
                _log("[COOP INPUT] click target=" .. coop_trace_value(target)
                    .. " board_click=" .. coop_string(board_click)
                    .. " legal_move=" .. coop_string(target_is_legal)
                    .. " native_target=" .. coop_trace_value(native_target)
                    .. " target_api=" .. coop_string(native_target_source)
                    .. " mouse=" .. coop_string(click_x) .. "," .. coop_string(click_y)
                    .. " board_left=" .. coop_string(board_left)
                    .. " board_top=" .. coop_string(board_top)
                    .. " MCW=" .. coop_string(MCW)
                    .. " board_y=" .. coop_string(board_y)
                    .. " target_source=board_coordinates")
            end
            return true
        end
        if _log then
            _log("[COOP INPUT CLICK] selected=" .. coop_string(mode.coop_selected)
                .. " mouse=" .. coop_string(click_x)
                .. "," .. coop_string(click_y)
                .. " king=" .. coop_trace_value(mode.coop_king_hero or hero)
                .. " knight=" .. coop_trace_value(mode.coop_knight))
        end
    end, "coop_board_click_guard")
    append("_update", function()
        if not mode or mode.id ~= "coop" then return end
        if mode.coop_king_kill_pending_floor then
            if mode.coop_floor_transition or mode.lvl ~= mode.coop_king_kill_pending_floor then
                mode.coop_king_kill_pending_floor = nil
                mode.coop_king_kill_pending_frames = nil
            else
                mode.coop_king_kill_pending_frames = mode.coop_king_kill_pending_frames - 1
                if mode.coop_king_kill_pending_frames <= 0 then
                    mode.coop_king_kill_pending_floor = nil
                    mode.coop_king_kill_pending_frames = nil
                    mode.coop_force_king_kill_turn = true
                    if _log then _log("[COOP WIN] advance native turn for white King surrender") end
                    new_turn()
                    coop_lock_surrender_controls()
                end
            end
        end
        local pending = mode.coop_manual_king_turn_pending
        if pending then
            mode.coop_manual_king_turn_frames = (mode.coop_manual_king_turn_frames or 1) - 1
            if hero and hero.sq == pending and not hero.in_move then
                mode.coop_manual_king_turn_pending = nil
                mode.coop_manual_king_turn_frames = nil
                if _log then _log("[COOP KING GHOST MOVE] committed; starting enemy turn") end
                if remove_buts then
                    -- The manual move bypasses the normal King controller's
                    -- button cleanup. Clear its old square controls before
                    -- the native white phase rebuilds the next turn's controls.
                    remove_buts()
                end
                -- The native enemy turn checks ready attacks before moving
                -- white pieces. Calling opp_move directly skipped those
                -- attacks when the King entered a threatened old square.
                mode.coop_manual_king_enemy_turn_pending = {
                    turn = mode.turns,
                }
                -- opp_turn owns the completion callback, including white
                -- movement animations not represented in the events table.
                opp_turn()
                return
            elseif mode.coop_manual_king_turn_frames <= 0 then
                if _log then _log("[COOP KING GHOST MOVE] not committed; turn unchanged") end
                mode.coop_manual_king_turn_pending = nil
                mode.coop_manual_king_turn_frames = nil
            end
        end
        local manual_enemy_turn = mode.coop_manual_king_enemy_turn_pending
        if manual_enemy_turn then
            if mode.turns ~= manual_enemy_turn.turn or coop_floor_is_ending() then
                mode.coop_manual_king_enemy_turn_pending = nil
            end
        end
        -- Refresh the native cursor once after switching control.
        if mode.coop_cursor_refresh_pending and not mode.coop_surrender_input_locked
            and not coop_white_move_animation_pending()
            and reset_move_cursor and hero and hero.sq then
            reset_move_cursor()
            mode.coop_cursor_refresh_pending = false
            coop_mute_king_button_on_knight_square()
            if _log then
                _log("[COOP CURSOR] refreshed after selection=" .. coop_string(mode.coop_selected))
            end
            if mode.coop_pickup_cleanup_pending then
                mode.coop_pickup_cleanup_pending = nil
                coop_mute_stale_knight_pickup(true)
            end
        end
        if mode.coop_killed_button_refresh_pending
            and coop_mute_dead_victim_button() then
            mode.coop_killed_button_refresh_pending = nil
        end
        if mode.coop_menu_click_grace and mode.coop_menu_click_grace > 0 then
            mode.coop_menu_click_grace = mode.coop_menu_click_grace - 1
        end
    end, "coop_menu_click_grace")
    append("_update", function()
        if not is_coop_active() then return end
        if coop_floor_is_ending() then
            mode.coop_auto_select_knight_pending = nil
            if mode.coop_knight then mode.coop_knight.ready = false end
            return
        end
        if (mode.coop_white_move_grace_frames or 0) > 0
            and not mode.coop_pause_menu_open
            and (type(events) ~= "table" or #events == 0) then
            local tracked = mode.coop_white_move_tracking
            local all_finished = tracked and #tracked > 0
            if all_finished then
                for _, movement in ipairs(tracked) do
                    if movement.piece and movement.piece.in_move then
                        movement.seen_in_move = true
                    end
                    if not movement.seen_in_move
                        or (movement.piece and movement.piece.in_move) then
                        all_finished = false
                    end
                end
            end
            -- A completed native movement needs only two quiet frames before
            -- switching control. Unobserved movements retain the 30-frame
            -- fallback, so early clicks cannot race their animation.
            if all_finished and mode.coop_white_move_grace_frames > 2 then
                if _log then
                    _log("[COOP TURN TRACE] white movement settled; release Knight selection early"
                        .. " floor=" .. coop_string(mode.lvl)
                        .. " turn=" .. coop_string(mode.turns))
                end
                mode.coop_white_move_grace_frames = 2
            end
            mode.coop_white_move_grace_frames = mode.coop_white_move_grace_frames - 1
            if mode.coop_white_move_grace_frames <= 0 then
                mode.coop_white_move_tracking = nil
            end
        end
        -- Spent soul buttons are refreshed when the card is consumed, a slot
        -- is refilled, or the player clicks. Polling the native button tree on
        -- every idle frame can race the engine's UI rebuild.
        if mode.coop_soul_refund_watch and hero and hero.sq
            and (hero.sq.px ~= mode.coop_soul_refund_origin_px
                or hero.sq.py ~= mode.coop_soul_refund_origin_py) then
            -- A Knight-soul move was committed instead of canceled. Do not let
            -- a later, unrelated Knight soul pickup be mistaken for a refund.
            mode.coop_soul_refund_watch = false
            mode.coop_soul_revival_descriptor = nil
            mode.coop_soul_refund_origin_px = nil
            mode.coop_soul_refund_origin_py = nil
        end
        -- Re-clear after the base update: the soul-card caller can set these
        -- fields after activate_soul's post-hook has already run.
        if mode.coop_force_clear_hero_soul and mode.coop_force_clear_hero_soul > 0 then
            hero.soul = mode.coop_hero_soul_cleanup
            hero.c_soul = mode.coop_hero_c_soul_cleanup
            hero.behavior = mode.coop_hero_behavior_cleanup
            mode.coop_force_clear_hero_soul = mode.coop_force_clear_hero_soul - 1
            if _log then
                _log("[COOP SOUL] post-update cleanup frames="
                    .. coop_string(mode.coop_force_clear_hero_soul)
                    .. " hero.soul=" .. coop_string(hero.soul)
                    .. " hero.c_soul=" .. coop_string(hero.c_soul))
            end
            if mode.coop_force_clear_hero_soul == 0 then
                mode.coop_hero_soul_cleanup = nil
                mode.coop_hero_c_soul_cleanup = nil
                mode.coop_hero_behavior_cleanup = nil
            end
        end
        if mode.knight_ever_died and not mode.coop_knight then
            -- Soul targets are calculated before the card is clicked. Keep
            -- the Knight soul range suppressed for the entire dead-knight
            -- state, so those cached squares never become king moves.
            mode.coop_block_knight_soul_range = true
            mode.coop_soul_range_block_turn = nil
        elseif mode.coop_block_knight_soul_range
            and mode.turns ~= mode.coop_soul_range_block_turn then
            mode.coop_block_knight_soul_range = false
            mode.coop_soul_range_block_turn = nil
        end
        coop_refresh_knight_death()
        if not mode.coop_floor_transition
            and not mode.coop_spawn_wait_for_turn
            and not mode.knight_ever_died and not mode.coop_knight then
            spawn_coop_knight()
        end
        coop_spawn_barricades()
        coop_break_king_barricade()
        coop_track_knight_presence()
        coop_watch_bishop_preparation()
        coop_refresh_divisive_edict()
        if mode.coop_select_king_pending then
            mode.coop_select_king_pending = nil
            -- Knight movement, blade, and charge do not call native new_turn.
            -- Mark their action before the King can move, otherwise the
            -- King's move is swallowed as the first half of another round.
            mode.black_actions = 1
            if mode.coop_selected ~= "king" then coop_set_selected("king") end
        end
        if mode.coop_auto_select_knight_pending then
            local knight = mode.coop_knight
            -- Delayed white-card reinforcements can still be animating after
            -- init_new_turn. Leave the King selected until those events end.
            local waiting_for_events = (type(events) == "table" and #events > 0)
                or coop_white_move_animation_pending()
            if waiting_for_events and _log then
                local key = coop_string(mode.lvl) .. ":" .. coop_string(mode.turns)
                if mode.coop_auto_select_wait_logged ~= key then
                    mode.coop_auto_select_wait_logged = key
                    _log("[COOP TURN TRACE] wait for white animation before Knight selection"
                        .. " floor=" .. coop_string(mode.lvl)
                        .. " turn=" .. coop_string(mode.turns)
                        .. " events=" .. coop_string(type(events) == "table"
                            and #events or nil)
                        .. " grace=" .. coop_string(mode.coop_white_move_grace_frames))
                end
            end
            if mode.knight_ever_died or not knight or knight.ready == false then
                mode.coop_auto_select_knight_pending = nil
                mode.coop_king_move_input_locked = nil
                mode.coop_extra_king_action_pending = nil
            elseif knight.sq and not mode.coop_floor_transition
                and not mode.coop_pause_menu_open and not waiting_for_events then
                if _log then
                    _log("[COOP TURN TRACE] auto-select Knight enter floor="
                        .. coop_string(mode.lvl) .. " turn=" .. coop_string(mode.turns)
                        .. " events=" .. coop_string(type(events) == "table"
                            and #events or nil))
                end
                mode.coop_auto_select_knight_pending = nil
                if mode.coop_selected ~= "knight" then
                    coop_set_selected("knight")
                    if _log then _log("[COOP INPUT] new round starts with Knight") end
                end
                mode.coop_king_move_input_locked = nil
                mode.coop_extra_king_action_pending = nil
            end
        end
        -- Native extra actions do not run init_new_turn. Release the click
        -- guard after their movement and event animations have settled.
        if mode.coop_king_move_input_locked
            and (mode.coop_penta_bonus_pending
                or mode.coop_extra_king_action_pending)
            and not mode.coop_manual_king_enemy_turn_pending
            and not mode.coop_native_turn_in_progress
            and not mode.coop_auto_select_knight_pending
            and not (hero and hero.in_move)
            and (type(events) ~= "table" or #events == 0)
            and not mode.coop_pause_menu_open then
            if mode.coop_extra_king_action_pending
                and mode.coop_extra_king_action_pending > 0 then
                mode.coop_extra_king_action_pending =
                    mode.coop_extra_king_action_pending - 1
            else
                mode.coop_king_move_input_locked = nil
                mode.coop_extra_king_action_pending = nil
                if _log then _log("[COOP ROUND] extra King action input unlocked") end
            end
        end
        if mode.coop_selected == "knight" and mode.coop_knight
            and mode.coop_knight_move_origin_sq
            and mode.coop_knight.sq ~= mode.coop_knight_move_origin_sq then
            coop_finish_knight_move(mode.coop_knight, mode.coop_knight.sq)
        end
        if not mode.coop_surrender_input_locked
            and not coop_white_move_animation_pending()
            and (not coop_controller or coop_controller.can_switch())
            and btnp("coop_switch", 0)
            and mode.coop_knight then
            local knight = mode.coop_knight
            local changed = false
            if mode.coop_selected == "knight" and knight.ready ~= false then
                -- Tab is an optional pass when 2P has no desired move.
                changed = coop_pass_knight_action()
            elseif mode.coop_selected == "king" and knight.ready ~= false then
                -- Allows selecting a Knight revived during the King's phase.
                coop_set_selected("knight")
                changed = true
            end
            if changed then
                if _log then
                    _log("[COOP INPUT] Tab selected=" .. coop_string(mode.coop_selected)
                        .. " knight_ready=" .. coop_string(knight.ready ~= false))
                end
                sfx("menu_in")
            end
        end
        if not mode.coop_knight and mode.knight_ever_died and btnp("coop_revive", 0) then
            activate_soul(1, hero.sq)
        end
    end, "coop_blocker_update")

    append("_update", function()
        if not is_coop_active() then return end
        coop_assign_warrant_hunter()
    end, "coop_warrant_hunter_update")

    append("_update", function()
        if not is_coop_active() then return end
        for _, guard in ipairs(mode.coop_spent_soul_click_guards or {}) do
            if (guard.soul and guard.soul.id ~= nil)
                or (guard.refilled_slot and guard.refilled_slot.id ~= nil) then
                -- A soul won during a Knight kill may be refilled before its
                -- native button can safely be reached. Retry after the
                -- animation rather than leaving that button disabled.
                coop_refresh_spent_souls()
                break
            end
        end
    end, "coop_refilled_soul_buttons")

    -- soul revive
    prepend("activate_soul", function(soul, sq)
        if is_coop_active() and mode.coop_selected == "knight"
            and mode.coop_knight and mode.coop_knight.ready ~= false
            and type(soul) == "table" and soul.id ~= nil then
            local usable = (soul.id == 1 and has_card and coop_has_knight_skill("Co-op Knight Spirit"))
                or ((soul.id == 2 or soul.id == 3)
                    and has_card and coop_has_knight_skill("Co-op In-Law"))
            if usable then
                mode.coop_knight_selected_soul = soul
                mode.coop_knight_soul_king_state = {
                    soul=hero.soul, c_soul=hero.c_soul,
                    behavior=coop_copy_table(hero.behavior)
                }
            end
        end
        -- This game version passes the soul animation/descriptor table, whose
        -- `id` is the soul type. Knight soul is id 1. activate_soul itself is
        -- not replaceable, so defer the revive until its native effect runs.
        if is_coop_active() and mode.knight_ever_died and not mode.coop_knight
            and type(soul) == "table" and soul.id == 1 then
            mode.coop_soul_revival_pending = true
            mode.coop_block_knight_soul_range = true
            mode.coop_soul_range_block_turn = mode.turns
            mode.coop_hero_soul_before = hero.soul
            mode.coop_hero_c_soul_before = hero.c_soul
            mode.coop_hero_behavior_before = coop_copy_table(hero.behavior)
            mode.coop_hero_sq_before = hero.sq
            mode.coop_hero_px_before = hero.sq and hero.sq.px
            mode.coop_hero_py_before = hero.sq and hero.sq.py
            mode.coop_soul_revival_descriptor = soul
            if _log then _log("[COOP SOUL] knight soul reserved for 2P revive") end
        end
    end, "coop_soul")

    append("activate_soul", function(soul)
        if mode and mode.id == "coop" then
            local old = mode.coop_knight_soul_king_state
            if old and hero then
                hero.soul = old.soul
                hero.c_soul = old.c_soul
                hero.behavior = old.behavior
                mode.coop_hero_soul_cleanup = old.soul
                mode.coop_hero_c_soul_cleanup = old.c_soul
                mode.coop_hero_behavior_cleanup = old.behavior
                mode.coop_force_clear_hero_soul = 3
                mode.coop_knight_soul_king_state = nil
            end
            -- The native soul effect runs first; then finish the Knight revive.
            if mode.coop_soul_revival_pending then
                coop_complete_soul_revival()
            end
        end
    end, "coop_soul_immediate_revival")

    prepend("add_soul", function(id, from)
        coop_stats_soul_refund(id, from)
        if not is_coop_active() or type(get_empty_soul_slot) ~= "function" then return end
        local slot = get_empty_soul_slot()
        mode.coop_pending_soul_fill_slot = slot
        if type(slot) == "table" and type(slot.x) == "number"
            and type(slot.y) == "number" then
            mode.coop_known_soul_slots = mode.coop_known_soul_slots or {}
            for _, known in ipairs(mode.coop_known_soul_slots) do
                if known == slot then return end
            end
            add(mode.coop_known_soul_slots, slot)
        end
    end, "coop_remember_soul_slot")

    append("add_soul", function(...)
        if mode and mode.id == "coop" then
            local filled_slot = mode.coop_pending_soul_fill_slot
            mode.coop_pending_soul_fill_slot = nil
            local args = {...}
            -- Native cancellation has no source and runs on right-click.
            -- A captured Knight also grants id=1, even while the King stays
            -- on the revival square; that is a new soul, never a refund.
            local is_revival_refund = mode.coop_soul_refund_watch
                and args[1] == 1 and args[2] == nil and mcr
            if is_revival_refund then
                local stayed_on_origin = hero and hero.sq
                    and hero.sq.px == mode.coop_soul_refund_origin_px
                    and hero.sq.py == mode.coop_soul_refund_origin_py
                if stayed_on_origin and mode.coop_soul_revival_descriptor
                    and filled_slot and filled_slot.id == 1 and exhaust_soul then
                    -- Only consume the slot THIS refund filled. The original
                    -- descriptor may now contain a legitimate captured soul.
                    -- A full inventory means no new slot was filled: consume none.
                    local guard = coop_track_spent_soul(filled_slot)
                    mode.coop_spent_soul_click_guard = guard
                    mode.coop_stats_soul_refund_cleanup = true
                    exhaust_soul(filled_slot)
                    mode.coop_stats_soul_refund_cleanup = nil
                    coop_hide_spent_soul(guard)
                    if _log then
                        _log("[COOP SOUL] removed Knight soul returned by cancel; empty_slot="
                            .. coop_string(get_empty_soul_slot and get_empty_soul_slot()))
                    end
                end
                mode.coop_soul_refund_watch = false
                mode.coop_soul_revival_descriptor = nil
                mode.coop_soul_refund_origin_px = nil
                mode.coop_soul_refund_origin_py = nil
            else
                -- Only release guards for the slot that native add_soul filled.
                -- The other soul slots retain their double-click protection.
                if _log and filled_slot then
                    _log("[COOP SOUL] added into slot x=" .. coop_string(filled_slot.x)
                        .. " y=" .. coop_string(filled_slot.y)
                        .. " id=" .. coop_string(filled_slot.id)
                        .. " oid=" .. coop_string(filled_slot.oid)
                        .. " draw=" .. type(filled_slot.dr))
                end
                coop_restore_refilled_soul(filled_slot)
                coop_release_spent_soul_slot(filled_slot)
                coop_refresh_spent_souls()
            end
        end
    end, "coop_soul_refund_cleanup")

    -- The log shows get_soul_range delegates the actual targets to
    -- get_range(hero, knight_piece). Override the source piece for that call,
    -- not around get_soul_range itself (which restores too early).
    prepend("get_range", function(piece, range_piece)
        if not is_coop_active() or mode.coop_floor_transition
            or mode.coop_spawn_wait_for_turn or mode.coop_native_turn_in_progress
            or (piece ~= hero and piece ~= mode.coop_king_hero) then return end
        local suppress_soul_range = mode.coop_block_knight_soul_range
            and type(range_piece) == "table"
            and (range_piece.type == 1 or range_piece.id == 1)
        if not suppress_soul_range then return end

        mode.coop_soul_range_override_entries = {}
        local seen = {}
        local function override(candidate)
            if type(candidate) ~= "table" or seen[candidate] then return end
            seen[candidate] = true
            add(mode.coop_soul_range_override_entries, {
                piece = candidate,
                custom_range = candidate.custom_range,
                behavior = candidate.behavior
            })
            candidate.custom_range = coop_no_soul_moves
            candidate.behavior = {}
        end
        override(range_piece)
        override(coop_get_knight_soul_piece())
        if _log then
            _log("[COOP RANGE] suppress Knight soul range=" .. coop_string(suppress_soul_range))
        end
    end, "coop_soul_range_override")

    append("get_range", function()
        local entries = mode and mode.id == "coop" and mode.coop_soul_range_override_entries
        if not entries then return end
        for _, entry in ipairs(entries) do
            entry.piece.custom_range = entry.custom_range
            entry.piece.behavior = entry.behavior
        end
        mode.coop_soul_range_override_entries = nil
    end, "coop_soul_range_restore")

    prepend("exhaust_soul", function(soul)
        coop_stats_soul_begin(soul)
    end, "coop_stats_soul_begin")
    append("exhaust_soul", function(soul)
        coop_stats_soul_end(soul)
    end, "coop_stats_soul_end")

    -- death check
    -- Handle both the generic death event and the underlying removal/damage
    -- paths. These hooks use only the affected piece argument, never the killer.
    append("kill_piece", function(piece)
        coop_award_ritual_dagger_kill(piece, true)
        coop_mark_knight_dead(piece)
        if is_coop_active() and coop_is_white_king(piece) then
            -- Gun kills reach this path without the Knight blade's explicit
            -- surrender lock. Stop queued 2P input before native turn cleanup.
            mode.coop_surrender_input_locked = true
            mode.coop_auto_select_knight_pending = nil
            if mode.coop_knight then mode.coop_knight.ready = false end
            if _log then _log("[COOP WIN] white King removed; Knight input locked") end
        end
    end, "coop_knight_kill_piece")

    prepend("hit", function(piece, damage, attributes)
        coop_stats_hit_begin(piece, attributes)
        coop_prepare_redemption_knight_death(piece, damage)
        if is_coop_active() and coop_is_white_king(piece) and _log then
            _log("[COOP KING HIT] enter hp=" .. coop_string(piece.hp)
                .. " damage=" .. coop_string(damage)
                .. " turn=" .. coop_string(mode.turns)
                .. " knight=" .. coop_string(mode.coop_knight ~= nil)
                .. " revived_this_turn=" .. coop_string(
                    mode.coop_revive_locked_turn == mode.turns))
        end
    end, "coop_white_king_hit_enter_trace")

    append("hit", function(piece)
        coop_stats_hit_end(piece)
        coop_award_ritual_dagger_kill(piece)
        if mode and mode.id == "coop"
            and piece == mode.coop_redemption_native_knight then
            -- A prevented death must leave the playable Knight's custom type
            -- intact. A dead piece stays type 1 for queued Redemption events.
            if piece.dead ~= true and type(piece.hp) == "number" and piece.hp > 0 then
                piece.type = mode.coop_redemption_native_knight_type
            end
            mode.coop_redemption_native_knight = nil
            mode.coop_redemption_native_knight_type = nil
        end
        if is_coop_active() and coop_is_white_king(piece) and _log then
            _log("[COOP KING HIT] returned hp=" .. coop_string(piece.hp)
                .. " floor_transition=" .. coop_string(mode.coop_floor_transition))
        end
        if mode and mode.id == "coop" and piece and piece == mode.coop_knight
            and (piece.dead == true or (piece.hp ~= nil and piece.hp <= 0)) then
            coop_mark_knight_dead(piece)
        end
        if type(piece) == "table" and piece.team == 1
            and (piece.dead == true or (piece.hp ~= nil and piece.hp <= 0)) then
            coop_award_warrant_knight_soul(piece)
        end
        coop_duet_king_hit(piece)
    end, "coop_knight_hit_death")

    append("ev_death", function(...)
        if not is_coop_active() then return end
        local args = {...}
        local victim = args[1]
        -- Some death paths pass a square or include the attacker. Only mark
        -- the knight dead when it appears in the event and is no longer on
        -- the board (or has definitively reached zero HP).
        if coop_event_has_knight(...) and mode.coop_knight then
            local knight = mode.coop_knight
            if knight.dead == true or (knight.hp ~= nil and knight.hp <= 0)
                or not coop_knight_is_on_board(knight) then
                coop_mark_knight_dead(knight)
            end
        end
        if type(victim) == "table" then
            victim = victim.piece or victim.entity or victim.target or victim
        end
        local warrant_type = get_coop_warrant_type()
        local is_warrant = type(victim) == "table" and victim.team == 1
            and warrant_type ~= nil and victim.type == warrant_type
        if is_warrant then coop_award_warrant_knight_soul(victim) end
        -- A full soul bar revives 2P after either ordinary Knight or
        -- Warrant Knight provides the Knight soul.
        if type(victim) == "table" and victim.team == 1
            and (victim.type == 1 or is_warrant)
            and not mode.coop_knight and mode.knight_ever_died then
            if get_empty_soul_slot() == nil then
                revive_coop_knight()
            end
        end
    end, "coop_death")
end

-- ==================== Game Procedure ====================
-- Run statistics use actual HP loss, not requested damage. Knight attacks
-- carry their owner in hit attributes so delayed/redirected hits retain it.
function coop_stats_begin_run()
    mode.coop_stats = {
        running=true, knight_deaths=0,
        players={{damage=0, kills=0, souls=0}, {damage=0, kills=0, souls=0}},
        hits={}, soul_calls={},
    }
    mode.coop_stats_soul_owner = nil
    mode.coop_stats_soul_refund_cleanup = nil
    mode.coop_stats_screen = nil
end

function coop_stats_hit_begin(piece, attributes)
    local stats = mode and mode.id == "coop" and mode.coop_stats
    if not stats then return end
    local owner = type(attributes) == "table" and attributes.coop_stats_owner or 1
    if owner ~= 2 then owner = 1 end
    local valid = stats.running and type(piece) == "table" and piece.team == 1
        and type(piece.hp) == "number" and piece.hp > 0 and not piece.dead
    stats.hits[#stats.hits+1] = {
        piece=piece, owner=owner, hp=valid and piece.hp or 0,
        valid=valid, child_loss=0,
    }
end

function coop_stats_hit_end(piece)
    local stats = mode and mode.id == "coop" and mode.coop_stats
    if not stats or #stats.hits == 0 then return end
    local frame = stats.hits[#stats.hits]
    stats.hits[#stats.hits] = nil
    if not frame.valid or frame.piece ~= piece or type(piece.hp) ~= "number" then return end
    local loss = max(0, frame.hp - max(0, piece.hp))
    local own_loss = max(0, loss - frame.child_loss)
    local player = stats.players[frame.owner]
    player.damage = player.damage + own_loss
    -- Recursive hits on the same piece must not be counted again by parents.
    for i=#stats.hits,1,-1 do
        local parent = stats.hits[i]
        if parent.valid and parent.piece == piece then
            parent.child_loss = parent.child_loss + loss
            break
        end
    end
    if own_loss > 0 and piece.hp <= 0 and piece.coop_stats_killed_run ~= stats then
        piece.coop_stats_killed_run = stats
        player.kills = player.kills + 1
    end
end

function coop_stats_soul_begin(soul)
    local stats = mode and mode.id == "coop" and mode.coop_stats
    if not stats then return end
    stats.soul_calls[#stats.soul_calls+1] = {
        soul=soul,
        valid=stats.running and type(soul) == "table" and soul.id ~= nil
            and not mode.coop_stats_soul_refund_cleanup,
        id=type(soul) == "table" and soul.id,
        owner=mode.coop_stats_soul_owner or 1,
        revival=mode.coop_soul_revival_pending,
    }
end

function coop_stats_soul_end(soul)
    local stats = mode and mode.id == "coop" and mode.coop_stats
    if not stats or #stats.soul_calls == 0 then return end
    local frame = stats.soul_calls[#stats.soul_calls]
    stats.soul_calls[#stats.soul_calls] = nil
    if frame.valid and frame.soul == soul and soul.id == nil then
        local player = stats.players[frame.owner]
        player.souls = player.souls + 1
        if frame.owner == 1 and frame.id and frame.id > 0 and not frame.revival then
            -- Native activate_soul spends immediately, then refunds on cancel.
            stats.king_soul_pending = frame.id
        end
    end
end

function coop_stats_soul_refund(id, from)
    local stats = mode and mode.id == "coop" and mode.coop_stats
    if not stats or not stats.running or from ~= nil
        or not mcr or not hero or hero.soul ~= id
        or stats.king_soul_pending ~= id then return end
    stats.players[1].souls = max(0, stats.players[1].souls - 1)
    stats.king_soul_pending = nil
end

function coop_show_run_stats(won)
    if mode.coop_stats_screen then return end
    local stats = mode.coop_stats
    if not stats then
        if won then init_menu() else end_game() end
        return
    end
    if coop_controller and coop_controller.show_stats then coop_controller.show_stats(stats,won) end
    stats.running = false
    mode.coop_run_active = false
    mode.coop_stats_screen = true
    mode.coop_auto_select_knight_pending = nil
    mode.coop_select_king_pending = nil
    mode.coop_pause_menu_open = false
    mode.coop_knight_selected_soul = nil
    -- Use the same scene teardown as native end_game. No live board/buttons
    -- remain behind the results, and no native turn callback is replaced.
    reset()
    btnclr()
    mouse("show", true)
    fade_to(0, 20)
    local zh=current_lang=="simplified_chinese"
    local left, top = (MCW-264)/2, (MCH-166)/2
    local bg = mke()
    bg.dp = DP_BG
    bg.dr = function()
        cls(1)
        hdclear(0, 0, MCW*2, MCH*2)
        lprint(won and (zh and "通关统计" or "Victory statistics") or (zh and "本局统计" or "Run statistics"), MCW/2, top+6, 4, 1)
        lprint(zh and "1P 黑王" or "1P King", left+151, top+32, 4, 1)
        lprint(zh and "2P 黑骑士" or "2P Knight", left+222, top+32, 4, 1)
        local labels = zh and {"造成伤害", "击杀棋子", "灵魂使用"} or {"Damage", "Kills", "Souls used"}
        local keys = {"damage", "kills", "souls"}
        for i=1,3 do
            local y = top+36+i*18
            lprint(labels[i], left+12, y, 3)
            lprint(stats.players[1][keys[i]], left+151, y, 4, 1)
            lprint(stats.players[2][keys[i]], left+222, y, 5, 1)
        end
        lprint(zh and "黑骑士死亡次数" or "Knight deaths", left+12, top+111, 3)
        lprint(stats.knight_deaths, left+222, top+111, 5, 1)
    end
    local leaving = false
    local function leave(restart)
        if leaving or bg.t < 15 then return end
        leaving = true
        btnclr()
        sfx("menu_in", .7)
        fade_to(-4, 20, function()
            mode.coop_stats_screen = nil
            if restart then
                if mode.coop_stats_continue then mode.coop_stats_continue() else start() end
            else init_menu() end
        end)
    end
    local function button(x, label, restart)
        local b = mk_but(x, top+140, 112, 20, function() leave(restart) end)
        b.dr = function(e, px, py)
            rectfill(px, py, px+111, py+19, e.ov and 3 or 2)
            lprint(label, px+56, py+5, e.ov and 1 or 4, 1)
        end
    end
    if not coop_controller or not coop_controller.can_restart or coop_controller.can_restart() then
        button(left+12, mode.coop_stats_continue and (zh and "返回剿灭" or "Back to Charnier") or (zh and "重新开始" or "Restart"), true)
    end
    button(left+140, zh and "返回主菜单" or "Main menu", false)
    if _log then
        _log("[COOP STATS] win=" .. coop_string(won)
            .. " king_damage=" .. stats.players[1].damage
            .. " king_kills=" .. stats.players[1].kills
            .. " king_souls=" .. stats.players[1].souls
            .. " knight_damage=" .. stats.players[2].damage
            .. " knight_kills=" .. stats.players[2].kills
            .. " knight_souls=" .. stats.players[2].souls
            .. " knight_deaths=" .. stats.knight_deaths)
    end
end

function start()
    if intro and not DEV then
        intro = false
        coop_start_story(false, start)
        return
    end
    local grant_wildcards=mode.coop_wildcards_pending==true
    mode.coop_wildcards_pending=nil
    coop_stats_begin_run()
    mode.coop_heir_reveal_floor=nil
    mode.coop_hidden_boss_pending = nil
    mode.coop_ending_sequence = nil
    mode.coop_ending_kind = nil
    mode.coop_bounty_marshal = nil
    mode.coop_marshal_triggered = nil
    mode.coop_marshal_transition = nil
    mode.coop_mixed_horsemen = nil
    mode.coop_hidden_boss_refilling = nil
    mode.coop_ending_knight_alive = nil
    mode.coop_throne_finishing = nil
    mode.coop_book_scene = nil
    mode.coop_duel = nil
    -- `start` is also used by the game-over restart flow; reset run-scoped state
    -- here because that flow does not necessarily call `initialize` again.
    mode.coop_new_job_knight = nil
    mode.coop_new_job_scene = nil
    mode.coop_knight = nil
    mode.coop_spawning = false
    mode.knight_spawned = false
    mode.knight_ever_died = false
    mode.coop_auto_select_wait_logged = nil
    mode.coop_floor_transition = false
    mode.coop_native_turn_in_progress = false
    mode.coop_duet_king_window = nil
    mode.coop_duet_king_action_id = 0
    mode.coop_duet_extra_hit = nil
    mode.coop_king_move_input_locked = nil
    mode.coop_extra_king_action_pending = nil
    mode.coop_locked_new_turn_origin = nil
    mode.coop_knight_killed_square = nil
    mode.coop_knight_killed_squares = nil
    mode.coop_knight_killed_attack_squares = nil
    mode.coop_killed_button_refresh_pending = nil
    mode.coop_manual_king_enemy_turn_pending = nil
    mode.coop_dead_knight_cursor_refresh_pending = nil
    mode.coop_surrender_input_locked = false
    mode.coop_knight_seen_on_board = false
    mode.coop_knight_missing_frames = 0
    mode.coop_soul_revival_pending = false
    mode.coop_soul_refund_watch = false
    mode.coop_soul_revival_descriptor = nil
    mode.coop_grindstone_turns = 0
    mode.coop_grindstone_bonus = 0
    mode.coop_grindstone_last_turn = nil
    mode.coop_rally_pending = false
    mode.coop_ritual_dagger_pending = false
    mode.coop_ritual_dagger_target = nil
    mode.coop_redemption_native_knight = nil
    mode.coop_redemption_native_knight_type = nil
    coop_reset_phantom_state()
    mode.coop_divisive_edict_applied_state = nil
    mode.coop_warrant_hunter = nil
    mode.coop_warrant_assigned_floor = nil
    mode.coop_warrant_check_pending = nil
    mode.coop_warrant_execution_fx = nil
    mode.coop_bounty_kills = 0
    mode.coop_bounty_pending = {}
    mode.coop_royal_vigil_pending = 0
    mode.coop_revival_bishops_pending = 0
    mode.coop_bounty_notice = nil
    mode.coop_spent_soul_click_guard = nil
    mode.coop_spent_soul_click_guards = {}
    mode.coop_pending_soul_fill_slot = nil
    mode.coop_knight_soul_hover_guards = {}
    mode.coop_known_soul_slots = {}
    mode.coop_knight_selected_soul = nil
    mode.coop_knight_move_soul_to_spend = nil
    mode.coop_knight_charge = nil
    mode.coop_knight_soul_king_state = nil
    mode.coop_soul_refund_origin_px = nil
    mode.coop_soul_refund_origin_py = nil
    mode.coop_force_clear_hero_soul = false
    mode.coop_hero_soul_cleanup = nil
    mode.coop_hero_c_soul_cleanup = nil
    mode.coop_hero_behavior_cleanup = nil
    mode.coop_block_knight_soul_range = false
    mode.coop_soul_range_block_turn = nil
    mode.coop_hero_soul_before = nil
    mode.coop_hero_c_soul_before = nil
    mode.coop_hero_behavior_before = nil
    mode.coop_hero_sq_before = nil
    mode.coop_hero_px_before = nil
    mode.coop_hero_py_before = nil
    mode.black_actions = 0
    mode.coop_opening_king_turn = true
    mode.coop_auto_select_knight_pending = nil
    mode.coop_white_move_grace_frames = 0
    mode.coop_white_move_tracking = nil
    mode.coop_barricades = {}
    mode.coop_barricade_squares = {}
    mode.coop_barricade_floor = nil
    mode.coop_barricades_pending = false
    mode.coop_revive_locked_turn = nil
    mode.coop_select_king_pending = nil
    mode.coop_king_kill_pending_floor = nil
    mode.coop_king_kill_pending_frames = nil
    mode.coop_force_king_kill_turn = nil
    mode.coop_knight_move_origin_sq = nil
    mode.coop_last_knight_origin_sq = nil
    mode.coop_last_knight_destination_sq = nil
    mode.coop_manual_king_turn_pending = nil
    mode.coop_manual_king_turn_frames = nil
    mode.coop_manual_king_origin_sq = nil
    mode.coop_pickup_cleanup_pending = nil
    coop_set_selected("king")
    mode.coop_pause_menu_open = false
    mode.coop_menu_click_grace = 0
    if mouse then mouse("show", true) end
    init_game()
    mode.coop_run_active = true
    -- Card Lab initializes this flag before adding Wild Cards. Keep the
    -- same card-button state in Co-op when granting its debug cards.
    mode.unlimited = false
    -- Only the menu's explicit right-click launch grants test cards.
    -- Consume the request once; restarts and subsequent floors do not regrant.
    if grant_wildcards and get_card and add_card
        and get_card("Black Wild Card") then
        add_card("Black Wild Card")
        mode.coop_dev_wild = true
        if _log then _log("[COOP DEBUG] granted Card Lab Black Wild Card for range test") end
    end
    if grant_wildcards and get_card and add_card
        and get_card("White Wild Card") then
        add_card("White Wild Card")
        mode.coop_dev_wild = true
        if _log then _log("[COOP DEBUG] granted Card Lab White Wild Card for card test") end
    end
    if mode.coop_dev_wild then
        -- Card Lab's Wild Card click handler never runs in this build: nothing
        -- calls its on_card_but_init hook, and native only creates hand-card
        -- buttons while stack.special=="dev". Wire the granted cards ourselves
        -- with the same flow Card Lab uses: tear the card, then pick any card
        -- of its team. append() replaces an earlier entry with the same id.
        local function coop_dev_wild_click(ca)
            return function()
                if not mode or not mode.coop_dev_wild then return end
                remove_buts()
                local team = ca.team
                if _log then
                    _log("[COOP DEBUG] wild card clicked; picking any card team="
                        .. coop_string(team))
                end
                tear_apart(ca, bind(add_any_card, {team = team}, play))
            end
        end
        append("_update", function()
            if not mode or not mode.coop_dev_wild or mode.coop_pause_menu_open then return end
            if leveling or mode.coop_selected ~= "king" then return end
            if type(get_slot_cards) ~= "function" or type(get_all_buts) ~= "function"
                or type(mk_but) ~= "function" or type(tear_apart) ~= "function"
                or type(add_any_card) ~= "function" or type(play) ~= "function" then return end
            local now = time()
            if mode.coop_dev_wild_next and now < mode.coop_dev_wild_next then return end
            mode.coop_dev_wild_next = now + .1
            local buttons = get_all_buts() or {}
            for ca in all(get_slot_cards() or {}) do
                if ca.wild and type(ca.x) == "number" and type(ca.y) == "number" then
                    local wired = false
                    for _, b in ipairs(buttons) do
                        if type(b) == "table" and not b.issq
                            and b.x == ca.x - 5 and b.y == ca.y - 5
                            and b.w == 24 and b.h == 32 then
                            wired = true
                            if not b.coop_dev_wild then
                                b.coop_dev_wild = true
                                b.left_clic = coop_dev_wild_click(ca)
                            end
                            break
                        end
                    end
                    if not wired then
                        local b = mk_but(ca.x - 5, ca.y - 5, 24, 32, coop_dev_wild_click(ca))
                        if b then b.coop_dev_wild = true end
                    end
                end
            end
        end, "coop_dev_wild_buttons")
    end
    mode.lvl = mode.coop_initial_floor or 0
    mode.turns = 0
    mode.ai_lvl = 0
    -- Match the base Throne mode's START_LVL shortcut. The value is the
    -- completed floor: next_floor() increments it before loading the board.
    local start_level = not mode.coop_variant and (COOP_START_LVL or START_LVL)
    if type(start_level) == "number" and start_level >= 1 then
        if _log then _log("[COOP FLOOR] debug shortcut begin level=" .. coop_string(start_level)) end
        build_stack()
        if _log then _log("[COOP FLOOR] debug shortcut stack built") end
        mode.lvl = start_level
        -- The base mode grants random cards here. Co-op's native card picker
        -- has faulted before reaching the boss board, so isolate floor 12
        -- with the starting deck instead of generating twenty random cards.
        if start_level == 11 then
            add(upgrades, {gain={6}, sac={5}})
        end
        if _log then
            _log("[COOP FLOOR] debug START_LVL=" .. coop_string(start_level)
                .. " next_floor=" .. coop_string(start_level + 1))
        end
    end
    next_floor()
end

function next_floor()
    mode.lvl = mode.lvl + 1
    -- Set this before new_level creates the board and dispatches its opening
    -- turn. Later rounds on this floor still use Knight, then King.
    mode.coop_opening_king_turn = true
    mode.black_actions = 0
    mode.coop_auto_select_knight_pending = nil
    if _log then _log("[COOP FLOOR] next_floor entering new_level floor=" .. coop_string(mode.lvl)) end
    new_level()
    if _log then _log("[COOP FLOOR] next_floor returned from new_level floor=" .. coop_string(mode.lvl)) end
end

function grow()
    if _log then _log("[COOP FLOOR] grow floor=" .. coop_string(mode.lvl)) end
    -- The boss vignette replaces the board just like an ordinary card choice.
    -- Release the old Knight before either transition; otherwise its cleared
    -- square and old UI references survive into the boss scene.
    if mode.coop_knight then
        if _log then
            _log("[COOP FLOOR] release old Knight before transition"
                .. " hp=" .. coop_string(mode.coop_knight.hp)
                .. " square=" .. coop_trace_value(mode.coop_knight.sq)
                .. " died=" .. coop_string(mode.knight_ever_died))
        end
        mode.coop_knight = nil
    end
    mode.coop_last_knight_origin_sq = nil
    mode.coop_last_knight_destination_sq = nil
    -- Keep exhausted soul descriptors until their slots are refilled. The
    -- new_level hook drops their old button references after the board swap.
    if _log then
        _log("[COOP FLOOR] retaining spent-soul guards="
            .. coop_string(type(mode.coop_spent_soul_click_guards) == "table"
                and #mode.coop_spent_soul_click_guards or 0))
    end
    mode.coop_knight_soul_hover_guards = {}
    mode.coop_known_soul_slots = {}
    if mode.coop_campaign_grow then
        mode.coop_campaign_grow()
        return
    end
    if mode.lvl < 11 then
        local data = {
            id = "level_up",
            pan_xm = 1,
            pan_ym = 2,
            pan_width = 80,
            pan_height = 96,
            choices = { {{team=0},{team=1}}, {{team=0},{team=1}} }
        }
        if mode.lvl == 3 then
            for i = 1, 2 do
                data.choices[i][2].id = "Homecoming"
            end
        end
        -- Keep native team constraints: explicit IDs bypass pool removal and
        -- make Search draw the same card again. Only Homecoming above is a
        -- scripted native offer (its own reroll becomes Tragic Homecoming).
        if _log then
            _log("[COOP FLOOR] opening level-up choices"
                .. " selected=" .. coop_string(mode.coop_selected)
                .. " knight=" .. coop_string(mode.coop_knight ~= nil)
                .. " knight_dead=" .. coop_string(mode.knight_ever_died)
                .. " hero=" .. coop_trace_value(hero)
                .. " cards=" .. coop_string(type(cards))
                .. " card_pool=" .. coop_string(type(cards) == "table"
                    and type(cards.pool) == "table" and #cards.pool or nil)
                .. " upgrades=" .. coop_string(type(upgrades))
                .. " upgrade_count=" .. coop_string(type(upgrades) == "table"
                    and #upgrades or nil)
                .. " unlimited=" .. coop_string(mode.unlimited))
        end
        -- end_level suspends event processing until the card screen is open.
        -- Open it in the callback, as the base Throne mode does.
        level_up(data, next_floor)
        if _log then _log("[COOP FLOOR] level_up returned directly") end
    elseif mode.lvl == 11 then
        -- The boss vignette also retires the old UI button references.
        for _, guard in ipairs(mode.coop_spent_soul_click_guards or {}) do
            guard.buttons = {}
        end
        add(upgrades, {gain={6}, sac={5}})
        build_stack()
        coop_start_boss_story(next_floor)
    end
end

function on_empty()
    -- Surrender and the queued turn can both report an empty board. Starting
    -- end_level twice creates overlapping floor transitions and breaks the
    -- next floor's board/input state.
    if mode.coop_floor_transition then
        if _log then _log("[COOP WIN] ignored duplicate on_empty on floor " .. coop_string(mode.lvl)) end
        return
    end
    coop_track_knight_presence()
    mode.coop_floor_transition = true
    mode.coop_surrender_input_locked = true
    mode.coop_auto_select_knight_pending = nil
    mode.coop_select_king_pending = nil
    mode.coop_knight_move_origin_sq = nil
    mode.coop_manual_king_turn_pending = nil
    mode.coop_manual_king_turn_frames = nil
    if mode.coop_knight then mode.coop_knight.ready = false end
    -- The old board is already being torn down. Restore the hero reference
    -- without rebuilding its cursor or touching square buttons here.
    if mode.coop_king_hero then hero = mode.coop_king_hero end
    mode.coop_king_hero = nil
    mode.coop_selected = "king"
    mode.coop_knight_selected_soul = nil
    mode.coop_knight_move_soul_to_spend = nil
    mode.coop_soul_selection_fx = nil
    mode.coop_cursor_refresh_pending = false
    mode.coop_king_kill_pending_floor = nil
    mode.coop_king_kill_pending_frames = nil
    mode.coop_force_king_kill_turn = nil
    mode.coop_opening_king_turn = false
    coop_log_knight_state("on_empty")
    coop_record_knight_state_before_floor_change()
    if _log then _log("[COOP FLOOR] calling end_level floor=" .. coop_string(mode.lvl)) end
    end_level(grow)
    if _log then _log("[COOP FLOOR] end_level returned floor=" .. coop_string(mode.lvl)) end
end

function on_hero_death()
    if mode.coop_duel and not mode.coop_duel.finished then coop_duel_finish("knight");return end
    if mode.coop_stats then mode.coop_stats.running = false end
    mode.coop_run_active = false
    mode.coop_opening_king_turn = false
    local rank = mode.ranks_index + 1
    if mode.lvl > bget(rank, 1) then
        bset(rank, 1, mode.lvl)
    end
    save()
    gameover(function() coop_show_run_stats(false) end)
end

function on_boss_death()
    if mode.coop_duel and not mode.coop_duel.finished then coop_duel_finish("king");return end
    if mode.coop_book_scene and mode.coop_book_scene.started then return end
    if coop_try_hidden_boss() then return end
    coop_finish_throne_story()
end

function outro()
    -- The disguised King reaches this directly from native spawn_horsemen.
    coop_freeze_throne_result()
    local completed_rank = mode.ranks_index + 1
    if completed_rank > bget(0, 1) then
        bset(0, 1, completed_rank)
        savbnk()
    end
    coop_start_story(true, function() coop_show_run_stats(true) end)
end

function get_weapons_list()
    local a = {0}
    for i = 2, #weapons do
        if bget(i, 4) == 1 then add(a, i-1) end
    end
    return a
end

function get_max_rank()
    return min(#ranks, bget(0,1) + 1)
end

function check_unlocks()
    local function unlock(index)
        if bget(index, 4) == 1 then return end
        bset(index, 4, 1)
        savbnk()
        if _log then
            _log("[COOP UNLOCK] " .. weapons[index].name
                .. " blade=" .. coop_string(stack and stack.blade))
        end
        fx_unlock(weapons[index].name, {icon={x=21, y=282, w=12, h=6}})
    end

    -- Match the unlock conditions in the current throne mode.
    if get_firerange() >= 6 then unlock(2) end
    if stack and stack.knockback and stack.knockback >= 100 then unlock(3) end
    if stack and stack.chamber_max and stack.chamber_max >= 4 then unlock(4) end
    if stack and stack.blade and stack.blade >= 4 then unlock(5) end
    if inter and (inter.searched or 0) >= 4 then unlock(6) end
    if stack and stack.firerange == 0 then unlock(7) end
    if stack and (stack.sheath or 0) >= 2 then unlock(9) end

    -- Attila is found on rank 6, floor 8 by digging up the same square as
    -- in throne mode. The unlock popup is enough here; the co-op controller
    -- does not own the original mode's discovery animation.
    local gun_sq = gsq and gsq(7, 1)
    if mode.ranks_index == 5 and mode.lvl == 8 and gun_sq and gun_sq.dug then
        unlock(8)
    end
end

function save_preferences()
    bset(0,4,mode.ranks_index)
    bset(1,4,mode.weapons_index)
    save()
end

function coop_draw_knight_blade_icon(x, y)
    -- A small diagonal sword, using the same red as the Knight's move hints.
    -- Draw it over the hovered enemy so it reads as an attack, not a landing.
    rectfill(x+12, y+3, x+12, y+4, 5)  -- point
    rectfill(x+11, y+4, x+12, y+5, 5)
    rectfill(x+10, y+5, x+11, y+6, 5)
    rectfill(x+9, y+6, x+10, y+7, 5)
    rectfill(x+8, y+7, x+9, y+8, 5)
    rectfill(x+7, y+8, x+8, y+9, 5)
    rectfill(x+4, y+8, x+5, y+9, 5)    -- crossguard
    rectfill(x+5, y+9, x+6, y+10, 5)
    rectfill(x+7, y+10, x+8, y+11, 5)
    rectfill(x+8, y+11, x+9, y+12, 5)
    rectfill(x+6, y+10, x+7, y+11, 5)  -- grip
    rectfill(x+5, y+11, x+6, y+12, 5)
    rectfill(x+4, y+12, x+5, y+13, 5)
end

function coop_draw_knight_spear_icon(x, y)
    -- A narrow red shaft and a pointed head distinguish the long thrust
    -- from the adjacent sword attack without covering the target piece.
    line(x+3, y+12, x+11, y+4, 5)
    line(x+4, y+12, x+12, y+4, 5)
    rectfill(x+11, y+3, x+12, y+4, 5)
    pset(x+13, y+2, 5)
    rectfill(x+2, y+12, x+4, y+13, 5)
end

function coop_draw_warrant_execution()
    local fx = mode and mode.coop_warrant_execution_fx
    if not fx then return end
    if not is_coop_active() or fx.floor ~= mode.lvl then
        mode.coop_warrant_execution_fx = nil
        return
    end
    local age = time() - fx.started
    if age < 0 or age >= 0.48 then
        mode.coop_warrant_execution_fx = nil
        return
    end
    if mode.coop_pause_menu_open then return end

    local board_left, board_top = coop_get_board_geometry()
    local hx = coop_floor_int(board_left + fx.hunter_x * 16 + 8 + 0.5)
    local hy = coop_floor_int(board_top + fx.hunter_y * 16 + 8 + 0.5)
    local kx = coop_floor_int(board_left + fx.knight_x * 16 + 8 + 0.5)
    local ky = coop_floor_int(board_top + fx.knight_y * 16 + 8 + 0.5)
    local ux = (kx - hx) / 16
    local uy = (ky - hy) / 16

    -- The Knight has already been removed from the game state. A short
    -- silhouette lets the strike visibly connect without restoring control.
    if age < 0.29 then
        rectfill(kx - 2, ky - 5, kx + 1, ky - 3, 3)
        rectfill(kx - 1, ky - 2, kx + 1, ky + 3, 3)
        rectfill(kx - 3, ky + 4, kx + 3, ky + 4, 3)
        if age >= 0.12 then rectfill(kx - 2, ky - 1, kx + 2, ky, 5) end
    end

    if age >= 0.12 and age < 0.21 then
        local sx=coop_floor_int(hx+ux*7+.5)
        local sy=coop_floor_int(hy+uy*7+.5)
        line(sx,sy,kx,ky,4)
        rectfill(sx-1,sy-1,sx+1,sy+1,7)
    end

    if age >= 0.12 then
        local radius = age < 0.24 and 3 or 5
        line(kx - radius, ky - radius, kx + radius, ky + radius, 5)
        line(kx - radius, ky + radius, kx + radius, ky - radius, 5)
        if age >= 0.24 then
            local spread = 2 + coop_floor_int((age - 0.24) * 20)
            pset(kx - spread, ky - 1, 5)
            pset(kx + spread, ky + 1, 5)
            pset(kx - 1, ky - spread, 5)
            pset(kx + 1, ky + spread, 5)
        end
    end
end

function coop_start_knight_swing(knight, target_sq, use_spear)
    if not knight or not knight.sq or not target_sq then return end
    knight.coop_weapon_angle = atan2(
        target_sq.px - knight.sq.px, target_sq.py - knight.sq.py)
    knight.coop_swing_angle = knight.coop_weapon_angle
    knight.coop_swing_spear = use_spear == true
    knight.coop_swing_started = time()
end

function coop_load_knight_weapon_pixels()
    if not mode.coop_weapon_sheet_loaded or type(spritesheet) ~= "function"
        or type(sget) ~= "function" then return end
    local previous_sheet = spritesheet()
    if not previous_sheet then return end

    local pixels = {}
    spritesheet(mode.coop_weapon_sheet_name)
    if mode.coop_weapon_uses_key then
        -- This game discards PNG alpha when it loads a spritesheet. The new
        -- artwork uses the upper-left corner's solid background as a key.
        local background = sget(0, 0)
        local size = mode.coop_weapon_source_size
        for y = 0, size - 1 do
            for x = 0, size - 1 do
                local col = sget(x, y)
                if col ~= nil and col ~= background then
                    pixels[y * size + x] = col
                end
            end
        end
    else
        -- Keep the old 24-pixel art working until a new sheet is supplied.
        local alpha_rows = {
            {},
            {19,20},
            {18,19,20,21},
            {17,18,19,20,21},
            {16,17,18,19,20},
            {12,13,15,16,17,18,19},
            {11,12,13,14,15,16,17,18},
            {12,13,14,15,16},
            {11,12,13,14,15,16,17},
            {10,11,12,13,14,15,16,17},
            {10,11,12,13,15,16},
            {11,12}
        }
        for row, xs in ipairs(alpha_rows) do
            for _, x in ipairs(xs) do
                pixels[(row - 1) * 24 + x] = sget(x, row - 1)
            end
        end
    end
    spritesheet(previous_sheet)
    mode.coop_weapon_pixels = pixels
    mode.coop_weapon_rotated_cache = {}
end

function coop_load_knight_spear_pixels()
    if type(spritesheet) ~= "function" or type(sget) ~= "function" then return end
    local previous_sheet = spritesheet()
    if not previous_sheet then return end
    local pixels = {}
    mode.coop_spear_native = not mode.coop_spear_sheet_loaded
    if mode.coop_spear_sheet_loaded then
        spritesheet("coop_knight_spear_hi")
        local background = sget(0, 0)
        for y = 0, 47 do
            for x = 0, 47 do
                local col = sget(x, y)
                if col ~= nil and col ~= background then pixels[y * 48 + x] = col end
            end
        end
    else
        -- Native pike, 5x19 at (106,72). Turn its upward tip to the right
        -- around a grip 14 pixels below the tip. Store final colors locally;
        -- changing the global palette would also recolor pieces and menus.
        spritesheet("gfx")
        local colors = {[1]=4, [4]=2, [3]=3, [2]=1}
        for y = 0, 18 do
            for x = 0, 4 do
                local col = sget(106+x, 72+y)
                if col ~= nil and col ~= 0 then
                    local color = colors[col] or col
                    if x==2 and y==7 then color=5 end
                    pixels[(23+x-2)*48 + 23+14-y] = color
                end
            end
        end
    end
    spritesheet(previous_sheet)
    mode.coop_spear_pixels = pixels
    mode.coop_spear_rotated_cache = {}
end

function coop_draw_knight_weapon(center_x, center_y)
    if not is_coop_active() or mode.coop_floor_transition then return end
    local knight = mode.coop_knight
    if not knight or not knight.sq or knight.dead == true
        or (knight.hp ~= nil and knight.hp <= 0)
        or type(center_x) ~= "number" or type(center_y) ~= "number" then return end

    local angle = knight.coop_weapon_angle or -0.125
    local now = time()
    local swing = knight.coop_swing_started
    local swing_progress = swing and (now - swing) / 0.24 or 1
    local use_spear = swing_progress < 1 and knight.coop_swing_spear == true

    if swing_progress >= 1 then
        knight.coop_swing_started = nil
        knight.coop_swing_spear = nil
        if mode.coop_selected == "knight" and not mode.coop_pause_menu_open then
            local mx = btnv("coop_mouse_x_probe", 0)
            local my = btnv("coop_mouse_y_probe", 0)
            if type(mx) == "number" and type(my) == "number"
                and (mx ~= center_x or my ~= center_y) then
                angle = atan2(mx - center_x, my - center_y)
                knight.coop_weapon_angle = angle
                use_spear = knight.ready ~= false
                    and not coop_knight_soul_ready(knight)
                    and coop_knight_can_spear_square(knight,
                        coop_get_square_at_mouse(mx, my)) or false
            end
            if coop_controller then angle,use_spear=coop_controller.weapon_aim(knight,angle,use_spear) end
        else
            -- The King controls the mouse again. Park the Knight's weapon in
            -- its drawn resting pose instead of following that cursor.
            angle = -0.125
        end
    else
        -- The hit resolves immediately, while the weapon sweeps across the
        -- locked target direction during the next quarter of a second.
        angle = (knight.coop_swing_angle or angle)
            - 0.14 + 0.28 * max(0, swing_progress)
    end

    -- Both sheets point up-right. Sample opaque source pixels around their
    -- grip without changing the game's palette transparency state.
    if use_spear and not mode.coop_spear_pixels then
        coop_load_knight_spear_pixels()
    end
    if not use_spear and mode.coop_weapon_sheet_loaded
        and not mode.coop_weapon_pixels then
        coop_load_knight_weapon_pixels()
    end
    local pixels, cache
    if use_spear then
        pixels = mode.coop_spear_pixels
        cache = mode.coop_spear_rotated_cache
    else
        pixels = mode.coop_weapon_pixels
        cache = mode.coop_weapon_rotated_cache
    end
    if pixels and cache then
        local source_angle = (use_spear and mode.coop_spear_native) and 0 or 0.125
        local direction = coop_floor_int((angle + source_angle) * 128 + 0.5) % 128
        local frame = cache[direction]
        if not frame then
            frame = {}
            local c, s = cos(direction / 128), sin(direction / 128)
            local size = use_spear and 48 or mode.coop_weapon_source_size
            local anchor = use_spear and 23 or mode.coop_weapon_anchor
            local radius = size == 48 and 24 or 16
            local minimum_coverage = size == 48 and 2 or 1
            -- Four subpixel reads reduce pinholes at steep angles. The new
            -- 48-pixel art has enough detail to keep its full outline while
            -- moving through 128 aim directions instead of eight poses.
            -- Keep samples and cached pixels in plain numeric slots. Aiming
            -- across many directions otherwise creates thousands of short-
            -- lived color tables and one table per cached opaque pixel.
            for dy = -radius, radius do
                for dx = -radius, radius do
                    local c1, c2, c3, c4
                    local n1, n2, n3, n4 = 0, 0, 0, 0
                    for oy = -0.25, 0.25, 0.5 do
                        for ox = -0.25, 0.25, 0.5 do
                            local sx = coop_floor_int(anchor + (dx + ox) * c + (dy + oy) * s + 0.5)
                            local sy = coop_floor_int(anchor - (dx + ox) * s + (dy + oy) * c + 0.5)
                            if sx >= 0 and sx < size and sy >= 0 and sy < size then
                                local col = pixels[sy * size + sx]
                                if col ~= nil then
                                    if col == c1 then n1 = n1 + 1
                                    elseif col == c2 then n2 = n2 + 1
                                    elseif col == c3 then n3 = n3 + 1
                                    elseif col == c4 then n4 = n4 + 1
                                    elseif c1 == nil then c1, n1 = col, 1
                                    elseif c2 == nil then c2, n2 = col, 1
                                    elseif c3 == nil then c3, n3 = col, 1
                                    else c4, n4 = col, 1 end
                                end
                            end
                        end
                    end
                    local best, count = c1, n1
                    if n2 > count then best, count = c2, n2 end
                    if n3 > count then best, count = c3, n3 end
                    if n4 > count then best, count = c4, n4 end
                    if count >= minimum_coverage then
                        frame[#frame + 1] = dx
                        frame[#frame + 1] = dy
                        frame[#frame + 1] = best
                    end
                end
            end
            cache[direction] = frame
        end
        for pixel_index = 1, #frame, 3 do
            local pixel_x = frame[pixel_index]
            local pixel_y = frame[pixel_index + 1]
            -- Keep the grip and shaft from appearing across the transparent
            -- gaps in the Knight's body, regardless of aim direction.
            if abs(pixel_x) > 2 or pixel_y < -5 or pixel_y > 6 then
                pset(center_x + pixel_x, center_y + pixel_y, frame[pixel_index + 2])
            end
        end
        return
    end

    if use_spear then
        -- The card works before its optional art is painted. This slim shaft
        -- and pointed head are replaced by knight_spear_hi.png when present.
        local ux, uy = cos(angle), sin(angle)
        local vx, vy = -uy, ux
        local function pixel_at(forward, sideways)
            return coop_floor_int(center_x + ux * forward + vx * sideways + 0.5),
                coop_floor_int(center_y + uy * forward + vy * sideways + 0.5)
        end
        local bx, by = pixel_at(-5, 0)
        local sx, sy = pixel_at(15, 0)
        local tx, ty = pixel_at(22, 0)
        line(bx, by, sx, sy, 7)
        local edge_x, edge_y = pixel_at(15, 1)
        line(bx, by, edge_x, edge_y, 5)
        local left_x, left_y = pixel_at(16, -3)
        local right_x, right_y = pixel_at(16, 3)
        line(left_x, left_y, tx, ty, 7)
        line(right_x, right_y, tx, ty, 7)
        return
    end

    -- Visible placeholder until knight_weapon.png is supplied. The grip is
    -- centred on the piece; the blade points along the current aim angle.
    local ux, uy = cos(angle), sin(angle)
    local bx = coop_floor_int(center_x - ux * 3 + 0.5)
    local by = coop_floor_int(center_y - uy * 3 + 0.5)
    local tx = coop_floor_int(center_x + ux * 11 + 0.5)
    local ty = coop_floor_int(center_y + uy * 11 + 0.5)
    line(bx, by, tx, ty, 7)
    line(coop_floor_int(center_x - uy * 2 + 0.5), coop_floor_int(center_y + ux * 2 + 0.5),
        coop_floor_int(center_x + uy * 2 + 0.5), coop_floor_int(center_y - ux * 2 + 0.5), 5)
    if swing_progress < 1 then
        local trail_angle = angle - 0.055
        line(coop_floor_int(center_x + cos(trail_angle) * 10 + 0.5),
            coop_floor_int(center_y + sin(trail_angle) * 10 + 0.5), tx, ty, 5)
    end
end

function coop_draw_knight_move_hints(behind_piece)
    if not is_coop_active() or coop_floor_is_ending()
        or coop_white_move_animation_pending()
        or mode.coop_selected ~= "knight"
        or mode.coop_pause_menu_open or (mode.coop_menu_click_grace or 0) > 0 then
        return
    end
    local knight = mode.coop_knight
    if not knight or not knight.sq or knight.ready == false
        or (knight.hp ~= nil and knight.hp <= 0) then return end

    local board_left, board_top = coop_get_board_geometry()
    local mouse_x = btnv("coop_mouse_x_probe", 0)
    local mouse_y = btnv("coop_mouse_y_probe", 0)
    if coop_controller then mouse_x,mouse_y=coop_controller.hover(mouse_x,mouse_y) end
    local hovered = coop_get_square_at_mouse(mouse_x, mouse_y)
    -- Soul selection replaces the ordinary Knight-jump preview. Charge
    -- selection marks directions, while bishop/rook souls mark safe landings.
    local selected_soul = coop_knight_soul_ready(knight)
    local preview_soul = selected_soul
    if not preview_soul then
        local soul = coop_get_known_soul_at(mouse_x, mouse_y)
        if soul and has_card and ((soul.id == 1 and coop_has_knight_skill("Co-op Knight Spirit"))
            or ((soul.id == 2 or soul.id == 3) and coop_has_knight_skill("Co-op In-Law"))) then
            preview_soul = soul
        end
    end
    local charge_preview = (selected_soul and mode.coop_knight_selected_soul
        and mode.coop_knight_selected_soul.id == 1)
        or (type(preview_soul) == "table" and preview_soul.id == 1)
    if behind_piece and not charge_preview then return end
    local targets
    if selected_soul then
        targets = coop_get_knight_input_targets(knight)
    elseif preview_soul and preview_soul.id == 1 then
        targets = coop_knight_charge_targets(knight)
    elseif preview_soul then
        targets = coop_knight_soul_move_targets(knight, preview_soul.id)
    else
        targets = coop_get_knight_move_targets(knight)
    end
    if _log and not mode.coop_logged_knight_move_hints then
        mode.coop_logged_knight_move_hints = true
        _log("[COOP HINTS] draw_game targets=" .. coop_string(#targets)
            .. " board=" .. coop_string(board_left) .. "," .. coop_string(board_top))
    end
    for _, sq in ipairs(targets) do
        local occupied = not behind_piece and charge_preview
            and coop_piece_on_square(sq)
        if (behind_piece and behind_piece.sq == sq)
            or (not behind_piece and not occupied) then
            local x = board_left + sq.px * 16
            local y = board_top + sq.py * 16
            local arm = sq == hovered and 5 or 3
            rectfill(x+2, y+2, x+2+arm, y+3, 5)
            rectfill(x+2, y+2, x+3, y+2+arm, 5)
            rectfill(x+13-arm, y+2, x+13, y+3, 5)
            rectfill(x+12, y+2, x+13, y+2+arm, 5)
            rectfill(x+2, y+12, x+2+arm, y+13, 5)
            rectfill(x+2, y+13-arm, x+3, y+13, 5)
            rectfill(x+13-arm, y+12, x+13, y+13, 5)
            rectfill(x+12, y+13-arm, x+13, y+13, 5)
        end
    end
    -- Movement keeps its corner marks; occupied attack squares show the
    -- corresponding weapon instead of a landing hint.
    if not behind_piece and not preview_soul and hovered
        and coop_knight_can_attack_target(knight, hovered) then
        local x = board_left + hovered.px * 16
        local y = board_top + hovered.py * 16
        if coop_knight_can_spear_target(knight, hovered) then
            coop_draw_knight_spear_icon(x, y)
        else
            coop_draw_knight_blade_icon(x, y)
        end
    end
end

function draw_inter()
    local s = lang.floor_ .. " "
    local x = lprint(s, MCW/2, board_y-19, 3, 1)
    local floor_label = mode.lvl
    if mode.coop_variant == "charnier" then
        floor_label = (mode.lvl+1).."/"..((mode.lvl_max or 3)+1)
    end
    lprint(floor_label, x, board_y-19, 5)

    local player=mode.coop_selected=="knight" and 2 or 1
    if mode.coop_duel then player=mode.coop_duel.input and 2 or 1 end
    coop_draw_turn_indicator(player,mode.coop_run_active and not mode.coop_native_turn_in_progress)

    if not mode.coop_duel and not mode.coop_knight and mode.knight_ever_died then
        lprint("Press R to revive knight (costs 1 soul)", 10, board_y+22, 2)
    end
end

-- Shared rule entry: local input and network adapters use the same action body.
function coop_perform_knight_action(knight, target, context)
    if not knight or not target or knight.ready==false then return false end
    local c=context or {}
    local board_click=c.board_click~=false
    local target_is_legal=c.target_is_legal
    if target_is_legal==nil then
        for _,sq in ipairs(coop_get_knight_input_targets(knight)) do
            if sq==target then target_is_legal=true break end
        end
    end
    if board_click and coop_knight_soul_ready(knight) and mode.coop_knight_selected_soul.id==1 then
        return coop_anchor_knight_charge(knight,target)
    end
    local blade_available=not coop_knight_soul_ready(knight)
    local click_x,click_y=c.click_x or 0,c.click_y or 0
    local native_target,native_target_source=c.native_target,c.native_target_source or "adapter"
    local coordinate_target=c.coordinate_target or target
    local native_target_is_actionable=c.native_target_is_actionable or false
            local target_piece = target and coop_piece_on_square(target)
            local blade_handled = false
            if board_click and target and blade_available
                and coop_knight_can_attack_target(knight, target)
                and knight.ready ~= false and type(hit) == "function" then
                blade_handled = true
                local target_was_white_king = coop_is_white_king(target_piece)
                local spear_attack = coop_knight_can_spear_target(knight, target)
                local blade_damage = coop_grand_phalanx_blade_damage(target_piece,
                    coop_knight_guarded_blade_damage(target_piece,
                        coop_knight_attack_damage(knight, nil, target_piece,
                            spear_attack and 2 or nil)))
                local hp_before = target_piece.hp
                if _log then
                    _log("[COOP ATTACK] blade target=" .. coop_trace_value(target_piece)
                        .. " damage=" .. coop_string(blade_damage)
                        .. " hp_before=" .. coop_string(hp_before)
                        .. " king_hop_before=" .. coop_string(hero and hero.hop)
                        .. " stack_hop=" .. coop_string(stack and stack.hop)
                        .. " hit_api=" .. type(hit))
                end
                sfx("blade")
                coop_start_knight_swing(knight, target, spear_attack)
                local sweep_targets = coop_knight_sweep_targets(knight.sq, target)
                local sweep_killed_king = false
                if target_was_white_king then
                    sweep_killed_king = coop_apply_knight_sweep(sweep_targets)
                end
                if blade_damage > 0 then
                    local victim_square = target_piece.sq
                    local victim_attacks = type(get_range) == "function"
                        and get_range(target_piece, {atk=1}) or nil
                    hit(target_piece, blade_damage, {coop_stats_owner=2})
                    if target_piece.dead == true
                        or (target_piece.hp ~= nil and target_piece.hp <= 0) then
                        coop_record_knight_kill_ui(target_piece, victim_square,
                            victim_attacks)
                    end
                    coop_record_bounty_kill(target_piece, hp_before)
                    coop_queue_royal_vigil(target_piece)
                    coop_apply_blade_revenge(target_piece)
                end
                if not target_was_white_king then
                    sweep_killed_king = coop_apply_knight_sweep(sweep_targets)
                end
                knight.ready = false
                coop_queue_warrant_knight_check(knight)
                mode.coop_auto_select_knight_pending = nil
                mode.coop_select_king_pending = true
                if sweep_killed_king or (target_was_white_king
                    and (target_piece.dead == true
                        or (target_piece.hp and target_piece.hp <= 0))) then
                    -- `hit` creates the surrender event, but a Knight attack
                    -- does not submit a King action to advance that event.
                    mode.coop_king_kill_pending_floor = mode.lvl
                    mode.coop_king_kill_pending_frames = 2
                    mode.coop_surrender_input_locked = true
                    coop_lock_surrender_controls()
                    if _log then _log("[COOP WIN] white King killed by Knight; queue native turn") end
                end
                if _log then
                    _log("[COOP ATTACK] blade resolved hp_after="
                        .. coop_string(target_piece.hp)
                        .. " king_hop_after=" .. coop_string(hero and hero.hop)
                        .. " knight_ready=" .. coop_string(knight.ready)
                        .. " selected=" .. coop_string(mode.coop_selected))
                end
            elseif board_click and target and target_piece then
                -- Occupied squares are never Knight destinations. Adjacent
                -- enemies are handled only by the separate blade action.
                if _log then
                    _log("[COOP GUARD] occupied Knight destination rejected target="
                        .. coop_trace_value(target)
                        .. " occupant=" .. coop_trace_value(target_piece))
                end
            elseif board_click and target and not is_free(target) and _log then
                _log("[COOP ATTACK TARGET] occupied square without piece lookup="
                    .. coop_trace_value(target)
                    .. " square_piece=" .. type(target.piece))
            elseif board_click and target and _log then
                _log("[COOP INPUT] knight click ignored legal=" .. coop_string(target_is_legal)
                    .. " ready=" .. coop_string(knight.ready ~= false)
                    .. " target=" .. coop_trace_value(target))
            end

            -- Recheck at the point of movement. The target list was built at
            -- click handling time, but an animation can change occupancy.
            if board_click and not blade_handled and target_is_legal
                and knight.ready ~= false and not target.piece
                and not target.moat and not coop_has_barricade(target)
                and is_free(target) then
                mode.coop_knight_move_soul_to_spend = nil
                if coop_knight_soul_ready(knight) then
                    mode.coop_knight_move_soul_to_spend = mode.coop_knight_selected_soul
                end
                mode.coop_knight_move_origin_sq = knight.sq
                if _log then
                    _log("[COOP INPUT] Knight jump click target=" .. coop_trace_value(target)
                        .. " from=" .. coop_trace_value(knight.sq)
                        .. " mouse=" .. coop_string(click_x) .. "," .. coop_string(click_y)
                        .. " native_target=" .. coop_trace_value(native_target)
                        .. " coordinate_target=" .. coop_trace_value(coordinate_target)
                        .. " target_api=" .. coop_string(native_target_source)
                        .. " source=" .. (native_target_is_actionable and "native" or "coordinates"))
                end
                -- `hero` remains the King for engine rendering and enemy AI.
                -- Submit the Knight move directly instead of routing it
                -- through the hero-only move_hero controller.
                move_piece(knight, target)
                if knight.sq == target then coop_finish_knight_move(knight, target) end
                return true
            end

    return blade_handled
end
