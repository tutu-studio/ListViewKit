//
//  Created by ktiays on 2025/1/14.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import DequeModule

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#else
    #error("ListViewKit requires UIKit or AppKit")
#endif

public struct ListViewHeightAnimation: Sendable, Equatable {
    public let duration: TimeInterval

    public init(duration: TimeInterval) {
        self.duration = max(0, duration)
    }
}

open class ListView: ListScrollView {
    private struct AnimatedHeightTransition {
        let changedIndex: Int
        let downstreamInitialOffsetY: CGFloat
    }

    public var id: UUID = .init()

    public typealias DataSource = ListViewDataSource
    public typealias Adapter = ListViewAdapter

    public weak var dataSource: DataSource? {
        didSet { assert(oldValue == nil) }
    }

    public weak var adapter: (any Adapter)?

    lazy var layoutCache: LayoutCache = .init(self)
    lazy var visibleRows: [AnyHashable: ListRowView] = [:]
    lazy var reusableRows: [AnyHashable: Reference<Deque<ListRowView>>] = [:]
    var rowsPendingRemoval: [ListRowView] = []
    private var animatedLayoutCleanupGeneration: UInt64 = 0
    private var animatedHeightTransition: AnimatedHeightTransition?
    private var isPerformingHeightTransition = false

    public var topInset: CGFloat = 0 {
        didSet {
            #if canImport(UIKit)
                setNeedsLayout()
            #elseif canImport(AppKit)
                needsLayout = true
            #endif
        }
    }

    public var bottomInset: CGFloat = 0 {
        didSet {
            #if canImport(UIKit)
                setNeedsLayout()
            #elseif canImport(AppKit)
                needsLayout = true
            #endif
        }
    }

    override public init(frame: CGRect) {
        super.init(frame: frame)

        #if canImport(UIKit)
            alwaysBounceVertical = true
            clipsToBounds = true
        #elseif canImport(AppKit)
            layer?.masksToBounds = true
        #endif
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError()
    }

    var supposedContentSize: CGSize {
        .init(
            width: frame.width,
            height: layoutCache.contentHeight + topInset + bottomInset
        )
    }

    override open var frame: CGRect {
        get { super.frame }
        set {
            if super.frame != newValue {
                // prevent scroll animation being canceled
                super.frame = newValue
            }
        }
    }

    #if canImport(UIKit)
        override open func layoutSubviews() {
            super.layoutSubviews()
            performLayout()
        }

    #elseif canImport(AppKit)
        override open func layout() {
            super.layout()
            performLayout()
        }
    #endif

    private func performLayout() {
        let bounds = bounds
        layoutCache.contentBounds = bounds
        contentSize = supposedContentSize

        let contentOffsetY = contentOffset.y
        let minimumContentOffsetY = minimumContentOffset.y
        let maximumContentOffsetY = maximumContentOffset.y
        let preservesRowsForAnimation = isPerformingHeightTransition
            || preservesRowsForCurrentLayoutAnimation
        let heightTransition = preservesRowsForAnimation
            && !isPerformingHeightTransition
            ? makeAnimatedHeightTransition()
            : nil
        if contentOffsetY >= minimumContentOffsetY,
           contentOffsetY <= maximumContentOffsetY,
           !preservesRowsForAnimation {
            animatedLayoutCleanupGeneration &+= 1
            recycleAllVisibleRows()
        }

        animatedHeightTransition = heightTransition
        prepareVisibleRows()
        animatedHeightTransition = nil
        for (id, rowView) in visibleRows {
            updateFrame(of: rowView, to: rectForRow(with: id))
        }

        #if DEBUG
            let sortedRows = visibleRows
                .map(\.value)
                .sorted {
                    $0.frame.minY < $1.frame.minY
                }
            var maxY: CGFloat = 0
            for row in sortedRows {
                assert(row.frame.minY >= maxY) // float precision error
                maxY = row.frame.maxY
            }
        #endif

        removeUnusedRowsFromSuperview()
        if preservesRowsForAnimation, !isPerformingHeightTransition {
            scheduleAnimatedLayoutCleanup()
        }
    }

