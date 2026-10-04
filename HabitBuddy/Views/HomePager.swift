import SwiftUI
import UIKit

/// The bottom bar's six pages side by side: Classic, Compact, Month, the streak views, Dashboard and Explore. A page
/// follows the finger as it's swiped, stretches against the first and last page, and lets go on a bouncy spring that
/// carries the swipe's speed. The spring runs on the display's frame clock, so where the pages are is always known,
/// a swipe can catch them mid-flight, and the bars and every item can follow it frame by frame.
@MainActor @Observable final class HomePager {
    static let count = 6
    /// A tap to a page further than the next draws that page beside the current one for the slide.
    struct Bridge: Equatable {
        let from: Int, to: Int
        var direction: Int { to > from ? 1 : -1 }
    }
    /// Where the pages are, in page widths: a page's slot minus this is how far it is from the screen.
    private(set) var position: CGFloat = 0
    /// Where the items at each depth of a page have got to: each follows `position` on its own spring, the deeper the
    /// looser, so lower items trail the page and catch up with a little wobble. Depth 0 moves with the page.
    private(set) var trail = Array(repeating: CGFloat(0), count: HomePager.depths)
    /// The page being swiped from, or the one a swipe or tap is heading to.
    private(set) var destination = 0
    /// The page the pager is resting on; nil while it moves.
    private(set) var rest: Int? = 0
    /// The pages kept built: the one shown and its neighbours, so a swipe starts without building one.
    private(set) var pages = [0]
    private(set) var bridge: Bridge?
    /// Counts swipes that land on another page, for the haptic.
    private(set) var swipes = 0
    var width: CGFloat = 390
    static let depths = 8
    @ObservationIgnored var reduceMotion = false
    @ObservationIgnored private var velocity: CGFloat = 0
    @ObservationIgnored private var trailVelocity = Array(repeating: CGFloat(0), count: HomePager.depths)
    @ObservationIgnored private var goal: CGFloat = 0
    /// Whether the page spring is running, and whether a finger is on the pages.
    @ObservationIgnored private var settling = false
    @ObservationIgnored private var dragging = false
    /// A tap's slide starts from rest, so it gets a little more damping than a swipe to bounce about as much.
    @ObservationIgnored private var tapped = false
    @ObservationIgnored private var start: CGFloat = 0
    @ObservationIgnored private var bounds: ClosedRange<CGFloat> = 0...0
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var lastFrame: CFTimeInterval = 0
    @ObservationIgnored private var preparing: Task<Void, Never>?

    var bridging: Bool { bridge != nil }
    /// Where a page is drawn; a bridged page takes the slot beside the one it's reached from.
    func slot(_ stop: Int) -> CGFloat {
        if let bridge, stop == bridge.to { return CGFloat(bridge.from + bridge.direction) }
        return CGFloat(stop)
    }
    func offset(_ stop: Int) -> CGFloat { (slot(stop) - position) * width }
    /// How far an item at `depth` is behind its page.
    func lag(_ depth: Int) -> CGFloat { (position - trail[min(max(depth, 0), Self.depths - 1)]) * width }
    /// The two pages the pager is between and how far it is from the first to the second, below 0 or above 1 while it
    /// stretches past the first or last page. The bars follow this.
    var segment: (from: Int, to: Int, progress: CGFloat) {
        if let bridge { return (bridge.from, bridge.to, (position - CGFloat(bridge.from)) * CGFloat(bridge.direction)) }
        let lower = min(max(Int(position.rounded(.down)), 0), Self.count - 2)
        return (lower, lower + 1, position - CGFloat(lower))
    }
    /// Between two habit layouts, which share the category filter, routines and empty state, so those stay put.
    var betweenLayouts: Bool {
        guard position >= 0, position <= 3 else { return false }
        guard let bridge else { return true }
        return bridge.from <= 3 && bridge.to <= 3
    }

