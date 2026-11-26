import AppKit
import SwiftUI

// Past the last space two fingers make a new one, as in Arc: the row gives
// on its usual rubber band, and a "+" comes in at the column's edge as far
// as it has given, its ring filling. Full, it turns over with a tick; lift
// after it has been full a moment and New Space opens. Anything less and it
// goes back out (SpacePaging has the numbers). It stands over the column
// rather than in the row, so it is the same whether the row is the live
// pages, their pictures, or, with Reduce Motion, not moving at all.

@MainActor
final class NewSpacePlus {
    static let shared = NewSpacePlus()

    private final class Host: NSHostingView<AnyView> {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    private let state = NewSpacePlusState()
    private var host: Host?
    private var wornBy: (Tone?, ColorScheme)?
    private var fullSince: TimeInterval?

    /// The row `past` points beyond the last space, the fingers' latest
    /// move at `time`.
    func pull(_ past: CGFloat, at time: TimeInterval, browser: Browser) {
        let was = fullSince
        fullSince = SpacePaging.fullSince(was, past: Double(past), at: time)
        // Arc ticks as the ring fills and again as it empties.
        if (was == nil) != (fullSince == nil) { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now) }
        guard let column = browser.column, let band = column.spaceBand(browser) else { return }
        place(in: column, band: band, browser: browser)
        let (shown, ring) = SpacePaging.plus(Double(past))
        if state.shown != shown { state.shown = shown }
        if state.ring != ring { state.ring = ring }
        if state.full != (fullSince != nil) { state.full = fullSince != nil }
    }

    /// Fingers that never paged the row, Reduce Motion's: `travel` points
    /// over the column, the "+" as far as the row would have given.
    func pull(unpaged travel: CGFloat, at time: TimeInterval, browser: Browser) {
        let order = browser.turnOrder
        guard browser.canSwipeNewSpace, order.last?.id == browser.spaceID,
              let page = browser.column?.spaceBand(browser)?.width else { return }
        let x = SpacePaging.offset(travel: Double(travel), page: Double(page), back: order.count > 1, forward: false)
        pull(CGFloat(max(0, -x)), at: time, browser: browser)
    }

    /// The fingers lifted at `time`, or went without lifting (nil): New
    /// Space if the ring had been full long enough, and the "+" goes.
    func lift(at time: TimeInterval?, browser: Browser) {
        let makes = time.map { SpacePaging.makesSpace(fullSince: fullSince, liftedAt: $0) } ?? false
        drop()
        if makes { SpaceTray.open(browser) }
    }

    /// The "+" back out, nothing made.
    func drop() {
        fullSince = nil
        if state.shown != 0 { state.shown = 0 }
        if state.ring != 0 { state.ring = 0 }
        if state.full { state.full = false }
    }

    /// Over the space's part of the column, in its words, clipped at its
    /// edge so the "+" comes in from past it.
    private func place(in column: ColumnView, band: CGRect, browser: Browser) {
        if host?.superview !== column {
            host?.removeFromSuperview()
            let made = Host(rootView: AnyView(EmptyView()))
            made.sizingOptions = []
            made.safeAreaRegions = []
            made.wantsLayer = true
            made.layer?.masksToBounds = true
            host = made
            wornBy = nil
        }
        guard let host else { return }
        let floating = browser.prefs.sideShut && browser.sideCard
        let painted = SpaceWash.grounded(in: browser)
        let worn = painted.map { Tone($0.color, lifted: true, glass: $0.glass) }
        let tone: Tone? = floating || (browser.prefs.backdrop == .none && !browser.prefs.edgeBackdrop) ? worn?.card(painted) : worn
        let dark = (column.window?.effectiveAppearance ?? NSApp.effectiveAppearance).bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let scheme = tone?.scheme ?? (dark ? .dark : .light)
        if wornBy?.0 != tone || wornBy?.1 != scheme {
            wornBy = (tone, scheme)
            host.rootView = AnyView(NewSpacePlusView(state: state).toned(tone).environment(\.colorScheme, scheme))
        }
        // The band is measured from the column's top.
        let frame = CGRect(x: band.minX, y: column.bounds.height - band.maxY, width: band.width, height: band.height)
        if host.frame != frame { host.frame = frame }
        if host.superview == nil { column.addSubview(host, positioned: .above, relativeTo: nil) }
    }
}

@MainActor
final class NewSpacePlusState: ObservableObject {
    /// How far in, 0 to 1, and how full the ring.
    @Published var shown: Double = 0
    @Published var ring: Double = 0
    @Published var full = false
}

/// Arc's "+" past the last space (SpacePaging.plus): a 30 point disc whose
/// left edge goes from 5 points past the column's edge to 42 inside it, seen
/// from a fifth of the way in, and a light of the column's ink behind it at
/// the edge. Its ring fills from the top, counterclockwise; full, it turns
/// over, the plus cut out of it, growing a little and back.
struct NewSpacePlusView: View {
    @ObservedObject var state: NewSpacePlusState
    @Environment(\.tone) private var tone
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let disc: CGFloat = 30
    /// How deep the light reaches into the column.
    static let light: CGFloat = 82
    /// Arc's own, for the disc and the light following the row.
    static let spring = Animation.spring(response: 0.4, dampingFraction: 0.8)

    var body: some View {
        GeometryReader { box in
            let width = box.size.width, middle = box.size.height / 2
            let shown = CGFloat(state.shown)
            let ink = Palette.strong(on: tone)
            ZStack {
                EllipticalGradient(colors: [ink.opacity(0.22), ink.opacity(0)])
                    .frame(width: 2 * Self.light, height: box.size.height)
                    .position(x: width + (Self.light - 10) * (1 - shown), y: middle)
                    .opacity(min(1, 2 * shown))
                ZStack {
                    Circle().fill(state.full ? ink : Palette.wash(on: tone))
                    Circle().inset(by: 1.25)
                        .trim(from: 0, to: CGFloat(state.ring))
                        .stroke(ink, lineWidth: 2.5)
                        .rotationEffect(.degrees(-90))
                        .scaleEffect(x: -1)
                    Symbol("plus", size: 12, weight: .semibold)
                        .foregroundStyle(ink.opacity(state.full ? 1 : 0.8))
                        .blendMode(state.full ? .destinationOut : .normal)
                }
                .compositingGroup()
                // Turned over at once: the plus is cut out in one frame, and
                // a fill fading under it showed an empty ring, then a blank disc.
                .animation(nil, value: state.full)
                .frame(width: Self.disc, height: Self.disc)
                .keyframeAnimator(initialValue: 1.0, trigger: state.full) { disc, scale in
                    disc.scaleEffect(scale)
                } keyframes: { _ in
                    // Grows only as it turns over, not as it empties.
                    CubicKeyframe(state.full && !reduceMotion ? 1.14 : 1, duration: 0.1)
                    CubicKeyframe(1, duration: 0.1)
                }
                .position(x: width + 5 - 47 * shown + Self.disc / 2, y: middle)
                .opacity(min(1, shown / 0.2))
            }
            .animation(reduceMotion ? nil : Self.spring, value: state.shown)
        }
        .accessibilityHidden(true)
    }
}
