-- Native campaigns own every callback and eligibility check. Only bounded
-- button geometry and fixed labels cross the wire; the guest sends an index.
local labels_zh={"撕书","不撕书","左","上","下","右","撕毁卡牌"}
local labels_en={"Tear book","Keep book","Left","Up","Down","Right","Tear card"}
function onlinecoop_choices_begin(kind,valid)
    local n=mode.net
    n.choice_serial=(n.choice_serial or 0)+1
    n.choices={id=n.choice_serial,kind=kind,valid=valid,buttons={}}
end
function onlinecoop_choices_button(x,y,w,h,label,click)
    local c=mode.net.choices
    if not c or #c.buttons>=64 then return false end
    add(c.buttons,{x=x,y=y,w=w,h=h,label=label,click=click})
    return true
end
function onlinecoop_choices_live()
    local c=mode.net and mode.net.choices
    return c and c.valid() and c or nil
end
function onlinecoop_choices_tick()
    local n=mode.net
    if n.role~="host" or not n.peer_ok then return end
    local c=onlinecoop_choices_live()
    local body="D1,"..(n.choice_serial or 0)..",0"
    if c then
        body="D1,"..c.id..","..c.kind
        for _,b in ipairs(c.buttons) do
            body=body..":"..flr(b.x-MCW/2+512)..","..flr(b.y)..","..b.w..","..b.h..","..b.label
        end
    end
    if body~=n.last_choices and onlinecoop_lan.send("data",body) then n.last_choices=body end
end
function onlinecoop_choices_receive(payload)
    local n=mode.net
    if n.role=="host" then
        if sub(payload,1,3)~="D2," then return false end
        n.last_choices=nil
        local a=onlinecoop_net_numbers(sub(payload,4),2,1000000)
        local c=onlinecoop_choices_live()
        if not a or not c or a[1]~=c.id or a[2]<1 or a[2]>#c.buttons
            or n.cg_active or mode.coop_pause_menu_open or onlinecoop_playback_busy() then return false end
        local b=c.buttons[a[2]]
        n.choices=nil -- retire before callback; a new offer gets a new serial
        b.click()
        return true
    end
    if sub(payload,1,3)~="D1," or #payload>4096 then return false end
    local parts={};local first=1
    for i=1,#payload do if sub(payload,i,i)==":" then add(parts,sub(payload,first,i-1));first=i+1 end end
    add(parts,sub(payload,first))
    local a=onlinecoop_net_numbers(sub(parts[1],4),2,1000000)
    if not a or a[2]>2 or a[1]<(n.choice_received or 0) or #parts>65 then return false end
    if a[2]==0 and #parts~=1 then return false end
    local c={id=a[1],kind=a[2],buttons={}}
    for i=2,#parts do
        local b=onlinecoop_net_numbers(parts[i],5,1024)
        if not b or b[1]>1024 or b[2]>240 or b[3]<1 or b[3]>240 or b[4]<1 or b[4]>80 or b[5]>7 then return false end
        add(c.buttons,{x=b[1]-512+MCW/2,y=b[2],w=b[3],h=b[4],label=b[5]})
    end
    n.choice_received=a[1];n.remote_choices=a[2]>0 and c or nil
    return true
end
function onlinecoop_choices_input()
    local n=mode.net
    if n.role=="host" then
        if onlinecoop_choices_live() then btnclr();return true end
        return false
    end
    local c=n.remote_choices
    if not c or n.cg_active or onlinecoop_playback_busy() then return false end
    if not c.sent and btnp("online_lclick",0) then
        local x,y=btnv("online_mx",0),btnv("online_my",0)
        for i,b in ipairs(c.buttons) do
            if x>=b.x and x<b.x+b.w and y>=b.y and y<b.y+b.h then
                if onlinecoop_lan.send("data","D2,"..c.id..","..i) then c.sent=true end
                break
            end
        end
    end
    btnclr();return true
end
function onlinecoop_choices_draw()
    local n=mode.net
    if n.role~="client" or n.cg_active or onlinecoop_playback_busy() then return end
    local c=n.remote_choices
    if not c then return end
    local zh=current_lang=="simplified_chinese"
    if c.kind==1 then
        local x,y=(MCW-240)/2,(MCH-68)/2
        rectfill(x,y,x+239,y+67,1);rect(x,y,x+239,y+67,3)
        lprint(zh and "黑骑士拾起了红色圣书" or "The Knight takes the Red Book",MCW/2,y+9,4,1)
    end
    for _,b in ipairs(c.buttons) do
        if b.label>0 then
            if b.label~=7 then rectfill(b.x,b.y,b.x+b.w-1,b.y+b.h-1,2) end
            rect(b.x,b.y,b.x+b.w-1,b.y+b.h-1,c.sent and 3 or 5)
            if b.label~=7 then lprint((zh and labels_zh or labels_en)[b.label],b.x+b.w/2,b.y+3,4,1) end
        end
    end
end
