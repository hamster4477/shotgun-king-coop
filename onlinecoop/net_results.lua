-- Both peers render the same shared results screen. Only numbers are sent.
function onlinecoop_results_show(stats,won)
    local n=mode.net
    if n.role~="host" then return end
    n.results_serial=(n.results_serial or 0)+1
    local p="Z1,"..n.results_serial..","..(n.cg_serial or 0)..","..(won and 1 or 0)
    for _,player in ipairs(stats.players) do
        for _,key in ipairs({"damage","kills","souls"}) do p=p..","..flr(max(0,min(100000000,player[key] or 0))) end
    end
    p=p..","..flr(max(0,min(100000000,stats.knight_deaths or 0)))
    n.results_outbox=n.results_outbox or {};add(n.results_outbox,p)
end
function onlinecoop_results_restart()
    local n=mode.net
    if n.role=="host" and n.results_serial then
        n.results_outbox=n.results_outbox or {};add(n.results_outbox,"Z2,"..n.results_serial)
    end
end
function onlinecoop_results_receive(payload)
    local n=mode.net
    if n.role~="client" then return false end
    if sub(payload,1,3)=="Z2," then
        local a=onlinecoop_net_numbers(sub(payload,4),1,1000000)
        if not a or a[1]~=(n.results_received or 0) then return false end
        n.results_restart=a[1];return true
    end
    local a=onlinecoop_net_numbers(sub(payload,4),10,100000000)
    if not a or a[1]~=(n.results_received or 0)+1 or a[2]>1000000 or a[3]>1 then return false end
    n.results_received=a[1]
    n.results_pending={id=a[1],cg=a[2],won=a[3]==1,players={
        {damage=a[4],kills=a[5],souls=a[6]},
        {damage=a[7],kills=a[8],souls=a[9]}},knight_deaths=a[10]}
    return true
end
function onlinecoop_results_tick()
    local n=mode.net
    if n.role=="host" then
        if n.results_outbox and #n.results_outbox>0 and n.peer_ok then
            if onlinecoop_lan.send("data",n.results_outbox[1]) then deli(n.results_outbox,1) end
        end
        return
    end
    if n.cg_active or #n.cg_queue>0 or onlinecoop_playback_busy() then return end
    local r=n.results_pending
    if r and (n.cg_finished or 0)>=r.cg then
        n.results_pending=nil
        mode.coop_stats=r
        coop_show_run_stats(r.won)
    end
    if n.results_restart and not n.results_pending then
        n.results_restart=nil
        mode.coop_stats_screen=nil
        n.wait_game=nil;n.runner_best=nil;n.rhythm_best=nil
        n.board_native=nil;n.boss_visual=nil;n.soul_fx=nil
        n.card_page=0;n.soul_page=0
        n.pending=nil;n.await_revision=nil;n.last_result=nil
        remove_buts();reset();btnclr()
        onlinecoop_events_clear(n)
        n.remote_choices=nil
    end
end
