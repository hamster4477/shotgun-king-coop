-- Fixed native vignette lists only. No remote function names or callbacks.
local cg_lists={{1,2,3},{4},{6,7}}
-- Vignette 4 reads stack.theocracy to select the native Boss introduction.
-- The observer never runs build_stack(). Give only this presentation flag to
-- its vignette, and release the temporary context on completion or menu exit.
local function restore_cg_stack(n)
    if n.cg_stack then
        if stack==n.cg_stack then stack=n.cg_previous_stack end
        n.cg_stack=nil; n.cg_previous_stack=nil
    end
end
function onlinecoop_play_cg(kind,done,theocracy,sequence)
    local n=mode.net
    if not n or n.cg_active or not cg_lists[kind] then return false end
    n.cg_active=kind
    local seq={}
    for _,id in ipairs(sequence or cg_lists[kind]) do seq[#seq+1]=id end
    if n.role=="host" then
        n.cg_serial=(n.cg_serial or 0)+1
        n.cg_outbox=n.cg_outbox or {}
        local variant=kind==2 and stack and stack.theocracy and 1 or 0
        local ids=""
        for i,id in ipairs(seq) do ids=ids..(i>1 and "," or "")..id end
        add(n.cg_outbox,"G3,"..n.cg_serial..","..kind..","..variant..":"..ids)
    end
    _log("[ONLINE CG] begin role="..n.role.." kind="..kind)
    if n.role=="client" then onlinecoop_events_clear(n) end
    -- The host's Boss introduction is an overlay between floors. Native
    -- init_vig preserves bg/inter/board; next_floor reuses those entities.
    -- A full reset here deletes the HUD and shadows for the rest of the run.
    if n.role=="client" or kind~=2 then reset() end
    if n.role=="client" and kind==2 then
        n.cg_previous_stack=stack
        n.cg_stack={theocracy=theocracy==1 and 1 or nil}
        stack=n.cg_stack
    end
    local custom=false
    for _,id in ipairs(seq) do if id>=17 then custom=true end end
    if custom then coop_load_story_art() end
    local play=custom and coop_play_vig or init_vig
    play(seq,function()
        restore_cg_stack(n)
        if not mode or mode.net~=n then return end
        n.cg_active=nil
        if n.role=="client" then
            onlinecoop_events_clear(n)
            if kind~=3 and n.snapshot then onlinecoop_events_snapshot(nil,n.snapshot) end
        end
        _log("[ONLINE CG] end role="..n.role.." kind="..kind)
        btnclr()
        if done then done() end
    end)
    return true
end

function onlinecoop_receive_cg(payload)
    local n=mode.net
    if n.role~="client" then return false end
    if sub(payload,1,3)~="G3," or #payload>256 then return false end
    local head,ids=match(sub(payload,4),"^([0-9,]+):([0-9,]+)$")
    if not head or not ids then return false end
    local a=onlinecoop_net_numbers(head,3,1000000)
    if not a or a[2]<1 or a[2]>3 or a[1]~=(n.cg_received or 0)+1 then return false end
    if a[3]>1 or (a[2]~=2 and a[3]~=0) then return false end
    if #n.cg_queue>=8 then return false end
    local count=1
    for i=1,#ids do if sub(ids,i,i)=="," then count=count+1 end end
    if count>32 then return false end
    local seq=onlinecoop_net_numbers(ids,count,36)
    if not seq then return false end
    for _,id in ipairs(seq) do if id<1 or id==16 then return false end end
    n.cg_received=a[1]; add(n.cg_queue,{kind=a[2],theocracy=a[3],sequence=seq})
    return true
end

function onlinecoop_cg_initialize()
    local n=mode.net
    n.cg_queue={}; n.cg_outbox={}
    prepend("init_menu",function()
        restore_cg_stack(n)
        if mode and mode.net==n then
            n.cg_active=nil; n.cg_intro_due=nil; n.cg_queue={}; n.cg_returned=true
        end
    end,"online_cg_return_menu")
    -- Intro is selected by the host too: local campaigns may add custom CGs.
    n.cg_intro_due=nil
    append("_update",function()
        if not mode or mode.net~=n or n.cg_returned then return end
        if n.role=="host" then
            if n.peer_ok and #n.cg_outbox>0 and onlinecoop_lan.status=="connected" then
                if onlinecoop_lan.send("data",n.cg_outbox[1]) then deli(n.cg_outbox,1) end
            end
            return
        end
        if n.role~="client" or n.cg_active or onlinecoop_playback_busy() then return end
        if n.cg_intro_due and time()>=n.cg_intro_due then
            n.cg_intro_due=nil
            onlinecoop_play_cg(1)
        elseif #n.cg_queue>0 then
            local cg=deli(n.cg_queue,1)
            local kind=cg.kind
            if kind==3 then
                n.draft=nil
                onlinecoop_play_cg(kind,function() n.cg_finished=(n.cg_finished or 0)+1 end,nil,cg.sequence)
            else onlinecoop_play_cg(kind,function() n.cg_finished=(n.cg_finished or 0)+1 end,cg.theocracy,cg.sequence) end
        end
    end,"online_native_cg")
end
