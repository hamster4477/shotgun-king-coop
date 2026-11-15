"""The choice watchdog must free a clip that a native choice stranded, and must
never cut a boss cinematic short."""
import io
import pathlib

import lupa

ROOT = pathlib.Path(__file__).resolve().parent.parent
source = (ROOT / 'net_playback.lua').read_text(encoding='utf-8')
start = source.index('function onlinecoop_playback_waiting_choice()')
end = source.index('local function animation_state()')
block = source[start:end]

HARNESS = r'''
local clock = 0
local sent = {}
local mode = { net = {} }
local function time() return clock end
local function sub(s, i, j) return string.sub(s, i, j) end
local function _log() end
local function send(s) sent[#sent+1] = s; return true end
local function onlinecoop_events_clear() end
local function onlinecoop_net_numbers() return nil end
local function onlinecoop_choices_live() return nil end
disrupt_menu = nil
''' + block + r'''
function run_case(steps)
    clock = 0; sent = {}
    mode = { net = {} }
    local n = mode.net
    n.peer_ok = true
    for _, st in ipairs(steps) do
        clock = clock + (st.dt or 0)
        disrupt_menu = st.choice and true or nil
        n.clip_host = st.host and { id = st.host } or nil
        n.clip_client = st.client and { id = st.client } or nil
        if st.recv then n.clip_received = st.recv end
        choice_clip_watchdog()
    end
    return (n.clip_host and "host" or "-") .. "," ..
           (n.clip_client and "client" or "-") .. "," ..
           tostring(n.clip_received or 0) .. "," ..
           table.concat(sent, "|")
end
'''

lua = lupa.LuaRuntime()
lua.execute(HARNESS)

CASES = [
    ('idle', '{ {dt=0} }', '-,-,0,'),
    ('clip without a choice is kept', '{ {dt=0,host=5}, {dt=100,host=5} }', 'host,-,0,'),
    ('choice under the limit is kept',
     '{ {dt=0,host=5,choice=true}, {dt=7,host=5,choice=true} }', 'host,-,0,'),
    ('host gives up after eight seconds',
     '{ {dt=0,host=5,choice=true}, {dt=8.1,host=5,choice=true} }', '-,-,0,X2,5'),
    ('closing the choice resets the clock',
     '{ {dt=0,host=5,choice=true}, {dt=7,host=5,choice=true}, {dt=1,host=5},'
     ' {dt=7,host=5,choice=true}, {dt=1,host=5,choice=true} }', 'host,-,0,'),
    ('client keeps the clip serial in step',
     '{ {dt=0,client=9,recv=9,choice=true}, {dt=8.1,client=9,recv=9,choice=true} }', '-,-,9,'),
    ('a boss cinematic is never cut',
     '{ {dt=0,host=3,client=3}, {dt=30,host=3,client=3}, {dt=60,host=3,client=3} }',
     'host,client,0,'),
]

for name, steps, expected in CASES:
    lua.execute('result = run_case(' + steps + ')')
    got = str(lua.globals().result)
    if got != expected:
        raise SystemExit(f'{name}: got {got!r}, expected {expected!r}')
    print(f'ok  {name:36} -> {got}')
print('PASS: choice clip watchdog')