    private func makeAnimatedHeightTransition() -> AnimatedHeightTransition? {
        guard let dataSource else { return nil }
        var changes: [(index: Int, oldHeight: CGFloat, newHeight: CGFloat)] = []
        for (identifier, rowView) in visibleRows {
            let targetFrame = rectForRow(with: identifier)
            guard abs(rowView.frame.height - targetFrame.height) > 0.5,
                  let index = dataSource.itemIndex(for: identifier, in: self) else {
                continue
            }
            changes.append((
                index: index,
                oldHeight: rowView.frame.height,
                newHeight: targetFrame.height
            ))
        }
        guard changes.count == 1, let change = changes.first else { return nil }
        return AnimatedHeightTransition(
            changedIndex: change.index,
            downstreamInitialOffsetY: change.oldHeight - change.newHeight
        )
    }

    private var preservesRowsForCurrentLayoutAnimation: Bool {
        #if canImport(AppKit)
            let context = NSAnimationContext.current
            return context.allowsImplicitAnimation && context.duration > 0
        #else
            return false
        #endif
    }

    private func scheduleAnimatedLayoutCleanup() {
        #if canImport(AppKit)
            scheduleAnimatedLayoutCleanup(
                after: NSAnimationContext.current.duration
            )
        #endif
    }

    #if canImport(AppKit)
        private func scheduleAnimatedLayoutCleanup(after delay: TimeInterval) {
            animatedLayoutCleanupGeneration &+= 1
            let generation = animatedLayoutCleanupGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self,
                      generation == animatedLayoutCleanupGeneration else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0
                    context.allowsImplicitAnimation = false
                    performLayout()
                }
            }
        }
    #endif

    func updateVisibleItemsLayout() {
        let bounds = bounds
        layoutCache.contentBounds = bounds
        contentSize = supposedContentSize

        for (id, rowView) in visibleRows {
            updateFrame(of: rowView, to: rectForRow(with: id))
        }

        removeUnusedRowsFromSuperview()
    }

    #if canImport(AppKit)
        public func animateHeightChange(
            forRowWithID identifier: some Hashable,
            animation: ListViewHeightAnimation,
            updates: () -> Void
        ) {
            let key = AnyHashable(identifier)
            guard animation.duration > 0,
                  let changedRow = visibleRows[key],
                  let dataSource,
                  let changedIndex = dataSource.itemIndex(
                      for: identifier,
                      in: self
                  ) else {
                updates()
                needsLayout = true
                layoutSubtreeIfNeeded()
                return
            }

            let oldHeight = changedRow.frame.height
            let startingGeometry = Dictionary(
                uniqueKeysWithValues: visibleRows.map { rowKey, row in
                    (rowKey, Self.presentationGeometry(for: row))
                }
            )

            animatedLayoutCleanupGeneration &+= 1
            isPerformingHeightTransition = true
            updates()
            performLayout()
            layoutSubtreeIfNeeded()
            isPerformingHeightTransition = false

            let newHeight = rectForRow(with: identifier).height
            let downstreamInitialOffsetY = oldHeight - newHeight
            let scale = max(
                1,
                window?.backingScaleFactor
                    ?? NSScreen.main?.backingScaleFactor
                    ?? 1
            )
            for (rowKey, row) in visibleRows {
                guard let rowIndex = dataSource.itemIndex(
                    for: rowKey,
                    in: self
                ) else { continue }
                let target = Self.modelGeometry(for: row)
                let start: LayerGeometry
                if let existing = startingGeometry[rowKey] {
                    start = existing
                } else if rowIndex > changedIndex {
                    start = LayerGeometry(
                        position: CGPoint(
                            x: target.position.x,
                            y: target.position.y + downstreamInitialOffsetY
                        ),
                        bounds: target.bounds
                    )
                } else {
                    start = target
                }
                Self.installHeightTransitionAnimations(
                    on: row,
                    from: start,
                    to: target,
                    duration: animation.duration,
                    scale: scale
                )
            }
            scheduleAnimatedLayoutCleanup(after: animation.duration)
        }

        private struct LayerGeometry {
            let position: CGPoint
            let bounds: CGRect
        }

        private static func presentationGeometry(
            for row: ListRowView
        ) -> LayerGeometry {
            guard let layer = row.layer else {
                return LayerGeometry(
                    position: CGPoint(x: row.frame.midX, y: row.frame.midY),
                    bounds: CGRect(origin: .zero, size: row.frame.size)
                )
            }
            let presented = layer.presentation() ?? layer
            return LayerGeometry(
                position: presented.position,
                bounds: presented.bounds
            )
        }

        private static func modelGeometry(
            for row: ListRowView
        ) -> LayerGeometry {
            guard let layer = row.layer else {
                return LayerGeometry(
                    position: CGPoint(x: row.frame.midX, y: row.frame.midY),
                    bounds: CGRect(origin: .zero, size: row.frame.size)
                )
            }
            return LayerGeometry(position: layer.position, bounds: layer.bounds)
        }

        private static func installHeightTransitionAnimations(
            on row: ListRowView,
            from start: LayerGeometry,
            to target: LayerGeometry,
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
                    let progress = easedProgress(
                        Double(step) / Double(sampleCount)
                    )
                    return NSValue(point: CGPoint(
                        x: pixelAligned(
                            interpolate(
                                start.position.x,
                                target.position.x,
                                progress
                            ),
                            scale: scale
                        ),
                        y: pixelAligned(
                            interpolate(
                                start.position.y,
                                target.position.y,
                                progress
                            ),
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
                    let progress = easedProgress(
                        Double(step) / Double(sampleCount)
                    )
                    return NSValue(rect: CGRect(
                        x: target.bounds.origin.x,
                        y: target.bounds.origin.y,
                        width: pixelAligned(
                            interpolate(
                                start.bounds.width,
                                target.bounds.width,
                                progress
                            ),
                            scale: scale
                        ),
                        height: pixelAligned(
                            interpolate(
                                start.bounds.height,
                                target.bounds.height,
                                progress
                            ),
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

        private static func interpolate(
            _ start: CGFloat,
            _ end: CGFloat,
            _ progress: Double
        ) -> CGFloat {
            start + (end - start) * CGFloat(progress)
        }

        private static func easedProgress(_ progress: Double) -> Double {
            progress * progress * (3 - 2 * progress)
        }

        private static func pixelAligned(
            _ value: CGFloat,
            scale: CGFloat
        ) -> CGFloat {
            (value * scale).rounded() / scale
        }
    #endif

    private func updateFrame(of rowView: ListRowView, to targetFrame: CGRect) {
        guard rowView.frame != targetFrame else { return }
        let sizeChanged = rowView.frame.size != targetFrame.size
        rowView.frame = targetFrame
        guard sizeChanged else { return }
        #if canImport(UIKit)
            rowView.setNeedsLayout()
        #elseif canImport(AppKit)
            rowView.needsLayout = true
        #endif
    }
}

extension ListView: @MainActor Identifiable {}

/// internal api
extension ListView {
    func reusableDequeRef(for kind: AnyHashable) -> Reference<Deque<ListRowView>> {
        if let ref = reusableRows[kind] {
            return ref
        }
        @Reference var newRef: Deque<ListRowView> = .init()
        reusableRows[kind] = _newRef
        return _newRef
    }

    @discardableResult
    func ensureRowView(for index: Int) -> ListRowView {
        guard let identifier = dataSource?.itemIdentifier(at: index, in: self) else {
            assertionFailure()
            return .init()
        }
        let key = AnyHashable(identifier)
        if let view = visibleRows[key] {
            return view
        }

        guard let dataSource, let adapter else {
            assertionFailure()
            return .init()
        }

        guard let item = dataSource.item(at: index, in: self) else {
            assertionFailure()
            return .init()
        }
        let kind = adapter.listView(self, rowKindFor: item, at: index)

        return reusableDequeRef(for: .init(kind))
            .modifying { pool in
                let row: ListRowView
                if let reusedRow = pool.popFirst() {
                    prepareReusedRowForPlacement(reusedRow)
                    row = reusedRow
                } else {
                    row = adapter.listViewMakeRow(for: kind)
                }
                row.rowKind = kind
                configureRowView(row, for: item, at: index)
                visibleRows[key] = row
                if row.superview != self {
                    addSubview(row)
                }
                var initialFrame = rectForRow(at: index)
                if let transition = animatedHeightTransition,
                   index > transition.changedIndex {
                    initialFrame.origin.y += transition.downstreamInitialOffsetY
                }
                installInitialFrame(initialFrame, on: row)
                return row
            }
    }

    private func prepareReusedRowForPlacement(_ rowView: ListRowView) {
        rowView.layer?.removeAllAnimations()
    }

    private func installInitialFrame(_ frame: CGRect, on rowView: ListRowView) {
        #if canImport(UIKit)
            UIView.performWithoutAnimation {
                rowView.frame = frame
            }
        #elseif canImport(AppKit)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                rowView.frame = frame
            }
        #endif
    }

    func prepareVisibleRows() {
        for index in indicesForVisibleRows {
            _ = ensureRowView(for: index)
        }
    }

    func reconfigureRowView(for identifier: any Hashable) {
        guard let dataSource, let view = visibleRows[AnyHashable(identifier)] else {
            return
        }
        guard let index = dataSource.itemIndex(for: identifier, in: self) else {
            return
        }
        guard let item = dataSource.item(at: index, in: self) else {
            return
        }
        configureRowView(view, for: item, at: index)
        #if canImport(UIKit)
            view.setNeedsLayout()
            view.layoutIfNeeded()
        #elseif canImport(AppKit)
            view.needsLayout = true
            view.display()
        #endif
    }

    func configureRowView(_ rowView: ListRowView, for _: any Identifiable, at index: Int) {
        guard let dataSource, let adapter else { return }
        guard let item = dataSource.item(at: index, in: self) else { return }
        rowView.prepareForReuse()
        adapter.listView(self, configureRowView: rowView, for: item, at: index)
    }

    func recycleAllVisibleRows() {
        let visibleRect = CGRect(origin: contentOffset, size: bounds.size)
        var identifiersNeedsRecycled: Set<AnyHashable> = .init()
        for (id, _) in visibleRows {
            let targetFrame = rectForRow(with: id)
            if !targetFrame.intersects(visibleRect) {
                identifiersNeedsRecycled.insert(id)
            }
        }

        for id in identifiersNeedsRecycled {
            let recycled = recycleRow(with: id)
            assert(recycled != nil)
        }
    }

    @discardableResult
    func recycleRow(with identifier: AnyHashable) -> ListRowView? {
        guard let rowView = visibleRows.removeValue(forKey: identifier) else {
            return nil
        }
        recycleRowView(rowView)
        return rowView
    }

    func recycleRowView(_ rowView: ListRowView) {
        guard let rowKind = rowView.rowKind else {
            assertionFailure()
            return
        }
        let kind = AnyHashable(rowKind)
        rowView.rowKind = nil
        reusableDequeRef(for: kind)
            .modifying { $0.append(rowView) }
        rowsPendingRemoval.append(rowView)
    }

    func removeUnusedRowsFromSuperview() {
        let pendingRows = rowsPendingRemoval
        rowsPendingRemoval.removeAll(keepingCapacity: true)
        for rowView in pendingRows where rowView.rowKind == nil {
            rowView.removeFromSuperview()
        }
    }

    @discardableResult
    func updateRowKindIfNeeded(for identifier: AnyHashable) -> ListRowView? {
        guard let adapter, let dataSource else {
            return nil
        }
        guard let rowView = visibleRows[identifier] else {
            return nil
        }
        guard let currentKind = rowView.rowKind else {
            return nil
        }
        guard let index = dataSource.itemIndex(for: identifier, in: self) else {
            assertionFailure()
            return nil
        }
        guard let item = dataSource.item(at: index, in: self) else {
            assertionFailure()
            return nil
        }
        let newKind = adapter.listView(self, rowKindFor: item, at: index)
        if AnyHashable(currentKind) == AnyHashable(newKind) {
            return nil
        }

        // The kind of the row has changed.
        recycleRow(with: identifier)
        return ensureRowView(for: index)
    }
}
