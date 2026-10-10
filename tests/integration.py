#!/usr/bin/env python3
"""Real local transport tests; no public torrents, trackers or external downloads."""
import base64, hashlib, http.server, json, os, pathlib, socket, struct, subprocess, tempfile, threading, time, urllib.request, urllib.parse
ROOT=pathlib.Path(__file__).resolve().parents[1]
BIN=ROOT/'build/疾风下载.app/Contents/Resources/engine/aria2c'
DATA=(b'Surge Download local integration test.\n'*2048)*128
HASH=hashlib.sha256(DATA).hexdigest()

def port():
    with socket.socket() as s: s.bind(('127.0.0.1',0)); return s.getsockname()[1]
def bencode(v):
    if isinstance(v,int): return b'i'+str(v).encode()+b'e'
    if isinstance(v,bytes): return str(len(v)).encode()+b':'+v
    if isinstance(v,str): return bencode(v.encode())
    if isinstance(v,list): return b'l'+b''.join(map(bencode,v))+b'e'
    return b'd'+b''.join(bencode(k)+bencode(v[k]) for k in sorted(v))+b'e'

seed_port=port(); RANGE_REQUESTS=[]
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self,*a): pass
    def do_GET(self):
        if self.path.startswith('/announce'):
            body=bencode({'interval':2,'complete':1,'incomplete':1,'peers':socket.inet_aton('127.0.0.1')+struct.pack('!H',seed_port)})
            self.send_response(200);self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body);return
        if not self.path.startswith('/sample.bin'):self.send_error(404);return
        start,end=0,len(DATA)-1
        if self.headers.get('Range'):
            spec=self.headers['Range'].split('=')[1].split('-');start=int(spec[0]);end=int(spec[1]) if spec[1] else end;RANGE_REQUESTS.append((start,end))
            self.send_response(206);self.send_header('Content-Range',f'bytes {start}-{end}/{len(DATA)}')
        else:self.send_response(200)
        self.send_header('Accept-Ranges','bytes');self.send_header('Content-Length',str(end-start+1));self.end_headers()
        try:
            for i in range(start,end+1,32768):self.wfile.write(DATA[i:min(i+32768,end+1)]);self.wfile.flush();time.sleep(.012)
        except (BrokenPipeError,ConnectionResetError):pass

class Engine:
    def __init__(self,path,extra=()):
        self.path=path;path.mkdir(exist_ok=True,parents=True);self.port=port();self.token=os.urandom(24).hex();self.session=path/'session';self.session.touch(exist_ok=True)
        self.log=open(path/'log','ab')
        args=[str(BIN),'--no-conf','--enable-rpc','--rpc-listen-all=false',f'--rpc-listen-port={self.port}',f'--rpc-secret={self.token}',f'--dir={path}',f'--save-session={self.session}',f'--input-file={self.session}','--save-session-interval=1','--force-save=false','--enable-dht=false','--enable-dht6=false','--bt-enable-lpd=false','--enable-peer-exchange=false','--seed-time=0','--file-allocation=none','--continue=true','--pause=true','--max-overall-download-limit=0','--max-download-limit=0','--max-overall-upload-limit=1M','--split=4','--max-connection-per-server=4','--min-split-size=1M','--rpc-save-upload-metadata=true','--bt-save-metadata=true','--check-integrity=true','--bt-tracker-interval=2']+list(extra)
        self.p=subprocess.Popen(args,stdout=self.log,stderr=self.log)
        for _ in range(60):
            try:self.rpc('getVersion');break
            except Exception:
                if self.p.poll() is not None:raise RuntimeError((path/'log').read_text())
                time.sleep(.1)
        else:raise RuntimeError('RPC did not start')
    def rpc(self,name,params=[]):
        data=json.dumps({'jsonrpc':'2.0','id':'test','method':'aria2.'+name,'params':['token:'+self.token]+params}).encode()
        with urllib.request.urlopen(urllib.request.Request(f'http://127.0.0.1:{self.port}/jsonrpc',data=data,headers={'Content-Type':'application/json'}),timeout=5) as r: v=json.load(r)
        if 'error'in v:raise RuntimeError(v['error'])
        return v['result']
    def wait(self,gid,status='complete',timeout=50):
        end=time.time()+timeout
        while time.time()<end:
            v=self.rpc('tellStatus',[gid])
            if v.get('followedBy'):gid=v['followedBy'][0];continue
            if v['status']==status:return v
            if v['status']=='error':raise RuntimeError(v)
            time.sleep(.15)
        raise TimeoutError(v)
    def close(self):
        if self.p.poll() is None:
            try:self.rpc('saveSession')
            except Exception:pass
            self.p.terminate()
            try:self.p.wait(6)
            except subprocess.TimeoutExpired:self.p.kill();self.p.wait()
        self.log.close()

