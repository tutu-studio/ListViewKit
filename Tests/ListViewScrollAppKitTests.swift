#if canImport(AppKit)
import AppKit
import Testing
@testable import ListViewKit

@MainActor
private final class FixedHeightListAdapter: ListViewAdapter {
    enum RowKind: Hashable {
        case row
    }

    func listView(_: ListView, rowKindFor _: ItemType, at _: Int) -> ListViewAdapter.RowKind {
        RowKind.row
    }

    func listViewMakeRow(for _: ListViewAdapter.RowKind) -> ListRowView {
        ListRowView()
    }

    func listView(_: ListView, heightFor _: ItemType, at _: Int) -> CGFloat {
        100
    }

    func listView(_: ListView, configureRowView _: ListRowView, for _: ItemType, at _: Int) {}
}

private struct ScrollItem: Identifiable, Hashable {
    let id: Int
}

@Suite(.serialized)
@MainActor
struct ListViewScrollAppKitTests {
    private func makeListView() -> (
        listView: ListView,
        dataSource: ListViewDiffableDataSource<ScrollItem>,
        adapter: FixedHeightListAdapter
    ) {
        let listView = ListView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let adapter = FixedHeightListAdapter()
        let dataSource = ListViewDiffableDataSource<ScrollItem>(listView: listView)
        listView.adapter = adapter
        listView.contentInsets = NSEdgeInsets(top: 20, left: 10, bottom: 30, right: 0)

        var snapshot = dataSource.snapshot()
        for index in 0 ..< 20 {
            snapshot.append(ScrollItem(id: index))
        }
        dataSource.applySnapshot(snapshot)
        listView.needsLayout = true
        listView.layoutSubtreeIfNeeded()
        return (listView, dataSource, adapter)
    }

    @Test
    func rowPositionsRespectVisibleInsets() {
        let context = makeListView()
        let listView = context.listView
        listView.contentOffset = CGPoint(x: -10, y: 700)

        listView.scrollToRow(at: 5, at: .top, animated: false)
        #expect(listView.contentOffset == CGPoint(x: -10, y: 480))

        listView.contentOffset.y = 700
        listView.scrollToRow(at: 5, at: .middle, animated: false)
        #expect(listView.contentOffset == CGPoint(x: -10, y: 455))

        listView.contentOffset.y = 700
        listView.scrollToRow(at: 5, at: .bottom, animated: false)
        #expect(listView.contentOffset == CGPoint(x: -10, y: 430))

        listView.contentOffset.y = 700
        listView.scrollToRow(at: 0, at: .middle, animated: false)
        #expect(listView.contentOffset == CGPoint(x: -10, y: -20))
    }

    @Test
    func minimalScrollUsesTheUnobscuredVisibleArea() {
        let context = makeListView()
        let listView = context.listView

        listView.contentOffset = CGPoint(x: -10, y: 440)
        listView.scrollToRow(at: 5, at: .none, animated: false)
        #expect(listView.contentOffset == CGPoint(x: -10, y: 440))

        listView.contentOffset.y = 0
        listView.scrollToRow(at: 5, at: .none, animated: false)
        #expect(listView.contentOffset.y == 430)

        listView.contentOffset.y = 700
        listView.scrollToRow(at: 5, at: .none, animated: false)
        #expect(listView.contentOffset.y == 480)
    }

    @Test
    func visibleIndicesExcludeRowsTouchingViewportEdges() {
        let context = makeListView()
        let listView = context.listView

        listView.contentOffset.y = 500
        #expect(listView.indicesForVisibleRows == [5, 6])

        listView.topInset = 40
        listView.contentOffset.y = 540
        #expect(listView.indicesForVisibleRows == [5, 6])
    }

    @Test
    func invalidRowDoesNotChangeTheContentOffset() {
        let context = makeListView()
        let listView = context.listView
        listView.contentOffset = CGPoint(x: -10, y: 321)

        listView.scrollToRow(at: -1, at: .top, animated: false)
        #expect(listView.contentOffset == CGPoint(x: -10, y: 321))

        listView.scrollToRow(at: 20, at: .bottom, animated: false)
        #expect(listView.contentOffset == CGPoint(x: -10, y: 321))
    }
}
#endif
