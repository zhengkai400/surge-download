"""Loopback, authenticated aria2-compatible facade: HTTP=aria2, BT=libtorrent.
No cloud cache, no arbitrary tracker injection. Atomic registry and resume files.
"""
import argparse,base64,hashlib,hmac,http.server,json,os,pathlib,re,secrets,signal,socket,subprocess,threading,time,urllib.request,urllib.parse
import libtorrent as lt
from linkswift import LinkSwiftReceiver
from video import VideoManager, worker
import sys
if __name__ == "__main__" and len(sys.argv)==3 and sys.argv[1]=="--video-worker":
    worker(sys.argv[2]);sys.exit(0)

def atomic(path,data):
    path=pathlib.Path(path);tmp=path.with_suffix(path.suffix+'.tmp')
    with open(tmp,'wb') as f:os.chmod(tmp,0o600);f.write(data);f.flush();os.fsync(f.fileno())
    os.replace(tmp,path)

def limit(value):
    v=str(value).upper();mult=1
    if v[-1:] in ('K','M','G'):mult=1024**('KMG'.index(v[-1])+1);v=v[:-1]
    return int(v)*mult

def system_socks():
    override=os.environ.get('SURGE_BT_PROXY')
    if override=='direct':return None
    if override:
        u=urllib.parse.urlsplit(override)
        if u.scheme!='socks5' or not u.hostname or not u.port:raise ValueError('Invalid SURGE_BT_PROXY')
        return u.hostname,u.port
    out=subprocess.check_output(['/usr/sbin/scutil','--proxy'],text=True,timeout=3)
    d=dict(re.findall(r'^\s*(\w+)\s*:\s*(.*?)\s*$',out,re.M))
    if d.get('SOCKSEnable')=='1':return d.get('SOCKSProxy','127.0.0.1'),int(d.get('SOCKSPort','1080'))
    return None

