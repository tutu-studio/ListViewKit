//
//  Created by ktiays on 2025/2/18.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

#if canImport(UIKit)
    import UIKit

    open class ListScrollView: UIScrollView {
        var rowContainerView: UIView {
            self
        }

        var scrollingDisplayLink: NativeListDisplayLink?
        var scrollingContext = SoftSpring2D(angularFrequency: 10, dampingRatio: 1, threshold: 0.05)
        var scrollingTik: CFTimeInterval = .init()
        private var scrollingTarget: CGPoint?

        var scrollLedger = ScrollLedger()

        /// While set, an offset that a content-size change pushed out of
        /// bounds travels to its new home instead of snapping there. A caller
        /// animating its rows has to move the viewport along with them, or the
        /// correction reads as a jump in the middle of the animation.
        var animatesContentSizeCorrection = false

        /// See ``suppressAutoScroll()``.
        public private(set) var isAutoScrollSuppressed = false

        /// The viewport size the previous layout pass ran against. Offsets
        /// route through layout too, so a resize is only recognisable by
        /// comparing against what was laid out last.
        var lastLaidOutViewportSize: CGSize?

        /// `UIScrollView` bounces as part of decelerating, which ownership
        /// already reports. Mirrors the AppKit property so the gate needs no
        /// platform split.
        var isReboundingFromOverscroll: Bool {
            false
        }

        /// Where the finger currently holds the content, measured from the
        /// viewport's top edge, or `nil` when no finger is down.
        ///
        /// Viewport-relative on purpose: the consumer remembers it across the
        /// end of a gesture, and what stays put through momentum is the place
        /// on the glass, not a point in the content rushing past it.
        var interactionLocationInViewportY: CGFloat? {
            guard isTracking else { return nil }
            return panGestureRecognizer.location(in: self).y - contentOffset.y
        }

        /// The minimum point (in content view coordinates) that the view can be scrolled.
        public var minimumContentOffset: CGPoint {
            .init(x: -adjustedContentInset.left, y: -adjustedContentInset.top)
        }

        /// The maximum point (in content view coordinates) that the view can be scrolled.
        public var maximumContentOffset: CGPoint {
            let min = minimumContentOffset
            return .init(
                x: ceil(max(min.x, contentSize.width - bounds.width + adjustedContentInset.right)),
                y: ceil(max(min.y, contentSize.height - bounds.height + adjustedContentInset.bottom))
            )
        }

        override open var contentSize: CGSize {
            get { super.contentSize }
            set {
                if super.contentSize != newValue {
                    let currentOffset = contentOffset
                    // Shrinking the content makes UIScrollView pull the offset
                    // back in by itself. That is a clamp, not a scroll, and
                    // inside a caller's block it would animate as one.
                    withoutListAnimation { super.contentSize = newValue }
                    applyContentOffset(currentOffset)
                }
                reconcileOffsetWithContentSize()
            }
        }

        override open var contentOffset: CGPoint {
            get { super.contentOffset }
            set {
                guard super.contentOffset != newValue else { return }
                super.contentOffset = newValue
            }
        }

        func isContentOffsetWithinBounds(offset: CGPoint) -> Bool {
            let min = minimumContentOffset
            let max = maximumContentOffset
            return true
                && offset.x >= min.x && offset.x <= max.x
                && offset.y >= min.y && offset.y <= max.y
        }

        func nearestScrollLocationInBounds(offset: CGPoint) -> CGPoint {
            let min = minimumContentOffset
            let max = maximumContentOffset
            return .init(
                x: CGFloat.minimum(CGFloat.maximum(min.x, offset.x), max.x),
                y: CGFloat.minimum(CGFloat.maximum(min.y, offset.y), max.y)
            )
        }

        /// Puts the offset back in bounds at the end of a layout pass. It runs
        /// even when the size is unchanged: a row shrinking above the anchor
        /// and one growing below it cancel out in the total while the offset
        /// still moved, and nothing else would notice it left the bounds.
        ///
        /// Whether the offset may sit outside the bounds is a question about
        /// who owns it, not about the offset itself: deferred measurement
        /// routinely shifts it past an edge on its way to the right place.
        private func reconcileOffsetWithContentSize() {
            // A finger, momentum or a rebound already owns the offset. Those
            // either clamp themselves every frame or are holding a deliberate
            // overscroll, and interrupting one cancels the bounce. Asked of
            // ownership rather than of ``isUserInteractingWithScroll``: an
            // offset outside the content is wrong regardless of whether the
            // host is currently allowed to scroll, and this is the only thing
            // left running that would notice.
            guard !isScrollOffsetOwnedByUser else { return }
            if let target = scrollingTarget {
                // A programmatic scroll keeps running, retargeted onto the new
                // edge so it lands there instead of short of it.
                let clamped = nearestScrollLocationInBounds(offset: target)
                if clamped != target {
                    scroll(to: clamped)
                }
                return
            }
            let clamped = nearestScrollLocationInBounds(offset: contentOffset)
            guard clamped != contentOffset else { return }
            if animatesContentSizeCorrection {
                scroll(to: clamped, preserveVelocity: false)
            } else {
                // Deferred measurement resizes the content over and over, so
                // an idle list lands on the new edge outright: animating every
                // correction restarts the slide on each pass and reads as the
                // list scrolling by itself.
                applyContentOffsetWithoutTravel(clamped)
            }
        }

        /// scroll to an offset
        /// - Parameters:
        ///   - offset: where
        ///   - angularFrequency: bigger value will handle animation faster
        ///   - preserveVelocity: keep current velocity when retargeting
        public func scroll(
            to offset: CGPoint,
            angularFrequency: Double? = nil,
            preserveVelocity: Bool = true
        ) {
            let target = nearestScrollLocationInBounds(offset: offset)
            // update the context, but we need to keep the velocity
            let velocity: CGPoint = if preserveVelocity {
                .init(
                    x: scrollingContext.x.velocity,
                    y: scrollingContext.y.velocity
                )
            } else {
                .init(x: 0, y: 0)
            }
            scrollingContext.setCurrent(
                .init(x: ceil(contentOffset.x), y: ceil(contentOffset.y)),
                vel: .init(x: velocity.x, y: velocity.y)
            )
            if let angularFrequency {
                assert(angularFrequency > 0)
                scrollingContext.x.angularFrequency = angularFrequency
                scrollingContext.y.angularFrequency = angularFrequency
            }
            scrollingContext.setTarget(.init(x: ceil(target.x), y: ceil(target.y)))
            scrollingTarget = target

            guard scrollingDisplayLink == nil else { return }
            scrollingDisplayLink = NativeListDisplayLink(attachedTo: self) { [weak self] _ in
                self?.handleScrollingAnimation()
            }
            scrollingTik = CACurrentMediaTime()
        }

        public func cancelCurrentScrolling() {
            let currentContentOffset = contentOffset
            scrollingContext.setCurrent(
                .init(x: currentContentOffset.x, y: currentContentOffset.y),
                vel: .init(x: 0, y: 0)
            )
            scrollingTarget = nil
            scrollingContext.setTarget(.init(x: currentContentOffset.x, y: currentContentOffset.y))
            scrollingDisplayLink?.invalidate()
            scrollingDisplayLink = nil
        }

        /// Translates the viewport and any in-flight programmatic spring after
        /// content coordinates change, without classifying the shift as travel.
        open func rebaseContentOffset(by delta: CGPoint) {
            guard delta.x.isFinite, delta.y.isFinite, delta != .zero else { return }

            scrollLedger.exclude(delta.y)
            withoutListAnimation {
                super.contentOffset = .init(
                    x: super.contentOffset.x + delta.x,
                    y: super.contentOffset.y + delta.y
                )
            }
            if let target = scrollingTarget {
                let translatedTarget = CGPoint(x: target.x + delta.x, y: target.y + delta.y)
                scrollingContext.setCurrent(
                    .init(
                        x: scrollingContext.x.value + delta.x,
                        y: scrollingContext.y.value + delta.y
                    ),
                    vel: .init(
                        x: scrollingContext.x.velocity,
                        y: scrollingContext.y.velocity
                    )
                )
                scrollingContext.setTarget(translatedTarget)
                scrollingTarget = translatedTarget
            }
        }

        /// Deferred height correction is the vertical form of public rebasing.
        func compensateScrollOffset(by dy: CGFloat) {
            rebaseContentOffset(by: .init(x: 0, y: dy))
        }

        func handleScrollingAnimation() {
            if isTracking || scrollingContext.completed {
                cancelCurrentScrolling()
                return
            }
            let time = CACurrentMediaTime()
            let delta = min(1 / 30, time - scrollingTik)
            scrollingTik = time
            scrollingContext.update(withDeltaTime: delta)
            let loc = nearestScrollLocationInBounds(offset: .init(
                x: scrollingContext.x.value,
                y: scrollingContext.y.value
            ))
            applyContentOffset(loc)
        }

        override open func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
            if animated {
                scroll(to: contentOffset)
            } else {
                cancelCurrentScrolling()
                applyContentOffsetWithoutTravel(contentOffset)
            }
        }

        /// Moves the offset without calling it travel.
        ///
        /// A jump to an arbitrary offset and a clamp back inside the bounds
        /// both relocate the reader rather than carry them, so neither is
        /// scrolling a row animator should answer.
        private func applyContentOffsetWithoutTravel(_ offset: CGPoint) {
            scrollLedger.exclude(offset.y - contentOffset.y)
            applyContentOffset(offset)
        }

        /// The funnel for every offset this class owns: display-link ticks, the
        /// clamp after a content-size change, and the unanimated branch of
        /// `setContentOffset`. None of those is a scroll anyone asked for, so
        /// none may ride an animation the caller happens to have open. The
        /// scrolls this class does animate run off the display link, which the
        /// suppression never touches; the public setter is left alone, since
        /// animating that one is a fair thing for a host to ask for.
        private func applyContentOffset(_ contentOffset: CGPoint) {
            withoutListAnimation {
                super.setContentOffset(contentOffset, animated: false)
            }
        }

        override open func layoutSubviews() {
            super.layoutSubviews()
            // Both of these before `layoutContent`, so the content-size change
            // it makes already sees the suppression.
            suppressAutoScrollIfViewportResized()
            // The platform's own drag and deceleration never call into this
            // class, so the tail after one is armed from here.
            if isTracking || isDragging || isDecelerating {
                suppressAutoScroll()
            }
            // Every offset change ends up here — changing the bounds is what
            // scrolling is — so this is where travel is counted, including the
            // dragging and deceleration `UIScrollView` performs without ever
            // calling into this class.
            scrollLedger.accrue(offsetY: contentOffset.y)
            layoutContent()
        }

        /// Where a subclass lays out its content. Mirrors the AppKit hook so
        /// `ListView` needs no platform split.
        func layoutContent() {}
    }