    func begin() {
        if let bridge { move(by: CGFloat(bridge.to) - CGFloat(bridge.direction) * (1 - segment.progress) - position); self.bridge = nil }
        settling = false; dragging = true
        start = position
        let near = Int(position.rounded())
        bounds = CGFloat(max(0, near - 1))...CGFloat(min(Self.count - 1, near + 1))
        rest = nil
        include(Array(max(0, near - 1)...min(Self.count - 1, near + 1)))
        run()
    }
    func drag(_ translation: CGFloat) { position = band(start - translation / width) }
    /// Lets go: a flick goes on to the next page in its direction, a slow release to the nearer one.
    func end(velocity: CGFloat) {
        dragging = false
        var speed = -velocity / width
        let p = position
        var target = abs(speed) > 0.35 ? (speed > 0 ? (p + 0.0001).rounded(.down) + 1 : (p - 0.0001).rounded(.up) - 1) : p.rounded()
        target = min(max(target, bounds.lowerBound), bounds.upperBound)
        // Past the first or last page the finger moves the page less, and so does the speed it lets go with.
        let past = max(bounds.lowerBound - p, p - bounds.upperBound, 0)
        if past > 0 { speed *= 0.55 * (1 - past) * (1 - past) }
        if Int(target) != Int(start.rounded()) { swipes += 1 }
        tapped = false
        settle(to: Int(target), velocity: speed)
    }
    /// Moves to a page: a neighbour slides over, a page further away slides in beside this one.
    func go(to stop: Int, animated: Bool) {
        guard (0..<Self.count).contains(stop) else { return }
        guard animated, !reduceMotion || abs(stop - destination) <= 1 else {
            halt(); settling = false; dragging = false; bridge = nil; velocity = 0
            position = CGFloat(stop); destination = stop; rest = stop
            trail = Array(repeating: position, count: Self.depths); trailVelocity = Array(repeating: 0, count: Self.depths)
            include([stop]); prepare(stop)
            return
        }
        guard stop != destination else { return }
        if bridge != nil { begin(); dragging = false }
        tapped = true
        let near = Int(position.rounded())
        if abs(stop - near) <= 1 { settle(to: stop, velocity: velocity); return }
        let bridge = Bridge(from: near, to: stop)
        self.bridge = bridge
        pages = [near, stop].sorted()
        destination = stop; goal = CGFloat(near + bridge.direction); rest = nil; settling = true
        run()
    }

