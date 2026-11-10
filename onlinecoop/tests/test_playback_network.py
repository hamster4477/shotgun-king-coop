"""Deterministic real-codec playback under TCP jitter; optional old-file comparison.

Run with PYTHONPATH pointing at an installed lupa, optionally --baseline old.lua.
These are simulated packet/render schedules, not a two-PC performance benchmark.
"""
from pathlib import Path
import argparse
import json
from lupa.luajit21 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


def runtime(playback):
    lua = LuaRuntime()
    lua.execute('''
sub=string.sub;match=string.match;flr=math.floor;min=math.min;max=math.max
add=table.insert;tostr=tostring;now=0;logs={};acks={};scenes={};ack_ok=true
function time() return now end
function _log(s) add(logs,s) end
function onlinecoop_net_numbers(s,count,limit)
 local a={};for v in s:gmatch("[^,]+") do
  if not v:match("^%d+$") or tonumber(v)>limit then return end
  add(a,tonumber(v))
 end
 if #a==count then return a end
end
onlinecoop_lan={send=function(k,s) if not ack_ok then return false end;add(acks,s);return true end}
function onlinecoop_events_clear(n) n.seen_units={} end
function onlinecoop_scenes_receive(p) add(scenes,p) end
function onlinecoop_receive_cg(p) add(scenes,p) end
mode={net={role="client",snapshot={floor=1,board=1,units={{1}}}}}
''')
    lua.execute((ROOT / 'net_board_frame.lua').read_text(encoding='utf-8'))
    lua.execute('''
decode=onlinecoop_decode_board_pixels;decodes=0
function onlinecoop_decode_board_pixels(s,keep)
 if keep then decodes=decodes+1 end
 return decode(s,keep)
end
function cache_count(c)
 local count=0;for _,f in ipairs(c.frames) do if f.runs then count=count+1 end end
 return count
end
''')
    lua.execute(playback)
    return lua


def clip(lua, serial, delay, *, story=False, render_stall=False, ack_retry=False,
         count=75, capped=False, fps=30, dense=False):
    g = lua.globals()
    start = float(g.now) + .1
    g.now = start
    floor = 2 if serial > 1 else 1
    assert g.onlinecoop_playback_receive(f'T2,{serial},{floor}')
    c = g.mode.net.clip_client
    seed = c.buffer_ms or 300
    events = []
    last_arrival = 0
    for i in range(count):
        ms = int(i * 1000 / fps)
        last_arrival = max(last_arrival, ms / 1000 + delay(ms / 1000))
        # Valid native codec frames with distinct palette values.
        data = (f'800{i % 6}' * 161)
        if dense:
            data = f'020{i % 6}' * (64 * 161)
        if story and i >= 12:
            data = '000000400040' + f'400{i % 6}' * 64
        parts = (len(data) + 11999) // 12000
        for part in range(parts):
            events.append((last_arrival, f'F2,{serial},{i+1},{floor},{i+1},{ms},{part+1},{parts}:'
                           + data[part*12000:(part+1)*12000]))
    duration = int(count * 1000 / fps) + 120
    ended = max(last_arrival, duration / 1000 + delay(duration / 1000))
    # A late ending tests the unknown final-frame duration and story barrier.
    if story:
        ended += .6
    events.append((ended, f'J2,{serial},{count},{duration},{int(capped)}'))
    assert g.onlinecoop_playback_defer('C1,1,1,1:choice')
    assert g.onlinecoop_playback_defer('G3,1,2,0')
    scenes_before, acks_before = len(g.scenes), len(g.acks)
    index = 0
    shown = []
    cached_shown = 0
    max_cache = 0
    first_show = None
    final_show = None
    blocked_ack = False
    final_due = None
    for tick in range(2400):
        t = tick / 60
        g.now = start + t
        while index < len(events) and events[index][0] <= t + 1e-8:
            assert g.onlinecoop_playback_receive(events[index][1]), events[index][1][:80]
            index += 1
        if render_stall and .9 <= t < 1.2:
            continue
        prev = int(c.index or 0)
        next_frame = c.frames[prev + 1]
        cached = next_frame is not None and next_frame.runs is not None
        before_decode = int(g.decodes)
        if ack_retry and prev == count and c.complete and not blocked_ack:
            g.ack_ok = False
            blocked_ack = True
        else:
            g.ack_ok = True
        g.onlinecoop_playback_client_tick()
        assert g.decodes - before_decode <= 1, 'unbounded decode burst'
        max_cache = max(max_cache, g.cache_count(c))
        assert max_cache <= 3, 'decoded full clip instead of bounded lookahead'
        played = int(c.index or 0)
        assert played - prev in (0, 1), 'skipped visible frames in one tick'
        if played > prev:
            assert g.mode.net.board_native.turn == played
            assert g.mode.net.board_native.runs[1][4] == (played - 1) % 6
            if story and played > 12:
                assert c.complete, 'story started before complete prebuffer'
            shown.append(played)
            cached_shown += int(cached)
            first_show = t if first_show is None else first_show
            if played == count:
                final_show = t
                final_due = float(c.due)
        if g.mode.net.clip_client is None:
            assert index == len(events)
            assert len(g.acks) == acks_before + 1
            assert g.acks[len(g.acks)] == f'U2,{serial}'
            assert len(g.scenes) == scenes_before + 2
            assert final_due is None or g.now + 1e-8 >= final_due
            break
        assert len(g.scenes) == scenes_before, 'choice/ending released early'
        assert len(g.acks) == acks_before
    else:
        raise AssertionError('playback did not unlock')
    assert shown == list(range(1, count + 1)), 'missing/replayed frames'
    if ack_retry:
        assert blocked_ack
    return dict(seed_ms=round(seed), rebuffer=int(c.underruns or 0),
                cached_frames=cached_shown, frames=count, max_cache=max_cache,
                first_s=round(first_show or 0, 3), unlocked_s=round(t, 3))


