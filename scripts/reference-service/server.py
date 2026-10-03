#!/usr/bin/env python3
"""私有局域网参考图队列。只调用独立安装的官方 Draw Things CLI。"""
import argparse, base64, fcntl, hashlib, hmac, json, os, queue, re, secrets, signal, subprocess, threading, time, uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

MAX_BODY = 3_000_000
class Service:
    def __init__(self, binary, models, root, steps=20, profile="baseline"):
        self.binary, self.models, self.root, self.steps = str(Path(binary).resolve()), str(Path(models).resolve()), Path(root).resolve(), steps
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.profile=profile
        self.jobs, self.pending, self.lock = {}, queue.Queue(maxsize=12), threading.RLock()
        threading.Thread(target=self.worker, daemon=True).start()
    def submit(self, payload):
        identifier = str(uuid.UUID(payload['id'])).upper()
        prompt = payload['prompt']
        if not isinstance(prompt, str) or not 1 <= len(prompt) <= 6000: raise ValueError()
        image = base64.b64decode(payload['image'], validate=True)
        if not 1 <= len(image) <= 2_000_000 or not image.startswith(b'\xff\xd8\xff'): raise ValueError()
        digest = hashlib.sha256(image + prompt.encode()).hexdigest()
        with self.lock:
            if identifier in self.jobs:
                if self.jobs[identifier]['digest'] != digest: raise ValueError()
                return identifier
            if self.pending.full(): raise ValueError()
            folder = self.root / identifier
            folder.mkdir(mode=0o700, exist_ok=True)
            (folder/'input.jpg').write_bytes(image)
            (folder/'prompt.txt').write_text(prompt)
            self.jobs[identifier] = dict(id=identifier,state='queued',progress=None,stage='已排队，模板可立即跟拍',digest=digest,created=time.time(),process=None)
            self.pending.put_nowait(identifier)
        return identifier
    def status(self, identifier):
        with self.lock:
            job=self.jobs.get(identifier)
            return {k:job[k] for k in ('id','state','progress','stage')} if job else None
    def cancel(self, identifier):
        with self.lock:
            job=self.jobs.get(identifier)
            if job and job['state'] in ('queued','running'):
                job.update(state='cancelled',progress=None,stage='已取消')
                if job['process'] and job['process'].poll() is None:
                    process=job['process']; process.terminate()
                    def kill_if_needed():
                        if process.poll() is None: process.kill()
                    timer=threading.Timer(5,kill_if_needed); timer.daemon=True; timer.start()
                else:
                    for filename in ('input.jpg','prompt.txt'): (self.root/identifier/filename).unlink(missing_ok=True)
    def expire(self):
        with self.lock:
            for identifier,job in list(self.jobs.items()):
                if time.time()-job['created'] > 86400 and job['state'] not in ('queued','running'):
                    for file in (self.root/identifier).glob('*'): file.unlink(missing_ok=True)
                    (self.root/identifier).rmdir(); del self.jobs[identifier]
    def worker(self):
        while True:
            identifier=self.pending.get(); folder=self.root/identifier
            try:
                with self.lock:
                    job=self.jobs[identifier]
                    if job['state']=='cancelled': continue
                    job.update(state='running',stage='正在加载模型与编码照片',progress=None)
                    args=[self.binary,'generate','--local','--offline','--no-download-missing','--models-dir',self.models,'--model','qwen_image_edit_2511_q6p.ckpt','--prompt-file',str(folder/'prompt.txt'),'--image',str(folder/'input.jpg'),'--width','384','--height','512','--steps',str(self.steps),'--cfg','1' if self.profile=='lightning' else '4','--seed','42','--disable-preview','--output',str(folder/'output.png')]
                    if self.profile=='lightning': args += ['--config-file',str(Path(__file__).with_name('qwen-lightning.json'))]
                    process=subprocess.Popen(args,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,start_new_session=True)
                    job['process']=process
                def timeout():
                    if process.poll() is None:
                        process.kill()
                timer=threading.Timer(1800,timeout); timer.start()
                # CLI may print prompts/configuration: never persist or relay raw output.
                buffer=''
                while chunk:=process.stdout.read(1):
                    char=chunk.decode('utf-8',errors='ignore')
                    buffer=(buffer+char)[-1024:]
                    if char in '\r\n':
                        match=re.search(r'Sampling.*?(\d+)\s*/\s*(\d+)',buffer)
                        with self.lock:
                            if job['state']=='running':
                                if match and 0 < int(match[2]) and 0 <= int(match[1]) <= int(match[2]):
                                    job.update(progress=int(match[1])/int(match[2]),stage='正在采样生成')
                                elif 'Finishing' in buffer: job.update(progress=None,stage='正在解码参考图')
                        buffer=''
                code=process.wait(); timer.cancel()
                with self.lock:
                    if job['state']!='cancelled':
                        success=code==0 and (folder/'output.png').is_file() and (folder/'output.png').stat().st_size <= 8_000_000
                        job.update(state='ready' if success else 'failed',progress=1 if success else None,stage='AI 生成参考 · 非实拍' if success else 'Mac 模型生成失败，请检查模型和可用内存')
            except Exception:
                with self.lock:
                    if self.jobs[identifier]['state']!='cancelled': self.jobs[identifier].update(state='failed',progress=None,stage='Mac 生成服务异常')
            finally:
                for filename in ('input.jpg','prompt.txt'): (folder/filename).unlink(missing_ok=True)
                self.pending.task_done()
                self.expire()

