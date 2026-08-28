#if canImport(UIKit)
// UIKit platforms (including Mac Catalyst) are exercised by the UIKit suites.
#elseif canImport(AppKit)
    import AppKit
    @testable import ListViewKit
    import Testing

    @Suite(.serialized)
    @MainActor
    struct ListScrollViewAppKitTests {
        private func makeScrollView() -> ListScrollView {
            let scrollView = ListScrollView(
                frame: CGRect(x: 0, y: 0, width: 200, height: 200)
            )
            scrollView.contentSize = CGSize(width: 200, height: 1000)
            scrollView.layoutSubtreeIfNeeded()
            return scrollView
        }

        @Test
        func appKitUsesOneNativeScrollHierarchy() throws {
            let scrollView = makeScrollView()
            let nativeScrollView = scrollView.nativeScrollView
            let documentView = try #require(nativeScrollView.documentView)

            #expect(nativeScrollView.superview === scrollView)
            #expect(nativeScrollView.frame == scrollView.bounds)
            #expect(documentView === scrollView.contentDocumentView)
            #expect(documentView.superview === nativeScrollView.contentView)
            #expect(documentView.isFlipped)
            #expect(nativeScrollView.verticalScrollElasticity == .allowed)
            #expect(nativeScrollView.hasVerticalScroller)
            #expect(nativeScrollView.scrollerStyle == .overlay)
            let verticalScroller = try #require(nativeScrollView.verticalScroller)
            #expect(type(of: verticalScroller) == NSScroller.self)
            #expect(verticalScroller.scrollerStyle == .overlay)
            #expect(type(of: verticalScroller).isCompatibleWithOverlayScrollers)
            let hostedScrollers = scrollerViews(in: scrollView)
            #expect(hostedScrollers.count == 1)
            #expect(hostedScrollers.first === verticalScroller)
        }

        private func scrollerViews(in view: NSView) -> [NSScroller] {
            let nested = view.subviews.flatMap { scrollerViews(in: $0) }
            if let scroller = view as? NSScroller {
                return [scroller] + nested
            }
            return nested
        }

        @Test
        func documentSizeAndOffsetAreProjectedThroughTheNativeClipView() {
            let scrollView = makeScrollView()

            #expect(scrollView.contentDocumentView.frame.size == CGSize(width: 200, height: 1000))
            scrollView.contentOffset = CGPoint(x: 0, y: 400)

            #expect(scrollView.contentOffset == CGPoint(x: 0, y: 400))
            #expect(scrollView.nativeScrollView.contentView.bounds.origin == CGPoint(x: 0, y: 400))
        }

        @Test
        func nativeInsetsDefineTheCrossPlatformScrollRange() {
            let scrollView = makeScrollView()
            scrollView.contentInsets = NSEdgeInsets(top: 20, left: 10, bottom: 30, right: 0)

            #expect(scrollView.nativeScrollView.contentInsets.top == 20)
            #expect(scrollView.nativeScrollView.contentInsets.left == 10)
            #expect(scrollView.nativeScrollView.contentInsets.bottom == 30)
            #expect(scrollView.nativeScrollView.contentInsets.right == 0)
            #expect(scrollView.minimumContentOffset == CGPoint(x: -10, y: -20))
            #expect(scrollView.maximumContentOffset == CGPoint(x: 0, y: 830))
        }

        @Test
        func contentShrinkClampsTheNativeViewport() {
            let scrollView = makeScrollView()
            scrollView.contentOffset = CGPoint(x: 0, y: 800)

            scrollView.contentSize.height = 300

            #expect(scrollView.contentOffset == CGPoint(x: 0, y: 100))
            #expect(scrollView.nativeScrollView.contentView.bounds.origin == CGPoint(x: 0, y: 100))
        }

        @Test
        func rebaseTranslatesTheNativeViewportCoordinates() {
            let scrollView = makeScrollView()
            scrollView.contentOffset = CGPoint(x: 0, y: 400)
            scrollView.contentSize.height += 500

            scrollView.rebaseContentOffset(by: CGPoint(x: 0, y: 500))

            #expect(scrollView.contentOffset == CGPoint(x: 0, y: 900))
            #expect(scrollView.nativeScrollView.contentView.bounds.origin == CGPoint(x: 0, y: 900))
        }

        @Test
        func rebaseRetargetsAProgrammaticSpringWithoutCancellingIt() {
            let scrollView = makeScrollView()
            scrollView.contentOffset = CGPoint(x: 0, y: 200)
            scrollView.scroll(to: CGPoint(x: 0, y: 700), preserveVelocity: false)

            scrollView.contentSize.height += 200
            scrollView.rebaseContentOffset(by: CGPoint(x: 0, y: 200))

            #expect(scrollView.contentOffset.y == 400)
            #expect(scrollView.scrollingContext.y.target == 900)
            #expect(scrollView.scrollingDisplayLink != nil)
        }

        @Test
        func rebaseRejectsZeroAndNonfiniteDeltas() {
            let scrollView = makeScrollView()
            scrollView.contentOffset = CGPoint(x: 0, y: 400)

            scrollView.rebaseContentOffset(by: .zero)
            scrollView.rebaseContentOffset(by: CGPoint(x: CGFloat.infinity, y: 100))

            #expect(scrollView.contentOffset == CGPoint(x: 0, y: 400))
        }

        @Test
        func interactionStateObservesNativeLiveScrollLifecycle() {
            let scrollView = makeScrollView()
            let notifications = NotificationCenter.default

            notifications.post(
                name: NSScrollView.willStartLiveScrollNotification,
                object: scrollView.nativeScrollView
            )
            #expect(scrollView.isScrollOffsetOwnedByUser)

            notifications.post(
                name: NSScrollView.didEndLiveScrollNotification,
                object: scrollView.nativeScrollView
            )
            #expect(!scrollView.isScrollOffsetOwnedByUser)
            #expect(scrollView.isAutoScrollSuppressed)
        }

        @Test
        func immediateNavigationUsesTheNativeClipView() {
            let scrollView = makeScrollView()

            scrollView.setContentOffset(CGPoint(x: 0, y: 600), animated: false)

            #expect(scrollView.contentOffset == CGPoint(x: 0, y: 600))
            #expect(scrollView.nativeScrollView.contentView.bounds.origin == CGPoint(x: 0, y: 600))
        }

        @Test
        func programmaticScrollUsesRetargetableSpring() {
            let scrollView = makeScrollView()

            scrollView.scroll(to: CGPoint(x: 0, y: 800), preserveVelocity: false)
            #expect(scrollView.scrollingDisplayLink != nil)

            scrollView.scroll(to: CGPoint(x: 0, y: 700), preserveVelocity: true)
            #expect(scrollView.scrollingContext.y.target == 700)
            #expect(scrollView.scrollingDisplayLink != nil)

            scrollView.cancelCurrentScrolling()
            #expect(scrollView.scrollingDisplayLink == nil)
        }

        @Test
        func activeNativeDisplayLinkDoesNotRetainTheScrollView() {
            weak var releasedScrollView: ListScrollView?

            autoreleasepool {
                let scrollView = makeScrollView()
                scrollView.scroll(to: CGPoint(x: 0, y: 800), preserveVelocity: false)
                releasedScrollView = scrollView
                #expect(scrollView.scrollingDisplayLink != nil)
            }

            #expect(releasedScrollView == nil)
        }

        @Test
        func liveScrollCancelsProgrammaticSpring() {
            let scrollView = makeScrollView()
            scrollView.scroll(to: CGPoint(x: 0, y: 800), preserveVelocity: false)

            NotificationCenter.default.post(
                name: NSScrollView.willStartLiveScrollNotification,
                object: scrollView.nativeScrollView
            )

            #expect(scrollView.scrollingDisplayLink == nil)
            #expect(scrollView.isScrollOffsetOwnedByUser)
        }

        @Test
        func scrollIndicatorConfigurationIsForwardedToNativeAppKit() {
            let scrollView = makeScrollView()

            scrollView.showsVerticalScrollIndicator = false
            #expect(!scrollView.nativeScrollView.hasVerticalScroller)
            #expect(scrollView.maximumContentOffset.y == 800)

            scrollView.showsVerticalScrollIndicator = true
            #expect(scrollView.nativeScrollView.hasVerticalScroller)
        }

        @Test
        func nativeScrollerTilingUsesDefaultInsets() {
            let scrollView = makeScrollView()
            let insets = scrollView.nativeScrollView.scrollerInsets

            #expect(insets.top == 0)
            #expect(insets.bottom == 0)
            #expect(insets.left == 0)
            #expect(insets.right == 0)
        }

        @Test
        func nativeScrollerTilingOwnsTheWindowSafeArea() {
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.titlebarAppearsTransparent = true
            let scrollView = ListScrollView(frame: window.contentView?.bounds ?? .zero)
            window.contentView = scrollView
            scrollView.contentSize = CGSize(width: 400, height: 1000)
            scrollView.layoutSubtreeIfNeeded()

            let insets = scrollView.nativeScrollView.scrollerInsets

            #expect(scrollView.nativeScrollView.safeAreaInsets.top > 0)
            #expect(insets.top == 0)
            #expect(insets.bottom == 0)
            #expect(insets.left == 0)
            #expect(insets.right == 0)
        }
    }
#endif
