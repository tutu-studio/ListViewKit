#if canImport(AppKit)
import AppKit
import Testing
@testable import ListViewKit

@Suite(.serialized)
@MainActor
struct ListScrollViewAppKitTests {
    private func makeWheelEvent(
        deltaY: Int32,
        phase: CGScrollPhase? = nil,
        momentumPhase: CGScrollPhase? = nil
    ) throws -> NSEvent {
        let cgEvent = try #require(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: deltaY,
            wheel2: 0,
            wheel3: 0
        ))
        cgEvent.setIntegerValueField(
            .scrollWheelEventScrollPhase,
            value: Int64(phase?.rawValue ?? 0)
        )
        cgEvent.setIntegerValueField(
            .scrollWheelEventMomentumPhase,
            value: Int64(momentumPhase?.rawValue ?? 0)
        )
        return try #require(NSEvent(cgEvent: cgEvent))
    }

    @Test
    func phaseLessWheelContinuesFromCurrentOffset() throws {
        let scrollView = ListScrollView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        scrollView.contentSize = CGSize(width: 200, height: 2_000)
        scrollView.contentOffset = CGPoint(x: 0, y: 500)

        let event = try makeWheelEvent(deltaY: 1)
        #expect(event.phase.isEmpty)
        #expect(event.momentumPhase.isEmpty)

        scrollView.scrollWheel(with: event)

        #expect(scrollView.contentOffset.y == 490)
    }

    @Test
    func directGestureEndDoesNotBlockProgrammaticScrolling() throws {
        let scrollView = ListScrollView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        scrollView.contentSize = CGSize(width: 200, height: 2_000)
        scrollView.contentOffset = CGPoint(x: 0, y: 500)

        scrollView.scrollWheel(with: try makeWheelEvent(deltaY: 1, phase: .began))
        scrollView.scrollWheel(with: try makeWheelEvent(deltaY: 0, phase: .ended))

        #expect(!scrollView.isTracking)
        scrollView.scroll(to: CGPoint(x: 0, y: 800), preserveVelocity: false)
        #expect(scrollView.scrollingDisplayLink != nil)
        scrollView.cancelCurrentScrolling()
    }

    @Test
    func animatedContentOffsetUsesSpringScrolling() {
        let scrollView = ListScrollView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        scrollView.contentSize = CGSize(width: 200, height: 2_000)

        scrollView.setContentOffset(CGPoint(x: 0, y: 800), animated: true)

        #expect(scrollView.scrollingDisplayLink != nil)
        scrollView.cancelCurrentScrolling()
    }

    @Test
    func immediateContentOffsetCancelsSpringScrolling() {
        let scrollView = ListScrollView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        scrollView.contentSize = CGSize(width: 200, height: 2_000)
        scrollView.scroll(to: CGPoint(x: 0, y: 800), preserveVelocity: false)
        #expect(scrollView.scrollingDisplayLink != nil)

        scrollView.setContentOffset(CGPoint(x: 0, y: 300), animated: false)

        #expect(scrollView.scrollingDisplayLink == nil)
        #expect(scrollView.contentOffset == CGPoint(x: 0, y: 300))
    }

    @Test
    func bounceHandoffContinuesIgnoringSystemMomentumAfterCancellation() throws {
        let scrollView = ListScrollView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        scrollView.contentSize = CGSize(width: 200, height: 2_000)

        scrollView.scrollWheel(with: try makeWheelEvent(deltaY: 100, phase: .began))
        scrollView.scrollWheel(with: try makeWheelEvent(deltaY: 0, phase: .ended))
        scrollView.cancelCurrentScrolling()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        let offsetAfterCancellation = scrollView.contentOffset

        let momentumEvent = try makeWheelEvent(
            deltaY: -10,
            momentumPhase: .changed
        )
        #expect(momentumEvent.momentumPhase == .changed)
        scrollView.scrollWheel(with: momentumEvent)

        #expect(scrollView.contentOffset == offsetAfterCancellation)
        scrollView.scrollWheel(with: try makeWheelEvent(
            deltaY: 0,
            momentumPhase: .ended
        ))
    }
}
#endif
