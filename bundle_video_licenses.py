from pathlib import Path
import importlib.metadata as m,shutil
out=Path('build/疾风下载.app/Contents/Resources/licenses/video');out.mkdir(parents=True,exist_ok=True)
for name in ['yt-dlp','yt-dlp-ejs','certifi','requests','urllib3','mutagen','websockets','brotli','pycryptodomex']:
 try:d=m.distribution(name)
 except m.PackageNotFoundError:continue
 for f in d.files or []:
  if any(w in str(f).lower() for w in ['license','copying','notice']):
   p=Path(d.locate_file(f))
   if p.is_file():shutil.copy2(p,out/(name+'-'+p.name))
shutil.copy2('backend/licenses/Node-v24.12.0-LICENSE.txt',out/'Node-LICENSE.txt')
(out/'NOTICE.txt').write_text('yt-dlp: https://github.com/yt-dlp/yt-dlp ; yt-dlp-ejs: https://github.com/yt-dlp/ejs ; Node.js v24.12.0: https://nodejs.org/ ; FFmpeg: https://ffmpeg.org/ . Bundled FFmpeg and its libraries use their respective licenses; Homebrew receipts and license files are in adjacent folders. Before redistribution, supply required corresponding sources and notices.\n')
