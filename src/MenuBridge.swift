import UIKit
import ObjectiveC
import QuartzCore

private func named(_ view: UIView, _ name: String) -> Bool {
    guard let cls = NSClassFromString(name) else { return false }
    return view.isKind(of: cls)
}
private func descendants(_ root: UIView, depth: Int = 7) -> [UIView] {
    guard depth > 0 else { return [] }
    return root.subviews.flatMap { [$0] + descendants($0, depth: depth - 1) }
}
private func visible(_ view: UIView) -> Bool {
    var next: UIView? = view
    while let v = next {
        if v.isHidden || v.alpha < 0.01 { return false }
        next = v.superview
    }
    return view is UIWindow || view.window != nil
}
@objc(TSMWhiteMaterialView) private final class WhiteMaterialView: UIView {}
@objc(TSMArrowCircleView) private final class ArrowCircleView: UIView {}
// The presentation point belongs to the interaction's view, not the effects window.
private final class MenuAnchor {
    weak var view: UIView?
    let point: CGPoint
    let time = ProcessInfo.processInfo.systemUptime
    init(_ view: UIView, _ point: CGPoint) { self.view = view; self.point = point }
}
// The visual changes are reversible; UIKit still owns the actual actions.
private final class LabelAppearance {
    let label: UILabel
    var originalColor: UIColor?
    var originalText: NSAttributedString?
    var appliedText: NSAttributedString?
    init(_ label: UILabel) {
        self.label = label; originalColor = label.textColor; originalText = label.attributedText
    }
    func apply() {
        if label.textColor != .white { originalColor = label.textColor }
        if label.attributedText != appliedText { originalText = label.attributedText }
        if let text = originalText, text.length > 0 {
            let white = NSMutableAttributedString(attributedString: text)
            white.addAttribute(.foregroundColor, value: UIColor.white, range: NSRange(location: 0, length: white.length))
            if label.attributedText != white { label.attributedText = white }
        }
        if label.textColor != .white { label.textColor = .white }
        appliedText = label.attributedText
    }
    func restore() {
        let shouldRestoreText = label.attributedText == appliedText && label.attributedText != originalText
        if label.textColor == .white { label.textColor = originalColor }
        if shouldRestoreText { label.attributedText = originalText }
    }
}
// Only a background decoration. The system owns every arrow glyph and action.
private final class ArrowAppearance {
    let button: UIView
    let circle = ArrowCircleView(frame: .zero)
    private var backgrounds: [(UIView, Float)] = []
    init(_ button: UIView) {
        self.button = button
        circle.isUserInteractionEnabled = false
        circle.accessibilityElementsHidden = true
        circle.isOpaque = false
    }
    func suppressBackgrounds(_ views: [UIView]) {
        backgrounds.removeAll { entry in
            if views.contains(where: { $0 === entry.0 }) { return false }
            entry.0.layer.opacity = entry.1; return true
        }
        for view in views {
            if !backgrounds.contains(where: { $0.0 === view }) {
                backgrounds.append((view, view.layer.opacity))
            } else if view.layer.opacity != 0,
                      let i = backgrounds.firstIndex(where: { $0.0 === view }) {
                backgrounds[i].1 = view.layer.opacity
            }
            if view.layer.opacity != 0 { view.layer.opacity = 0 }
        }
    }
    func restore() {
        circle.removeFromSuperview()
        for (view, opacity) in backgrounds where view.layer.opacity == 0 { view.layer.opacity = opacity }
        backgrounds.removeAll()
    }
}
private final class PasteAppearance {
    let control: UIPasteControl
    var originalColor: UIColor?
    private var attempted = false
    init(_ control: UIPasteControl) { self.control = control; originalColor = control.configuration.baseForegroundColor }
    func apply() {
        let config = control.configuration
        // Some UIKit versions render paste into a slot; avoid endless relayout
        // if the read-only configuration accessor returns a non-live object.
        guard !attempted else { return }
        attempted = true
        if config.baseForegroundColor != .white {
            originalColor = config.baseForegroundColor
            config.baseForegroundColor = .white
            control.setNeedsLayout()
        }
    }
    func restore() {
        if control.configuration.baseForegroundColor == .white { control.configuration.baseForegroundColor = originalColor; control.setNeedsLayout() }
    }
}
private final class MenuState: NSObject {
    weak var menu: UIView?
    weak var effect: UIVisualEffectView?
    weak var backdrop: UIView?
    weak var collection: UIView?
    weak var nativeShadow: UIView?
    let material = WhiteMaterialView(frame: .zero)
    let shadow = UIView(frame: .zero)
    private let capsule = CAShapeLayer()
    private var previousMask: CALayer?
    private var lastMaskRect = CGRect.null
    private var lastMaskBounds = CGRect.null
    var previousShadowOpacity: Float = 1
    var previousBackdropOpacity: Float = 1
    var previousBackdropHidden = false
    var separators: [(UIView, Float)] = []
    var centered: [(UIView, CGAffineTransform, CGAffineTransform)] = []
    var closing = false
    var closeEpoch: UInt64 = 0
    var closeWork: DispatchWorkItem?
    var lastShadowRect = CGRect.null
    var anchor: MenuAnchor?
    private var baseCenter: CGPoint?
    private var appliedCenter: CGPoint?
    private var gapStatus = "no-anchor"
    var diagnosticGap: String { gapStatus }
    private static let heightScale: CGFloat = 0.83
    private var labels: [ObjectIdentifier: LabelAppearance] = [:]
    private var arrows: [ObjectIdentifier: ArrowAppearance] = [:]
    private var pasteControls: [ObjectIdentifier: PasteAppearance] = [:]
    private var dark: Bool {
        // Prefer the app's presentation context over the separate effects window.
        if let style = anchor?.view?.traitCollection.userInterfaceStyle, style != .unspecified { return style == .dark }
        return menu?.traitCollection.userInterfaceStyle == .dark
    }
    private func restoreForeground() {
        labels.values.forEach { $0.restore() }; labels.removeAll()
        pasteControls.values.forEach { $0.restore() }; pasteControls.removeAll()
    }
    private func updateForeground(in content: UIView, dark: Bool) {
        guard dark else { restoreForeground(); return }
        for key in Array(labels.keys) where labels[key]?.label.isDescendant(of: content) != true {
            labels.removeValue(forKey: key)?.restore()
        }
        for key in Array(pasteControls.keys) where pasteControls[key]?.control.isDescendant(of: content) != true {
            pasteControls.removeValue(forKey: key)?.restore()
        }
        let pageButtons = content.subviews.filter { named($0,"_UIEditMenuPageButton") }
        for view in descendants(content, depth: 12) {
            guard !pageButtons.contains(where: { view === $0 || view.isDescendant(of: $0) }) else { continue }
            if let label = view as? UILabel {
                let key = ObjectIdentifier(label)
                let entry = labels[key] ?? LabelAppearance(label)
                labels[key] = entry; entry.apply()
            } else if let paste = view as? UIPasteControl {
                let key = ObjectIdentifier(paste)
                let entry = pasteControls[key] ?? PasteAppearance(paste)
                pasteControls[key] = entry; entry.apply()
            }
        }
    }
    private func updateArrows(in content: UIView, dark: Bool, frame: CGRect) {
        let buttons = content.subviews.filter { named($0,"_UIEditMenuPageButton") }
        let ids = Set(buttons.map { ObjectIdentifier($0) })
        for key in Array(arrows.keys) where !ids.contains(key) { arrows.removeValue(forKey: key)?.restore() }
        for button in buttons {
            let key = ObjectIdentifier(button)
            let arrow = arrows[key] ?? ArrowAppearance(button)
            arrows[key] = arrow
            let circle = arrow.circle
            guard !button.isHidden, button.alpha > 0.01,
                  let glyph = button.subviews.compactMap({ $0 as? UIImageView }).first(where: {
                      !$0.isHidden && $0.alpha > 0.01 && $0.bounds.width > 0 && $0.bounds.height > 0 &&
                      ($0.image != nil || $0.layer.contents != nil)
                  }) else { arrow.restore(); continue }
            let r = button.convert(button.bounds, to: content)
            let glyphRect = glyph.convert(drawnRect(glyph), to: content)
            let center = CGPoint(x: glyphRect.midX, y: frame.midY)
            // The native glyph remains a real UIImageView; only its vertical position changes.
            let diameter = min(34, r.width - 4, frame.height - 4,
                               2 * min(center.x-frame.minX, frame.maxX-center.x) - 2)
            guard diameter >= max(12, glyphRect.width + 4, glyphRect.height + 4),
                  r.insetBy(dx: 0, dy: -0.5).contains(center) else { arrow.restore(); continue }
            // iOS 17.1.1 trace: the native image is a direct sibling of the
            // system background and a thin separator. Hide only those siblings.
            let backgrounds = button.subviews.filter { view in
                guard view !== glyph, view !== circle else { return false }
                if named(view,"_UISystemBackgroundView") { return true }
                return view is UIVisualEffectView && view.bounds.width <= 1 && view.bounds.height > 10
            }
            arrow.suppressBackgrounds(backgrounds)
            if circle.superview !== button { button.insertSubview(circle, belowSubview: glyph) }
            else if let i = button.subviews.firstIndex(of: circle),
                    let j = button.subviews.firstIndex(of: glyph), i > j {
                button.insertSubview(circle, belowSubview: glyph)
            }
            translate(glyph, dx: 0, dy: frame.midY-glyphRect.midY, host: content)
            let local = button.convert(center, from: content)
            let target = CGRect(x:local.x-diameter/2,y:local.y-diameter/2,width:diameter,height:diameter)
            if circle.frame != target { circle.frame = target }
            circle.isHidden = false
            circle.alpha = 1 // inherits the native button's fade automatically
            circle.layer.cornerRadius = diameter/2
            circle.backgroundColor = UIColor(white: dark ? 0.28 : 0.87, alpha: 1)
        }
    }
    private func restoreArrows() {
        arrows.values.forEach { $0.restore() }; arrows.removeAll()
    }

