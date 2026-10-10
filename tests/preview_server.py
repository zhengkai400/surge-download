#!/usr/bin/env python3
"""Owned local fixture for interactive UI smoke test. Bounded, deterministic file."""
import http.server,time,hashlib,pathlib
DATA=(b'SURGE LOCAL TEST\n'*4096)*256
class H(http.server.BaseHTTPRequestHandler):
 def do_GET(self):
  if self.path!='/surge-test.bin':self.send_error(404);return
  start,end=0,len(DATA)-1
  if self.headers.get('Range'):
   parts=self.headers['Range'].split('=')[1].split('-');start=int(parts[0]);end=int(parts[1]) if parts[1] else end
   self.send_response(206);self.send_header('Content-Range',f'bytes {start}-{end}/{len(DATA)}')
  else:self.send_response(200)
  self.send_header('Content-Length',str(end-start+1));self.send_header('Accept-Ranges','bytes');self.end_headers()
  try:
   for i in range(start,end+1,32768):self.wfile.write(DATA[i:min(i+32768,end+1)]);self.wfile.flush();time.sleep(.08)
  except (BrokenPipeError,ConnectionResetError):pass
srv=http.server.ThreadingHTTPServer(('127.0.0.1',0),H)
print(f'http://127.0.0.1:{srv.server_port}/surge-test.bin',flush=True)
print('SHA256 '+hashlib.sha256(DATA).hexdigest(),flush=True)
srv.serve_forever()
