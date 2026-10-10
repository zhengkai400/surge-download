"""Full packaged dual-engine regression; isolated files and loopback peers."""
import base64,hashlib,http.server,json,os,pathlib,socket,struct,subprocess,tempfile,threading,time,urllib.request
import libtorrent as lt
ROOT=pathlib.Path(__file__).resolve().parents[1];APP=ROOT/'build/疾风下载.app/Contents/Resources'

def freeport():
 with socket.socket() as s:s.bind(('127.0.0.1',0));return s.getsockname()[1]

class Client:
 def __init__(self,root,proxy='direct',migration=''):
  self.root=root;root.mkdir(exist_ok=True);self.port=freeport();self.secret=os.urandom(24).hex()
  session=root/'session'
  if not session.exists():session.write_text(migration)
  c={'enable-rpc':'true','rpc-listen-all':'false','rpc-listen-port':str(self.port),'rpc-secret':self.secret,'input-file':str(session),'save-session':str(session),'pause':'true','dir':str(root/'downloads'),'enable-dht':'false','enable-dht6':'false','bt-enable-lpd':'false','seed-time':'0','continue':'true','force-save':'false','file-allocation':'none','max-overall-download-limit':'0','max-overall-upload-limit':'1M','stop-with-process':str(os.getpid())}
  conf=root/'engine.conf';conf.write_text('\n'.join(f'{k}={v}' for k,v in c.items()));conf.chmod(0o600)
  self.log=open(root/'bridge.log','ab');env=dict(os.environ,SURGE_BT_PROXY=proxy,SURGE_BT_TEST_NO_DHT='1') if proxy=='direct' else dict(os.environ,SURGE_BT_PROXY=proxy)
  self.p=subprocess.Popen([str(APP/'bt/surge-bt'),f'--conf-path={conf}',f'--aria2={APP}/engine/aria2c'],stdout=self.log,stderr=self.log,env=env)
  for _ in range(150):
   try:self.call('getVersion');break
   except Exception:
    if self.p.poll() is not None:raise RuntimeError((root/'bridge.log').read_text())
    time.sleep(.1)
  else:raise TimeoutError('startup')
 def call(self,m,p=[],token=None):
  raw=json.dumps({'id':1,'jsonrpc':'2.0','method':'aria2.'+m,'params':['token:'+(self.secret if token is None else token)]+p}).encode()
  op=urllib.request.build_opener(urllib.request.ProxyHandler({}))
  with op.open(urllib.request.Request(f'http://127.0.0.1:{self.port}/jsonrpc',data=raw),timeout=8) as r:j=json.load(r)
  if 'error'in j:raise RuntimeError(j['error'])
  return j['result']
 def until(self,g,predicate,timeout=60):
  end=time.monotonic()+timeout
  while time.monotonic()<end:
   s=self.call('tellStatus',[g])
   if predicate(s):return s
   if s['status']=='error':raise RuntimeError(s)
   time.sleep(.2)
  raise TimeoutError(s)
 def close(self):
  if self.p.poll() is None:
   self.p.terminate()
   try:self.p.wait(10)
   except subprocess.TimeoutExpired:self.p.kill();self.p.wait();raise
  self.log.close()