#elseif canImport(AppKit)
    import AppKit

    final class ListDocumentView: NSView {
        override var isFlipped: Bool {
            true
        }
    }

    final class NativeListScrollView: NSScrollView {
        weak var owner: ListScrollView?

        override func scrollWheel(with event: NSEvent) {
            owner?.nativeScrollWheelWillBegin(event)
            defer { owner?.nativeScrollWheelDidEnd(event) }
            super.scrollWheel(with: event)
        }
    }

    /// An AppKit list viewport backed by one native `NSScrollView` hierarchy.
    ///
    /// AppKit owns wheel and trackpad gestures, momentum, elasticity, clipping,
    /// and scroller behaviour. ListViewKit keeps only its retargetable spring
    /// for programmatic scrolling.
    open class ListScrollView: NSView {
        override open var isFlipped: Bool {
            true
        }

        let nativeScrollView = NativeListScrollView(frame: .zero)
        let contentDocumentView = ListDocumentView(frame: .zero)
        var rowContainerView: NSView {
            contentDocumentView
        }

        private var _contentSize: CGSize = .zero
        private var isNativeLiveScrollActive = false
        private var excludesNativeOffsetTravel = false
        private var lastObservedNativeOffsetY: CGFloat = 0
        private var _lastScrollWheelViewportY: CGFloat?
        private var _isTracking = false
        private var _isVerticalScrollerTracking = false

        var scrollingDisplayLink: NativeListDisplayLink?
        var scrollingContext = SoftSpring2D(angularFrequency: 16, dampingRatio: 1, threshold: 0.05)
        private var scrollingTarget: CGPoint?

        var scrollLedger = ScrollLedger()

        /// Whether the list asks AppKit to draw its vertical scroller.
        /// Scrolling remains enabled when the indicator is hidden.
        open var showsVerticalScrollIndicator: Bool = true {
            didSet {
                guard showsVerticalScrollIndicator != oldValue else { return }
                nativeScrollView.hasVerticalScroller = showsVerticalScrollIndicator
                nativeScrollView.tile()
            }
        }

        open var contentInsets: NSEdgeInsets = .init() {
            didSet {
                nativeScrollView.contentInsets = contentInsets
                needsLayout = true
            }
        }

        /// While set, an offset pushed out of bounds by an animated content
        /// change travels to its new edge instead of being corrected outright.
        var animatesContentSizeCorrection = false

        public private(set) var isAutoScrollSuppressed = false
        var lastLaidOutViewportSize: CGSize?
        var isReboundingFromOverscroll: Bool {
            false
        }

        /// Native live scrolling includes AppKit-owned momentum.
        var isTracking: Bool {
            isNativeLiveScrollActive || _isTracking || _isVerticalScrollerTracking
        }

        var interactionLocationInViewportY: CGFloat? {
            _lastScrollWheelViewportY
        }

        public var minimumContentOffset: CGPoint {
            .init(x: -contentInsets.left, y: -contentInsets.top)
        }

        public var maximumContentOffset: CGPoint {
            let minimum = minimumContentOffset
            return .init(
                x: ceil(max(minimum.x, _contentSize.width - bounds.width + contentInsets.right)),
                y: ceil(max(minimum.y, _contentSize.height - bounds.height + contentInsets.bottom))
            )
        }

        /// The native clip-view origin, exposed with the UIKit-compatible name.
        open var contentOffset: CGPoint {
            get { nativeScrollView.contentView.bounds.origin }
            set {
                guard contentOffset != newValue else { return }
                applyContentOffset(newValue)
            }
        }

        /// The complete native document size.
        open var contentSize: CGSize {
            get { _contentSize }
            set {
                let normalized = CGSize(width: max(0, newValue.width), height: max(0, newValue.height))
                if _contentSize != normalized {
                    let previousOffset = contentOffset
                    _contentSize = normalized
                    performExcludingNativeOffsetTravel {
                        // Same as UIKit's `contentSize` setter: the write is a
                        // correction, and AppKit would otherwise inherit the
                        // list's row-slide context and interpolate the overlay
                        // scroller onto the trailing edge.
                        withoutListAnimation {
                            contentDocumentView.frame = CGRect(origin: .zero, size: normalized)
                        }
                        applyContentOffset(previousOffset)
                    }
                    needsLayout = true
                }
                reconcileOffsetWithContentSize()
            }
        }

        var adjustedContentInset: NSEdgeInsets {
            contentInsets
        }

        override public init(frame: CGRect) {
            super.init(frame: frame)

            wantsLayer = true
            nativeScrollView.owner = self
            nativeScrollView.drawsBackground = false
            nativeScrollView.contentView.drawsBackground = false
            nativeScrollView.borderType = .noBorder
            nativeScrollView.hasHorizontalScroller = false
            nativeScrollView.scrollerStyle = .overlay
            nativeScrollView.hasVerticalScroller = true
            nativeScrollView.autohidesScrollers = true
            nativeScrollView.verticalScrollElasticity = .allowed
            nativeScrollView.horizontalScrollElasticity = .none
            nativeScrollView.automaticallyAdjustsContentInsets = false
            nativeScrollView.documentView = contentDocumentView
            addSubview(nativeScrollView)

            nativeScrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(nativeClipViewBoundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: nativeScrollView.contentView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(nativeLiveScrollDidBegin(_:)),
                name: NSScrollView.willStartLiveScrollNotification,
                object: nativeScrollView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(nativeLiveScrollDidEnd(_:)),
                name: NSScrollView.didEndLiveScrollNotification,
                object: nativeScrollView
            )
            lastObservedNativeOffsetY = contentOffset.y
        }

        @available(*, unavailable)
        public required init?(coder _: NSCoder) {
            fatalError()
        }

        deinit {
            scrollingDisplayLink?.invalidate()
            NotificationCenter.default.removeObserver(self)
        }

        override open func layout() {
            super.layout()
            suppressAutoScrollIfViewportResized()
            if nativeScrollView.frame != bounds {
                withoutListAnimation { nativeScrollView.frame = bounds }
            }
            scrollLedger.accrue(offsetY: contentOffset.y)
            layoutContent()
        }

        func layoutContent() {}

        /// The native scroll view normally receives wheel events through hit
        /// testing. Forward events sent to the wrapper as well, which keeps
        /// responder-chain forwarding and direct host integrations native.
        override open func scrollWheel(with event: NSEvent) {
            nativeScrollView.scrollWheel(with: event)
        }

        func isContentOffsetWithinBounds(offset: CGPoint) -> Bool {
            let minimum = minimumContentOffset
            let maximum = maximumContentOffset
            return offset.x >= minimum.x && offset.x <= maximum.x
                && offset.y >= minimum.y && offset.y <= maximum.y
        }

        func nearestScrollLocationInBounds(offset: CGPoint) -> CGPoint {
            let minimum = minimumContentOffset
            let maximum = maximumContentOffset
            return .init(
                x: min(maximum.x, max(minimum.x, offset.x)),
                y: min(maximum.y, max(minimum.y, offset.y))
            )
        }

        private func reconcileOffsetWithContentSize() {
            guard !isScrollOffsetOwnedByUser else { return }
            if let target = scrollingTarget {
                let clamped = nearestScrollLocationInBounds(offset: target)
                if clamped != target {
                    scroll(to: clamped)
                }
                return
            }
            let clamped = nearestScrollLocationInBounds(offset: contentOffset)
            guard clamped != contentOffset else { return }
            if animatesContentSizeCorrection {
                scroll(to: clamped, preserveVelocity: false)
            } else {
                applyContentOffsetWithoutTravel(clamped)
            }
        }

        public func scroll(
            to offset: CGPoint,
            angularFrequency: Double? = nil,
            preserveVelocity: Bool = true
        ) {
            let target = nearestScrollLocationInBounds(offset: offset)
            let velocity: CGPoint = preserveVelocity
                ? .init(x: scrollingContext.x.velocity, y: scrollingContext.y.velocity)
                : .zero
            scrollingContext.setCurrent(
                .init(x: ceil(contentOffset.x), y: ceil(contentOffset.y)),
                vel: velocity
            )
            if let angularFrequency {
                assert(angularFrequency > 0)
                scrollingContext.x.angularFrequency = angularFrequency
                scrollingContext.y.angularFrequency = angularFrequency
            }
            scrollingContext.setTarget(.init(x: ceil(target.x), y: ceil(target.y)))
            scrollingTarget = target

            guard scrollingDisplayLink == nil else { return }
            scrollingDisplayLink = NativeListDisplayLink(attachedTo: self) { [weak self] duration in
                self?.handleScrollingAnimation(duration: duration)
            }
        }

        public func cancelCurrentScrolling() {
            let current = contentOffset
            scrollingContext.setCurrent(current, vel: .zero)
            scrollingContext.setTarget(current)
            scrollingTarget = nil
            scrollingDisplayLink?.invalidate()
            scrollingDisplayLink = nil
        }

        open func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
            if animated {
                scroll(to: contentOffset)
            } else {
                cancelCurrentScrolling()
                applyContentOffsetWithoutTravel(contentOffset)
            }
        }

        /// Translates the viewport and any in-flight programmatic spring after
        /// document coordinates change. AppKit remains the owner of native
        /// gesture, momentum, elasticity, and scroller state.
        open func rebaseContentOffset(by delta: CGPoint) {
            guard delta.x.isFinite, delta.y.isFinite, delta != .zero else { return }

            if let target = scrollingTarget {
                let translatedTarget = CGPoint(x: target.x + delta.x, y: target.y + delta.y)
                scrollingContext.setCurrent(
                    .init(
                        x: scrollingContext.x.value + delta.x,
                        y: scrollingContext.y.value + delta.y
                    ),
                    vel: .init(
                        x: scrollingContext.x.velocity,
                        y: scrollingContext.y.velocity
                    )
                )
                scrollingContext.setTarget(translatedTarget)
                scrollingTarget = translatedTarget
            }
            performExcludingNativeOffsetTravel {
                applyContentOffset(.init(
                    x: contentOffset.x + delta.x,
                    y: contentOffset.y + delta.y
                ))
            }
        }

        func compensateScrollOffset(by dy: CGFloat) {
            rebaseContentOffset(by: .init(x: 0, y: dy))
        }

        public func flashScrollers() {
            nativeScrollView.flashScrollers()
        }

        func handleScrollingAnimation(duration: TimeInterval) {
            if isTracking || scrollingContext.completed {
                cancelCurrentScrolling()
                return
            }
            scrollingContext.update(withDeltaTime: min(1 / 30, duration))
            applyContentOffset(nearestScrollLocationInBounds(offset: .init(
                x: scrollingContext.x.value,
                y: scrollingContext.y.value
            )))
        }

        func nativeScrollWheelWillBegin(_ event: NSEvent) {
            suppressAutoScroll()
            if event.window != nil {
                _lastScrollWheelViewportY = convert(event.locationInWindow, from: nil).y
            }
            excludesNativeOffsetTravel = event.phase.isEmpty && event.momentumPhase.isEmpty
            if !event.phase.isEmpty,
               event.phase != .ended,
               event.phase != .cancelled
            {
                _isTracking = true
            }
        }

        func nativeScrollWheelDidEnd(_ event: NSEvent) {
            excludesNativeOffsetTravel = false
            if event.phase == .ended || event.phase == .cancelled {
                _isTracking = false
            }
        }

        @objc private func nativeLiveScrollDidBegin(_: Notification) {
            isNativeLiveScrollActive = true
            if let event = NSApp.currentEvent,
               event.type == .leftMouseDown || event.type == .leftMouseDragged
            {
                // AppKit's live-scroll notifications cover the system
                // scroller too. Remember direct knob tracking without
                // replacing NSScrollView's native NSScroller.
                _isVerticalScrollerTracking = true
            }
            cancelCurrentScrolling()
            suppressAutoScroll()
        }

        @objc private func nativeLiveScrollDidEnd(_: Notification) {
            isNativeLiveScrollActive = false
            _isVerticalScrollerTracking = false
            suppressAutoScroll()
            needsLayout = true
        }

        @objc private func nativeClipViewBoundsDidChange(_: Notification) {
            let offsetY = contentOffset.y
            if excludesNativeOffsetTravel {
                scrollLedger.exclude(offsetY - lastObservedNativeOffsetY)
            }
            scrollLedger.accrue(offsetY: offsetY)
            lastObservedNativeOffsetY = offsetY
            needsLayout = true
        }

        private func performExcludingNativeOffsetTravel(_ body: () -> Void) {
            let wasExcluding = excludesNativeOffsetTravel
            excludesNativeOffsetTravel = true
            body()
            excludesNativeOffsetTravel = wasExcluding
        }

        private func applyContentOffsetWithoutTravel(_ offset: CGPoint) {
            performExcludingNativeOffsetTravel { applyContentOffset(offset) }
        }

        private func applyContentOffset(_ offset: CGPoint) {
            withoutListAnimation {
                nativeScrollView.contentView.scroll(to: offset)
                nativeScrollView.reflectScrolledClipView(nativeScrollView.contentView)
            }
            needsLayout = true
        }
    }

