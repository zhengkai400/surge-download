"""Isolated yt-dlp workers with per-task directories and resumable registry."""
import json,os,pathlib,re,secrets,signal,subprocess,sys,threading,time,urllib.parse

def resolve_page(url):
    import urllib.request
    host=urllib.parse.urlsplit(url).hostname or ''
    if host in ('xhslink.cn','xhslink.com','v.douyin.com'):
        request=urllib.request.Request(url,headers={'User-Agent':'Mozilla/5.0'})
        with urllib.request.urlopen(request,timeout=20) as response:url=response.url
    target=urllib.parse.urlsplit(url)
    if target.hostname and (target.hostname=='xiaohongshu.com' or target.hostname.endswith('.xiaohongshu.com')) and target.path.startswith('/login'):
        destination=urllib.parse.parse_qs(target.query).get('redirectPath',[''])[0]
        candidate=urllib.parse.urljoin('https://www.xiaohongshu.com',destination)
        parsed=urllib.parse.urlsplit(candidate)
        if parsed.scheme in ('http','https') and parsed.hostname=='www.xiaohongshu.com' and parsed.path.startswith(('/explore/','/discovery/item/')) and not parsed.username and not parsed.password:
            return urllib.parse.urlunsplit(("https", "www.xiaohongshu.com", parsed.path, parsed.query, parsed.fragment))
        raise ValueError('分享链接跳转到登录页，未找到有效笔记地址；请复制浏览器中的笔记完整链接。')
    return url

def worker(config):
    import yt_dlp
    task=json.loads(pathlib.Path(config).read_text());base=pathlib.Path(task['dir'])
    engine=pathlib.Path(sys.executable).parent.parent/'engine' if getattr(sys,'frozen',False) else pathlib.Path(__file__).resolve().parents[1]/'build/疾风下载.app/Contents/Resources/engine'
    def emit(v):print(json.dumps(v,ensure_ascii=False),flush=True)
    def hook(d):
        i=d.get('info_dict',{});emit({'title':i.get('title','视频任务'),'done':d.get('downloaded_bytes',0),'total':d.get('total_bytes') or d.get('total_bytes_estimate') or 0,'speed':d.get('speed') or 0})
    class Log:
        def debug(self,*a):pass
        def warning(self,*a):pass
        def error(self,*a):pass
    opts={'quiet':True,'no_warnings':True,'logger':Log(),'noplaylist':True,'lazy_playlist':True,'socket_timeout':20,'retries':3,'fragment_retries':3,'continuedl':True,'overwrites':False,'concurrent_fragment_downloads':4,'outtmpl':str(base/'%(title).150B [%(id)s].%(ext)s'),'progress_hooks':[hook], 'ffmpeg_location':str(engine),'js_runtimes':{'node':{'path':str(engine/'node')}},'remote_components':set(),'windowsfilenames':True}
    if task['mode']=='audio':
        opts.update(format='bestaudio/best',postprocessors=[{'key':'FFmpegExtractAudio','preferredcodec':'mp3','preferredquality':'192'}])
    else:
        h=task['quality']
        opts.update(format='bv*+ba/b',merge_output_format='mkv')
        # yt-dlp res sorting uses the shorter dimension for portrait media.
        # Prefer <= target but retain available formats when the site offers no match.
        if h!='best':opts['format_sort']=[f'res:{h}']
    try:
        with yt_dlp.YoutubeDL(opts) as y:
            info=y.extract_info(resolve_page(task['url']),download=False)
            if not info or info.get('_type') in ('playlist','multi_video'):raise ValueError('首版仅支持单视频，请使用具体视频页面地址')
            info=y.process_ie_result(info,download=True)
        paths=[str(p) for p in base.iterdir() if p.is_file() and p.suffix.lower() in ('.mp4','.mkv','.webm','.mp3','.m4a','.ogg','.opus','.mov','.flv','.aac','.wav')]
        if not paths:raise ValueError('没有找到输出媒体文件')
        emit({'complete':True,'paths':paths,'title':info.get('title','视频')})
    except Exception as e:
        message=re.sub(r'https?://\S+','[链接]',str(e))[:450]
        emit({'error':message});sys.exit(1)