class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def send(self,code,payload):
        data=json.dumps(payload).encode(); self.send_response(code); self.send_header('Content-Type','application/json'); self.send_header('Content-Length',str(len(data))); self.end_headers(); self.wfile.write(data)
    def authorized(self):
        if not hmac.compare_digest(self.headers.get('Authorization',''),'Bearer '+self.server.token): self.send(401,{'error':'连接密钥无效'}); return False
        return True
    def do_POST(self):
        if not self.authorized(): return
        if self.path!='/v1/reference-jobs': return self.send(404,{})
        try:
            length=int(self.headers.get('Content-Length','0'))
            if not 0 < length <= MAX_BODY: raise ValueError()
            self.connection.settimeout(15)
            payload=json.loads(self.rfile.read(length)); identifier=self.server.service.submit(payload)
            self.send(202,self.server.service.status(identifier))
        except (ValueError,KeyError,TypeError,TimeoutError): self.send(400,{'error':'请求无效或队列已满'})
    def route(self):
        parts=self.path.strip('/').split('/')
        if len(parts) not in (3,4) or parts[:2]!=['v1','reference-jobs']: return None,None
        try: identifier=str(uuid.UUID(parts[2])).upper()
        except ValueError: return None,None
        return identifier, parts[3] if len(parts)==4 else ''
    def do_GET(self):
        if not self.authorized(): return
        if self.path=='/health': return self.send(200,{'provider':'Draw Things · Mac 本地 Qwen','protocol':1})
        identifier,action=self.route(); status=self.server.service.status(identifier)
        if not status: return self.send(404,{})
        if action=='': return self.send(200,status)
        if action=='image' and status['state']=='ready':
            data=(self.server.service.root/identifier/'output.png').read_bytes()
            self.send_response(200); self.send_header('Content-Type','image/png'); self.send_header('Content-Length',str(len(data))); self.end_headers(); self.wfile.write(data); return
        self.send(409,{})
    def do_DELETE(self):
        if not self.authorized(): return
        identifier,action=self.route()
        if action!='' or not self.server.service.status(identifier): return self.send(404,{})
        self.server.service.cancel(identifier); self.send(200,self.server.service.status(identifier))

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary',required=True); parser.add_argument('--models',required=True); parser.add_argument('--root',required=True)
    parser.add_argument('--host',default='127.0.0.1'); parser.add_argument('--port',type=int,default=7861); parser.add_argument('--steps',type=int); parser.add_argument('--profile',choices=['baseline','lightning'],default='lightning')
    args=parser.parse_args(); os.umask(0o077)
    args.steps=args.steps if args.steps is not None else (4 if args.profile=='lightning' else 20)
    if args.profile=='lightning' and args.steps!=4: parser.error('Lightning 配置固定使用匹配的 4 步')
    if not 1 <= args.steps <= 50: parser.error('采样步数必须为 1 至 50')
    root=Path(args.root); root.mkdir(parents=True,exist_ok=True,mode=0o700)
    root.chmod(0o700)
    tokenfile=root/'connection-token'
    if not tokenfile.exists(): tokenfile.write_text(secrets.token_urlsafe(32))
    tokenfile.chmod(0o600)
    ownership=(root/'service.lock').open('a')
    try: fcntl.flock(ownership,fcntl.LOCK_EX|fcntl.LOCK_NB)
    except BlockingIOError: parser.error('此目录的参考图服务已经在运行')
    server=ThreadingHTTPServer((args.host,args.port),Handler); server.token=tokenfile.read_text().strip()
    # 上次崩溃留下的输入不应长期保留；输出可由手机保存后的记录展示。
    for folder in (root/'jobs').glob('*'):
        try: uuid.UUID(folder.name)
        except ValueError: continue
        if not folder.is_dir() or folder.is_symlink(): continue
        expired=time.time()-folder.stat().st_mtime > 86400
        for filename in ('input.jpg','prompt.txt') + (('output.png',) if expired else ()):
            (folder/filename).unlink(missing_ok=True)
        if expired and not any(folder.iterdir()): folder.rmdir()
    server.service=Service(args.binary,args.models,root/'jobs',args.steps,args.profile)
    print('参考图服务已启动；连接密钥保存在私有目录。',flush=True)
    def stop(signum,frame): raise KeyboardInterrupt()
    signal.signal(signal.SIGTERM,stop)
    try: server.serve_forever()
    except KeyboardInterrupt: pass
    finally:
        for identifier in list(server.service.jobs): server.service.cancel(identifier)
        server.server_close()
if __name__=='__main__': main()