    private func settle(to stop: Int, velocity: CGFloat) {
        destination = stop; goal = CGFloat(stop); self.velocity = velocity; rest = nil; settling = true
        include([stop])
        run()
    }
    /// Moves the pages and everything trailing them together, when a bridged page takes its own slot.
    private func move(by delta: CGFloat) {
        position += delta; goal += delta
        trail = trail.map { $0 + delta }
    }
    /// iOS's rubber band: past the pages a swipe can reach, the page moves less the further it's pulled.
    private func band(_ x: CGFloat) -> CGFloat {
        if x < bounds.lowerBound { return bounds.lowerBound - (1 - 1 / ((bounds.lowerBound - x) * 0.55 + 1)) }
        if x > bounds.upperBound { return bounds.upperBound + (1 - 1 / ((x - bounds.upperBound) * 0.55 + 1)) }
        return x
    }
    private var spring: Spring {
        reduceMotion ? Spring(response: 0.38, dampingRatio: 1) : Spring(response: 0.5, dampingRatio: tapped ? 0.76 : 0.68)
    }
    private func follow(_ depth: Int) -> Spring { Spring(response: 0.1 + 0.035 * Double(depth), dampingRatio: 0.62) }
    private func run() {
        guard link == nil else { return }
        lastFrame = 0
        let link = CADisplayLink(target: FrameTarget { [weak self] link in
            guard let self else { link.invalidate(); return }
            self.tick(link)
        }, selector: #selector(FrameTarget.fire))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }
    private func halt() { link?.invalidate(); link = nil }
    /// One frame: the page spring, then each depth's follower toward where the page now is.
    private func tick(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        let step = min(max(lastFrame == 0 ? now - link.timestamp : now - lastFrame, 0.001), 1 / 30)
        lastFrame = now
        if settling {
            var p = position, v = velocity
            spring.update(value: &p, velocity: &v, target: goal, deltaTime: step)
            velocity = v
            if abs(p - goal) < 0.0008, abs(v) < 0.02 { arrive() } else { position = p }
        }
        var next = trail, still = true
        next[0] = position
        for depth in 1..<Self.depths {
            if reduceMotion { next[depth] = position; continue }
            var value = next[depth], speed = trailVelocity[depth]
            follow(depth).update(value: &value, velocity: &speed, target: position, deltaTime: step)
            if abs(value - position) < 0.00025, abs(speed) < 0.005 { value = position; speed = 0 } else { still = false }
            next[depth] = value; trailVelocity[depth] = speed
        }
        if next != trail { trail = next }
        if still, !settling, !dragging { halt() }
    }
    private func arrive() {
        settling = false
        if let bridge { move(by: CGFloat(bridge.to) - goal); self.bridge = nil }
        position = goal
        velocity = 0
        rest = destination
        prepare(destination)
    }
    /// Builds the new neighbours once the page has settled, rather than in the frame it lands.
    private func prepare(_ stop: Int) {
        preparing?.cancel()
        preparing = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self, !Task.isCancelled, self.rest == stop else { return }
            let wanted = Array(max(0, stop - 1)...min(Self.count - 1, stop + 1))
            if self.pages != wanted { self.pages = wanted }
        }
    }
    private func include(_ stops: [Int]) {
        let merged = Set(pages).union(stops).sorted()
        if merged != pages { pages = merged }
    }
}

@MainActor private final class FrameTarget: NSObject {
    let action: (CADisplayLink) -> Void
    init(_ action: @escaping (CADisplayLink) -> Void) { self.action = action }
    @objc func fire(_ link: CADisplayLink) { action(link) }
}

extension EnvironmentValues {
    /// The bottom-bar page a view is on, while the pager shows it.
    @Entry var homeStop: Int? = nil
}

/// Lays the pages out side by side under one sideways swipe.
struct HomePagerView<Page: View>: View {
    let pager: HomePager
    var enabled: Bool
    let land: (Int) -> Void
    @ViewBuilder let page: (Int) -> Page
    var body: some View {
        ZStack {
            ForEach(pager.pages, id: \.self) { stop in
                page(stop).modifier(PageSlot(pager: pager, stop: stop))
            }
        }
        // No content shape here: it would limit touches on the pages to this frame, short of the bars they scroll under.
        .gesture(PageSwipe(pager: pager, enabled: enabled && !pager.bridging))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { if $0 > 0, pager.width != $0 { pager.width = $0 } }
        .background { PagerLanding(pager: pager, land: land) }
        .environment(pager)
    }
}
/// Commits the page the pager settles on. Kept apart so a swipe starting or ending redraws only this.
private struct PagerLanding: View {
    @Environment(AppStore.self) private var store
    let pager: HomePager
    let land: (Int) -> Void
    var body: some View {
        Color.clear
            .onChange(of: pager.rest) { _, stop in if let stop { land(stop) } }
            .sensoryFeedback(.selection, trigger: pager.swipes) { _, _ in store.settings.haptics }
    }
}
/// Places a page in its slot. Only the page being shown takes touches and is read by VoiceOver.
private struct PageSlot: ViewModifier {
    let pager: HomePager
    let stop: Int
    func body(content: Content) -> some View {
        let shown = pager.destination == stop
        content
            .environment(\.homeStop, stop)
            .offset(x: pager.offset(stop))
            .allowsHitTesting(shown)
            .accessibilityHidden(!shown)
    }
}

/// An item on a page trails the page's sideways move, the lower and further right the more, so the page flows in
/// and out like something elastic rather than sliding as one sheet. Nothing moves while the page rests.
private struct PageFlow: ViewModifier {
    @Environment(HomePager.self) private var pager: HomePager?
    @Environment(\.homeStop) private var stop
    /// Rows to count before this item, for a block that comes after another at the same height.
    let after: Int
    @State private var depth = 0
    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: Int.self) { proxy in
                let frame = proxy.frame(in: .scrollView), width = proxy.bounds(of: .scrollView)?.width ?? 0
                let row = Int(max(0, frame.minY - 90) / 120), column = width > 0 ? Int(max(0, frame.minX) / (width / 3)) : 0
                return min(row + column + after, HomePager.depths - 1)
            } action: { depth = $0 }
            .offset(x: stop == nil ? 0 : pager?.lag(depth) ?? 0)
    }
}
/// The habit layouts' shared header (category filter, routines) and empty state stay still while the layouts below
/// them change, handing over to the next layout's copy halfway.
private struct LayoutPinned: ViewModifier {
    @Environment(HomePager.self) private var pager: HomePager?
    @Environment(\.homeStop) private var stop
    func body(content: Content) -> some View {
        let pinned = pager?.betweenLayouts == true && stop != nil
        let away = pinned ? abs(pager!.slot(stop!) - pager!.position) : 0
        content.offset(x: pinned ? -pager!.offset(stop!) : 0).opacity(pinned ? min(1, 2 * (1 - away)) : 1)
    }
}
/// While the pages move, a page's items trail past its edges, so its scroll view stops clipping them. At rest it clips
/// again: a scroll view that doesn't clip takes touches only inside its own frame, short of the bars it scrolls under.
private struct PageClip: ViewModifier {
    @Environment(HomePager.self) private var pager: HomePager?
    @Environment(\.homeStop) private var stop
    func body(content: Content) -> some View { content.scrollClipDisabled(stop != nil && pager?.rest == nil) }
}
extension View {
    func homeFlow(after rows: Int = 0) -> some View { modifier(PageFlow(after: rows)) }
    func layoutPinned() -> some View { modifier(LayoutPinned()) }
    func pageClip() -> some View { modifier(PageClip()) }
}

