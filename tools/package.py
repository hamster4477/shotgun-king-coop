from pathlib import Path
import json,sys
from zipfile import ZipFile,ZIP_DEFLATED
root=Path(__file__).resolve().parent.parent
output=Path(sys.argv[1]) if len(sys.argv)>1 else root/'dist/coop-unified-r72c-lan-only.zip'
output.parent.mkdir(parents=True,exist_ok=True)
names=json.loads((root/'tools/package-files.json').read_text(encoding='utf-8'))
with ZipFile(output,'x',ZIP_DEFLATED) as z:
 for name in names:
  p=root/'onlinecoop'/name
  assert p.is_file() and '..' not in Path(name).parts
  z.write(p,'onlinecoop/'+name)
with ZipFile(output) as z: assert z.testzip() is None
print(output)