#else
    #error("ListViewKit requires UIKit or AppKit")
#endif

extension ListScrollView {
    /// How long auto scroll stays off after the event that suppressed it.
    ///
    /// Long enough to bridge the gap between the events of one gesture, and
    /// short enough that a reader who stops gets their list following the tail
    /// again without noticing they waited.
    ///
    /// The gap that sets the floor is a detented mouse wheel's: momentum
    /// frames and live-resize ticks arrive every frame, but a wheel turned
    /// deliberately — one notch at a time, reading back through a log — leaves
    /// a fifth of a second between notches, and every gap the window fails to
    /// cover is a frame where the host scrolls the reader back to the tail.
    /// That is the jitter this exists to remove, so the window is sized to
    /// outlast a slow notch rather than a fast one.
    static var autoScrollSuppressionWindow: TimeInterval {
        0.25
    }

    /// Holds auto scroll off for ``autoScrollSuppressionWindow`` seconds,
    /// restarting the window if one is already running.
    ///
    /// A reader who just moved the viewport — by scrolling it, or by resizing
    /// the window under it — is looking at what they moved it to. Following
    /// the content instead would take it away from them, and the events that
    /// say so arrive in bursts, so the window is a debounce rather than a
    /// timeout: it expires ``autoScrollSuppressionWindow`` seconds after the
    /// *last* one.
    ///
    /// Scheduled in the common run loop modes, so a live resize — which runs
    /// its own tracking loop — still both re-arms and expires the window
    /// while the drag is in progress.
    func suppressAutoScroll() {
        isAutoScrollSuppressed = true
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(endAutoScrollSuppression),
            object: nil
        )
        perform(
            #selector(endAutoScrollSuppression),
            with: nil,
            afterDelay: Self.autoScrollSuppressionWindow,
            inModes: [.common]
        )
    }

    @objc private func endAutoScrollSuppression() {
        isAutoScrollSuppressed = false
        // An offset the content left outside its bounds while this was set
        // still has to be clamped: ``reconcileOffsetWithContentSize`` only ever
        // runs from a layout pass, and with the reader stopped nothing else
        // would schedule one.
        //
        // Only then, though. Invalidating on every expiry would close a loop on
        // UIKit, where the pass re-arms the window from `isTracking`: a finger
        // resting motionless on the list would drive a full layout ten times a
        // second, on content that is not moving at all.
        guard !isContentOffsetWithinBounds(offset: contentOffset) else { return }
        #if canImport(UIKit)
            setNeedsLayout()
        #elseif canImport(AppKit)
            needsLayout = true
        #endif
    }

    /// Suppresses auto scroll when the viewport changed size since the last
    /// layout pass.
    ///
    /// Reading the bounds rather than the frame is what makes this cheap to
    /// call from layout: the frame arrives through several setters the
    /// platforms do not agree on, while every one of them lands here, and
    /// scrolling moves only the bounds *origin*.
    func suppressAutoScrollIfViewportResized() {
        let size = bounds.size
        // Only a viewport with area is a viewport the reader saw, and only
        // those are worth remembering. Auto Layout lays a view out at zero
        // before it lays it out for real, and a list that took that second
        // pass for a resize would open a conversation at the top: the host's
        // first scroll to the end arrives well inside the window and would be
        // declined. Skipping the empty sizes rather than the transitions out
        // of them also gets a collapsed pane right — reopening one at the size
        // it had is not a change the reader needs protecting from, and
        // reopening it at a different size still is.
        guard size.width > 0, size.height > 0 else { return }
        defer { lastLaidOutViewportSize = size }
        guard let previous = lastLaidOutViewportSize, previous != size else { return }
        suppressAutoScroll()
    }
}