/// A round top-bar control the shared top bar shows for a page.
struct BarButton {
    var symbol: String
    var label: String
    var filled = false
    var glyph: CGFloat
    var disabled = false
    var action: () -> Void
}
/// The shared top bar's trailing controls. A control both pages have stays where it is while its icon turns into the
/// next page's; one only a page has shrinks away with it.
struct HomeBarControls: View {
    let pager: HomePager
    let buttons: (Int) -> [BarButton?]
    var body: some View {
        let segment = pager.segment, progress = min(max(segment.progress, 0), 1)
        let from = buttons(segment.from), to = buttons(segment.to)
        ForEach(0..<max(from.count, to.count), id: \.self) { i in
            MorphControl(from: i < from.count ? from[i] : nil, to: i < to.count ? to[i] : nil, progress: progress)
        }
    }
}
private struct MorphControl: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accent) private var accent
    @Environment(\.glass) private var glass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let from: BarButton?
    let to: BarButton?
    let progress: CGFloat
    var body: some View {
        let current = progress < 0.5 ? from : to, chrome = current ?? from ?? to
        let presence = from == nil ? progress : to == nil ? 1 - progress : 1
        let filled = chrome?.filled ?? false
        Button { current?.action() } label: {
            ZStack {
                // An icon both pages share stays; one with no counterpart goes with the whole control.
                if let from { icon(from, shown: to == nil || to?.symbol == from.symbol ? 1 : 1 - progress) }
                if let to, to.symbol != from?.symbol { icon(to, shown: from == nil ? 1 : progress) }
            }
            .frame(width: 42, height: 42)
            .glassChrome(in: Circle(), prominent: filled, fill: filled ? accent.color : BuddyStyle.control(scheme), border: filled ? nil : AnyShapeStyle(BuddyStyle.controlBorder(scheme)))
            .foregroundStyle(filled ? accent.foreground : BuddyStyle.text(scheme)).contentShape(Circle())
        }
        .buttonStyle(.plain).disabled(current?.disabled ?? true)
        .scaleEffect(reduceMotion ? 1 : 0.55 + 0.45 * presence).opacity(Double(presence))
        .allowsHitTesting(current != nil)
        .accessibilityLabel(current?.label ?? "").accessibilityHidden(current == nil)
    }
    /// The icon blurs and turns as it gives way to the other page's, like an SF Symbol replace.
    private func icon(_ button: BarButton, shown: CGFloat) -> some View {
        let eased = shown * shown * (3 - 2 * shown)
        return LucideIcon(button.symbol, size: button.glyph)
            .scaleEffect(reduceMotion ? 1 : 0.5 + 0.5 * eased)
            .rotationEffect(.degrees(reduceMotion ? 0 : Double(1 - eased) * (button.symbol == from?.symbol ? -40 : 40)))
            .blur(radius: reduceMotion || glass != nil ? 0 : (1 - eased) * 4)
            .opacity(Double(eased))
    }
}

