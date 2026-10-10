#!/usr/bin/env python3
"""Smoke-test a fresh DHT routing table, without downloading any public torrent."""
import pathlib,subprocess,tempfile,secrets,socket,hashlib
binary=pathlib.Path(__file__).resolve().parents[1]/'build/疾风下载.app/Contents/Resources/engine/aria2c'
with tempfile.TemporaryDirectory(prefix='surge-dht-') as td:
 p=pathlib.Path(td);log=p/'dht.log'
 helper=binary.parents[5]/'.build/dht-tests'
 if helper.exists(): subprocess.run([str(helper),str(p/'dht.dat')],check=True)
 with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
 args=[str(binary),'--no-conf','--enable-rpc=true','--rpc-listen-all=false',f'--rpc-listen-port={port}','--rpc-secret='+secrets.token_hex(24),'--enable-dht=true','--enable-dht6=false','--dht-entry-point=dht.transmissionbt.com:6881',f'--dht-file-path={p}/dht.dat','--dht-listen-port=49401-49440','--listen-port=49360-49400',f'--log={log}','--log-level=debug','--console-log-level=error','--stop=18','--bt-metadata-only=true','magnet:?xt=urn:btih:'+hashlib.sha1(b'Surge DHT bootstrap diagnostic - no published torrent').hexdigest()]
 r=subprocess.run(args,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,timeout=25)
 text=log.read_text() if log.exists() else ''
 (pathlib.Path(__file__).parent/'dht-bootstrap.log').write_text(text)
 table=p/'dht.dat'
 print('DHT process exit',r.returncode)
 print('Saved routing table bytes',table.stat().st_size if table.exists() else 0)
 relevant=[x for x in text.splitlines() if any(q in x.lower() for q in ['received','recv','entry point','serialized','routing table','bootstrap'])]
 for x in relevant[-14:]:print(x)
 # aria2 returns 7 when the deliberately nonexistent test torrent is unfinished.
 assert r.returncode in (0, 7)
 assert table.exists() and table.stat().st_size>64, 'DHT did not save discovered nodes; network may block UDP'
 assert 'dht response ping' in text or 'dht response find_node' in text or 'dht response get_peers' in text
 print('PASS: fresh bootstrap cache is accepted by aria2 and routing responses are received; not a proof of swarm availability')
