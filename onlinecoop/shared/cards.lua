-- Diagnostic interpreter-only fallback: several native dumps show the same
-- corrupted all() closure upvalue. Disabling only all() did not prevent it.
-- Disable compilation engine-wide, including callers, and discard old traces.
-- This is a compatibility experiment, not a confirmed root-cause repair.
if type(jit) == "table" and type(jit.off) == "function" then
    jit.off()
    if type(jit.flush) == "function" then jit.flush() end
    if type(_log) == "function" then
        if type(jit.status) == "function" then
            local enabled = jit.status()
            _log("[COOP CRASH GUARD] global JIT enabled=" .. (enabled and "true" or "false"))
        else
            _log("[COOP CRASH GUARD] global JIT disabled; status unavailable")
        end
    end
end

local max_type = 0
for _, p in ipairs(PIECES) do
    if p.type > max_type then max_type = p.type end
end
local coop_knight_typ = max_type + 1
local warrant_knight_typ = coop_knight_typ + 1

-- Custom mode buttons use the mod's list position and the mode filename as
-- their language key (for example "1.coop"), rather than just "coop".
local coop_mod_index
for i, entry in ipairs(MODLIST or {}) do
    if entry.name == "onlinecoop" then
        coop_mod_index = i
        break
    end
end

local function coop_localize_mode_menu(language)
    local chinese = language == "simplified_chinese"
    local entries = {
        {"onlinecoop_endless", "局域网无尽", "LAN Endless", "房主黑王，加入者黑骑士", "Host: King. Guest: Knight"},
        {"onlinecoop_charnier", "局域网剿灭", "LAN Charnier", "房主管理余烬与商店", "Host manages cinders and shop"},
        {"onlinecoop", "局域网合作", "LAN Co-op", "房主黑王，加入者黑骑士", "Host: King. Guest: Knight"},
        {"coop", "合作模式", "Co-op", "两人本地合作\n黑王+黑骑士同屏作战！", "Local King and Knight co-op"},
        {"coop_endless", "合作无尽", "Co-op Endless", "两人合作挑战无尽楼层", "Endless floors for two players"},
        {"coop_charnier", "合作剿灭", "Co-op Charnier", "共同剿灭，积累余烬与负担", "Cooperative raids, cinders and burdens"}
    }
    for _, entry in ipairs(entries) do
        local title=chinese and entry[2] or entry[3]
        local description=title.."|"..(chinese and entry[4] or entry[5])
        lang[entry[1]]=title
        if coop_mod_index then
            for _, key in ipairs({coop_mod_index.."."..entry[1],coop_mod_index..". "..entry[1]}) do
                lang[key]=title
                lang[key.."_desc"]=description
            end
        end
    end
end

coop_localize_mode_menu(current_lang)
append("load_lang", coop_localize_mode_menu, "coop_mode_menu_translation")

-- Use the native menu button's right-click path, not a board-wide mouse hook.
-- set_mode runs synchronously inside act_menu; starting the run is deferred
-- until rank/weapon selection. Store the opt-in on that new mode only.
append("mk_menu_but",function(id)
    if not coop_mod_index then return end
    local matches=false
    for _,name in ipairs({"coop","coop_endless","coop_charnier"}) do
        if id==coop_mod_index..". "..name or id==coop_mod_index.."."..name then matches=true end
    end
    if not matches then return end
    for _,entry in ipairs(menu or {}) do
        if entry.id==id and entry.but and not entry.lock then
            local button=entry.but
            button.right_clic=function()
                if button.skip then return end
                act_menu(id)
                if mode and mode.id=="coop" then
                    mode.coop_wildcards_pending=true
                    if _log then _log("[COOP DEBUG] right-click Wild Cards enabled for next run") end
                end
            end
        end
    end
end,"coop_wildcards_menu_opt_in")

