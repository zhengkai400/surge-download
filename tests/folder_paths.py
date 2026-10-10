import sys,tempfile,pathlib,types
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'backend'))
from linkswift import LinkSwiftReceiver
with tempfile.TemporaryDirectory() as t:
 root=pathlib.Path(t); dest=root/'downloads';dest.mkdir()
 bridge=types.SimpleNamespace(root=root,c={'dir':str(dest)})
 r=LinkSwiftReceiver(bridge,lambda *args:None)
 opts=r.options(['https://example.com/file'],{'out':'剧集/第一季/01.mp4'})
 assert opts['dir']==str(dest.resolve()/'剧集/第一季') and opts['out']=='01.mp4'
 for bad in ['../a','/tmp/a','a//b','a/../b','a/./b','a\\b','a/','C:/x','a/\x01b']:
  try:r.options(['https://example.com/file'],{'out':bad})
  except ValueError:pass
  else:raise AssertionError(bad)
 (dest/'outside').symlink_to(root,target_is_directory=True)
 for bad in ['outside/file','outside']:
  try:r.options(['https://example.com/file'],{'out':bad})
  except ValueError:pass
  else:raise AssertionError(bad)
 print('PASS: nested paths, traversal, absolute paths, control characters, symlink rejection')
