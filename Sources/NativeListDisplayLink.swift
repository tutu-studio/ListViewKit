//
//  NativeListDisplayLink.swift
//  ListViewKit
//

import Foundation

#if canImport(UIKit)
    import UIKit
    typealias ListPlatformView = UIView
#elseif canImport(AppKit)
    import AppKit
    import QuartzCore
    typealias ListPlatformView = NSView
#else
    #error("ListViewKit requires UIKit or AppKit")
#endif

/// A platform display link that does not retain its owner.
///
/// On AppKit the link is created by the host view, so it follows that view
/// between displays and pauses while the view is hidden or detached.
@MainActor
final class NativeListDisplayLink: @unchecked Sendable {
    nonisolated(unsafe) private let link: CADisplayLink
    private let proxy: Proxy

    init(attachedTo view: ListPlatformView, onTick: @escaping (TimeInterval) -> Void) {
        let proxy = Proxy(onTick: onTick)
        self.proxy = proxy
        #if canImport(UIKit)
            let link = CADisplayLink(
                target: proxy,
                selector: #selector(Proxy.tick(_:))
            )
        #elseif canImport(AppKit)
            let link = view.displayLink(
                target: proxy,
                selector: #selector(Proxy.tick(_:))
            )
        #endif
        link.preferredFrameRateRange = .init(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    deinit {
        link.invalidate()
    }

    nonisolated func invalidate() {
        link.invalidate()
    }

    @MainActor
    private final class Proxy: NSObject {
        let onTick: (TimeInterval) -> Void

        init(onTick: @escaping (TimeInterval) -> Void) {
            self.onTick = onTick
            super.init()
        }

        @objc func tick(_ displayLink: CADisplayLink) {
            onTick(displayLink.duration)
        }
    }
}
