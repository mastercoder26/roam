"""Local editor: native Tesseract renders and validates every saved project."""
from pathlib import Path
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
import json, subprocess, threading, shutil, datetime, urllib.parse, hashlib, os
ROOT=Path(__file__).resolve().parent.parent
CLI='/Users/akhilkonduru/Library/Application Support/Tesseract/bin/tsrct'
PROJECT=ROOT/'Watkins-Recreation.tsrct'
LOCK=threading.Lock()
WORK=ROOT/'.tesseract-work';CACHE=WORK/'editor-cache';CACHE.mkdir(exist_ok=True)
def run(*args):
    result=subprocess.run([CLI,*map(str,args)],capture_output=True,text=True)
    if result.returncode:raise RuntimeError(result.stderr[-3000:])
    return result.stdout
class Handler(SimpleHTTPRequestHandler):
    def __init__(self,*args,**kwargs):super().__init__(*args,directory=str(ROOT),**kwargs)
    def reply(self,data,status=200,kind='application/json'):
        payload=data if isinstance(data,bytes) else json.dumps(data).encode()
        self.send_response(status);self.send_header('Content-Type',kind);self.send_header('Content-Length',str(len(payload)));self.send_header('Cache-Control','no-store');self.send_header('X-Project-Version',str(PROJECT.stat().st_mtime_ns));self.end_headers();self.wfile.write(payload)
    def do_GET(self):
        url=urllib.parse.urlparse(self.path)
        try:
            if url.path=='/api/project':
                with LOCK:
                    target=WORK/'editor-current.json';run('project','checkout','--project',PROJECT,'--output',target)
                    self.reply(target.read_bytes(),kind='application/json')
            elif url.path=='/api/frame':
                t=max(0,min(20.458,float(urllib.parse.parse_qs(url.query).get('t',['0'])[0])))
                key=hashlib.sha256(f'{PROJECT.stat().st_mtime_ns}:{t:.3f}'.encode()).hexdigest()[:16];frame=CACHE/f'{key}.png'
                with LOCK:
                    if not frame.exists():run('preview','--project',PROJECT,'--time',f'{t:.3f}','--output',frame)
                self.reply(frame.read_bytes(),kind='image/png')
            elif url.path=='/Watkins-Recreation.mp4' and self.headers.get('Range','').startswith('bytes='):
                video=ROOT/'Watkins-Recreation.mp4';size=video.stat().st_size
                bounds=self.headers['Range'][6:].split('-');start=int(bounds[0] or 0);end=min(size-1,int(bounds[1]) if bounds[1] else size-1)
                if not 0<=start<=end<size:self.reply({'error':'Invalid range'},416);return
                self.send_response(206);self.send_header('Content-Type','video/mp4');self.send_header('Accept-Ranges','bytes');self.send_header('Content-Range',f'bytes {start}-{end}/{size}');self.send_header('Content-Length',str(end-start+1));self.end_headers()
                with open(video,'rb') as stream:
                    stream.seek(start);remaining=end-start+1
                    while remaining:
                        block=stream.read(min(65536,remaining));self.wfile.write(block);remaining-=len(block)
            else:super().do_GET()
        except (BrokenPipeError,ConnectionResetError):pass
        except Exception as e:self.reply({'error':str(e)},500)
    def do_POST(self):
        # Restrict mutations to this same local editor origin.
        origin=self.headers.get('Origin','')
        if origin and origin not in ['http://127.0.0.1:8774','http://localhost:8774']:
            self.reply({'error':'Local editor origin required'},403);return
        if self.path not in ['/api/save','/api/export']:self.reply({'error':'Unknown operation'},404);return
        try:
            if self.path=='/api/export':
                with LOCK:
                    target=WORK/'editor-export.mp4'
                    run('export','--project',PROJECT,'--output',target,'--resolution','1080p','--fps','24')
                    # Preserve original AAC packets when the original audio has no edits.
                    document=json.loads((WORK/'editable.json').read_text())
                    audios=[]
                    def find_audio(items):
                        for layer in items:
                            if layer['type']=='Audio':audios.append(layer)
                            find_audio(layer.get('layers',[]))
                    find_audio(document['composition']['layers'])
                    untouched=len(audios)==1 and audios[0].get('volume')==1 and audios[0].get('source',{}).get('assetId')=='original-audio' and audios[0].get('sourceRange')=={'start':0,'duration':20459} and not audios[0].get('effects')
                    untouched=untouched and audios[0].get('playback',{}).get('inputRange')=={'start':0,'duration':20459} and not any(e['target']['layerId']==audios[0]['id'] for e in document['composition']['dynamics']['entries'])
                    if untouched:
                        exact=WORK/'editor-audio-exact.mp4'
                        subprocess.run(['/opt/homebrew/bin/ffmpeg','-v','error','-y','-i',str(target),'-i',str(WORK/'original-audio.m4a'),'-map','0:v:0','-map','1:a:0','-c','copy','-movflags','+faststart',str(exact)],check=True,capture_output=True)
                        os.replace(exact,target)
                    previous=ROOT/'Watkins-Recreation.mp4'
                    versions=ROOT/'Versions';versions.mkdir(exist_ok=True)
                    if previous.exists():shutil.copy2(previous,versions/f'Before-Export-{datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")}.mp4')
                    os.replace(target,previous)
                self.reply({'exported':True});return
            length=int(self.headers.get('Content-Length','0'))
            if not 0<length<50_000_000:raise ValueError('Invalid project size')
            document=json.loads(self.rfile.read(length));target=WORK/'editor-save.json'
            with LOCK:
                expected=self.headers.get('X-Project-Version')
                if expected and expected!=str(PROJECT.stat().st_mtime_ns):
                    self.reply({'error':'This project has a newer revision. Reload the editor before saving.'},409);return
                target.write_text(json.dumps(document))
                # Commit a copy first: invalid documents cannot alter the working project.
                candidate=WORK/'editor-validated.tsrct';shutil.copy2(PROJECT,candidate)
                run('project','commit','--project',candidate,'--file',target)
                versions=ROOT/'Versions';versions.mkdir(exist_ok=True)
                stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
                shutil.copy2(PROJECT,versions/f'Before-Edit-{stamp}.tsrct')
                os.replace(candidate,PROJECT)
                (WORK/'editable.json').write_text(json.dumps(document,indent=2))
            self.reply({'saved':True,'project':str(PROJECT)})
        except Exception as e:self.reply({'error':str(e)},400)
    def log_message(self,*args):pass
print('Editor ready at http://127.0.0.1:8774/Editor.html',flush=True)
ThreadingHTTPServer(('127.0.0.1',8774),Handler).serve_forever()
