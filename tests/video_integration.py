import functools,http.server,json,pathlib,subprocess,tempfile,threading,time,hashlib
from bridge_integration import Client,APP,ROOT
with tempfile.TemporaryDirectory(prefix='surge-video-test-') as tmp:
 root=pathlib.Path(tmp);web=root/'web';web.mkdir()
 subprocess.run(['/opt/homebrew/bin/ffmpeg','-v','error','-f','lavfi','-i','testsrc=size=160x90:rate=10','-f','lavfi','-i','sine=frequency=440','-t','3','-c:v','libx264','-pix_fmt','yuv420p','-c:a','aac',str(web/'clip.mp4')],check=True)
 class Handler(http.server.SimpleHTTPRequestHandler):
  def log_message(self,*a):pass
 server=http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Handler,directory=str(web)));threading.Thread(target=server.serve_forever,daemon=True).start()
 url=f'http://127.0.0.1:{server.server_port}/clip.mp4';home=root/'home';c=Client(home);results=[]
 try:
  video=c.call('addVideo',[url,{'dir':str(root/'out'),'mode':'video','quality':'1080'}]);st=c.until(video,lambda s:s['status']=='complete',120)
  output=pathlib.Path(st['files'][0]['path']);assert output.read_bytes()==(web/'clip.mp4').read_bytes();results.append('packaged yt-dlp downloads video; bytes match')
  audio=c.call('addVideo',[url,{'dir':str(root/'out'),'mode':'audio','quality':'1080'}]);st=c.until(audio,lambda s:s['status']=='complete',120)
  out=pathlib.Path(st['files'][0]['path']);assert out.suffix=='.mp3'
  probe=json.loads(subprocess.check_output([str(APP/'engine/ffprobe'),'-v','error','-show_streams','-of','json',str(out)]));assert probe['streams'][0]['codec_name']=='mp3';results.append('bundled FFmpeg extracts valid MP3')
  c.close();c=Client(home);assert c.call('tellStatus',[audio])['status']=='complete';results.append('completion survives restart')
  c.call('removeDownloadResult',[audio]);assert out.exists();results.append('remove record preserves output file')
  bad=c.call('addVideo',[f'http://127.0.0.1:{server.server_port}/missing',{'dir':str(root/'out')}])
  for _ in range(150):
   s=c.call('tellStatus',[bad])
   if s['status']=='error':break
   time.sleep(.1)
  assert s['status']=='error';assert 'http://' not in s['errorMessage'];results.append('invalid URL reports sanitized error')
  paused=c.call('addVideo',[url,{'dir':str(root/'out')}]);c.call('pause',[paused]);assert c.call('tellStatus',[paused])['status']=='paused'
  c.close();c=Client(home);assert c.call('tellStatus',[paused])['status']=='paused';c.call('unpause',[paused]);c.until(paused,lambda s:s['status']=='complete',120);results.append('pause, app restart and resume')
 finally:c.close();server.shutdown()
 (ROOT/'tests/video-results.json').write_text(json.dumps(results,indent=2));print('\n'.join('PASS '+x for x in results))