local function coop_localize_cards(language)
    local chinese = language == "simplified_chinese"
    lang["Co-op In-Law"] = chinese and "裂颅" or "shotgun wedding"
    lang["Co-op Knight Spirit"] = chinese and "骑士精神" or "chivalry"
    lang["Co-op Rally Order"] = chinese and "整顿号令" or "Rally Order"
    lang["Co-op Warrant"] = chinese and "通缉令" or "Warrant"
    lang["Co-op Bounty Cavalry"] = chinese and "悬赏骑兵" or "Bounty Cavalry"
    lang["Co-op Joust Compact"] = chinese and "骑士对决" or "Joust Compact"
    lang["Co-op Excommunication"] = chinese and "绝罚" or "Excommunication"
    lang["Co-op Divisive Edict"] = chinese and "离间法令" or "Divisive Decree"
    lang["Co-op Revenant Bell"] = chinese and "返魂警钟" or "Revenant Bell"
    lang["Co-op Royal Vigil"] = chinese and "王庭警戒" or "Royal Vigil"
    lang["Co-op Blade Revenge"] = chinese and "白刃复仇" or "Blade Revenge"
    lang["Co-op Grand Phalanx"] = chinese and "大方阵" or "Grand Phalanx"
    lang["Co-op Mechanism Order"] = chinese and "机关号令" or "Knight Phantom"
    lang["Co-op Sweeping Blade"] = chinese and "横扫之刃" or "Sweeping Blade"
    lang["Co-op Gun Knight Duet"] = chinese and "枪骑协奏" or "Gun-Knight Duet"
    lang["Co-op Timar Cavalry Pact"] = chinese and "帝玛尔骑兵协议" or "Akinji System"
    lang["Co-op Cheval de Frise"] = chinese and "拒马阵" or "place palings"
    lang["piece_"..warrant_knight_typ] = chinese and "缉骑官" or "gen d'arme"
    lang["short_piece_"..warrant_knight_typ] = chinese and "缉骑官" or "gen d'arme"
    lang["effect_coop_in_law"] = chinese
        and "骑士模式：使用主教或城堡灵魂，按其走法移动黑骑士"
        or "Knight mode: spend a bishop or rook soul to move the Black Knight by its pattern"
    lang["effect_coop_knight_spirit"] = chinese
        and "骑士模式：选择骑士灵魂后，左键选择同一行或列的格子；回合结束时冲锋，对首个白棋造成双倍利刃伤害"
        or "Knight mode: select a knight soul, then left-click a square on the same rank or file. After the King's action, charge and deal double blade damage to the first white piece"
    lang["effect_coop_rally_order"] = chinese
        and "合作模式：黑王在弹仓未空时主动上弹，黑骑士刀锋 +1，攻击后恢复"
        or "Co-op: reloading before the King's chamber is empty gives the Black Knight +1 blade until its next attack"
    lang["effect_coop_warrant"] = chinese
        and "增加一名4血的缉骑官；回合结束时若黑骑士停在其周围八格内，将被击杀"
        or "Add a 4 HP gen d'arme that kills the Black Knight if it ends the round adjacent"
    lang["effect_coop_bounty_cavalry"] = chinese
        and "黑骑士每击杀3枚白棋，白方增援1名骑士；第6枚改为增援1名缉骑官"
        or "Every 3 white pieces killed by the Black Knight bring a Knight reinforcement; the sixth brings a gen d'arme instead"
    lang["effect_coop_joust_compact"] = chinese
        and "黑骑士与白方骑士相邻时，黑王无法开枪"
        or "The Black King cannot shoot while the Black Knight is adjacent to a white Knight"
    lang["effect_coop_excommunication"] = chinese
        and "主教准备移动时黑骑士刀锋-1"
        or "While any white bishop is ready to move, the Black Knight has -1 blade; restored afterward, without stacking (minimum 1)"
    lang["effect_coop_divisive_edict"] = chinese
        and "黑王与黑骑士相邻时散射+15；不相邻时火力-1；黑骑士死亡时翻面"
        or "The Black King has +15 spread while adjacent to the Black Knight; otherwise, -1 firepower. Flips when the Black Knight dies"
    lang["effect_coop_revenant_bell"] = chinese
        and "复活黑骑士时，白方增援两枚主教"
        or "Reviving the Black Knight brings two white Bishop reinforcements"
    lang["effect_coop_royal_vigil"] = chinese
        and "白王被黑骑士攻击时，白方增援一名禁军"
        or "When the Black Knight attacks the white King, the white side gains one Warden reinforcement"
    lang["effect_coop_blade_revenge"] = chinese
        and "被黑骑士攻击的白棋等待行动回合-1"
        or "White pieces attacked by the Black Knight wait one fewer turn before acting"
    lang["effect_coop_grand_phalanx"] = chinese
        and "白兵与另一枚白兵上下左右相邻时，受到黑骑士刀锋伤害-1"
        or "White pawns orthogonally adjacent to another white pawn take 1 less blade damage from the Black Knight"
    lang["effect_coop_nightbane"] = chinese
        and "合作模式：黑骑士利刃 +1"
        or "Co-op: Black Knight blade +1"
    lang["effect_coop_moat"] = chinese
        and "合作模式：黑骑士位于护城河下方时，刀锋 +1"
        or "Co-op: Black Knight blade +1 while below the moat"
    lang["Co-op High Cantle Saddle"] = chinese and "高鞍尾马鞍" or "High Cantle Saddle"
    lang["Co-op Deflect Armor"] = chinese and "偏转护甲" or "Deflect Armor"
    lang["Co-op Abbey of Kings"] = chinese and "列王修道院" or "Abbey of Kings"
    lang["effect_coop_high_saddle"] = chinese and "冲锋后的下一回合，黑骑士刀锋 +2" or "The Black Knight gains +2 blade for the turn after a charge"
    lang["effect_coop_deflect_armor"] = chinese and "白王持盾时子弹落空，准备移动的回合可受到最多1点射击伤害，等待行动回合-1；刀锋破盾，破盾当回合免伤，移动后恢复盾牌" or "Shielded white Kings evade bullets, but can take up to 1 bullet damage per turn when ready to move; wait 1 fewer turn. Blade breaks the shield; immune for that turn. Moving restores the shield"
    lang["effect_coop_abbey"] = chinese and "白王周围的白棋每回合恢复1点血量" or "White pieces around the white King recover 1 HP each turn"
    lang["effect_coop_grindstone"] = chinese
        and "合作模式：每经过12回合，黑骑士利刃 +1"
        or "Co-op: Black Knight blade +1 every 12 turns"
    lang["effect_coop_redemption"] = chinese
        and "合作模式：黑骑士死亡时，生成一枚普通白骑士"
        or "Co-op: when the Black Knight dies, spawn an ordinary white Knight"
    lang["effect_coop_ritual_dagger"] = chinese
        and "合作模式：黑王用刀锋击杀白棋后，黑骑士下一次攻击刀锋 +1"
        or "Co-op: after the King's blade kills a white piece, the Black Knight's next attack gains +1 blade"
    lang["effect_coop_bushido"] = chinese
        and "合作模式：黑王弹仓为空时，黑骑士刀锋 +1"
        or "Co-op: the Black Knight has +1 blade while the King's chamber is empty"
    lang["effect_coop_small_fry_harvest"] = chinese
        and "合作模式：黑骑士对兵伤害 +1"
        or "Co-op: the Black Knight deals +1 damage to pawns"
    lang["effect_coop_mechanism_order"] = chinese
        and "黑骑士自刎归天，召唤六名幻影骑士"
        or "The Black Knight sacrifices itself to summon six Phantom Knights"
    lang["effect_coop_sweeping_blade"] = chinese
        and "黑骑士砍中白棋时，目标两侧的白棋各受到1点伤害（斜砍波及斜向两格）"
        or "A Black Knight blade hit deals 1 damage to white pieces on either side of the target (diagonal hits splash diagonally)"
    lang["effect_coop_gun_knight_duet"] = chinese
        and "黑王和黑骑士攻击对方曾攻击过的白棋时，额外造成1点伤害"
        or "The Black King and Knight deal 1 extra damage to white pieces previously attacked by the other"
    lang["effect_coop_timar_cavalry_pact"] = chinese
        and "黑骑士可用长矛攻击两格外的白棋，造成2点伤害"
        or "The Black Knight may spear a white piece exactly two squares away for 2 damage"
    lang["effect_coop_cheval_de_frise"] = chinese
        and "每层生成3个拒马；黑骑士不能落在拒马格，黑王走入可拆除"
        or "Place 3 barricades each floor. The Black Knight cannot land on them; the Black King removes one by moving onto it"
