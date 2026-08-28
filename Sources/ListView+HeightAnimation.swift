//
//  ListView+HeightAnimation.swift
//  ListViewKit
//

import Foundation

/// Timing for an explicit semantic row-height transition.
public struct ListViewHeightAnimation: Sendable, Equatable {
    public let duration: TimeInterval

    public init(duration: TimeInterval) {
        self.duration = max(0, duration)
    }
}

#if canImport(AppKit)
    import AppKit
    import QuartzCore

    public extension ListView {
        /// Applies a row-height update while preserving visible presentation
        /// identities and moving the changed row and its downstream rows as one
        /// semantic transition.
        ///
        /// Rows that cross the viewport boundary remain mounted until the
        /// transition finishes. Returning rows begin at their former downstream
        /// coordinates, and no opacity animation is introduced.
        func animateHeightChange(
            forRowWithID identifier: Item.ID,
            animation: ListViewHeightAnimation,
            updates: () -> Void
        ) {
            guard animation.duration > 0,
                  let changedIndex = index(of: identifier),
                  let changedRow = rowView(for: identifier)
            else {
                updates()
                requestLayout()
                layoutNow()
                return
            }

            let oldHeight = changedRow.placedFrame.height
            let startingGeometry = Dictionary(
                uniqueKeysWithValues: visibleRows.map { key, entry in
                    (key, Self.presentationGeometry(for: entry.view))
                }
            )

            let wasHeightTransitionActive = isHeightTransitionActive
            isHeightTransitionActive = true
            updates()
            requestLayout()
            layoutNow()

            let newHeight = rectForRow(with: identifier).height
            guard abs(newHeight - oldHeight) > 0.5 else {
                // Streaming updates usually change text without crossing a
                // line boundary. Do not restart an earlier height animation
                // for those frames; let it keep its original arrival time.
                isHeightTransitionActive = wasHeightTransitionActive
                return
            }

            heightTransitionCleanupGeneration &+= 1
            let generation = heightTransitionCleanupGeneration
            let downstreamInitialOffsetY = oldHeight - newHeight
            let scale = max(
                1,
                window?.backingScaleFactor
                    ?? NSScreen.main?.backingScaleFactor
                    ?? 1
            )

            for (key, entry) in visibleRows {
                guard let rowIndex = index(of: key) else { continue }
                let target = Self.modelGeometry(for: entry.view)
                let start: HeightLayerGeometry = if let existing = startingGeometry[key] {
                    existing
                } else if rowIndex > changedIndex {
                    .init(
                        position: .init(
                            x: target.position.x,
                            y: target.position.y + downstreamInitialOffsetY
                        ),
                        bounds: target.bounds
                    )
                } else {
                    target
                }
                Self.installHeightTransitionAnimations(
                    on: entry.view,
                    from: start,
                    to: target,
                    duration: animation.duration,
                    scale: scale
                )
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + animation.duration) { [weak self] in
                guard let self,
                      generation == heightTransitionCleanupGeneration
                else { return }
                isHeightTransitionActive = false
                requestLayout()
                layoutNow()
            }
        }
    }

    private struct HeightLayerGeometry {
        let position: CGPoint
        let bounds: CGRect
    }

    private extension ListView {
        static func presentationGeometry(for row: ListRowView) -> HeightLayerGeometry {
            guard let layer = row.layer else {
                return .init(
                    position: .init(x: row.frame.midX, y: row.frame.midY),
                    bounds: .init(origin: .zero, size: row.frame.size)
                )
            }
            let presented = layer.presentation() ?? layer
            return .init(position: presented.position, bounds: presented.bounds)
        }

        static func modelGeometry(for row: ListRowView) -> HeightLayerGeometry {
            guard let layer = row.layer else {
                return .init(
                    position: .init(x: row.frame.midX, y: row.frame.midY),
                    bounds: .init(origin: .zero, size: row.frame.size)
                )
            }
            return .init(position: layer.position, bounds: layer.bounds)
        }

        static func installHeightTransitionAnimations(
            on row: ListRowView,
            from start: HeightLayerGeometry,
            to target: HeightLayerGeometry,
            duration: TimeInterval,
            scale: CGFloat
        ) {
            guard let layer = row.layer else { return }
            layer.removeAnimation(forKey: "position")
            layer.removeAnimation(forKey: "bounds")
            layer.removeAnimation(forKey: "ListViewKit.height.position")
            layer.removeAnimation(forKey: "ListViewKit.height.bounds")

            let sampleCount = max(2, Int(ceil(duration * 120)))
            let keyTimes = (0 ... sampleCount).map {
                NSNumber(value: Double($0) / Double(sampleCount))
            }
            if start.position != target.position {
                let animation = CAKeyframeAnimation(keyPath: "position")
                animation.values = (0 ... sampleCount).map { step in
                    let progress = easedHeightProgress(Double(step) / Double(sampleCount))
                    return NSValue(point: .init(
                        x: pixelAlignedHeightValue(
                            interpolateHeightValue(start.position.x, target.position.x, progress),
                            scale: scale
                        ),
                        y: pixelAlignedHeightValue(
                            interpolateHeightValue(start.position.y, target.position.y, progress),
                            scale: scale
                        )
                    ))
                }
                animation.keyTimes = keyTimes
                animation.calculationMode = .discrete
                animation.duration = duration
                layer.add(animation, forKey: "ListViewKit.height.position")
            }
            if start.bounds != target.bounds {
                let animation = CAKeyframeAnimation(keyPath: "bounds")
                animation.values = (0 ... sampleCount).map { step in
                    let progress = easedHeightProgress(Double(step) / Double(sampleCount))
                    return NSValue(rect: .init(
                        x: target.bounds.origin.x,
                        y: target.bounds.origin.y,
                        width: pixelAlignedHeightValue(
                            interpolateHeightValue(start.bounds.width, target.bounds.width, progress),
                            scale: scale
                        ),
                        height: pixelAlignedHeightValue(
                            interpolateHeightValue(start.bounds.height, target.bounds.height, progress),
                            scale: scale
                        )
                    ))
                }
                animation.keyTimes = keyTimes
                animation.calculationMode = .discrete
                animation.duration = duration
                layer.add(animation, forKey: "ListViewKit.height.bounds")
            }
        }

        static func interpolateHeightValue(
            _ start: CGFloat,
            _ end: CGFloat,
            _ progress: Double
        ) -> CGFloat {
            start + (end - start) * CGFloat(progress)
        }

        static func easedHeightProgress(_ progress: Double) -> Double {
            progress * progress * (3 - 2 * progress)
        }

        static func pixelAlignedHeightValue(_ value: CGFloat, scale: CGFloat) -> CGFloat {
            (value * scale).rounded() / scale
        }
    }
#endif
