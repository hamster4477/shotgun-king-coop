-- Full-phantom branch only. Native bishop/queen priority remains unchanged.
function coop_ending_phantoms()
    local result,seen={},{}
    for _,entry in ipairs(mode.coop_phantoms or {}) do
        local p=entry.piece
        if p and p.coop_phantom and not seen[p] and coop_phantom_is_live(p) then
            seen[p]=true
            result[#result+1]=p
        end
    end
    return result
end

function coop_story_ascend(piece,nxt)
    -- fx_ascend removes the entity but does not clear its board occupancy.
    leave_sq(piece)
    fx_ascend(piece,nxt)
end

function coop_flash_mechanism_card(nxt)
    local ca=get_slot_card("Co-op Mechanism Order")
    if not ca then nxt();return end
    -- Same card-entity lifetime/blink mechanism as spawn_dark_bishop.
    sfx("show_book")
    ca.life=120
    ca.blink=120
    if ca.sl and ca.sl.ca==ca then ca.sl.ca=nil end
    build_stack()
    wait(120,function()
        kl(ca)
        nxt()
    end)
end

-- Let the native storm perform the actual black-to-white replacement at
-- the lightning strike. Keep the old piece's palette until that instant.
function coop_phantom_lightning(phantoms,white_knights,nxt)
    local selected={list=1}
    local squares={}
    for _,p in ipairs(phantoms) do
        squares[#squares+1]=p.sq
        p.wsq=p.sq
        p.stormed=nil
        local present=false
        for _,b in ipairs(bads) do if b==p then present=true end end
        if not present then add(bads,p) end
        selected[#selected+1]=p
    end
    for _,p in ipairs(white_knights) do selected[#selected+1]=p end
    storm_all_but(selected,function()
        local ghosts={}
        for _,sq in ipairs(squares) do
            local e=sq.p
            if e and e.type==11 then
                -- Native type 11 starts with the ordinary white Knight skin.
                -- give_role(), called only after mounting, switches to dr_apo.
                e.coop_phantom=true
                e.give_soul=false
                ghosts[#ghosts+1]=e
            end
        end
        nxt(ghosts)
    end)
end

function coop_begin_phantom_ending(phantoms)
    local disguised=hero.disguised==0
    mode.coop_ending_kind=disguised and "phantom_king" or "phantom"
    -- Detach the timer registry before staging; the cinematic owns these pieces.
    mode.coop_phantoms={}
    mode.coop_phantom_pending=nil
    for i=5,#phantoms do coop_story_ascend(phantoms[i]) end
    local four={phantoms[1],phantoms[2],phantoms[3],phantoms[4]}
    coop_flash_mechanism_card(function()
        coop_phantom_lightning(four,{},function(riders)
            coop_mount_phantom_horsemen(riders,disguised)
        end)
    end)
end

function coop_mount_phantom_horsemen(phantoms,disguised)
    fast_tracker(false)
    local riders={}
    local names={lang.apo_name_0,lang.apo_name_1,lang.apo_name_2,lang.apo_name_3}
    inter.role=nil
    for i,p in ipairs(phantoms) do
        local sq=p.sq
        local e=p
        e.coop_phantom=true
        e.coop_story_rider=true
        e.give_soul=false
        riders[i]=e
        if i==4 and disguised then
            e.pawn=hero
        else
            local free=get_zone(sq,2,function(cell) return is_free(cell) end)
            local pawn_sq=free[1] or get_nearest_free_square(sq)
            e.pawn=new_piece(0,true,pawn_sq)
            e.pawn.c_raise=60
        end
    end
    local index=1
    local function depart()
        local remaining=#riders
        sfx("ascend")
        for _,e in ipairs(riders) do
            coop_story_ascend(e,function()
                remaining=remaining-1
                if remaining==0 then coop_finish_throne_story() end
            end)
        end
    end
    local function jump()
        if index>#riders then wait(60,depart);return end
        local e=riders[index]
        if not e.pawn.named then
            sfx("apo_talk")
            e.pawn.named=true
            e.pawn.c_detect=60
            fx_emote(e.pawn,names[index],60,jump)
            return
        end
        sfx("apo_jump")
        local sq=e.sq
        leave_sq(e)
        goto_sq(e.pawn,sq,TEMPO,function()
            sfx("apo_sit")
            e.give_role()
            kl(e.pawn)
            del(bads,e.pawn)
            goto_sq(e,sq,0)
            if e.pawn==hero then
                e.an=hero.an
                e.ta=hero.an
                hero.sq=hero.wsq
                hero.disguised=nil
                hero.apo=1
                e.black_king=1
            end
            index=index+1
            wait(30,jump)
        end)
    end
    wait(60,jump)
end
