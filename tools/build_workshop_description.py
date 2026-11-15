"""Build the Workshop description text from the recorded canonical page text.

The page text is authoritative in WORKSHOP_PAGE_TEXT.md; this joins its two
language blocks into the single description Steam stores, so a restore never has
to be retyped.
"""
import io
import pathlib
import re

REPO = pathlib.Path(__file__).resolve().parent.parent
SOURCE = REPO / 'WORKSHOP_PAGE_TEXT.md'


def build(source=SOURCE):
    text = source.read_text(encoding='utf-8')
    blocks = {}
    for part in re.split(r'^## ', text, flags=re.M)[1:]:
        name, _, body = part.partition('\n')
        blocks[name.strip()] = body.strip('\n').strip()
    english = blocks.get('English', '')
    chinese = blocks.get('简体中文', '')
    if not english or not chinese:
        raise SystemExit('WORKSHOP_PAGE_TEXT.md is missing a language block')
    return english + '\n\n' + chinese + '\n'


def main():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=pathlib.Path,
                        help='Where to write the description (UTF-8, no BOM)')
    args = parser.parse_args()
    description = build()
    if len(description) > 8000:
        raise SystemExit(f'Description is {len(description)} chars; Steam allows 8000.')
    args.output.write_text(description, encoding='utf-8', newline='')
    print(f'{len(description)} chars -> {args.output}')


if __name__ == '__main__':
    main()