    // Move the whole native view (including hit targets), not just its background.
    // Recompute from UIKit's unmodified center so layout passes cannot accumulate offsets.
    private func applyGap() {
        guard let menu = menu, let host = menu.superview, let window = menu.window else { return }
        let current = menu.center
        let base = current == appliedCenter ? (baseCenter ?? current) : current
        let undo = host.convert(base, to:window).y - host.convert(current, to:window).y
        let rect = menu.convert(menu.bounds,to:window).offsetBy(dx:0,dy:undo)
        var dy: CGFloat = 0
        gapStatus = "no-anchor"
        if let anchor = anchor, let view = anchor.view, let source = view.window,
           source.screen === window.screen, rect.height >= 30, rect.height <= 120 {
            let point = source.convert(view.convert(anchor.point,to:source),to:window)
            let safe = window.bounds.inset(by:window.safeAreaInsets).insetBy(dx:0,dy:8)
            if point.y.isFinite, point.x.isFinite, safe.height > 0, window.bounds.insetBy(dx:-1,dy:-1).contains(point) {
                if rect.maxY <= point.y + 1 {
                    dy = -min(10,max(0,rect.minY-safe.minY))
                    gapStatus = "above: \(dy)pt"
                } else if rect.minY >= point.y - 1 {
                    dy = min(10,max(0,safe.maxY-rect.maxY))
                    gapStatus = "below: +\(dy)pt"
                } else { gapStatus = "anchor-overlap: unchanged" }
            }
        }
        let from = host.convert(CGPoint.zero,from:window)
        let to = host.convert(CGPoint(x:0,y:dy),from:window)
        let target = CGPoint(x:base.x+to.x-from.x,y:base.y+to.y-from.y)
        baseCenter = base; appliedCenter = target
        if abs(current.x-target.x) > 0.05 || abs(current.y-target.y) > 0.05 { menu.center = target }
    }
    private func restoreGap() {
        if let menu = menu, let base = baseCenter, menu.center == appliedCenter, menu.center != base { menu.center = base }
        baseCenter = nil; appliedCenter = nil
    }
    // UIKit's clipping wrapper is the page viewport, not the full collection bounds.
    private func nativeMaterialRect() -> CGRect {
        guard let effect = effect, let collection = collection else { return .zero }
        let content = effect.contentView
        let bounds = content.bounds
        var rect = collection.convert(collection.bounds, to: content)
        var ancestor = collection.superview
        while let v = ancestor, v !== content {
            if v.clipsToBounds { rect = rect.intersection(v.convert(v.bounds, to: content)) }
            ancestor = v.superview
        }
        rect = rect.intersection(bounds)
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { return bounds }
        // Buttons slide/fade at the page edges. Use their opacity to interpolate
        // the extension, retaining the actual native hit areas and layout.
        let viewport = rect
        for button in content.subviews where named(button, "_UIEditMenuPageButton") && !button.isHidden {
            let a = min(1, max(0, button.alpha))
            guard a > 0.01 else { continue }
            let r = button.convert(button.bounds, to: content).intersection(bounds)
            guard !r.isNull, r.width > 0 else { continue }
            let left = min(rect.minX, viewport.minX - max(0, viewport.minX-r.minX)*a)
            let right = max(rect.maxX, viewport.maxX + max(0, r.maxX-viewport.maxX)*a)
            rect = CGRect(x:left,y:bounds.minY,width:right-left,height:bounds.height)
        }
        // Small horizontal breathing room for the pill, bounded by native host.
        let padded = rect.insetBy(dx: -6, dy: 0).intersection(bounds)
        let scale = max(1, effect.window?.screen.scale ?? UIScreen.main.scale)
        let left = floor(padded.minX * scale)/scale
        let right = ceil(padded.maxX * scale)/scale
        let aligned = CGRect(x:left,y:padded.minY,width:right-left,height:padded.height).intersection(bounds)
        return aligned.width >= 44 ? aligned : bounds
    }
    // Keep native vertical baselines (including the asynchronously rendered paste
    // slot). The capsule follows the native row, instead of moving a 40pt bitmap.
    // A 48pt menu therefore always paints 39.84pt, on either page.
    private var rowCenter: CGFloat?
    private var rowHeight: CGFloat?
    private func materialRect() -> CGRect {
        let rect = nativeMaterialRect()
        guard let effect = effect, let collection = collection, rect.height > 0 else { return rect }
        let content = effect.contentView
        let height = rect.height * Self.heightScale
        if rowHeight != rect.height { rowCenter = nil; rowHeight = rect.height }
        // Stable native label center, without waiting for a paste slot to render.
        // Restrict candidates to on-page cells; the center is cached for this height.
        if rowCenter == nil {
            let centers = collection.subviews.filter { named($0,"_UIEditMenuListViewCell") && visible($0) }
                .flatMap { payload(($0 as? UICollectionViewCell)?.contentView ?? $0) }
                .compactMap { leaf -> CGFloat? in
                    guard leaf is UILabel else { return nil }
                    let r = leaf.convert(drawnRect(leaf), to: content)
                    guard !r.isEmpty, r.intersects(rect), r.midY.isFinite else { return nil }
                    return r.midY
                }.sorted()
            if !centers.isEmpty { rowCenter = centers[centers.count/2] }
        }
        // Observed iOS 17.1.1 native 48pt row baseline: center Y=20pt.
        // Use this only as an initialization fallback before labels are available.
        let fallback = rect.midY - (abs(rect.height-48) < 0.5 ? 4 : 0)
        let mid = min(rect.maxY-height/2, max(rect.minY+height/2, rowCenter ?? fallback))
        return CGRect(x:rect.minX,y:mid-height/2,width:rect.width,height:height)
    }
    private var centering = false
    // Measure all visible visual leaves, including labels nested in native paste
    // controls. Never translate the actual UIControl or its touch target.
    private func payload(_ root: UIView) -> [UIView] {
        guard !root.isHidden, root.alpha > 0.01, root.layer.opacity > 0.01,
              root.bounds.width > 0, root.bounds.height > 0 else { return [] }
        if root is UILabel { return [root] }
        if let image = root as? UIImageView { return image.image == nil ? [] : [image] }
        if named(root,"_UISystemBackgroundView") || named(root,"_UIVisualEffectBackdropView") || named(root,"_UIEditMenuListSeparatorView") { return [] }
        return root.subviews.flatMap { payload($0) }
    }
    private func drawnRect(_ leaf: UIView) -> CGRect {
        if let label = leaf as? UILabel {
            let rect = label.textRect(forBounds: label.bounds, limitedToNumberOfLines: label.numberOfLines)
            if !rect.isEmpty, !rect.isNull, !rect.isInfinite { return rect }
        }
        if let v = leaf as? UIImageView, let image = v.image,
           image.size.width > 0, image.size.height > 0, v.contentMode == .scaleAspectFit {
            let scale = min(v.bounds.width/image.size.width,v.bounds.height/image.size.height)
            let size = CGSize(width:image.size.width*scale,height:image.size.height*scale)
            return CGRect(x:v.bounds.midX-size.width/2,y:v.bounds.midY-size.height/2,width:size.width,height:size.height)
        }
        return leaf.bounds
    }
    private func translate(_ moving: UIView, dx: CGFloat, dy: CGFloat, host: UIView) {
        guard let parent = moving.superview else { return }
        let oldIndex = centered.firstIndex { $0.0 === moving }
        let current = moving.transform
        let base = oldIndex.flatMap { current == centered[$0].2 ? centered[$0].1 : nil } ?? current
        let origin = parent.convert(CGPoint.zero, from:host)
        let destination = parent.convert(CGPoint(x:dx,y:dy), from:host)
        let corrected = CGAffineTransform(a:current.a,b:current.b,c:current.c,d:current.d,
                                          tx:current.tx+destination.x-origin.x,ty:current.ty+destination.y-origin.y)
        if max(abs(dx),abs(dy)) > 0.05 { moving.transform = corrected }
        let applied = moving.transform
        if let i = oldIndex { centered[i] = (moving,base,applied) }
        else if applied != base { centered.append((moving,base,applied)) }
    }
    private func centerItem(_ item: UIView) {
        guard let effect = effect, item.isDescendant(of:effect.contentView),
              !item.isHidden, item.alpha > 0.01 else { return }
        guard named(item,"_UIEditMenuListViewCell") else { return }
        let host = (item as? UICollectionViewCell)?.contentView ?? item
        // Preserve the native slot's position, including its internal baseline.
        // No transform is applied to a slot even if its hidden UILabel loads first.
        let hasSlot = descendants(host, depth: 5).contains { named($0,"_UISlotView") }
        if hasSlot {
            centered.removeAll { entry in
                guard entry.0.isDescendant(of: host) else { return false }
                if entry.0.transform == entry.2 { entry.0.transform = entry.1 }
                return true
            }
            return
        }
        let leaves = payload(host)
        guard !leaves.isEmpty else { return }
        let actual = leaves.reduce(CGRect.null) { $0.union($1.convert(drawnRect($1),to:item)) }
        guard !actual.isNull, !actual.isInfinite, actual.width > 0, actual.width <= item.bounds.width + 0.5 else { return }
        let dx = item.bounds.midX - actual.midX
        guard dx.isFinite, abs(dx) <= 24 else { return }
        // Keep existing horizontal centering only. Do not alter the native baseline.
        for leaf in leaves where leaf !== item && leaf !== host { translate(leaf,dx:dx,dy:0,host:item) }
    }
    func centerAfterLayout(_ item: UIView) {
        guard alive, !closing, !centering else { return }
        centering = true
        CATransaction.begin(); CATransaction.setDisableActions(true)
        var target: UIView? = item
        while let v = target, v !== menu {
            if named(v,"_UIEditMenuListViewCell") || named(v,"_UIEditMenuPageButton") { centerItem(v); break }
            target = v.superview
        }
        CATransaction.commit(); centering = false
    }
    func centerContent() {
        guard !centering, let effect = effect, let collection = collection else { return }
        centering = true; defer { centering = false }
        centered.removeAll { entry in
            if entry.0.isDescendant(of: effect.contentView) { return false }
            if entry.0.transform == entry.2 { entry.0.transform = entry.1 }
            return true
        }
        for cell in collection.subviews where named(cell,"_UIEditMenuListViewCell") { centerItem(cell) }
    }
    func beginClose() {
        guard alive, !closing else { return }
        closing = true; status = "closing"; closeEpoch &+= 1
        let epoch = closeEpoch
        // Model alpha reaches zero at the START of UIKit's dismissal animation.
        // Keep the current adaptive material and mask until the presentation actually fades.
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.alive, self.closing, self.closeEpoch == epoch else { return }
            if let menu = self.menu { MenuBridge.remove(menu) } else { self.stop() }
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline:.now()+0.45,execute:work)
    }
    func reopen() { guard closing else { return }; closing = false; closeEpoch &+= 1; closeWork?.cancel(); closeWork = nil }

    var status = "initializing"
    var alive = true
    var observer: NSObjectProtocol?

    init(menu: UIView, effect: UIVisualEffectView, backdrop: UIView, collection: UIView, anchor: MenuAnchor?) {
        super.init()
        self.menu = menu; self.effect = effect; self.backdrop = backdrop; self.collection = collection; self.anchor = anchor
        nativeShadow = menu.subviews.first { named($0, "_UIDiffuseShadowView") }
        material.isUserInteractionEnabled = false
        material.accessibilityElementsHidden = true
        material.isOpaque = false
        // Only the background is translucent, never the text/action container.
        shadow.isUserInteractionEnabled = false
        shadow.accessibilityElementsHidden = true
        shadow.layer.shadowColor = UIColor.black.cgColor
        shadow.layer.shadowOpacity = 0.20
        shadow.layer.shadowRadius = 13
        shadow.layer.shadowOffset = CGSize(width: 0, height: 5)
        shadow.isHidden = true
        previousBackdropOpacity = backdrop.layer.opacity
        previousBackdropHidden = backdrop.layer.isHidden
        previousShadowOpacity = nativeShadow?.layer.opacity ?? 1
        menu.insertSubview(shadow, belowSubview: effect)
        effect.contentView.insertSubview(material, at: 0)
        applyAppearance()
        observer = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in self?.stop() }
    }
    func refresh() {
        guard !closing else { return }
        guard alive, let menu = menu, let effect = effect, visible(menu),
              effect.superview === menu, backdrop?.superview === effect,
              collection?.isDescendant(of: effect.contentView) == true else { stop(); return }
        applyAppearance()
    }
    // Restore the 024 capsule clipping for the entire visual effect subtree.
    // Keep native controls at their original size and use the 025 visual rect.
    private func applyCapsule(_ frame: CGRect) {
        guard alive, let effect = effect, !frame.isEmpty, !frame.isNull else { return }
        let bounds = effect.bounds
        let rect = effect.contentView.convert(frame, to: effect)
        guard !rect.isEmpty, !rect.isNull, !rect.isInfinite else { return }
        if lastMaskRect != rect || lastMaskBounds != bounds || capsule.path == nil {
            capsule.frame = bounds
            capsule.fillColor = UIColor.black.cgColor
            capsule.path = UIBezierPath(roundedRect: rect.offsetBy(dx: -bounds.minX, dy: -bounds.minY),
                                        cornerRadius: min(rect.width, rect.height)/2).cgPath
            lastMaskRect = rect; lastMaskBounds = bounds
        }
        // UIKit may replace the mask during native layout. Reinstall ours and
        // remember the current native mask for reversible teardown.
        if effect.layer.mask !== capsule {
            previousMask = effect.layer.mask
            effect.layer.mask = capsule
        }
    }
    func applyAppearance() {
        guard alive, let effect = effect, let menu = menu else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        applyGap()
        let isDark = dark
        let background = isDark ? UIColor(white: 0.16, alpha: 0.80) : UIColor.white.withAlphaComponent(0.80)
        if material.backgroundColor != background { material.backgroundColor = background }
        status = isDark ? "dark-80" : "white-80"
        updateForeground(in: effect.contentView, dark: isDark)
        centerContent()
        let frame = materialRect()
        // Clip visible system backgrounds and native content to the same capsule.
        applyCapsule(frame)
        if material.superview !== effect.contentView { effect.contentView.insertSubview(material, at: 0) }
        if material.frame != frame { material.frame = frame }
        material.layer.cornerRadius = min(frame.width,frame.height)/2
        material.layer.masksToBounds = true
        backdrop?.layer.opacity = 0
        backdrop?.layer.isHidden = true
        nativeShadow?.layer.opacity = 0
        let rect = effect.contentView.convert(frame,to:menu)
        if shadow.frame != rect { shadow.frame = rect }
        if lastShadowRect != rect {
            shadow.layer.shadowPath = UIBezierPath(roundedRect: shadow.bounds, cornerRadius: min(shadow.bounds.width,shadow.bounds.height)/2).cgPath
            lastShadowRect = rect
        }
        shadow.isHidden = false
        updateArrows(in: effect.contentView, dark: isDark, frame: frame)
        if let collection = collection {
            separators.removeAll { entry in
                if entry.0.isDescendant(of: effect.contentView) { return false }
                entry.0.layer.opacity = entry.1
                return true
            }
            let hiddenViews = collection.subviews.filter { named($0,"_UIEditMenuListSeparatorView") }
            // Hide collection separators only; page backgrounds are handled in updateArrows.
            for v in hiddenViews {
                if !separators.contains(where: { $0.0 === v }) { separators.append((v,v.layer.opacity)) }
                v.layer.opacity = 0
            }
        }
    }
    func stop() {
        guard alive else { return }; alive = false
        status = "stopped"
        closeWork?.cancel(); closeWork = nil
        if let observer = observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        restoreGap()
        restoreForeground()
        restoreArrows()
        if effect?.layer.mask === capsule { effect?.layer.mask = previousMask }
        previousMask = nil
        backdrop?.layer.opacity = previousBackdropOpacity
        backdrop?.layer.isHidden = previousBackdropHidden
        nativeShadow?.layer.opacity = previousShadowOpacity
        for (v,opacity) in separators { v.layer.opacity = opacity }
        for (v,base,applied) in centered where v.transform == applied { v.transform = base }
        centered.removeAll()
        separators.removeAll()
        material.removeFromSuperview(); shadow.removeFromSuperview()
        CATransaction.commit()
    }
    deinit { if let observer = observer { NotificationCenter.default.removeObserver(observer) } }
}
@objc(TSMMenuBridge) final class MenuBridge: NSObject {
    private static var key: UInt8 = 0
    private static var reasonKey: UInt8 = 0
    private static var hookStatus = "not-installed"
    private static var latestAnchor: MenuAnchor?
    @objc(recordPresentationForView:point:) static func recordPresentation(for view: UIView, point: CGPoint) {
        guard Thread.isMainThread else { return }
        latestAnchor = MenuAnchor(view,point)
    }
    @objc(diagnosticGapForMenu:) static func diagnosticGap(for menu: UIView) -> String {
        (objc_getAssociatedObject(menu,&key) as? MenuState)?.diagnosticGap ?? "no-state"
    }
    private static func recentAnchor(_ window: UIWindow) -> MenuAnchor? {
        guard let a = latestAnchor, ProcessInfo.processInfo.systemUptime - a.time < 2,
              let source = a.view?.window, source.screen === window.screen else { return nil }
        return a
    }
    @objc(recordHookStatus:) static func recordHookStatus(_ status: String) { hookStatus = status }
    @objc(diagnosticStatus) static func diagnosticStatus() -> String { hookStatus }
    @objc(diagnosticForMenu:) static func diagnosticForMenu(_ menu: UIView) -> String {
        (objc_getAssociatedObject(menu,&key) as? MenuState)?.status ??
            (objc_getAssociatedObject(menu,&reasonKey) as? String ?? "not-seen")
    }
    @objc(diagnosticSourceForMenu:) static func diagnosticSourceForMenu(_ menu: UIView) -> String {
        "not-needed: adaptive-80"
    }
    private static func reject(_ menu: UIView, _ reason: String) {
        remove(menu)
        objc_setAssociatedObject(menu,&reasonKey,reason,.OBJC_ASSOCIATION_COPY_NONATOMIC)
    }
    @objc(updateMenu:) static func update(_ menu: UIView) {
        guard Thread.isMainThread else { return }
        // The app switcher temporarily makes the application inactive. Preserve
        // an installed appearance instead of tearing it down during that transition.
        // Actual background entry still performs the existing reversible cleanup;
        // activation observers in Tweak.m then rediscover and rebuild the state.
        guard UIApplication.shared.applicationState == .active else { return }
        guard let window = menu.window else { reject(menu,"not-visible"); return }
        guard visible(menu) else {
            // A model-alpha zero update can precede installation of the native animation.
            if let state = objc_getAssociatedObject(menu,&key) as? MenuState, state.alive, !menu.isHidden {
                state.beginClose(); return
            }
            reject(menu,"not-visible"); return
        }
        guard named(window,"UITextEffectsWindow") else { reject(menu,"unsupported-window"); return }
        guard !UIAccessibility.isReduceTransparencyEnabled else { reject(menu,"reduce-transparency"); return }
        guard let effect = menu.subviews.compactMap({ $0 as? UIVisualEffectView }).first(where: { $0.effect is UIBlurEffect }) else { reject(menu,"effect-not-found"); return }
        guard let backdrop = effect.subviews.first(where: { named($0,"_UIVisualEffectBackdropView") }) else { reject(menu,"backdrop-not-found"); return }
        guard let collection = descendants(effect.contentView).first(where: { named($0,"_UIEditMenuCollectionView") }) else { reject(menu,"collection-not-found"); return }
        guard effect.bounds.width >= 44, effect.bounds.height >= 30, effect.bounds.height <= 100 else { reject(menu,"waiting-for-geometry"); return }
        if let existing = objc_getAssociatedObject(menu,&key) as? MenuState {
            if existing.alive && existing.effect === effect && existing.backdrop === backdrop && existing.collection === collection {
                if let a = recentAnchor(window) { existing.anchor = a }
                existing.reopen(); existing.refresh(); return
            }
            remove(menu)
        }
        let state = MenuState(menu: menu,effect: effect,backdrop: backdrop,collection: collection,anchor: recentAnchor(window))
        objc_setAssociatedObject(menu,&key,state,.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    @objc(centerLayoutForView:menu:) static func centerLayout(for view: UIView, menu: UIView) {
        guard Thread.isMainThread else { return }
        (objc_getAssociatedObject(menu,&key) as? MenuState)?.centerAfterLayout(view)
    }
    @objc(removeMenu:) static func remove(_ menu: UIView) {
        guard Thread.isMainThread else { return }
        (objc_getAssociatedObject(menu,&key) as? MenuState)?.stop()
        objc_setAssociatedObject(menu,&key,nil,.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(menu,&reasonKey,"removed",.OBJC_ASSOCIATION_COPY_NONATOMIC)
    }
}