end
coop_localize_cards(current_lang)
append("load_lang", coop_localize_cards, "coop_card_translation")

-- Native images below are fallbacks if the dedicated card atlas is absent.
-- A positive draw weight also registers the cards with the codex and Card
-- Lab's Wild Card picker; pwe=0 made them unavailable there and to Patience.
add(CARDS, {gid=5, team=0, n=1, pwe=5, played=1, ignored=0,
    id="Co-op In-Law", soul_slot=1, coop_in_law=1})
add(CARDS, {gid=47, team=0, n=1, pwe=5, played=1, ignored=0,
    id="Co-op Knight Spirit", soul_slot=1, coop_knight_spirit=1})
add(CARDS, {gid=34, team=0, n=1, pwe=4, played=1, ignored=0,
    id="Co-op Rally Order", coop_rally_order=1})
add(CARDS, {gid=28, team=0, n=1, pwe=4, played=1, ignored=0,
    id="Co-op Mechanism Order", coop_mechanism_order=1})
add(CARDS, {gid=47, team=0, n=1, pwe=4, played=1, ignored=0,
    id="Co-op Sweeping Blade", coop_sweeping_blade=1})
add(CARDS, {gid=31, team=0, n=1, pwe=4, played=1, ignored=0,
    id="Co-op Gun Knight Duet", coop_gun_knight_duet=1})
