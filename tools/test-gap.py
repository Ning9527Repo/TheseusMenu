"""Independent scalar model for the Swift vertical gap calculation, not UIKit testing."""
def gap(top,bottom,point,safe_top,safe_bottom):
    if bottom <= point+1: return -min(10,max(0,top-safe_top))
    if top >= point-1: return min(10,max(0,safe_bottom-bottom))
    return 0
assert gap(100,148,170,8,844)==-10
assert gap(200,248,170,8,844)==10
assert gap(11,59,170,8,844)==-3
assert gap(793,841,170,8,844)==3
assert gap(100,148,120,8,844)==0
assert gap(8,56,170,8,844)==0
assert gap(796,844,170,8,844)==0
for above in (True,False):
    base=100 if above else 200
    previous=None; current=base
    for _ in range(100):
        origin=base if previous==current else current
        current=origin+gap(origin,origin+48,170,8,844)
        previous=current
        assert current==base+(-10 if above else 10)
print('7 gap cases and 200 repeated-offset model passes')
