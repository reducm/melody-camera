import base64, tempfile, unittest, uuid, threading, queue
from pathlib import Path
from server import Service

class QueueTests(unittest.TestCase):
    def setUp(self):
        self.directory=tempfile.TemporaryDirectory()
        # No worker: deterministic queue lifecycle and validation tests.
        self.service=Service.__new__(Service)
        self.service.root=Path(self.directory.name)
        self.service.jobs={}; self.service.pending=queue.Queue(maxsize=12); self.service.lock=threading.RLock()
        self.payload=dict(id=str(uuid.uuid4()),prompt='参考构图',image=base64.b64encode(b'\xff\xd8\xfftest').decode())
    def tearDown(self): self.directory.cleanup()
    def test_duplicate_is_idempotent_and_cannot_replace_input(self):
        identifier=self.service.submit(self.payload)
        self.assertEqual(identifier,self.service.submit(self.payload))
        self.assertEqual(self.service.pending.qsize(),1)
        with self.assertRaises(ValueError): self.service.submit(dict(self.payload,prompt='不同输入'))
    def test_invalid_input_and_path_are_rejected(self):
        for patch in ({'id':'../../outside'},{'image':'bad'},{'prompt':'a'*6001},{'image':base64.b64encode(b'not image').decode()}):
            with self.assertRaises(ValueError): self.service.submit(dict(self.payload,**patch))
    def test_cancel_preserves_bounded_status_without_input(self):
        identifier=self.service.submit(self.payload); self.service.cancel(identifier)
        status=self.service.status(identifier)
        self.assertEqual(status['state'],'cancelled'); self.assertNotIn('prompt',status); self.assertNotIn('image',status)

class HTTPRoundTripTests(unittest.TestCase):
    def test_authenticated_job_lifecycle_and_cli_is_offline(self):
        import json,time,urllib.request,urllib.error
        from http.server import ThreadingHTTPServer
        from server import Handler
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary); binary=root/'fake-cli'
            binary.write_text("#!/usr/bin/env python3\nimport sys,pathlib\na=sys.argv\nassert '--local' in a and '--offline' in a and '--no-download-missing' in a\nprint('Sampling... 1 / 2',flush=True)\npathlib.Path(a[a.index('--output')+1]).write_bytes(b'test-output')\n")
            binary.chmod(0o700)
            service=Service(binary,root,root/'jobs')
            server=ThreadingHTTPServer(('127.0.0.1',0),Handler);server.token='test-connection';server.service=service
            thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
            base='http://127.0.0.1:'+str(server.server_port)
            try:
                with self.assertRaises(urllib.error.HTTPError) as failed: urllib.request.urlopen(base+'/health')
                self.assertEqual(failed.exception.code,401); failed.exception.close()
                def request(path,data=None,method=None):
                    return urllib.request.urlopen(urllib.request.Request(base+path,data=data,method=method,headers={'Authorization':'Bearer test-connection'}))
                payload=dict(id=str(uuid.uuid4()),prompt='构图测试',image=base64.b64encode(b'\xff\xd8\xfftest').decode())
                accepted=json.load(request('/v1/reference-jobs',json.dumps(payload).encode()))
                path='/v1/reference-jobs/'+accepted['id']
                for _ in range(100):
                    state=json.load(request(path))
                    if state['state']=='ready':break
                    time.sleep(.02)
                self.assertEqual(state['state'],'ready')
                self.assertEqual(request(path+'/image').read(),b'test-output')
                self.assertEqual(json.load(request(path,method='DELETE'))['state'],'ready')
                service.pending.join()
                self.assertFalse((service.root/accepted['id']/'input.jpg').exists())
                self.assertFalse((service.root/accepted['id']/'prompt.txt').exists())
            finally: server.shutdown();server.server_close()

if __name__=='__main__': unittest.main()