add(CARDS, {gid=47, team=0, n=1, pwe=4, played=1, ignored=0,
    id="Co-op Timar Cavalry Pact", coop_timar_cavalry_pact=1})
-- A custom piece type must not enter the native card gain parser. The co-op
-- controller spawns the Warrant Knight after the new board is ready.
add(CARDS, {gid=100, team=1, n=1, pwe=4, played=1, ignored=0,
    id="Co-op Warrant", coop_warrant=1})
add(CARDS, {gid=61, team=1, n=1, pwe=4, played=1, ignored=0,
    id="Co-op Bounty Cavalry", coop_bounty_cavalry=1})
add(CARDS, {gid=31, team=1, n=1, pwe=4, played=1, ignored=0,
    id="Co-op Joust Compact", coop_joust_compact=1})
add(CARDS, {gid=100, team=1, n=1, pwe=4, played=1, ignored=0,
    id="Co-op Excommunication", coop_excommunication=1})
add(CARDS, {gid=94, team=1, n=1, pwe=4, played=1, ignored=0,
    id="Co-op Divisive Edict", coop_divisive_edict=1})
add(CARDS, {gid=62, team=1, n=1, pwe=4, played=1, ignored=0,
    id="Co-op Revenant Bell", coop_revenant_bell=1})
add(CARDS, {gid=91, team=1, n=1, pwe=4, played=1, ignored=0,
    id="Co-op Royal Vigil", coop_royal_vigil=1})
add(CARDS, {gid=75, team=1, n=1, pwe=4, played=1, ignored=0,
    id="Co-op Blade Revenge", coop_blade_revenge=1})
add(CARDS, {gid=79, team=1, n=1, pwe=4, played=1, ignored=0,
    id="Co-op Grand Phalanx", coop_grand_phalanx=1})
add(CARDS, {gid=17, team=1, n=1, pwe=4, played=1, ignored=0,
    id="Co-op Cheval de Frise", coop_cheval_de_frise=1})