class VideoManager:
    def __init__(self,root,atomic):
        self.root=root;self.path=root/'video-tasks.json';self.atomic=atomic;self.lock=threading.RLock();self.procs={};self.jobs={};self.slots=threading.Semaphore(2)
        if self.path.exists():self.jobs=json.loads(self.path.read_text())
        for t in self.jobs.values():
            if t['status'] in ('active','waiting'):t['status']='paused'
            t['speed']=0
        self.save()
    def save(self):self.atomic(self.path,json.dumps(self.jobs,ensure_ascii=False).encode())
    def add(self,url,opts):
        u=urllib.parse.urlsplit(url)
        if u.scheme not in ('http','https') or not u.hostname or u.username or u.password:raise ValueError('请输入 HTTP/HTTPS 视频页面地址')
        mode=opts.get('mode','video');quality=str(opts.get('quality','1080'))
        if mode not in ('video','audio') or quality not in ('best','2160','1080','720','480'):raise ValueError('无效视频选项')
        directory=pathlib.Path(opts['dir'])
        if not directory.is_absolute():raise ValueError('无效保存目录')
        gid=secrets.token_hex(8);directory=directory/('Video-'+gid)
        directory.mkdir(parents=True,exist_ok=False)
        with self.lock:
            self.jobs[gid]={'url':url,'dir':str(directory),'mode':mode,'quality':quality,'title':'正在解析视频…','status':'paused','total':0,'done':0,'speed':0,'paths':[],'error':''};self.save()
        self.resume(gid);return gid
    def status(self,gid):
        with self.lock:
            t=dict(self.jobs[gid]);paths=t['paths'] or [str(pathlib.Path(t['dir'])/t['title'])]
            return {'gid':gid,'video':True,'title':t['title'],'status':t['status'],'dir':t['dir'],'totalLength':str(t['total']),'completedLength':str(t['done']),'downloadSpeed':str(int(t['speed'])),'uploadSpeed':'0','connections':'0','errorMessage':t['error'],'files':[{'index':str(i+1),'path':p,'uris':[{'uri':'video:'+t['url']}]} for i,p in enumerate(paths)]}
    def statuses(self):
        with self.lock:return [self.status(g) for g in self.jobs]
    def resume(self,gid):
        with self.lock:
            t=self.jobs[gid]
            if t['status'] in ('active','waiting','complete'):return gid
            t.update(status='waiting',error='',speed=0);self.save()
        threading.Thread(target=self.run,args=(gid,),daemon=True).start();return gid
    def run(self,gid):
        with self.slots:
            with self.lock:
                if gid not in self.jobs or self.jobs[gid]['status']!='waiting':return
                t=self.jobs[gid];cfg=self.root/('video-worker-'+gid+'.json');self.atomic(cfg,json.dumps(t).encode())
                cmd=[sys.executable] if getattr(sys,'frozen',False) else [sys.executable,str(pathlib.Path(__file__).with_name('btbridge.py'))]
                try:p=subprocess.Popen(cmd+['--video-worker',str(cfg)],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True,start_new_session=True)
                except Exception:
                    t.update(status='error',error='视频工作进程启动失败');self.save();cfg.unlink(missing_ok=True);return
                self.procs[gid]=p;t['status']='active'
            last=0
            try:
                for line in p.stdout:
                    try:d=json.loads(line)
                    except Exception:continue
                    with self.lock:
                        if gid not in self.jobs or t['status']!='active' or self.procs.get(gid) is not p:continue
                        if 'error'in d:t.update(status='error',error=d['error'],speed=0)
                        elif d.get('complete'):
                            t.update(status='complete',paths=d['paths'],title=d['title'],speed=0)
                            t['total']=t['done']=sum(pathlib.Path(x).stat().st_size for x in t['paths'])
                        else:t.update({k:d[k] for k in ('title','done','total','speed') if k in d})
                        if time.monotonic()-last>2 or t['status']!='active':self.save();last=time.monotonic()
                p.wait()
            finally:
                with self.lock:
                    if self.procs.get(gid) is not p:return
                    self.procs.pop(gid,None);cfg.unlink(missing_ok=True)
                    if gid in self.jobs:
                        if t['status']=='active':t.update(status='error',error='视频进程提前结束，可重试',speed=0)
                        self.save()
    def pause(self,gid):
        with self.lock:
            t=self.jobs[gid]
            if t['status'] in ('complete','error'):return gid
            t.update(status='paused',speed=0);p=self.procs.get(gid);self.save()
        if p:
            try:os.killpg(p.pid,signal.SIGTERM);p.wait(timeout=5)
            except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait()
            except ProcessLookupError:pass
        return gid
    def remove(self,gid):
        self.pause(gid)
        with self.lock:self.jobs.pop(gid,None);self.save()
        return gid
    def close(self):
        for gid in list(self.jobs):self.pause(gid)
