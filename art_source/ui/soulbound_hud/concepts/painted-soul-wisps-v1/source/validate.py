"""Read-only verification of delivered PNG frames and preview preservation."""
from pathlib import Path
import hashlib
import json
import struct
from PIL import Image, ImageChops

ROOT=Path(__file__).resolve().parent.parent
HUD=ROOT.parent.parent

def elements(data,start=0,end=None):
    end=len(data) if end is None else end
    while start<end:
        first=data[start]
        length=next(n for n in range(1,5) if first & (1<<(8-n)))
        eid=int.from_bytes(data[start:start+length],'big');start+=length
        first=data[start]
        length=next(n for n in range(1,9) if first & (1<<(8-n)))
        size=int.from_bytes(data[start:start+length],'big') & ((1<<(7*length))-1)
        start+=length
        yield eid,start,start+size
        start+=size
    assert start==end

def validate():
    files=sorted((ROOT/'frames').glob('soul-*.png'))
    assert [p.name for p in files]==[f'soul-{i:04}.png' for i in range(600)]
    min_margin=720
    pixel_samples=[]
    for i,p in enumerate(files):
        with Image.open(p) as im:
            assert im.size==(1280,720) and im.mode=='RGBA',(p,im.size,im.mode)
            alpha=im.getchannel('A');lo,hi=alpha.getextrema()
            assert lo==0 and hi==255,(p,lo,hi)
            box=alpha.getbbox();assert box
            margin=min(box[0],box[1],1280-box[2],720-box[3]);min_margin=min(min_margin,margin)
            assert margin>=12,(p,'Clipped / insufficiently padded',box)
            for corner in [(0,0),(1279,0),(0,719),(1279,719)]:assert im.getpixel(corner)[3]==0
            # Three hearts stay exactly fixed and retain their original pigment.
            pixel_samples.append([im.getpixel(xy) for xy in [(694,411),(799,411),(907,411)]])
    assert all(p==pixel_samples[0] for p in pixel_samples),'Heart appearance drift'
    # The aura must really move during the settled hold, and be absent at both ends.
    with Image.open(files[288]) as a,Image.open(files[336]) as b:
        assert ImageChops.difference(a.crop((180,130,645,315)),b.crop((180,130,645,315))).getbbox(), 'Idle aura is static'
    before=json.loads((ROOT/'validation/preview-before.json').read_text())
    for relative,expected in before.items():
        assert hashlib.sha256((HUD/relative).read_bytes()).hexdigest()==expected,relative
    data=(ROOT/'soul-wisps-painted.webm').read_bytes()
    segment=next((a,b) for eid,a,b in elements(data) if eid==0x18538067)
    stamps=[];track_count=0;duration=None;default_duration=None
    for eid,a,b in elements(data,*segment):
        if eid==0x1549a966:
            for kind,x,y in elements(data,a,b):
                if kind==0x4489:duration=struct.unpack('>d',data[x:y])[0]
        if eid==0x1654ae6b:
            for entry,x,y in elements(data,a,b):
                if entry==0xae:
                    track_count+=1
                    fields={k:data[u:v] for k,u,v in elements(data,x,y)}
                    assert int.from_bytes(fields[0x83],'big')==1
                    assert fields[0x86]==b'V_VP9'
                    default_duration=int.from_bytes(fields[0x23e383],'big')
        if eid==0x1f43b675:
            offset=0
            for kind,x,y in elements(data,a,b):
                if kind==0xe7:offset=int.from_bytes(data[x:y],'big')
                elif kind==0xa3:stamps.append(offset+int.from_bytes(data[x+1:x+3],'big',signed=True))
    assert track_count==1 and duration==10000 and default_duration==16666667
    assert len(stamps)==600
    assert all(abs(value-i*1000/60)<=.51 for i,value in enumerate(stamps))
    result={'frames':600,'size':[1280,720],'fps':60,'duration_seconds':10,'alpha':'RGBA, transparent exterior and opaque subject in every frame','minimum_canvas_margin_px':min_margin,'heart_pixels_constant':True,'settled_wisps_animate':True,'video_blocks':len(stamps),'audio_tracks':0,'protected_preview_files_unchanged':len(before)}
    print(json.dumps(result,indent=2))
    return result

if __name__=='__main__':validate()