add(CARDS, {gid=47, team=0, n=1, pwe=4, played=1, ignored=0,
    id="Co-op High Cantle Saddle", need_card="Co-op Knight Spirit", coop_high_saddle=1})
add(CARDS, {gid=20, team=1, n=1, pwe=4, played=1, ignored=0,
    id="Co-op Deflect Armor", coop_deflect_armor=1})
add(CARDS, {gid=21, team=1, n=1, pwe=4, played=1, ignored=0,
    id="Co-op Abbey of Kings", coop_abbey=1})
require("card_art.lua")
for _, card in ipairs(CARDS) do
    if card.id == "Nightbane" then card.coop_nightbane = 1 break end
end
for _, card in ipairs(CARDS) do
    if card.id == "The Moat" then card.coop_moat = 1 break end
end
for _, card in ipairs(CARDS) do
    if card.id == "Grindstone" then card.coop_grindstone = 1 break end
end
for _, card in ipairs(CARDS) do
    if card.id == "Redemption" then card.coop_redemption = 1 break end
end
for _, card in ipairs(CARDS) do
    if card.id == "Ritual Dagger" then card.coop_ritual_dagger = 1 break end
end
for _, card in ipairs(CARDS) do
    if card.id == "Bushido" then card.coop_bushido = 1 break end
end
for _, card in ipairs(CARDS) do
    if card.id == "Small Fry Harvest" then card.coop_small_fry_harvest = 1 break end
end

-- The co-op controller owns movement and blade attacks. Exposing targets to
-- the native black-piece controller would allow a capture onto an occupied
-- square even when the co-op click handler rejects that landing square.
local function coop_knight_no_native_targets() end

lang["piece_"..coop_knight_typ] = "Black Knight"
lang["short_piece_"..coop_knight_typ] = "2P Knight"

add(PIECES, {
    type = coop_knight_typ,
    name = "coop_knight",
    is_coop_p2 = true,
    hp = 1,
    tempo = 1,                     -- 每回合可手动操作一次
    danger = 0,
    give_soul = false,
    nocarry = 1,
    team = 0,
    -- Match the native tutorial's second black piece: it is an NPC ally,
    -- while the real Black King remains the only hero for distance tracing.
    npc = 1,
    hdy = 0,

    -- Manual Knight actions are handled by the co-op mode controller.
    behavior = {},
    custom_range = coop_knight_no_native_targets,
    custom_atk = coop_knight_no_native_targets,


    custom_dr = function(e, x, y, angle)
        -- dr_skin has already applied the native black-side palette and air mask.
        spritesheet("gfx")
        spr(433, x, y)
        -- Eye only: palette index 3 is also used by the body, so do not remap it.
        pset(x+8, y+5, 5)
    end,


    boost = {}, cards = {}, status = {}, items = {}, wand = {},
    -- No soul override: 0 is truthy in Lua and dr_piece renders type 0 (Pawn).
    angle = 0, an = 0, weapon = nil, chamber = nil, ammo = nil,
    soul_slot = 0,
    custom_move_dr = function() end,
    custom_debris = function() end,
})

local native_knight
for _, piece in ipairs(PIECES) do
    if piece.type == 1 then native_knight = piece break end
end

local warrant_jumps = {{1,2}, {2,1}, {2,-1}, {1,-2},
    {-1,-2}, {-2,-1}, {-2,1}, {-1,2}}
local function warrant_attack_range(piece, max_range, flying, add_sq)
    if not piece or not piece.sq or type(add_sq) ~= "function" then return end
    local x, y = piece.sq.px, piece.sq.py
    for _, offset in ipairs(warrant_jumps) do
        local square = gsq(x + offset[1], y + offset[2])
        if square then add_sq(square) end
    end
    for dy = -1, 1 do
        for dx = -1, 1 do
            if dx ~= 0 or dy ~= 0 then
                local square = gsq(x + dx, y + dy)
                if square then add_sq(square) end
            end
        end
    end
