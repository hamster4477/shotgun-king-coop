"""Build the Workshop description text from the recorded canonical page text.

The page text is authoritative in docs/WORKSHOP_PAGE_TEXT.md. The published description
is English only: the Chinese block in that file is a reference translation and is
never uploaded, so a restore cannot fall back to mixing the two languages.
"""
import io
import pathlib
import re

REPO = pathlib.Path(__file__).resolve().parent.parent
SOURCE = REPO / 'docs' / 'WORKSHOP_PAGE_TEXT.md'


def build(source=SOURCE, with_chinese=False):
    text = source.read_text(encoding='utf-8')
    blocks = {}
    for part in re.split(r'^## ', text, flags=re.M)[1:]:
        name, _, body = part.partition('\n')
        blocks[name.strip()] = body.strip('\n').strip()
    english = blocks.get('English', '')
    if not english:
        raise SystemExit('WORKSHOP_PAGE_TEXT.md is missing the English block')
    if not with_chinese:
        return english + '\n'
    chinese = blocks.get('简体中文', '')
    if not chinese:
        raise SystemExit('WORKSHOP_PAGE_TEXT.md is missing the Chinese block')
    return english + '\n\n' + chinese + '\n'


def main():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=pathlib.Path,
                        help='Where to write the description (UTF-8, no BOM)')
    parser.add_argument('--with-chinese', action='store_true',
                        help='Append the Chinese reference block (not for the live page)')
    args = parser.parse_args()
    description = build(with_chinese=args.with_chinese)
    if len(description) > 8000:
        raise SystemExit(f'Description is {len(description)} chars; Steam allows 8000.')
    args.output.write_text(description, encoding='utf-8', newline='')
    print(f'{len(description)} chars -> {args.output}')


if __name__ == '__main__':
    main()
