#!/usr/bin/env python3
"""Regression model: no translation of native slot or its hidden label."""
import json, sys, math

def native_slot(rect, transform):
    # Undo the old 024 transform in replay only; 025 never applies one.
    x,y,w,h=rect; return x-transform[4],y-transform[5],w,h

assert native_slot((2,4,55,40),(1,0,0,1,0,4))==(2,0,55,40)
assert native_slot((2,0,55,40),(1,0,0,1,0,0))==(2,0,55,40)
count=0
if len(sys.argv)>1:
    for line in open(sys.argv[1]):
        if '[TSML] ' not in line:continue
        try:r=json.loads(line.split('[TSML] ',1)[1])
        except ValueError:continue
        if r.get('event')!='FRAME':continue
        for v in r.get('rows',[]):
            if v['class']=='_UISlotView' and v['inTarget'][3]>0:
                x,y,w,h=native_slot(v['inTarget'],v['transform'])
                assert abs(y)<.03 and math.isclose(h,40,abs_tol=.03)
                count+=1
    assert count
print(f'2 native-slot cases and {count} logged slot samples; internal glyph baseline not measured')