end

-- Keep the native Knight movement, while giving the Warrant Knight its own
-- type, health and panel text. gfx sprite 433 is the original white Knight.
add(PIECES, {
    type = warrant_knight_typ,
    name = "warrant_knight",
    hp = 4,
    tempo = native_knight and native_knight.tempo or 3,
    behavior = native_knight and native_knight.behavior or {},
    danger = native_knight and native_knight.danger or 3,
    seek = native_knight and native_knight.seek or "kdist",
    hdy = native_knight and native_knight.hdy or 1,
    nocarry = native_knight and native_knight.nocarry or 1,
    -- The native soul code keys off the piece type. Co-op awards a Knight
    -- soul on this custom piece's death instead of creating a new soul type.
    give_soul = false,
    custom_atk = warrant_attack_range,
    custom_dr = function(piece, x, y)
        if mode and mode.coop_draw_janissary and mode.coop_draw_janissary(piece,x,y) then return end
        spritesheet("gfx")
        sprgrid(16, 16)
        spr(433, x, y)
    end,
    custom_move_dr = function(x, y)
        if mode and mode.coop_draw_janissary_move and mode.coop_draw_janissary_move(x,y) then return end
        spritesheet("gfx")
        sprgrid(16, 16)
        spr(433, x, y)
    end,
})



-- Reinforcement hidden boss: native big/boss flags own occupancy and death.
local marshal_type=warrant_knight_typ+1
lang["piece_"..marshal_type]=current_lang=="simplified_chinese" and "悬赏元帅" or "champion"
lang["short_piece_"..marshal_type]=lang["piece_"..marshal_type]
add(PIECES,{
    type=marshal_type,name="bounty_marshal",hp=36,tempo=1,boss=1,big=true,
    danger=16,seek="wdist",hdy=-16,nocarry=1,unlift=1,give_soul=false,
    -- Movement is native; ranged execution is owned by the alt_move callback.
    behavior={{id="line",0,3,1,move=1}},
    custom_dr=function(e,x,y)
        if mode and mode.coop_draw_marshal_art and mode.coop_draw_marshal_art(e,x,y) then return end
        if e.coop_custom_marshal_art then
            spritesheet("coop_bounty_marshal")
            sspr(0,0,32,48,x,y-16)
            spritesheet("gfx")
        else
            spritesheet("gfx")
            -- Placeholder: native white rook with a broad-barrel firearm.
            sspr(48,432,16,16,x,y,32,32)
            rectfill(x+14,y+10,x+34,y+14,1)
            rectfill(x+17,y+10,x+33,y+11,3)
            rectfill(x+14,y+13,x+18,y+19,1)
            pset(x+32,y+10,5)
        end
    end,
})

-- Player-controlled rival: no native automatic attack behavior; alt_move owns it.
local rebel_type=marshal_type+1
lang["piece_"..rebel_type]=current_lang=="simplified_chinese" and "反叛骑士" or "Rebel Knight"
lang["short_piece_"..rebel_type]=lang["piece_"..rebel_type]
add(PIECES,{
 type=rebel_type,name="rebel_knight",hp=40,tempo=1,boss=1,big=true,
 danger=16,seek="wdist",hdy=-16,nocarry=1,unlift=1,give_soul=false,behavior={},
 custom_dr=function(e,x,y)
  if mode and mode.coop_draw_cavalier_art and mode.coop_draw_cavalier_art(e,x,y) then return end
  spritesheet("gfx")
  pal_rst()
  if mode and mode.coop_duel_draw_charge then mode.coop_duel_draw_charge(e,x,y,true) end
  pal(4,1);pal(3,2)
  sspr(16,432,16,16,x,y,32,32)
  pal_rst();rectfill(x+16,y+10,x+17,y+11,5)
  if mode and mode.coop_duel_draw_charge then mode.coop_duel_draw_charge(e,x,y,false) end
 end,
})
