#!/usr/bin/env python3
"""Portable source checks (not a native iOS compile)."""
import hashlib,json,plistlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
CONFIG=json.loads((ROOT/'packaging/config.json').read_text())
def sha256(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def rel(path): return Path(path).relative_to(ROOT).as_posix()
def discover():
    return {'swift':sorted((ROOT/'src').glob('*.swift')), 'core':sorted((ROOT/'src').glob('*.m'))}
def check():
    sources=discover(); assert [p.name for p in sources['swift']]==['MenuBridge.swift']; assert [p.name for p in sources['core']]==['Tweak.m']
    assert not (ROOT/'Vendor').exists()
    assert not any(p.suffix in ('.metal','.metallib') for p in ROOT.rglob('*') if not {'build','dist'} & set(p.relative_to(ROOT).parts))
    assert plistlib.loads((ROOT/'src/Filter.plist').read_bytes())['Filter']['Bundles']==['com.apple.UIKit']
    assert not {'Metal','MetalKit','IOSurface','CoreVideo','Accelerate'} & set(CONFIG['frameworks'])
    bridge=(ROOT/'src/MenuBridge.swift').read_text()
    for text in ('UIColor.white.withAlphaComponent(0.80)','UIColor(white: 0.16, alpha: 0.80)','heightScale: CGFloat = 0.83','nativeMaterialRect()', 'rect.height * Self.heightScale', 'rowCenter ?? fallback', 'applyCapsule(frame)', 'effect.layer.mask = capsule', 'effect?.layer.mask = previousMask', 'cornerRadius: min(rect.width, rect.height)/2', 'updateArrows(in:', 'button.insertSubview(circle, belowSubview: glyph)', 'arrow.suppressBackgrounds(backgrounds)', 'circle.layer.cornerRadius = diameter/2','let hasSlot = descendants(host, depth: 5)', 'if hasSlot {','restoreArrows()','restoreForeground()','UIColor.white, range:','backdrop?.layer.isHidden = true','material.removeFromSuperview()','payload(host)','drawnRect','dy:0,host:item','applyGap()','restoreGap()','recordPresentationForView:point:'):
        assert text in bridge,text
    for text in ('widthScale','applyWidth','restoreWidth','chevron','suppressNativeVisuals','menu.transform =','fitPayload','scaledBy(', 'translate(slot,'):
        assert text not in bridge,text
    tweak=(ROOT/'src/Tweak.m').read_text()
    for text in ('UIApplicationDidBecomeActiveNotification','UIApplicationWillEnterForegroundNotification','UISceneDidActivateNotification','installLifecycle()','findMenus(w,12)','weakObjectsHashTable','@1500','queueScans()'):
        assert text in tweak,text
    assert 'guard UIApplication.shared.applicationState == .active else { return }' in bridge
    assert 'reject(menu,"app-inactive")' not in bridge
    for text in ('TheseusView','CADisplayLink','renderNow','captureRect','import Metal'):
        assert text not in bridge,text
    assert CONFIG['version']=='1.0' and CONFIG['package']=='com.banshengnianhua.theseusmenu'
    return {'status':'passed','sources':{k:[rel(p) for p in v] for k,v in sources.items()},'native_build_executed':False,'device_validation_executed':False}
if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser();p.add_argument('--output');a=p.parse_args();s=json.dumps(check(),indent=2)+'\n'
    if a.output:
        path=Path(a.output);path.parent.mkdir(parents=True,exist_ok=True);path.write_text(s)
    print(s)
