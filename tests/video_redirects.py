import sys,urllib.parse,pathlib
from unittest.mock import patch
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'backend'))
from video import resolve_page
class Response:
 def __init__(self,url):self.url=url
 def __enter__(self):return self
 def __exit__(self,*args):pass
for dest in ['/discovery/item/abc?xsec_token=test','http://www.xiaohongshu.com/discovery/item/abc?xsec_token=test','https://www.xiaohongshu.com/explore/abc?xsec_token=test']:
 with patch('urllib.request.urlopen',return_value=Response('https://www.xiaohongshu.com/login?'+urllib.parse.urlencode({'redirectPath':dest}))):
  u=resolve_page('https://xhslink.cn/o/test');assert u.startswith('https://www.xiaohongshu.com/') and 'xsec_token=test'in u and '/login' not in u
for dest in ['https://evil.example/explore/a','https://www.xiaohongshu.com@evil.example/explore/a','javascript:alert(1)']:
 with patch('urllib.request.urlopen',return_value=Response('https://www.xiaohongshu.com/login?'+urllib.parse.urlencode({'redirectPath':dest}))):
  try:resolve_page('https://xhslink.cn/o/test');raise AssertionError()
  except ValueError:pass
print('PASS: relative + HTTP + HTTPS redirect targets; query retained; unsafe destinations rejected')
