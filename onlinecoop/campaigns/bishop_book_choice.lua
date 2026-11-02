-- Capture the native floating-book entity at dark_bishop_up's boundary.
-- Its own draw/update callbacks are replaced, not the global engine function.
function coop_book_distance(sq,anchor,big)
    local edge=big and 1 or 0
    local dx=max(max(anchor.px-sq.px,0),sq.px-anchor.px-edge)
    local dy=max(max(anchor.py-sq.py,0),sq.py-anchor.py-edge)
    return max(dx,dy)
end

function coop_book_snapshot()
    if not mode or mode.id~="coop" or mode.coop_variant
        or mode.coop_throne_finishing or mode.coop_book_scene then return end
    local b=boss
    local k=mode.coop_knight
    local sq=b and (b.sq or b.wsq)
    if not b or not b.dark or not sq or not k or k.dead or not k.sq
        or not k.hp or k.hp<=0 or not hero or not hero.sq then return end
    if coop_book_distance(k.sq,sq,b.big)>coop_book_distance(hero.sq,sq,b.big) then return end
    mode.coop_book_scene={boss=b,knight=k}
    coop_pause_for_boss_story()
    if _log then _log("[COOP BOOK] Knight reaches the book first (ties included)") end
end

function coop_book_capture_before()
    local scene=mode and mode.coop_book_scene
    if not scene or scene.boss~=boss or scene.started then return end
    scene.before={}
    for _,e in ipairs(ents) do scene.before[e]=true end
end

function coop_book_choose(tear)
    local scene=mode and mode.coop_book_scene
    if not scene or not scene.choosing or scene.chosen then return end
    scene.chosen=true;scene.choosing=false
    remove_buts()
    if scene.panel then kl(scene.panel) end
    mode.coop_ending_kind=tear and "book_torn" or "book_kept"
    -- Snapshot survival before the actor leaves the board in the cinematic.
    coop_freeze_throne_result()
    local function finish()
        if mode.coop_book_scene~=scene then return end
        if scene.book then kl(scene.book) end
        coop_finish_throne_story()
    end
    if tear then
        local x,y=scene.book.x,scene.book.y
        kl(scene.book);scene.book=nil
        sfx("tear_up")
        for side=0,1 do
            local source_x=80+side*3
            local half=mke(0,x+side*3,y)
            half.dr=function(e,px,py) sspr(source_x,56,3,8,px,py) end
            half.life=40
            mvt(half,x+(side*2-1)*14,y+18,36)
        end
        wait(48,finish)
    else
        sfx("move_piece")
        -- This is a cinematic tween, not a move_piece action or enemy turn.
        mvt(scene.knight,scene.knight.x,board_y-32,80,finish)
    end
    if _log then _log("[COOP BOOK] choice="..(tear and "tear" or "keep")) end
end

function coop_book_offer(scene)
    if mode.coop_book_scene~=scene or scene.chosen then return end
    remove_buts()
    scene.choosing=true
    local chinese=current_lang=="simplified_chinese"
    local left,top=(MCW-240)/2,(MCH-68)/2
    local panel=mke()
    scene.panel=panel
    panel.dp=DP_TOP
    panel.dr=function()
        rectfill(left,top,left+239,top+67,1)
        rect(left,top,left+239,top+67,3)
        lprint(chinese and "黑骑士拾起了红色圣书" or "The Knight takes the Red Book",MCW/2,top+9,4,1)
    end
    if coop_controller and coop_controller.begin_choices then
        coop_controller.begin_choices(1,function() return mode.coop_book_scene==scene and scene.choosing and not scene.chosen end)
    end
    local function choice(x,label,tear)
        if coop_controller and coop_controller.choice_button then
            coop_controller.choice_button(x,top+33,104,24,tear and 1 or 2,function() coop_book_choose(tear) end)
            return
        end
        local button=mk_but(x,top+33,104,24,function() coop_book_choose(tear) end)
        button.dp=DP_TOP+1
        button.dr=function(e,px,py)
            rectfill(px,py,px+103,py+23,e.ov and 3 or 2)
            lprint(label,px+52,py+7,e.ov and 1 or 4,1)
        end
    end
    choice(left+10,chinese and "撕书" or "Tear the book",true)
    choice(left+126,chinese and "不撕书" or "Keep the book",false)
    mouse("show",true)
    if _log then _log("[COOP BOOK] choice panel ready") end
end

function coop_book_capture_after()
    local scene=mode and mode.coop_book_scene
    if not scene or not scene.before or scene.started then return end
    local found,count=nil,0
    for _,e in ipairs(ents) do
        if not scene.before[e] and e.x==scene.boss.x+16 and e.y==scene.boss.y+32
            and type(e.upd)=="function" and type(e.dr)=="function" then
            found=e;count=count+1
        end
    end
    scene.before=nil
    if count~=1 then
        -- Unknown native version: leave its book and completion callback intact.
        mode.coop_book_scene=nil
        if _log then _log("[COOP BOOK] native book not uniquely found; original ending retained") end
        return
    end
    scene.started=true;scene.book=found
    found.upd=nil
    found.x=scene.boss.x+16;found.y=scene.boss.y-16
    found.dp=DP_FX
    found.dr=function(e,x,y) sspr(80,56,6,8,x,y) end
    remove_buts()
    local function current() return mode.coop_book_scene==scene and not scene.chosen end
    mvt(found,scene.boss.x+13,scene.boss.y+20,36,function()
        if not current() then return end
        sfx("land")
        mvt(scene.knight,found.x-10,found.y-3,40,function()
            if not current() then return end
            sfx("grab_done")
            found.upd=function(e) e.x=scene.knight.x+11;e.y=scene.knight.y+3 end
            wait(16,function() if current() then coop_book_offer(scene) end end)
        end)
    end)
end
