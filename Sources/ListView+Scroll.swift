//
//  ListView+Scroll.swift
//  ListViewKit
//
//  Created by 秋星桥 on 5/21/25.
//

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#else
    #error("ListViewKit requires UIKit or AppKit")
#endif

public extension ListView {
    /// The position in the list view (top, middle, bottom) to scroll a specified row to.
    enum ScrollPosition {
        /// The list view scrolls the row of interest to be fully visible with a minimum of movement.
        case none
        /// The list view scrolls the row of interest to the top of the visible table view.
        case top
        /// The list view scrolls the row of interest to the middle of the visible table view.
        case middle
        /// The list view scrolls the row of interest to the bottom of the visible table view.
        case bottom
    }

    /// Scrolls through the list view until a row that an index path identifies is at a particular location on the screen.
    func scrollToRow(at index: Int, at scrollPosition: ScrollPosition, animated: Bool = true) {
        guard index >= 0,
              let itemCount = dataSource?.numberOfItems(in: self),
              index < itemCount
        else {
            return
        }

        let targetRect = rectForRow(at: index)
        let insets = adjustedContentInset
        let visibleMinY = contentOffset.y + insets.top
        let visibleHeight = max(0, bounds.height - insets.top - insets.bottom)
        let visibleMaxY = visibleMinY + visibleHeight
        let targetContentOffsetY: CGFloat = {
            switch scrollPosition {
            case .none:
                if targetRect.height > visibleHeight {
                    return targetRect.minY - insets.top
                }

                if targetRect.minY >= visibleMinY, targetRect.maxY <= visibleMaxY {
                    // The `targetRect` is already fully visible.
                    return contentOffset.y
                }

                return if targetRect.minY < visibleMinY {
                    // The `targetRect` is above the visible content area.
                    targetRect.minY - insets.top
                } else {
                    // The `targetRect` is below the visible content area.
                    targetRect.maxY - bounds.height + insets.bottom
                }
            case .top:
                return targetRect.minY - insets.top
            case .middle:
                return targetRect.midY - insets.top - visibleHeight / 2
            case .bottom:
                return targetRect.maxY - bounds.height + insets.bottom
            }
        }()
        let targetOffset = nearestScrollLocationInBounds(offset: CGPoint(
            x: contentOffset.x,
            y: targetContentOffsetY
        ))
        if animated {
            scroll(to: targetOffset)
        } else {
            setContentOffset(targetOffset, animated: false)
        }
    }
}
