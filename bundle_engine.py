#!/usr/bin/env python3
"""Bundle Homebrew aria2 and its non-system dylibs without retaining brew paths."""
import pathlib, subprocess, shutil, sys, json, os
app = pathlib.Path(sys.argv[1]); out = app / 'Contents/Resources/engine'
source = pathlib.Path('/opt/homebrew/bin/aria2c').resolve()
if not source.exists(): raise SystemExit('Install aria2 from Homebrew first: brew install aria2')
out.mkdir(parents=True, exist_ok=True)
node = pathlib.Path(os.environ.get("NODE_BINARY") or shutil.which("node") or "/usr/local/bin/node").resolve()
if not node.is_file(): raise SystemExit("Node.js is required: set NODE_BINARY to its executable path")
seen = {}; pending = [source, pathlib.Path("/opt/homebrew/bin/ffmpeg").resolve(), pathlib.Path("/opt/homebrew/bin/ffprobe").resolve(), node]
while pending:
    src = pending.pop().resolve()
    if str(src) in seen: continue
    dest = out / src.name
    shutil.copy2(src, dest); dest.chmod(0o755); seen[str(src)] = dest
    # Remove the old signature before rewriting load commands.
    # install_name_tool invalidates the original signature; re-sign after relocation.
    lines = subprocess.check_output(['otool', '-L', str(src)], text=True).splitlines()[1:]
    for line in lines:
        dependency = line.strip().split(' (')[0]
        if dependency.startswith(('/opt/homebrew/', '/usr/local/')):
            dep = pathlib.Path(dependency).resolve()
            if dep == src:
                subprocess.run(['install_name_tool','-id','@loader_path/'+src.name,str(dest)],check=True)
            else:
                subprocess.run(['install_name_tool','-change',dependency,'@loader_path/'+dep.name,str(dest)],check=True)
                pending.append(dep)
for dest in seen.values(): subprocess.run(['codesign','--force','--sign','-',str(dest)],check=True,capture_output=True)
licenses = app / 'Contents/Resources/licenses'; licenses.mkdir(exist_ok=True)
for src in seen:
    p = pathlib.Path(src)
    # Homebrew package root: /opt/homebrew/Cellar/<formula>/<version>
    if 'Cellar' in p.parts:
        index = p.parts.index('Cellar'); root = pathlib.Path(*p.parts[:index+3]); package = p.parts[index+1]
        d = licenses/package; d.mkdir(exist_ok=True)
        for f in root.glob('*'):
            if f.is_file() and any(w in f.name.upper() for w in ['COPYING','LICENSE','AUTHORS','NOTICE']): shutil.copy2(f,d/f.name)
        receipt=root/'INSTALL_RECEIPT.json'
        if receipt.exists(): shutil.copy2(receipt,d/'INSTALL_RECEIPT.json')
(licenses/'README.txt').write_text('aria2 is GPL-2.0-or-later. This local demo bundles an unmodified aria2 executable with relocated dynamic-library paths. Official corresponding source: https://github.com/aria2/aria2/releases/tag/release-1.37.0 . Dependency package versions and build receipts are included. Before redistribution, satisfy all bundled licenses and GPL corresponding-source obligations.\n')
print(subprocess.check_output([str(out/'aria2c'),'--version'],text=True).splitlines()[0])
