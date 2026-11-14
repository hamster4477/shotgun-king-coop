"""A full mailbox sequence must disconnect explicitly, not strand clip ACKs."""
from pathlib import Path
import sys
from lupa.luajit21 import LuaRuntime

root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]
lua = LuaRuntime()
lua.execute(r'''
files={}; writes={}; now=1; hooks={}; logs={}
match=string.match; find=string.find; sub=string.sub; tonum=tonumber
function time() return now end
function _log(text) logs[#logs+1]=text end
function append(name,f,id) hooks[id]=f end
function isfile(path) return files[path]~=nil end
function file(path,value)
 if value then files[path]=value; writes[#writes+1]=path end
 return files[path]
end
function session(id)
 files['lan/config.txt']='OC3|'..id..'|host|END'
 files['lan/'..id..'/status.txt']='OC1|'..id..'|connected|END'
end
session('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
-- Seed the real sender's counter at its boundary without replacing source.
function seed_sequence(n)
 for i=1,40 do
  local name=debug.getupvalue(onlinecoop_lan.send,i)
  if name=='tx' then debug.setupvalue(onlinecoop_lan.send,i,n);return end
 end
 error('sender counter not found')
end
string=nil; math=nil
''')
lua.execute((root / 'transport.lua').read_text(encoding='utf-8-sig'))
lua.execute(r'''
local tick=hooks.onlinecoop_lan_transport
tick()
assert(onlinecoop_lan.status=='connected')
seed_sequence(299999)
assert(onlinecoop_lan.send('data','U2,1'))
local base='lan/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/'
assert(files[base..'out/300000.msg'])
assert(not onlinecoop_lan.send('data','U2,2'))
assert(onlinecoop_lan.status=='error')
assert(files[base..'stop.txt']=='stop')
assert(match(files[base..'error.txt'],'message limit'))
assert(not files[base..'out/300001.msg'])
local before=#writes
assert(not onlinecoop_lan.send('data','U2,2'))
assert(#writes==before) -- one error/stop request, no per-frame writes
now=2; tick() -- stale connected helper status cannot re-enable transmission
assert(onlinecoop_lan.status=='error')
assert(not onlinecoop_lan.can_send_visual())
session('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb')
now=3; tick()
assert(onlinecoop_lan.status=='connected')
assert(onlinecoop_lan.send('data','U2,1'))
assert(files['lan/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/out/1.msg'])
''')
print('PASS: final valid sequence, explicit limit disconnect, stale-status latch, new session reset; no string/math globals')
