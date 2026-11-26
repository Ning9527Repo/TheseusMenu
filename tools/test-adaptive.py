#!/usr/bin/env python3
"""Independent model; no UIKit rendering or typechecking."""
import math, json, sys
SCALE=.83

def material(x,y,w,h,center=None):
    height=h*SCALE
    if center is None: center=y+h/2-(4 if abs(h-48)<.5 else 0)
    center=min(y+h-height/2,max(y+height/2,center))
    return x,center-height/2,w,height

def circle(rect,button,glyph):
    x,y,w,h=rect; bx,by,bw,bh=button; gx,gy,gw,gh=glyph
    cx=gx+gw/2; cy=y+h/2
    d=min(34,bw-4,h-4,2*min(cx-x,x+w-cx)-2)
    if d<max(12,gw+4,gh+4) or not (bx<=cx<=bx+bw and by-.5<=cy<=by+bh+.5):return None
    return cx,cy,d

count=0
for w in (44,60,100,160,320,400):
    for h in (30,40,48,56,100):
        for offset in (-8,-4,0,4,8):
            r=material(5,10,w,h,10+h/2+offset)
            assert r[0]==5 and r[2]==w and math.isclose(r[3],h*.83)
            assert r[1]>=10-1e-9 and r[1]+r[3]<=10+h+1e-9
            for _ in range(100): assert material(5,10,w,h,10+h/2+offset)==r
            count+=1
print(f'{count} fixed height/width cases and {count*100} repeated passes')
assert math.isclose(material(0,0,356,48)[1],.08)
assert math.isclose(material(0,0,356,48,20)[3],39.84)
count=0
if len(sys.argv)>1:
    heights=[]; circles=0; fallback=0; slots=0
    for line in open(sys.argv[1]):
        if '[TSML] ' not in line:continue
        try:r=json.loads(line.split('[TSML] ',1)[1])
        except ValueError:continue
        if r.get('event')!='FRAME' or not r.get('glass') or r.get('status') not in ('white-80','dark-80'):continue
        x,_,w,_=r['glass']; _,y,_,h=r['effect']; rect=material(x,y,w,h,20 if h==48 else None)
        heights.append(rect[3]); assert math.isclose(rect[3],h*.83)
        for v in r['rows']:
            if not v.get('effectiveVisible'):continue
            if v['class']=='_UISlotView' and v['inMenu'][3]>0:slots+=1
            if v['class']!='_UIEditMenuPageButton':continue
            imgs=[q for q in r['rows'] if q['class']=='UIImageView' and q.get('target')==v['id'] and q.get('effectiveVisible') and q['inMenu'][2]>0]
            for img in imgs:
                result=circle(rect,v['inMenu'],img['inMenu'])
                if result is None:fallback+=1;continue
                cx,cy,d=result
                assert d>0 and cx-d/2>=x-1e-9 and cx+d/2<=x+w+1e-9
                assert cy-d/2>=rect[1]-1e-9 and cy+d/2<=rect[1]+rect[3]+1e-9
                circles+=1
    assert heights and circles and slots
    print(f'024 trace replay: {len(heights)} menu frames, {circles} circle placements, {fallback} transition fallbacks, {slots} visible paste samples; fixed heights={sorted(set(round(h,2) for h in heights))}')
