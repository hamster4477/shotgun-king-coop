-- Append-only indices: native saved brands occupy zero-based indices 0..11.
add(AUGMENTS,{price=3,n=2}) -- 12: blade, resets with the raid campaign
add(AUGMENTS,{price=4,n=1}) -- 13: Knight Spirit, campaign scoped
add(AUGMENTS,{price=4,n=1}) -- 14: In-Law, campaign scoped
add(AUGMENTS,{price=3,n=1}) -- 15: Timar Cavalry Pact, campaign scoped

local skill_cards = {
    [13]="Co-op Knight Spirit", [14]="Co-op In-Law", [15]="Co-op Timar Cavalry Pact"
}
local names = {
    [12]={"骑士磨刃", "Knight Blade"},
    [13]={"骑士精神", "chivalry"},
    [14]={"裂颅", "shotgun wedding"},
    [15]={"帝玛尔骑兵协议", "Akinji System"}
}

function coop_raid_owned_brands()
    return clone(SAVE.coop_charnier.augments or {})
end

function coop_raid_buy_brand(index)
    local ag=AUGMENTS[index+1]
    local ch=SAVE.coop_charnier
    if not ag or not ch or ch.cinders<ag.price then return false end
    local count=0
    for _,owned in ipairs(coop_raid_owned_brands()) do
        if owned==index then count=count+1 end
    end
    if count >= (ag.n or 1) then return false end
    local owned=clone(ch.augments)
    add(owned,index)
    ch.augments=owned
    ch.cinders=ch.cinders-ag.price
    return true
end

function coop_raid_apply_brands()
    mode.coop_raid_blade_bonus=0
    mode.coop_raid_skills={}
    mode.ban={}
    for _,index in ipairs(SAVE.coop_charnier.augments or {}) do
        if index==12 then
            mode.coop_raid_blade_bonus=min(2,mode.coop_raid_blade_bonus+1)
        elseif skill_cards[index] then
            local card=skill_cards[index]
            mode.coop_raid_skills[card]=true
            -- init_game uses mode.ban when building the native draw pool.
            add(mode.ban,card)
        elseif index>=0 and index<12 then
            add(mode.upgrades,AUGMENTS[index+1])
        end
    end
end

function coop_raid_brand_desc(index)
    if index<12 then return get_desc(AUGMENTS[index+1]) end
    local chinese=current_lang=="simplified_chinese"
    local description
    if index==12 then
        description=chinese and "黑骑士刀锋+1"
            or "Black Knight blade +1. Buy twice at most; resets with the raid campaign."
    elseif index==13 then
        description=chinese and "消耗骑士灵魂，左键选择横竖方向，回合结束时冲锋。不再抽到骑士精神卡。"
            or "For this raid campaign: spend a knight soul to charge at turn end. Removes chivalry from this campaign's card pool."
    elseif index==14 then
        description=chinese and "消耗主教或城堡灵魂，按对应走法移动黑骑士。不再抽到裂颅卡。"
            or "For this raid campaign: spend bishop or rook souls to move the Knight. Removes shotgun wedding from this campaign's card pool."
    else
        description=chinese and "黑骑士可用长矛攻击两格外的白棋，造成2点伤害。不再抽到帝玛尔骑兵协议卡。"
            or "For this raid campaign: spear enemies two squares away for 2 damage. Removes Akinji System from this campaign's card pool."
    end
    return names[index][chinese and 1 or 2].."|"..description
end

function coop_raid_load_brand_icons()
    mode.coop_raid_brand_icons=false
    if isfile("assets/gfx/knight_brands.png") then
        newsrf("coop_knight_brands","assets/gfx/knight_brands.png")
        mode.coop_raid_brand_icons=true
    end
end

function coop_raid_draw_brand(index,x,y)
    if index>=12 and mode.coop_raid_brand_icons then
        spritesheet("coop_knight_brands")
        sspr((index-12)*12,0,12,12,x,y)
        spritesheet("charnier")
        return
    end
    -- Temporary native icons until the artist supplies the four-icon strip.
    local fallback={[12]=3,[13]=4,[14]=6,[15]=7}
    local tile=fallback[index] or index
    if tile>8 then tile=tile+9 end
    spritesheet("charnier")
    sspr(tile*12,20,12,12,x,y)
end