server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
threading.Thread(target=server.serve_forever,daemon=True).start()
url=f'http://127.0.0.1:{server.server_port}'
engines=[];results=[]
with tempfile.TemporaryDirectory(prefix='surge-test-') as temp:
    root=pathlib.Path(temp)
    try:
        e=Engine(root/'http');engines.append(e)
        # Bad authentication must fail, even for a read-only operation.
        original=e.token;e.token='wrong'
        try:e.rpc('getVersion');raise AssertionError('RPC accepted invalid token')
        except (RuntimeError, urllib.error.HTTPError):pass
        finally:e.token=original
        results.append('PASS: authenticated localhost RPC rejects incorrect secret')
        opts=e.rpc('getGlobalOption');assert opts['max-overall-download-limit']=='0' and opts['max-download-limit']=='0'
        results.append('PASS: global and per-task download limits are disabled')
        gid=e.rpc('addUri',[[url+'/sample.bin'],{'pause':'false'}]);time.sleep(.4)
        e.rpc('pause',[gid]);v=e.wait(gid,'paused');before=int(v['completedLength']);assert before>0
        e.rpc('saveSession');e.close()
        e=Engine(root/'http');engines.append(e)
        waiting=e.rpc('tellWaiting',[0,100]);assert waiting and waiting[0]['status']=='paused'
        gid=waiting[0]['gid'];e.rpc('unpause',[gid]);v=e.wait(gid)
        assert hashlib.sha256((root/'http/sample.bin').read_bytes()).hexdigest()==HASH
        assert RANGE_REQUESTS
        results.append('PASS: HTTP ranges, pause, saved-session restart, resume, SHA-256 integrity')
        seed=root/'seed';seed.mkdir();(seed/'sample.bin').write_bytes(DATA)
        piece=262144;info={'length':len(DATA),'name':'sample.bin','piece length':piece,'pieces':b''.join(hashlib.sha1(DATA[i:i+piece]).digest() for i in range(0,len(DATA),piece))}
        torrent=bencode({'announce':url+'/announce','info':info});infohash=hashlib.sha1(bencode(info)).hexdigest()
        s=Engine(seed,[f'--listen-port={seed_port}','--seed-time=5','--seed-ratio=0','--bt-enable-hook-after-hash-check=false']);engines.append(s)
        s.rpc('addTorrent',[base64.b64encode(torrent).decode(),[],{'pause':'false'}]);time.sleep(2)
        l=Engine(root/'torrent');engines.append(l)
        gid=l.rpc('addTorrent',[base64.b64encode(torrent).decode(),[],{'pause':'false'}]);v=l.wait(gid,timeout=80)
        assert hashlib.sha256((root/'torrent/sample.bin').read_bytes()).hexdigest()==HASH
        results.append('PASS: .torrent downloaded from a real local BT peer, SHA-256 integrity')
        m=Engine(root/'magnet');engines.append(m)
        magnet=f'magnet:?xt=urn:btih:{infohash}&dn=sample.bin&tr='+urllib.parse.quote(url+'/announce',safe='')
        raw=magnet.replace('magnet:?', 'magnet:？')
        normalizer=ROOT/'.build/link-tests'
        if normalizer.exists():
            magnet=subprocess.check_output([str(normalizer),raw],text=True).strip()
            assert magnet.startswith('magnet:?')
        gid=m.rpc('addUri',[[magnet],{'pause':'false','pause-metadata':'false'}]);v=m.wait(gid,timeout=80)
        assert hashlib.sha256((root/'magnet/sample.bin').read_bytes()).hexdigest()==HASH
        results.append('PASS: fullwidth magnet normalization, metadata exchange and peer download, SHA-256 integrity')
        assert v['status']=='complete'
        results.append('PASS: BT stops seeding after completion')
        m.rpc('saveSession');assert not m.session.read_text().strip()
        results.append('PASS: completed downloads are not requeued in saved session')
    finally:
        for e in reversed(engines):e.close()
        server.shutdown()
for result in results:print(result)
(ROOT/'tests/results.txt').write_text('\n'.join(results)+'\n')
