from pathlib import Path
import subprocess,json,re
root=Path(__file__).resolve().parent.parent
src=root/'.tesseract-work/Roam-native-mix.mp4'
dst=root/'Roam-Promo.mp4'
# Measured two-pass finishing. Video pixels and the native editable stems remain intact.
first=subprocess.run(['ffmpeg','-nostdin','-i',str(src),'-af','loudnorm=I=-15:TP=-1.5:LRA=7:print_format=json','-f','null','-'],capture_output=True,text=True,check=True)
data=json.loads(re.findall(r'\{[^{}]*"input_i"[^{}]*\}',first.stderr)[-1])
recipe=f"loudnorm=I=-15:TP=-1.5:LRA=7:measured_I={data['input_i']}:measured_TP={data['input_tp']}:measured_LRA={data['input_lra']}:measured_thresh={data['input_thresh']}:offset={data['target_offset']}:linear=true:print_format=json"
second=subprocess.run(['ffmpeg','-nostdin','-n','-i',str(src),'-map','0:v:0','-map','0:a:0','-c:v','copy','-af',recipe,'-ar','48000','-c:a','aac','-b:a','256k','-movflags','+faststart',str(dst)],capture_output=True,text=True,check=True)
(root/'.tesseract-work/checks/mastering.json').write_text(json.dumps({'firstPass':data,'secondPassFilter':recipe,'note':'Final audio finishing only. Pictures are stream-copied. Tesseract document retains the independent keys/bass, drums and motion accents.'},indent=2))
print(dst)