class Bridge:
    def __init__(self,config,aria):
        self.config=config;self.c=dict(l.split('=',1) for l in config.read_text().splitlines() if '=' in l and not l.startswith('#'))
        self.root=config.parent;self.store=self.root/'bt-tasks.json';self.lock=threading.RLock();self.tasks={};self.handles={};self.lookup={};self.peers={};self.last_query={};self.errors={};self.stopping=False
        self.proxy=system_socks();self.upload=limit(self.c.get('max-overall-upload-limit','1M'))
        settings={'peer_fingerprint':'-SG0200-'+secrets.token_hex(6),'listen_interfaces':'0.0.0.0:0','ignore_limits_on_local_network':False,'enable_upnp':False,'enable_natpmp':False,'enable_lsd':False,'download_rate_limit':limit(self.c.get('max-overall-download-limit','0')),'upload_rate_limit':self.upload,'alert_mask':int(lt.alert.category_t.all_categories),'dht_bootstrap_nodes':'dht.libtorrent.org:25401,router.bittorrent.com:6881,dht.transmissionbt.com:6881,router.bt.ouinet.work:6881'}
        if os.environ.get('SURGE_BT_TEST_NO_DHT')=='1':settings.update(enable_dht=False,ssrf_mitigation=False,listen_interfaces='127.0.0.1:0',enable_outgoing_utp=False,enable_incoming_utp=False)
        discovery_settings=dict(settings)
        if self.proxy:settings.update(proxy_type=2,proxy_hostname=self.proxy[0],proxy_port=self.proxy[1],proxy_peer_connections=True,proxy_tracker_connections=True,enable_dht=False,enable_incoming_tcp=False,enable_incoming_utp=False)
        self.session=lt.session(settings);self.discovery=lt.session(discovery_settings) if self.proxy else None
        if self.store.exists():
            saved=json.loads(self.store.read_text())
            if saved.get('version')!=1:raise ValueError('Unsupported BT registry version')
            self.tasks=saved['tasks']
            for gid,t in self.tasks.items():
                if not t.get('complete'):
                    t['paused']=True
                    try:self.attach(gid,restore=True)
                    except Exception as e:self.errors[gid]=str(e)
        self.migrate()
        self.persist()
        with socket.socket() as s:s.bind(('127.0.0.1',0));self.aria_port=s.getsockname()[1]
        # Child uses a distinct private port. Aria input now contains HTTP tasks only.
        self.proc=subprocess.Popen([aria,f'--conf-path={config}',f'--rpc-listen-port={self.aria_port}','--enable-dht=false','--enable-dht6=false',f'--stop-with-process={os.getpid()}'],stdout=subprocess.DEVNULL,stderr=None)
        for _ in range(70):
            try:self.forward('getVersion',[]);break
            except Exception:
                if self.proc.poll() is not None:raise RuntimeError('aria2 failed to start')
                time.sleep(.1)
        else:raise RuntimeError('aria2 startup timed out')
        self.linkswift=LinkSwiftReceiver(self,atomic)
        self.video=VideoManager(self.root,atomic)
        self.thread=threading.Thread(target=self.pump,daemon=True);self.thread.start()

    def persist(self):atomic(self.store,json.dumps({'version':1,'tasks':self.tasks},ensure_ascii=False).encode())
    def resume_path(self,gid):return self.root/('bt-'+gid+'.resume')
    def params(self,t):
        if t['kind']=='magnet':return lt.parse_magnet_uri(t['source'])
        p=lt.add_torrent_params();p.ti=lt.torrent_info(lt.bdecode(base64.b64decode(t['source'])));return p
    def attach(self,gid,restore=False):
        t=self.tasks[gid];p=self.params(t)
        if restore and self.resume_path(gid).exists():
            try:p=lt.read_resume_data(self.resume_path(gid).read_bytes())
            except Exception:pass  # Recheck the actual files using the original source.
        p.save_path=t['dir'];p.flags &= ~lt.torrent_flags.auto_managed
        p.flags |= lt.torrent_flags.paused
        h=self.session.add_torrent(p);self.handles[gid]=h
        key=str(h.info_hashes().v1);self.lookup[key]=gid;self.peers[gid]=set();self.last_query[gid]=0
        if not t['paused']:h.resume()
        return h
    def add(self,kind,source,options,gid=None,migrating=False):
        t={'kind':kind,'source':source,'dir':os.path.abspath(os.path.expanduser(options.get('dir',self.c.get('dir',str(pathlib.Path.home()/'Downloads'))))),'paused':options.get('pause','false')=='true','complete':False}
        p=self.params(t);hashes=p.ti.info_hashes() if p.ti else p.info_hashes
        if not hashes.has_v1():raise ValueError('此版本支持 BT v1 / 混合种子')
        key=str(hashes.v1)
        for old,task in self.tasks.items():
            if task.get('hash')==key:return old
        t['hash']=key
        # New tasks get a dedicated location when a known torrent file collides.
        # Magnet names become known later; reserving a per-infohash folder avoids overwrites.
        if not migrating:
            t['dir']=str(pathlib.Path(t['dir'])/('BT-'+key[:12]))
        pathlib.Path(t['dir']).mkdir(parents=True,exist_ok=True)
        gid=gid or 'bt'+secrets.token_hex(7);self.tasks[gid]=t
        try:self.attach(gid);self.persist()
        except Exception:self.tasks.pop(gid,None);raise
        return gid
    def migrate(self):
        path=pathlib.Path(self.c['input-file'])
        if not path.exists():return
        raw=path.read_text();blocks=[]
        for line in raw.splitlines():
            if line and not line[0].isspace() and not line.startswith('#'):blocks.append([line])
            elif blocks:blocks[-1].append(line)
        kept=[];changed=False
        for block in blocks:
            src=block[0];opts=dict(x.strip().split('=',1) for x in block[1:] if '=' in x)
            kind=None;value=src
            if src.startswith('magnet:'):kind='magnet'
            elif pathlib.Path(src).is_file() and src.lower().endswith('.torrent'):
                kind='torrent';value=base64.b64encode(pathlib.Path(src).read_bytes()).decode()
            if kind:
                # Preserve aria gid for history and pause every imported task.
                self.add(kind,value,{**opts,'pause':'true'},gid=opts.get('gid'),migrating=True);changed=True
            else:kept.extend(block)
        if changed:
            backup=path.with_name(path.name+'.pre-libtorrent.bak')
            if not backup.exists():atomic(backup,raw.encode())
            self.persist();atomic(path,('\n'.join(kept)+'\n' if kept else '').encode())
    def drain(self):
        for a in self.session.pop_alerts():
            name=type(a).__name__
            if os.environ.get('SURGE_BT_TEST_NO_DHT')=='1' and name in ('peer_error_alert','peer_disconnected_alert','peer_blocked_alert','tracker_reply_alert'):print(a.message(),flush=True)
            h=getattr(a,'handle',None)
            gid=next((g for g,x in self.handles.items() if h is not None and x==h),None)
            if not gid:continue
            if name=='save_resume_data_alert':atomic(self.resume_path(gid),bytes(lt.write_resume_data_buf(a.params)))
            elif name=='torrent_finished_alert':
                t=self.tasks[gid];t['complete']=True;t['paused']=True
                self.handles[gid].pause();self.handles[gid].save_resume_data(lt.save_resume_flags_t.save_info_dict | lt.save_resume_flags_t.flush_disk_cache);t['snapshot']=self.status(gid);self.persist()
            elif name in ('torrent_error_alert','file_error_alert'):
                self.errors[gid]=a.message();self.tasks[gid]['paused']=True;self.handles[gid].pause();self.persist()
            elif name=='tracker_error_alert':print('BT tracker error:',gid,a.error.message(),flush=True)
            elif name=='metadata_received_alert':self.handles[gid].save_resume_data(lt.save_resume_flags_t.save_info_dict | lt.save_resume_flags_t.flush_disk_cache)
        if self.discovery:
            for a in self.discovery.pop_alerts():
                if type(a).__name__!='dht_get_peers_reply_alert':continue
                gid=self.lookup.get(str(a.info_hash))
                if not gid or gid not in self.handles or self.tasks[gid]['paused'] or self.tasks[gid]['complete']:continue
                h=self.handles[gid]
                if h.status().has_metadata and h.torrent_file().priv():continue
                for peer in a.peers():
                    if len(self.peers[gid])>=2000:break
                    if peer not in self.peers[gid]:
                        self.peers[gid].add(peer);h.connect_peer(peer)
    def pump(self):
        last_save=time.monotonic()
        while not self.stopping:
            try:
                with self.lock:
                    self.drain();now=time.monotonic()
                    for gid,h in self.handles.items():
                        t=self.tasks[gid]
                        if t['paused'] or t['complete']:continue
                        s=h.status()
                        if self.discovery and now-self.last_query[gid]>30 and not (s.has_metadata and h.torrent_file().priv()):
                            self.discovery.dht_get_peers(h.info_hashes().v1);self.last_query[gid]=now
                    if now-last_save>10:
                        for gid,h in self.handles.items():
                            if not self.tasks[gid]['complete']:h.save_resume_data(lt.save_resume_flags_t.save_info_dict | lt.save_resume_flags_t.flush_disk_cache)
                        self.persist();last_save=now
            except Exception as e:print('BT maintenance:',type(e).__name__,str(e),flush=True)
            time.sleep(.2)
    def status(self,gid):
        t=self.tasks[gid]
        if gid not in self.handles:
            if t.get('snapshot'):return {**t['snapshot'],'status':'complete' if t['complete'] else 'paused','downloadSpeed':'0','uploadSpeed':'0','connections':'0','numSeeders':'0'}
            return {'gid':gid,'status':'error','infoHash':t['hash'],'dir':t['dir'],'errorMessage':self.errors.get(gid,'恢复失败')}
        h=self.handles[gid];s=h.status();ti=h.torrent_file() if s.has_metadata else None
        files=[]
        if ti:
            fs=ti.files();progress=h.file_progress()
            for i in range(fs.num_files()):files.append({'index':str(i+1),'path':str(pathlib.Path(t['dir'])/fs.file_path(i)),'length':str(fs.file_size(i)),'completedLength':str(progress[i]),'uris':[]})
        verified=sum(ti.piece_size(i) for i,have in enumerate(h.status(lt.status_flags_t.query_pieces).pieces) if have) if ti else 0
        state='complete' if t['complete'] else 'error' if gid in self.errors else 'paused' if t['paused'] else 'active'
        return {'gid':gid,'status':state,'infoHash':t['hash'],'bittorrent':{'info':{'name':s.name or ''}},'dir':t['dir'],'files':files,'totalLength':str(s.total_wanted),'completedLength':str(s.total_wanted_done),'verifiedLength':str(verified),'downloadSpeed':str(s.download_payload_rate if state=='active' else 0),'uploadSpeed':str(s.upload_payload_rate if state=='active' else 0),'connections':str(s.num_peers if state=='active' else 0),'numSeeders':str(s.num_seeds if state=='active' else 0),'errorMessage':self.errors.get(gid,''),'dhtCandidates':str(len(self.peers.get(gid,set()))),'metadata':s.has_metadata}
    def save(self):
        for h in self.handles.values():h.save_resume_data(lt.save_resume_flags_t.save_info_dict | lt.save_resume_flags_t.flush_disk_cache)
        self.persist()
    def forward(self,method,params):
        data=json.dumps({'jsonrpc':'2.0','id':'internal','method':'aria2.'+method,'params':['token:'+self.c['rpc-secret']]+params}).encode()
        opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open(urllib.request.Request(f'http://127.0.0.1:{self.aria_port}/jsonrpc',data=data),timeout=4) as r:reply=json.load(r)
        if 'error' in reply:raise ValueError(reply['error']['message'])
        return reply['result']
    def call(self,method,p):
        if method=='linkSwiftStatus':return self.linkswift.status()
        if method=='linkSwiftConfigure':return self.linkswift.configure(p[0] if p else {})
        if method=='addVideo':return self.video.add(p[0],p[1])
        if p and isinstance(p[0],str) and p[0] in self.video.jobs:
            gid=p[0]
            if method=='tellStatus':return self.video.status(gid)
            if method in ('pause','forcePause'):return self.video.pause(gid)
            if method=='unpause':return self.video.resume(gid)
            if method in ('remove','forceRemove','removeDownloadResult'):return self.video.remove(gid)
            raise ValueError('Unsupported video operation')
        if method in ('pauseAll','unpauseAll'):
            for gid in list(self.video.jobs):
                if method=='pauseAll':self.video.pause(gid)
                else:self.video.resume(gid)
        with self.lock:
            if method=='getVersion':return {'version':'libtorrent '+lt.__version__+' + aria2','enabledFeatures':['BitTorrent','HTTPS'],'btNetwork':('DHT 直连 · 节点 SOCKS5 '+self.proxy[0]+':'+str(self.proxy[1])) if self.proxy else 'DHT / BT 直连','dhtNodes':str((self.discovery or self.session).status().dht_nodes)}
            if method=='addUri' and p[0][0].startswith('magnet:'):return self.add('magnet',p[0][0],p[1] if len(p)>1 else {})
            if method=='addTorrent':return self.add('torrent',p[0],p[2] if len(p)>2 else {})
            if method in ('tellActive','tellWaiting','tellStopped'):
                states={'tellActive':('active',),'tellWaiting':('paused','waiting'),'tellStopped':('complete','error')}[method]
                own=[self.status(g) for g in self.tasks];own=[s for s in own if s['status'] in states]
                return self.forward(method,p)+own+[v for v in self.video.statuses() if v["status"] in states]
            if method=='getGlobalStat':
                r=self.forward(method,p);ss=[self.status(g) for g in self.tasks]+self.video.statuses()
                for k in ('downloadSpeed','uploadSpeed'):r[k]=str(int(r[k])+sum(int(s.get(k,0)) for s in ss))
                for k,states in [('numActive',('active',)),('numWaiting',('paused','waiting')),('numStopped',('complete','error'))]:r[k]=str(int(r.get(k,0))+sum(s['status'] in states for s in ss))
                return r
            if method=='saveSession':self.save();return self.forward(method,p)
            if method in ('pauseAll','unpauseAll'):
                for gid,t in self.tasks.items():
                    if not t['complete'] and gid in self.handles:
                        t['paused']=method=='pauseAll';h=self.handles[gid]
                        h.pause() if t['paused'] else h.resume()
                self.save();return self.forward(method,p)
            if method=='changeGlobalOption':
                options=p[0];settings={}
                if 'max-overall-upload-limit'in options:settings['upload_rate_limit']=limit(options['max-overall-upload-limit'])
                if 'max-overall-download-limit'in options:settings['download_rate_limit']=limit(options['max-overall-download-limit'])
                self.session.apply_settings(settings);return self.forward(method,p)
            gid=p[0] if p and isinstance(p[0],str) else None
            if gid in self.tasks:
                t=self.tasks[gid];h=self.handles.get(gid)
                if method=='tellStatus':return self.status(gid)
                if method=='getFiles':return self.status(gid).get('files',[])
                if method=='btDiagnostics':
                    st=h.status();return {'paused':bool(st.flags & lt.torrent_flags.paused),'state':str(st.state),'trackers':str(h.trackers()),'peers':len(h.get_peer_info())}
                if method in ('pause','forcePause','unpause'):
                    if t['complete']:return gid
                    if not h:raise ValueError(self.errors.get(gid,'BT 恢复失败'))
                    t['paused']=method!='unpause';h.pause() if t['paused'] else h.resume();self.last_query[gid]=0;self.save();return gid
                if method in ('remove','forceRemove','removeDownloadResult'):
                    if h:self.session.remove_torrent(h);self.handles.pop(gid,None)
                    self.tasks.pop(gid);self.lookup.pop(t['hash'],None);self.peers.pop(gid,None);self.errors.pop(gid,None);self.persist();self.resume_path(gid).unlink(missing_ok=True);return gid
                if method=='getOption':return {'dir':t['dir'],'max-download-limit':'0'}
                raise ValueError('Unsupported BT operation: '+method)
            return self.forward(method,p)
    def close(self):
        self.video.close()
        self.linkswift.close()
        self.stopping=True;self.thread.join(timeout=2)
        with self.lock:
            for h in self.handles.values():h.pause();h.save_resume_data(lt.save_resume_flags_t.save_info_dict | lt.save_resume_flags_t.flush_disk_cache)
            deadline=time.monotonic()+2
            while time.monotonic()<deadline:self.drain();time.sleep(.05)
            self.persist()
            try:self.forward('saveSession',[])
            except Exception:pass
            self.proc.terminate()
            try:self.proc.wait(5)
            except subprocess.TimeoutExpired:self.proc.kill();self.proc.wait()

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--conf-path',required=True);parser.add_argument('--aria2',required=True);args=parser.parse_args()
    os.umask(0o077);config=pathlib.Path(args.conf_path);b=Bridge(config,args.aria2)
    class Handler(http.server.BaseHTTPRequestHandler):
        def setup(self):
            super().setup();self.connection.settimeout(8)
        def log_message(self,*args):pass
        def do_POST(self):
            if self.path!='/jsonrpc':self.send_error(404);return
            if self.headers.get('Origin'):self.send_error(403);return
            req={}
            try:
                n=int(self.headers.get('Content-Length','0'))
                if n<1 or n>24*1024*1024:raise ValueError('Invalid request size')
                req=json.loads(self.rfile.read(n));p=req.get('params',[])
                if not p or not isinstance(p[0],str) or not hmac.compare_digest(p[0],'token:'+b.c['rpc-secret']):raise ValueError('Unauthorized')
                method=req.get('method','')
                if not method.startswith('aria2.'):raise ValueError('Unknown method')
                reply={'jsonrpc':'2.0','id':req.get('id'),'result':b.call(method[6:],p[1:])}
            except Exception as e:reply={'jsonrpc':'2.0','id':req.get('id'),'error':{'code':1,'message':str(e)}}
            data=json.dumps(reply).encode();self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)));self.end_headers()
            try:self.wfile.write(data)
            except BrokenPipeError:pass
    server=http.server.ThreadingHTTPServer(('127.0.0.1',int(b.c['rpc-listen-port'])),Handler);server.timeout=.5
    done=threading.Event();signal.signal(signal.SIGTERM,lambda *_:done.set());signal.signal(signal.SIGINT,lambda *_:done.set())
    parent=int(b.c.get('stop-with-process','0'))
    try:
        while not done.is_set():
            if parent:
                try:os.kill(parent,0)
                except ProcessLookupError:break
            if b.proc.poll() is not None:raise RuntimeError('HTTP engine stopped')
            server.handle_request()
    finally:server.server_close();b.close()
if __name__=='__main__':main()
