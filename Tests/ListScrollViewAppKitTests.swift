#if canImport(AppKit)
import AppKit
import Testing
@testable import ListViewKit

@MainActor
struct ListScrollViewAppKitTests {
    @Test
    func phaseLessWheelContinuesFromCurrentOffset() throws {
        let scrollView = ListScrollView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        scrollView.contentSize = CGSize(width: 200, height: 2_000)
        scrollView.contentOffset = CGPoint(x: 0, y: 500)

        let cgEvent = try #require(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: 1,
            wheel2: 0,
            wheel3: 0
        ))
        let event = try #require(NSEvent(cgEvent: cgEvent))
        #expect(event.phase.isEmpty)
        #expect(event.momentumPhase.isEmpty)

        scrollView.scrollWheel(with: event)

        #expect(scrollView.contentOffset.y == 490)
    }
}
#endif