def suite(source):
    lua = runtime(source)
    # TCP preserves FIFO: a short outage stalls a burst, then catches up.
    jitter = lambda t: .1 + (max(0, 1.5-t) if .8 <= t < 1.5 else 0)
    results = {'jitter_first': clip(lua, 1, jitter),
               'jitter_next_floor': clip(lua, 2, jitter)}
    remembered = float(lua.globals().mode.net.clip_buffer_ms or 300)
    results['short'] = clip(lua, 3, lambda t: .1, count=2)
    assert float(lua.globals().mode.net.clip_buffer_ms or 300) == remembered
    for serial in range(4, 8):
        results[f'recovery_{serial}'] = clip(lua, serial, lambda t: .1)
    if remembered > 300:
        assert 300 <= float(lua.globals().mode.net.clip_buffer_ms) < remembered
    for name, delay, options in [
        ('smooth', lambda t: .1, {}),
        ('slow_link', lambda t: .1+t*.8, {}),
        ('outage', lambda t: .1+max(0, 2.4-t) if t >= .6 else .1, {}),
        ('render_stall', lambda t: .1, {'render_stall': True}),
        ('story', jitter, {'story': True, 'ack_retry': True}),
        ('capped', lambda t: .1, {'capped': True}),
        ('dense_60fps', lambda t: .1, {'fps': 60, 'count': 120, 'dense': True}),
        ('long_boss', lambda t: .1, {'count': 900}),
        ('empty', lambda t: .1, {'count': 0, 'ack_retry': True}),
    ]:
        results[name] = clip(runtime(source), 1, delay, **options)
    return results


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--baseline', type=Path)
    args = parser.parse_args()
    current = suite((ROOT/'net_playback.lua').read_text(encoding='utf-8'))
    assert current['jitter_next_floor']['rebuffer'] == 0
    assert current['smooth']['cached_frames'] >= current['smooth']['frames'] - 1
    result = {'current': current}
    if args.baseline:
        old = suite(args.baseline.read_text(encoding='utf-8'))
        assert current['jitter_next_floor']['rebuffer'] < old['jitter_next_floor']['rebuffer']
        assert current['smooth']['unlocked_s'] <= old['smooth']['unlocked_s'] + .017
        result['baseline'] = old
    print(json.dumps(result, indent=2))
    print('PASS: frame order, complete stories, bounded predecode, tail/ACK gating, jitter recovery')
