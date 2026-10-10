"""Opt-in, loopback-only LinkSwift receiver. Separate capability from app RPC.
Implements the public aria2 wire format, not the LinkSwift userscript itself.
"""
import http.server,json,secrets,hmac,pathlib,threading,urllib.parse,re,os

class LinkSwiftReceiver:
    def __init__(self,bridge,atomic):
        self.bridge=bridge;self.atomic=atomic;self.path=bridge.root/'linkswift.json';self.lock=threading.RLock();self.server=None;self.thread=None;self.error=''
        self.state={'enabled':False,'port':16801,'token':secrets.token_hex(32),'directory':bridge.c.get('dir',str(pathlib.Path.home()/'Downloads')),'received':0}
        if self.path.exists():self.state.update(json.loads(self.path.read_text()))
        if self.state['enabled']:
            try:self.start()
            except OSError:self.error='本机推送端口被占用，请关闭后重新开启。'
    def persist(self):self.atomic(self.path,json.dumps(self.state,ensure_ascii=False).encode())
    def status(self):
        return {**self.state,'enabled':self.server is not None,'host':'http://127.0.0.1','path':'/jsonrpc','error':self.error}
    def configure(self,options):
        with self.lock:
            if 'directory' in options:
                directory=options['directory']
                if not isinstance(directory,str) or not os.path.isabs(directory) or any(c in directory for c in '\r\n\x00'):raise ValueError('无效保存目录')
                self.state['directory']=directory
            if options.get('rotate'):
                self.state['token']=secrets.token_hex(32)
            if 'enabled'in options:
                if not isinstance(options['enabled'],bool):raise ValueError('无效开关')
                if options['enabled'] and self.server is None:
                    self.start();self.state['enabled']=True;self.error=''
                elif not options['enabled']:
                    self.stop();self.state['enabled']=False
            self.persist();return self.status()
    def origin_allowed(self,origin):
        return not origin or origin=='https://pan.quark.cn'
    def options(self,uris,options):
        if not isinstance(uris,list) or len(uris)!=1 or not isinstance(uris[0],str):raise ValueError('一次推送一个 HTTP/HTTPS 文件')
        url=uris[0]
        if len(url)>16384 or any(c in url for c in '\r\n\x00'):raise ValueError('无效下载地址')
        u=urllib.parse.urlsplit(url)
        if u.scheme not in ('http','https') or not u.hostname or u.username or u.password:raise ValueError('仅接收 HTTP/HTTPS 下载直链')
        if not isinstance(options,dict) or set(options)-{'dir','out','header'}:raise ValueError('推送包含不支持的下载选项')
        # An external script cannot overwrite files by selecting arbitrary directories.
        directory=options.get('dir')
        if directory and os.path.abspath(directory)!=os.path.abspath(self.state['directory']):raise ValueError('LinkSwift 存储路径请留空，在疾风内选择保存目录')
        filename=options.get('out','')
        if not isinstance(filename,str) or any(x in filename for x in ('\\','\r','\n','\x00')) or len(filename.encode())>4096:raise ValueError('无效文件路径')
        parts=filename.split('/') if filename else []
        if parts and (len(parts)>34 or any(not x or x in ('.','..') or ':' in x or any(ord(c)<32 for c in x) or len(x.encode())>240 for x in parts)):raise ValueError('无效相对路径')
        root=pathlib.Path(self.state['directory']).resolve()
        target=root.joinpath(*parts[:-1])
        cursor=root
        for segment in parts:
            cursor=cursor/segment
            if cursor.is_symlink():raise ValueError('保存路径含符号链接')
        if not target.resolve().is_relative_to(root):raise ValueError('保存路径超出下载目录')
        headers=options.get('header') or []
        if not isinstance(headers,list) or len(headers)>16:raise ValueError('无效请求头')
        clean=[];seen=set()
        for header in headers:
            if not isinstance(header,str) or len(header)>32768 or '\r'in header or '\n'in header or '\x00'in header or ':' not in header:raise ValueError('无效请求头')
            key,value=header.split(':',1);key=key.strip().lower()
            if key not in ('user-agent','referer','cookie','accept','origin') or key in seen:raise ValueError('不支持或重复的请求头')
            if key=='cookie' and value.strip():
                # Current integration is Quark-specific. Never send its session cookies
                # to arbitrary hosts supplied by another page or copied command.
                host=u.hostname.lower()
                if u.scheme!='https' or not (host=='quark.cn' or host.endswith('.quark.cn')):
                    if not (os.environ.get('SURGE_LINKSWIFT_TEST_LOOPBACK')=='1' and host=='127.0.0.1'):raise ValueError('Cookie 下载仅允许夸克 HTTPS 域名；其他 CDN 需单独验证后接入')
            clean.append(header);seen.add(key)
        result={'dir':str(target),'pause':'false','allow-overwrite':'false','auto-file-renaming':'true','continue':'false','header':clean}
        if filename:result['out']=parts[-1]
        return result
    def dispatch(self,request):
        if not isinstance(request,dict):raise ValueError('单次 JSON-RPC 对象请求')
        p=request.get('params',[])
        if not isinstance(p,list) or not p or not isinstance(p[0],str) or not hmac.compare_digest(p[0],'token:'+self.state['token']):raise ValueError('Unauthorized')
        if request.get('method')=='aria2.getVersion':return {'version':'Surge LinkSwift Receiver 0.2.2','enabledFeatures':['HTTPS']}
        if request.get('method')!='aria2.addUri':raise ValueError('此密钥仅支持连接测试和新增下载，不授予任务控制权限')
        if len(p) not in (2,3):raise ValueError('Invalid parameters')
        opts=self.options(p[1],p[2] if len(p)==3 else {})
        gid=self.bridge.forward('addUri',[p[1],opts])
        self.state['received']+=1;self.persist()
        self.bridge.forward('saveSession',[])
        return gid
    def start(self):
        owner=self
        class Handler(http.server.BaseHTTPRequestHandler):
            def setup(self):super().setup();self.connection.settimeout(8)
            def log_message(self,*a):pass  # Never log tokens, signed URLs or cookies.
            def valid(self):
                return self.path=='/jsonrpc' and self.headers.get('Host','') in (f'127.0.0.1:{owner.state["port"]}',f'localhost:{owner.state["port"]}') and owner.origin_allowed(self.headers.get('Origin'))
            def cors(self):
                if self.headers.get('Origin')=='https://pan.quark.cn':
                    self.send_header('Access-Control-Allow-Origin','https://pan.quark.cn');self.send_header('Vary','Origin');self.send_header('Access-Control-Allow-Credentials','true')
            def do_OPTIONS(self):
                if not self.valid():self.send_error(403);return
                self.send_response(204);self.cors();self.send_header('Access-Control-Allow-Methods','POST');self.send_header('Access-Control-Allow-Headers','Content-Type, Cache-Control, Pragma, Expires, DNT, Accept');self.end_headers()
            def do_POST(self):
                if not self.valid():self.send_error(403);return
                request={}
                try:
                    n=int(self.headers.get('Content-Length','0'))
                    if not 0<n<=262144:raise ValueError('Request too large')
                    request=json.loads(self.rfile.read(n))
                    with owner.lock:result=owner.dispatch(request)
                    reply={'jsonrpc':'2.0','id':request.get('id'),'result':result}
                except Exception as e:
                    # Downstream errors may include signed URLs: do not reflect them.
                    message=str(e) if isinstance(e,ValueError) and not ('http://'in str(e) or 'https://'in str(e)) else '下载推送失败，请在疾风中检查状态'
                    reply={'jsonrpc':'2.0','id':request.get('id') if isinstance(request,dict) else None,'error':{'code':1,'message':message}}
                raw=json.dumps(reply).encode();self.send_response(200);self.cors();self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(raw)));self.end_headers()
                try:self.wfile.write(raw)
                except BrokenPipeError:pass
        port=int(self.state['port'])
        try:self.server=http.server.ThreadingHTTPServer(('127.0.0.1',port),Handler)
        except OSError:
            # Keep a stable port once chosen, but don't take another app's socket.
            self.server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
        self.state['port']=self.server.server_port
        self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start()
    def stop(self):
        if self.server:self.server.shutdown();self.server.server_close();self.server=None
    def close(self):self.stop()
