#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
APP="$PWD/build/疾风下载.app"
.venv/bin/python -m PyInstaller --noconfirm --clean --onedir --name surge-bt --distpath .build/bt-dist --workpath .build/bt-work --specpath .build --hidden-import libtorrent --collect-all yt_dlp --collect-all yt_dlp_ejs backend/btbridge.py > .build/bt-bundle.log 2>&1
mkdir -p "$APP/Contents/Resources/bt"
rsync -a --delete .build/bt-dist/surge-bt/ "$APP/Contents/Resources/bt/"
mkdir -p "$APP/Contents/Resources/licenses/bt"
cp backend/licenses/*.txt "$APP/Contents/Resources/licenses/bt/"
.venv/bin/python - <<'PY'
import importlib.metadata as m,pathlib,shutil,sysconfig
out=pathlib.Path('build/疾风下载.app/Contents/Resources/licenses/bt')
for name in ['libtorrent','pyinstaller','yt-dlp','yt-dlp-ejs']:
 d=m.distribution(name)
 for f in d.files or []:
  if any(x in str(f).lower() for x in ['license','copying']):
   src=pathlib.Path(d.locate_file(f))
   if src.is_file():shutil.copy2(src,out/(name+'-'+src.name))
p=pathlib.Path(sysconfig.get_path('stdlib'))/'LICENSE.txt'
if p.exists():shutil.copy2(p,out/'Python-LICENSE.txt')
(out/'NOTICE.txt').write_text('libtorrent 2.1.1 (BSD-3-Clause), Python 3.13 (PSF), PyInstaller bootloader (GPL with bundling exception).\nSources: https://github.com/arvidn/libtorrent https://github.com/python/cpython https://github.com/pyinstaller/pyinstaller\n')
PY