/// The bottom bar's selection, which follows the pager: it slides between buttons with the swipe, stretching as it
/// travels and squashing against the ends. Reduce Motion cross-fades it from button to button instead.
struct SwitcherLens: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.glass) private var glass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let pager: HomePager
    let frames: [Int: CGRect]
    var body: some View {
        if reduceMotion {
            ForEach(Array(frames.keys), id: \.self) { stop in
                let frame = frames[stop]!
                lens.frame(width: frame.width, height: frame.height).position(x: frame.midX, y: frame.midY)
                    .opacity(pager.destination == stop ? 1 : 0)
            }
            .animation(.easeInOut(duration: 0.2), value: pager.destination)
        } else if let rect = rect {
            lens.frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
        }
    }
    @ViewBuilder private var lens: some View {
        if glass != nil { Capsule().fill(scheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.07)) }
        else {
            Capsule().fill(scheme == .dark ? Color(hex: 0x3E3E40) : Color.black.opacity(0.08))
                .overlay { Capsule().strokeBorder(scheme == .dark ? Color(hex: 0x545456) : Color.black.opacity(0.08), lineWidth: 1) }
        }
    }
    private var rect: CGRect? {
        let segment = pager.segment
        guard let a = frames[segment.from], let b = frames[segment.to] else { return nil }
        let t = segment.progress
        if t < 0 || t > 1 {
            // Pulled past the first or last page: the lens leans out and narrows a little.
            let edge = t < 0 ? a : b, pull = min(t < 0 ? -t : t - 1, 1)
            let width = edge.width * (1 - 0.22 * pull)
            return CGRect(x: edge.midX - width / 2 + (t < 0 ? -1 : 1) * 10 * pull, y: edge.minY + edge.height * 0.03 * pull, width: width, height: edge.height * (1 - 0.06 * pull))
        }
        let stretch = sin(.pi * t), travel = abs(b.midX - a.midX)
        let width = a.width + (b.width - a.width) * t + min(travel * 0.45, 34) * stretch
        let height = a.height + (b.height - a.height) * t - 3 * stretch
        let midX = a.midX + (b.midX - a.midX) * t, midY = a.midY + (b.midY - a.midY) * t
        return CGRect(x: midX - width / 2, y: midY - height / 2, width: width, height: height)
    }
}

/// The sideways swipe over the pages. It's a UIKit pan that begins only for a mostly horizontal move, so the pages'
/// own scrolling is untouched; once it begins it cancels the tap or hold of the card under the finger and stops the
/// page scrolling up or down, and a row that scrolls sideways itself keeps its own swipe.
struct PageSwipe: UIGestureRecognizerRepresentable {
    let pager: HomePager
    let enabled: Bool
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }
    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = HorizontalPan()
        pan.delegate = context.coordinator
        return pan
    }
    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) { recognizer.isEnabled = enabled }
    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began:
            context.coordinator.holdScrolling()
            pager.begin()
            pager.drag(recognizer.translation(in: recognizer.view).x)
        case .changed: pager.drag(recognizer.translation(in: recognizer.view).x)
        case .ended: pager.end(velocity: recognizer.velocity(in: recognizer.view).x)
        case .cancelled, .failed: pager.end(velocity: 0)
        default: break
        }
    }
    /// Fails as soon as the first real movement is more vertical than horizontal; the velocity isn't known yet when a
    /// delegate is asked whether to begin, so the direction is read from the touches themselves.
    final class HorizontalPan: UIPanGestureRecognizer {
        private var origin = CGPoint.zero
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            origin = touches.first?.location(in: view) ?? .zero
            super.touchesBegan(touches, with: event)
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            if state == .possible, let point = touches.first?.location(in: view) {
                let dx = abs(point.x - origin.x), dy = abs(point.y - origin.y)
                if max(dx, dy) > 8, dx < dy * 1.25 { state = .failed; return }
            }
            super.touchesMoved(touches, with: event)
        }
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// The scroll views under the finger, innermost first.
        private var scrolls: [UIScrollView] = []
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            scrolls = []
            var view = touch.view
            while let current = view { if let scroll = current as? UIScrollView { scrolls.append(scroll) }; view = current.superview }
            return true
        }
        // Alongside the scroll views' own pans only; a card's tap or hold must give way once the swipe begins.
        func gestureRecognizer(_ a: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith b: UIGestureRecognizer) -> Bool { b is UIPanGestureRecognizer }
        func gestureRecognizer(_ a: UIGestureRecognizer, shouldRequireFailureOf b: UIGestureRecognizer) -> Bool {
            guard let scroll = b.view as? UIScrollView, b === scroll.panGestureRecognizer else { return false }
            return scroll.contentSize.width > scroll.bounds.width + 1
        }
        /// Stops the page under the finger scrolling up or down for the rest of the swipe.
        func holdScrolling() {
            for scroll in scrolls where scroll.contentSize.width <= scroll.bounds.width + 1 {
                scroll.panGestureRecognizer.isEnabled = false
                scroll.panGestureRecognizer.isEnabled = true
            }
            scrolls = []
        }
    }
}
