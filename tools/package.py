from pathlib import Path
import sys
from zipfile import ZipFile,ZIP_DEFLATED
from check_release import release_files
root=Path(__file__).resolve().parent.parent
output=Path(sys.argv[1]) if len(sys.argv)>1 else root/'dist/coop-unified-r72c-lan-only.zip'
output.parent.mkdir(parents=True,exist_ok=True)
files=release_files(root)  # Fail before creating a partial ZIP if any input is missing.
with ZipFile(output,'x',ZIP_DEFLATED) as z:
 for name,p in files:
  z.write(p,'onlinecoop/'+name)
with ZipFile(output) as z: assert z.testzip() is None
print(output)