public extension ListScrollView {
    /// Whether the list is under the reader's control rather than free to be
    /// scrolled on its behalf.
    ///
    /// True while direct user scrolling, platform momentum or a rebound is
    /// active, and for ``autoScrollSuppressionWindow`` seconds after either
    /// that or a change to the viewport's size — see ``suppressAutoScroll()``.
    ///
    /// Consumers can use this to avoid retargeting programmatic scrolling while
    /// the user is inspecting earlier content. Programmatic spring scrolling is
    /// intentionally not reported as user interaction.
    ///
    /// This is the question a host asks — may I scroll this list for you —
    /// and not the question of who is holding the offset right now, which is
    /// ``isScrollOffsetOwnedByUser``. The two differ by the suppression
    /// window, and the list itself only ever asks the second one: an offset
    /// left outside the content has to be clamped whether or not the host
    /// would have been welcome to scroll.
    var isUserInteractingWithScroll: Bool {
        isScrollOffsetOwnedByUser || isReboundingFromOverscroll || isAutoScrollSuppressed
    }

    /// Whether a finger, a trackpad, or the platform's own momentum currently
    /// owns the content offset.
    var isScrollOffsetOwnedByUser: Bool {
        #if canImport(UIKit)
            isTracking || isDragging || isDecelerating
        #elseif canImport(AppKit)
            isTracking
        #endif
    }

    /// Whether a finger or a pointer is on the content right now.
    ///
    /// Stricter than ``isScrollOffsetOwnedByUser``, which keeps reporting
    /// through momentum: this is the direct-manipulation window only — a
    /// touch dragging, or a trackpad gesture before the lift, or the scroller
    /// knob held. Momentum and rebounds are the offset still owned but the
    /// hand already gone.
    var isReaderHoldingScroll: Bool {
        #if canImport(UIKit)
            isTracking || isDragging
        #elseif canImport(AppKit)
            _isTracking || _isVerticalScrollerTracking
        #endif
    }

    /// Returns whether the vertical offset is at the bottom edge, allowing a
    /// small tolerance for fractional layout and display-scale differences.
    ///
    /// Bottom overscroll also returns `true`. A negative or non-finite
    /// tolerance is treated as zero.
    func isScrolledToBottom(tolerance: CGFloat = 1) -> Bool {
        let normalizedTolerance = tolerance.isFinite ? max(0, tolerance) : 0
        return maximumContentOffset.y - contentOffset.y <= normalizedTolerance
    }
}
