"""Isolated packaged receiver test; all cookies/tokens below are synthetic."""
import hashlib,http.server,json,os,pathlib,subprocess,tempfile,threading,time,urllib.request,urllib.error
from bridge_integration import Client,ROOT
DATA=b'LinkSwift header-preservation fixture\n'*30000
UA='Surge-LinkSwift-fixture/1.0';COOKIE='fixture_session=not-a-real-cookie';REF='https://pan.quark.cn/'
seen=[]
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*a):pass
 def do_GET(self):
  headers=[self.headers.get('User-Agent'),self.headers.get('Cookie'),self.headers.get('Referer')]
  if headers!=[UA,COOKIE,REF]:self.send_error(403);return
  seen.append(True);self.send_response(200);self.send_header('Content-Length',str(len(DATA)));self.end_headers()
  try:self.wfile.write(DATA)
  except BrokenPipeError:pass
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);threading.Thread(target=server.serve_forever,daemon=True).start()
results=[]
os.environ['SURGE_LINKSWIFT_TEST_LOOPBACK']='1'
with tempfile.TemporaryDirectory(prefix='surge-linkswift-test-') as tmp:
 home=pathlib.Path(tmp);c=Client(home)
 def external(method='aria2.getVersion',params=[],token=None,origin='https://pan.quark.cn'):
  req=urllib.request.Request(f'http://127.0.0.1:{info["port"]}/jsonrpc',data=json.dumps({'jsonrpc':'2.0','id':1,'method':method,'params':['token:'+(info['token'] if token is None else token)]+params}).encode(),headers={'Origin':origin,'Content-Type':'application/json'})
  with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(req,timeout=8) as r:return json.load(r)
 try:
  assert not c.call('linkSwiftStatus')['enabled'];results.append('off by default')
  info=c.call('linkSwiftConfigure',[{'enabled':True,'directory':str(home/'downloads')}]);assert info['enabled'];assert info['token']!=c.secret
  assert 'result'in external();assert 'error'in external(token='wrong');assert 'error'in external(token=c.secret);results.append('separate token + connection test')
  try:external(origin='https://evil.example');raise AssertionError('origin accepted')
  except urllib.error.HTTPError as e:assert e.code==403
  assert 'error'in external('aria2.shutdown');assert 'error'in external('aria2.tellActive');results.append('untrusted origin and privileged operations rejected')
  url=f'http://127.0.0.1:{server.server_port}/file'
  bad=[{'out':'../escape'},{'dir':'/tmp/escape'},{'on-download-complete':'touch /tmp/evil'},{'header':['Cookie:test\r\nX-Evil:1']},{'header':['Host:evil.example']}]
  for opts in bad:assert 'error'in external('aria2.addUri',[[url],opts])
  assert 'error'in external('aria2.addUri',[['file:///etc/passwd'],{}]);results.append('path traversal, arbitrary options and header injection rejected')
  opts={'out':'LinkSwift-test.bin','header':['User-Agent:'+UA,'Referer:'+REF,'Cookie:'+COOKIE]}
  reply=external('aria2.addUri',[[url],opts]);assert 'result'in reply,reply
  gid=reply['result'];s=c.until(gid,lambda x:x['status']=='complete');output=pathlib.Path(s['files'][0]['path']);assert hashlib.sha256(output.read_bytes()).digest()==hashlib.sha256(DATA).digest();assert seen;results.append('actual download requires and receives UA + Referer + synthetic Cookie; SHA256 matched')
  for relative in ['剧集/第一季/01.bin','剧集/第二季/01.bin']:
   nested={**opts,'out':relative}
   reply=external('aria2.addUri',[[url],nested]);assert 'result' in reply,reply
   status=c.until(reply['result'],lambda x:x['status']=='complete')
   output=pathlib.Path(status['files'][0]['path'])
   assert output.resolve()==(home/'downloads'/relative).resolve()
   assert hashlib.sha256(output.read_bytes()).digest()==hashlib.sha256(DATA).digest()
  results.append('nested Unicode directories and same basename in different folders: actual download SHA256 matched')
  old=info['token'];info=c.call('linkSwiftConfigure',[{'rotate':True}]);assert 'error'in external(token=old);assert 'result'in external();results.append('token rotation invalidates old token')
  port=info['port'];token=info['token'];c.close();c=Client(home);info=c.call('linkSwiftStatus');assert info['enabled'] and info['port']==port and info['token']==token;results.append('opt-in, port and token survive restart')
  c.call('linkSwiftConfigure',[{'enabled':False}]);assert not c.call('linkSwiftStatus')['enabled'];results.append('disable closes receiver')
  assert (home/'linkswift.json').stat().st_mode&0o777==0o600;assert COOKIE not in (home/'bridge.log').read_text();results.append('0600 config and no cookie in log')
 finally:c.close();server.shutdown()
(ROOT/'tests/linkswift-results.json').write_text(json.dumps(results,indent=2));print('\n'.join('PASS '+x for x in results))