if __name__=='__main__':
 class Results(list):
  def append(self,value):super().append(value);print('PASS '+value,flush=True)
 results=Results();client=None
 with tempfile.TemporaryDirectory(prefix='surge-bridge-regression-') as tmp:
  root=pathlib.Path(tmp);data=os.urandom(3*1024*1024);seed=root/'seed';seed.mkdir();(seed/'fixture.bin').write_bytes(data);sp=freeport()
  class Handler(http.server.BaseHTTPRequestHandler):
   def log_message(self,*a):pass
   def do_GET(self):
    body=lt.bencode({b'interval':2,b'peers':socket.inet_aton('127.0.0.1')+struct.pack('!H',sp)}) if self.path.startswith('/announce') else data
    self.send_response(200);self.send_header('Content-Length',str(len(body)));self.end_headers()
    try:self.wfile.write(body)
    except (BrokenPipeError,ConnectionResetError):pass
  server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);threading.Thread(target=server.serve_forever,daemon=True).start();url=f'http://127.0.0.1:{server.server_port}'
  info={b'name':b'fixture.bin',b'length':len(data),b'piece length':262144,b'pieces':b''.join(hashlib.sha1(data[i:i+262144]).digest() for i in range(0,len(data),262144))}
  torrent=lt.bencode({b'announce':(url+'/announce').encode(),b'info':info});ih=hashlib.sha1(lt.bencode(info)).hexdigest();magnet=f'magnet:?xt=urn:btih:{ih}&tr={url}/announce'
  se=lt.session({'peer_fingerprint':'-TEST01-'+os.urandom(6).hex(),'listen_interfaces':f'127.0.0.1:{sp}','enable_dht':False,'enable_lsd':False,'enable_upnp':False,'enable_natpmp':False,'ignore_limits_on_local_network':False,'upload_rate_limit':524288,'enable_outgoing_utp':False,'enable_incoming_utp':False,'alert_mask':int(lt.alert.category_t.all_categories)});p=lt.add_torrent_params();p.ti=lt.torrent_info({b'info':info});p.save_path=str(seed);p.flags &= ~lt.torrent_flags.auto_managed;p.flags &= ~lt.torrent_flags.paused;h=se.add_torrent(p)
  for _ in range(100):
   if h.status().is_seeding:break
   time.sleep(.1)
  assert h.status().is_seeding
  def seedlogs():
   while True:
    for a in se.pop_alerts():
     if type(a).__name__ in ('peer_error_alert','peer_disconnected_alert'):print('SEED',a.message(),flush=True)
    time.sleep(.2)
  threading.Thread(target=seedlogs,daemon=True).start()
  try:
   home=root/'home';gid='0123456789abcdef';migration=f'{magnet}\n gid={gid}\n dir={root}/migrated\n'
   client=Client(home,migration=migration)
   try:client.call('getVersion',token='bad');raise AssertionError('auth bypass')
   except RuntimeError:results.append('auth enforced')
   assert client.call('tellStatus',[gid])['status']=='paused';assert (home/'session.pre-libtorrent.bak').exists();assert 'magnet:' not in (home/'session').read_text();results.append('legacy magnet migrated, gid kept, paused, original backup')
   http=client.call('addUri',[[url+'/fixture.bin'],{'pause':'false','dir':str(root/'http')}]);st=client.until(http,lambda x:x['status']=='complete');assert pathlib.Path(st['files'][0]['path']).read_bytes()==data;results.append('HTTP unchanged, full SHA256 '+hashlib.sha256(data).hexdigest())
   client.call('changeGlobalOption',[{'max-overall-download-limit':'256K'}]);client.call('unpause',[gid]);client.until(gid,lambda x:int(x.get('verifiedLength',0))>=262144)
   client.call('pause',[gid]);assert client.call('tellStatus',[gid])['status']=='paused';client.close();client=Client(home)
   assert client.call('tellStatus',[gid])['status']=='paused';results.append('BT pause and restart restore paused')
   client.call('unpause',[gid]);st=client.until(gid,lambda x:x['status']=='complete');assert pathlib.Path(st['files'][0]['path']).read_bytes()==data;results.append('BT magnet metadata, resume, full payload SHA256 matched')
   time.sleep(1);assert client.call('tellStatus',[gid])['uploadSpeed']=='0';client.close();client=Client(home);assert client.call('tellStatus',[gid])['status']=='complete';results.append('complete stays complete; no resumed seeding')
   client.call('removeDownloadResult',[gid]);assert pathlib.Path(st['files'][0]['path']).exists();results.append('remove keeps file')
   new=client.call('addTorrent',[base64.b64encode(torrent).decode(),[],{'dir':str(root/'torrent'),'pause':'false'}]);st=client.until(new,lambda x:x['status']=='complete');assert pathlib.Path(st['files'][0]['path']).read_bytes()==data;results.append('torrent import complete, data matched')
   client.close();client=None
  except Exception:
   print((home/'bridge.log').read_text()[-8000:]);raise
  finally:
   if client:client.close()
   se.remove_torrent(h);server.shutdown()
 (ROOT/'tests/bridge-results.json').write_text(json.dumps(results,indent=2));print('\n'.join('PASS '+r for r in results))
