'use strict';
// TheseusMenu 0.1.6 diagnostics. Read-only; no input text, titles, screenshots,
// clipboard, or view mutations. All UIKit reads run on main queue.
if (!ObjC.available) { console.log('[TSML] ERROR Objective-C unavailable'); } else {
 const C=ObjC.classes, start=Date.now();
 const names=['_UIEditMenuListView','_UIEditMenuContainerView','_UIEditMenuCollectionView','_UIEditMenuListViewCell','_UIEditMenuPageButton','UIPasteControl'];
 const hooks=[], seen=new Set(), last=new Map();
 let busy=false, seq=0, until=0, lastIdle=0, active=false, total=0, errors=0, eventCount=0, eventWindow=0;
 const now=()=>Date.now()-start;
 function emit(kind,data){ console.log('[TSML] '+JSON.stringify(Object.assign({t:now(),seq:++seq,event:kind},data))); }
 const ok=o=>!!o&&!!o.handle&&!o.handle.isNull();
 const cls=o=>ok(o)?o.$className:null;
 const id=o=>ok(o)?o.handle.toString():null;
 const isa=(o,n)=>ok(o)&&!!C[n]&&!!o.isKindOfClass_(C[n]);
 function arr(a){const r=[];if(ok(a)) for(let i=0,n=Math.min(Number(a.count()),300);i<n;i++)r.push(a.objectAtIndex_(i));return r;}
 const num=x=>Math.round(Number(x)*100)/100;
 function flat(a){return Array.isArray(a)?a.reduce((r,v)=>r.concat(flat(v)),[]):[num(a)];}
 function rect(a){const r=flat(a);return r.length===4?r:null;}
 function safe(fn){try{return fn();}catch(e){return null;}}
 function layer(v){const l=v.layer(),p=l.presentationLayer(),m=l.mask();return {opacity:num(l.opacity()),corner:num(l.cornerRadius()),mask:cls(m),maskFrame:ok(m)?rect(m.frame()):null,maskBounds:ok(m)?rect(m.bounds()):null,clips:!!l.masksToBounds(),presentation:ok(p)?{frame:rect(p.frame()),bounds:rect(p.bounds()),opacity:num(p.opacity())}:null,animations:safe(()=>arr(l.animationKeys()).map(k=>k.toString()))};}
 function geom(v,menu){return {id:id(v),class:cls(v),frame:rect(v.frame()),bounds:rect(v.bounds()),center:flat(v.center()),inMenu:safe(()=>rect(v.convertRect_toView_(v.bounds(),menu))),hidden:!!v.isHidden(),alpha:num(v.alpha()),layer:layer(v)};}
 // No strings from labels, actions, accessibility labels or clipboard are read.
 function visualLayers(l,d=0,budget={left:32}){
   if(!ok(l)||d>5||budget.left--<=0)return null;
   return {id:id(l),class:cls(l),frame:safe(()=>rect(l.frame())),bounds:safe(()=>rect(l.bounds())),position:safe(()=>flat(l.position())),anchor:safe(()=>flat(l.anchorPoint())),affine:safe(()=>flat(l.affineTransform())),hidden:safe(()=>!!l.isHidden()),opacity:safe(()=>num(l.opacity())),hasContents:safe(()=>ok(l.contents())),delegateClass:safe(()=>cls(l.delegate())),children:(safe(()=>arr(l.sublayers()))||[]).slice(0,16).map(x=>visualLayers(x,d+1,budget)).filter(Boolean)};
 }
 function localConstraints(v){return (safe(()=>arr(v.constraints()))||[]).slice(0,20).map(c=>({first:safe(()=>id(c.firstItem())),firstAttribute:safe(()=>Number(c.firstAttribute())),second:safe(()=>id(c.secondItem())),secondAttribute:safe(()=>Number(c.secondAttribute())),relation:safe(()=>Number(c.relation())),constant:safe(()=>num(c.constant())),priority:safe(()=>num(c.priority())),active:safe(()=>!!c.isActive())}));}
 function status(menu){const b=C.TSMMenuBridge;return b&&b.diagnosticForMenu_?safe(()=>b.diagnosticForMenu_(menu).toString()):null;}
 function snapshot(menu){
   const rows=[], cells=[]; let effect=null,content=null,glass=null,collection=null;
   function visit(v,d,cell,visible,page){
     if(d>11||rows.length>=180)return;
     const n=cls(v)||'', isCell=isa(v,'_UIEditMenuListViewCell'), isLabel=isa(v,'UILabel'), isImage=isa(v,'UIImageView');
     const isEffect=isa(v,'UIVisualEffectView'), isGlass=/TSMWhiteMaterialView|TheseusView/.test(n), isContent=/_UIVisualEffectContentView/.test(n), isCollection=isa(v,'_UIEditMenuCollectionView');
     const show=visible&&!v.isHidden()&&Number(v.alpha())>0.01&&!v.layer().isHidden()&&Number(v.layer().opacity())>0.01;
     if(isCell)cell=v;
     if(isa(v,'_UIEditMenuPageButton'))page=v;
     const row=Object.assign({depth:d,parent:id(v.superview()),effectiveVisible:show},geom(v,menu));
     if(cell||page){
       const target=cell||page;
       row.target=id(target);row.targetClass=cls(target);
       row.inTarget=safe(()=>rect(v.convertRect_toView_(v.bounds(),target)));
       row.transform=safe(()=>flat(v.transform()));row.contentMode=safe(()=>Number(v.contentMode()));row.clips=safe(()=>!!v.clipsToBounds());
       row.margins=safe(()=>flat(v.layoutMargins()));row.intrinsic=safe(()=>flat(v.intrinsicContentSize()));
       row.constraints=localConstraints(v);
       row.isControl=isa(v,'UIControl');row.isPaste=isa(v,'UIPasteControl')||/Paste/i.test(n);
       if(show&&(isCell||row.isPaste||row.isControl||v.subviews().count().toString()==='0'))row.visualLayers=visualLayers(v.layer());
       if(isCell){const cv=safe(()=>v.contentView());row.cellContent=ok(cv)?safe(()=>rect(cv.convertRect_toView_(cv.bounds(),v))):null;const col=safe(()=>v.superview());const ip=ok(col)&&col.indexPathForCell_?safe(()=>col.indexPathForCell_(v)):null;row.index=ok(ip)?safe(()=>[Number(ip.section()),Number(ip.item())]):null;}
     }
     if(isLabel){row.textAlignment=Number(v.textAlignment());row.numberOfLines=Number(v.numberOfLines());row.fontSize=safe(()=>num(v.font().pointSize()));row.intrinsic=safe(()=>flat(v.intrinsicContentSize()));row.textRect=safe(()=>rect(v.textRectForBounds_limitedToNumberOfLines_(v.bounds(),v.numberOfLines())));}
     if(cell&&(isLabel||isImage)){
       const r=safe(()=>rect(v.convertRect_toView_(v.bounds(),cell))), b=rect(cell.bounds());
       row.cell=id(cell);row.inCell=r;
       if(r&&b)row.centerDelta=[num(r[0]+r[2]/2-b[0]-b[2]/2),num(r[1]+r[3]/2-b[1]-b[3]/2)];
       if(isLabel&&row.textRect&&b){const tr=safe(()=>rect(v.convertRect_toView_(v.textRectForBounds_limitedToNumberOfLines_(v.bounds(),v.numberOfLines()),cell)));if(tr){row.textInCell=tr;row.textCenterDelta=[num(tr[0]+tr[2]/2-b[0]-b[2]/2),num(tr[1]+tr[3]/2-b[1]-b[3]/2)];}}
     }
     if(page&&isImage){const r=safe(()=>rect(v.convertRect_toView_(v.bounds(),page))),b=rect(page.bounds());if(r&&b){row.page=id(page);row.pageCenterDelta=[num(r[0]+r[2]/2-b[0]-b[2]/2),num(r[1]+r[3]/2-b[1]-b[3]/2)];}}
     if(isCollection){collection=row;row.offset=flat(v.contentOffset());row.contentSize=flat(v.contentSize());row.inset=flat(v.contentInset());row.adjustedInset=safe(()=>flat(v.adjustedContentInset()));row.dragging=!!v.isDragging();row.decelerating=!!v.isDecelerating();row.tracking=!!v.isTracking();row.layoutClass=cls(v.collectionViewLayout());row.layoutSize=safe(()=>flat(v.collectionViewLayout().collectionViewContentSize()));}
     if(isEffect&&d===1)effect=row;
     if(isContent&&d===2)content=row;
     if(isGlass)glass=row;
     if(/Paste/i.test(n)||isa(v,"UIPasteControl"))row.pasteControl=true;
     if(isCell)cells.push(row);
     rows.push(row);
     arr(v.subviews()).forEach(x=>visit(x,d+1,cell,show,page));
   }
   visit(menu,0,null,true);
   const win=menu.window(), s=status(menu), b=C.TSMMenuBridge;
   const source=b&&b.diagnosticSourceForMenu_?safe(()=>b.diagnosticSourceForMenu_(menu).toString()):null;
   const clipAnc=[];let p=menu.superview();for(let i=0;ok(p)&&i<6;i++,p=p.superview())clipAnc.push(geom(p,menu));
   const gap=b&&b.diagnosticGapForMenu_?safe(()=>b.diagnosticGapForMenu_(menu).toString()):null;
   return {menu:id(menu),class:cls(menu),status:s,source,gap,window:id(win),windowClass:cls(win),screenRect:safe(()=>rect(menu.convertRect_toView_(menu.bounds(),win))),effect:effect&&effect.inMenu,content:content&&content.inMenu,glass:glass&&glass.inMenu,collection:collection&&{rect:collection.inMenu,offset:collection.offset,size:collection.contentSize,layoutSize:collection.layoutSize},cellCount:cells.length,ancestors:clipAnc,rows};
 }
 function menus(){const app=C.UIApplication.sharedApplication(),wins=new Map(),out=[];const add=w=>wins.set(id(w),w);arr(app.windows()).forEach(add);arr(app.connectedScenes().allObjects()).forEach(s=>{if(isa(s,'UIWindowScene'))arr(s.windows()).forEach(add);});
   let visited=0;
   function walk(v,d){if(d>12||++visited>1600)return;if(isa(v,'_UIEditMenuListView')||/^_UIEditMenuListView(?:_|$)/.test(cls(v)||'')){out.push(v);return;}arr(v.subviews()).forEach(x=>walk(x,d+1));}
   wins.forEach(w=>{if(isa(w,'UITextEffectsWindow')||/TextEffectsWindow/.test(cls(w)||''))walk(w,0);});return out;
 }
 function sample(){
   if(busy||total>=600)return;busy=true;
   ObjC.schedule(ObjC.mainQueue,()=>{try{
     const ms=menus(),present=new Set();
     if(ms.length){active=true;until=Math.max(until,now()+500);}
     for(const m of ms){const s=snapshot(m);present.add(s.menu);const key=JSON.stringify(s);if(last.get(s.menu)!==key){last.set(s.menu,key);emit('FRAME',s);total++;}}
     for(const key of Array.from(last.keys()))if(!present.has(key)){last.delete(key);emit('MENU_REMOVED',{menu:key});}
     if(!ms.length&&active){active=false;emit('NO_MENU',{});}
   }catch(e){if(errors++<12)emit('ERROR',{message:String(e.stack||e)});}finally{busy=false;}});
 }
 // Only attach to the exact implementations of targeted classes. Never hook all UIView layout calls.
 function attach(c,n,sel,kind,allowInherited=false){
   const m=c&&c[sel];if(!m)return;
   if(!allowInherited&&!(c.$ownMethods||[]).includes(sel))return;
   const k=m.implementation.toString();if(seen.has(k))return;seen.add(k);
   try{const h=Interceptor.attach(m.implementation,{onEnter(args){
       if(now()-eventWindow>1000){eventWindow=now();eventCount=0;}
       until=Math.max(until,now()+1500);
       if(eventCount++>=100)return;
       // only pointer and selector here: never read UIKit off main thread.
       const data={class:n,selector:sel,object:args[0].toString()};
       if(sel==='- presentEditMenuWithConfiguration:' && safe(()=>!!C.NSThread.isMainThread())){
         data.anchor=safe(()=>{const interaction=new ObjC.Object(args[0]),config=new ObjC.Object(args[2]),view=interaction.view(),win=view.window(),point=config.sourcePoint();return {view:cls(view),window:cls(win),point:flat(point),pointInWindow:flat(view.convertPoint_toView_(point,win)),viewInWindow:rect(view.convertRect_toView_(view.bounds(),win)),windowBounds:rect(win.bounds())};});
       }
       emit(kind,data);
     }});hooks.push(h);emit('HOOK',{class:n,selector:sel});}catch(e){emit('HOOK_ERROR',{class:n,selector:sel,message:String(e)});}
 }
 const bridge=C.TSMMenuBridge;
 ['+ updateMenu:','+ removeMenu:'].forEach(s=>attach(bridge,'TSMMenuBridge',s,'BRIDGE',true));
 ['- presentEditMenuWithConfiguration:','- dismissMenu','- reloadVisibleMenu','- updateVisibleMenuPositionAnimated:'].forEach(s=>attach(C.UIEditMenuInteraction,'UIEditMenuInteraction',s,'INTERACTION',true));
 names.forEach(n=>['- layoutSubviews','- setFrame:','- setBounds:','- setCenter:','- setContentOffset:','- setContentOffset:animated:','- reloadData','- didMoveToWindow','- setAlpha:'].forEach(s=>attach(C[n],n,s,'LAYOUT')));
 // Dynamic QQ subclasses may own overrides; attach only discovered menu classes.
 ObjC.schedule(ObjC.mainQueue,()=>{try{Object.keys(C).filter(n=>/^_UIEditMenu(?:ListView|ContainerView|CollectionView|PageButton)(?:_|$)/.test(n)&&!names.includes(n)).slice(0,40).forEach(n=>['- layoutSubviews','- setFrame:','- setBounds:','- didMoveToWindow'].forEach(s=>attach(C[n],n,s,'LAYOUT')));}catch(e){emit('ERROR',{message:String(e)});}});
 ObjC.schedule(ObjC.mainQueue,()=>emit('READY',{version:'paste-gap-1.0',bridge:!!bridge,hook:bridge&&bridge.diagnosticStatus?safe(()=>bridge.diagnosticStatus().toString()):null,os:safe(()=>C.UIDevice.currentDevice().systemVersion().toString()),note:'read-only; paste geometry, constraints, layers, source point; no text captured'}));
 until=now()+1500;sample();
 const timer=setInterval(()=>{if(total>=600){clearInterval(timer);hooks.forEach(h=>h.detach());emit('LIMIT',{frames:total});return;}if(now()<until||active){sample();}else if(now()-lastIdle>500){lastIdle=now();sample();}},100);
}
