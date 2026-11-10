"""Published captions and branch order, using the actual Lua story module."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parents[1] / 'diagnostics/python_libs'))
from lupa.luajit21 import LuaRuntime

lua = LuaRuntime()
lua.execute('lang={vig_6="native ending"};mode={};function isfile() return true end')
lua.execute((ROOT / 'campaigns/story.lua').read_text(encoding='utf-8-sig'))
for language in ('simplified_chinese', 'english'):
    lua.globals().current_lang = language
    caption = lua.globals().coop_story_caption
    for scene in range(17, 37):
        text = caption(scene)
        assert len(text) > 40, scene
        assert 'placeholder' not in text.lower() and '待补充' not in text, scene
    assert caption(6) == 'native ending'
    if language == 'english':
        assert 'Rebel Knight' in caption(32) and 'Revolutionary Knight' not in caption(32)
        assert 'With their help' in caption(33) and 'Revolutionary Knight' in caption(33)
        assert 'Black Knight' in caption(27) and 'wanted poster' in caption(27)
        assert 'abandoned by all' not in caption(3) and 'follower' not in caption(3)
    else:
        assert '反叛骑士' in caption(32) and '革命骑士' not in caption(32)
        assert '在他们的帮助下' in caption(33) and '革命骑士' in caption(33)
        assert '印着黑骑士模样' in caption(27)
        assert '被所有人抛弃' not in caption(3) and '追随者' not in caption(3)
lua.execute('''
function sequence(expected,ending,native)
 local actual=coop_story_sequence(ending,native)
 assert(#actual==#expected)
 for i,v in ipairs(expected) do assert(actual[i]==v) end
end
sequence({1,2,17,3},false,false)
sequence({1,2,3},false,true)
mode={coop_ending_kind="duel_knight",coop_ending_sequence={33,34,35},coop_ending_knight_alive=true,coop_stats={knight_deaths=0}}
sequence({33,34,35},true,false)
mode.coop_ending_kind="duel_king";mode.coop_ending_sequence={32,6,7}
sequence({32,6,7},true,false)
mode={coop_ending_sequence={8,9,10,6,12},coop_ending_knight_alive=false}
sequence({8,26,9,10,6,24,12},true,false)
mode={coop_ending_sequence={27,6,7},coop_ending_knight_alive=false}
sequence({27,28,6,24,7},true,false)
''')
print('PASS: bilingual captions, perspective names, collective victory, bounty target, minimal intro and ending sequences')
