#if canImport(AppKit)
import AppKit
import Foundation
import ListViewKit

private struct BenchmarkItem: Identifiable, Hashable {
    let id: Int
}

@MainActor
private final class BenchmarkAdapter: ListViewAdapter {
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
        44
    }

    func listView(_: ListView, configureRowView _: ListRowView, for _: ItemType, at _: Int) {}
}

@main
@MainActor
private struct ListViewKitBenchmarks {
    private struct Context {
        let listView: ListView
        let dataSource: ListViewDiffableDataSource<BenchmarkItem>
        let adapter: BenchmarkAdapter
    }

    private static let itemCounts = [1_000, 10_000, 100_000]
    private static let sampleCount = 3
    private static let visibleQueryCount = 20_000
    private static let scrollLayoutCount = 1_000

    static func main() {
        let warmupContext = makeContext(itemCount: 100)
        _ = runVisibleQueries(in: warmupContext.listView, count: 100)
        _ = runScrollLayouts(in: warmupContext.listView, count: 10)

        print("ListViewKit runtime benchmark")
        print("Release configuration; fixed 44pt rows; 800×600 viewport")
        print("")
        print("| Items | Initial layout | 20k visible queries | Per query | 1k scroll layouts |")
        print("| ---: | ---: | ---: | ---: | ---: |")

        for itemCount in itemCounts {
            var context: Context?
            var initialSamples: [Double] = []
            for _ in 0 ..< sampleCount {
                let (candidate, milliseconds) = measure {
                    makeContext(itemCount: itemCount)
                }
                context = candidate
                initialSamples.append(milliseconds)
            }
            guard let context else { continue }

            let visibleSamples = (0 ..< sampleCount).map { _ in
                measure {
                    runVisibleQueries(in: context.listView, count: visibleQueryCount)
                }.1
            }
            let layoutSamples = (0 ..< sampleCount).map { _ in
                measure {
                    runScrollLayouts(in: context.listView, count: scrollLayoutCount)
                }.1
            }
            let initialMilliseconds = median(initialSamples)
            let visibleMilliseconds = median(visibleSamples)
            let layoutMilliseconds = median(layoutSamples)
            let microsecondsPerQuery = visibleMilliseconds * 1_000 / Double(visibleQueryCount)

            print(
                "| \(itemCount) | \(format(initialMilliseconds)) ms "
                    + "| \(format(visibleMilliseconds)) ms "
                    + "| \(format(microsecondsPerQuery)) µs "
                    + "| \(format(layoutMilliseconds)) ms |"
            )
            withExtendedLifetime(context) {}
        }
    }

    private static func makeContext(itemCount: Int) -> Context {
        let listView = ListView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let adapter = BenchmarkAdapter()
        let dataSource = ListViewDiffableDataSource<BenchmarkItem>(listView: listView)
        listView.adapter = adapter

        dataSource.applySnapshot(
            using: (0 ..< itemCount).map(BenchmarkItem.init(id:)),
            animatingDifferences: false
        )
        listView.needsLayout = true
        listView.layoutSubtreeIfNeeded()
        return Context(listView: listView, dataSource: dataSource, adapter: adapter)
    }

    private static func runVisibleQueries(in listView: ListView, count: Int) -> Int {
        let maximumOffset = listView.maximumContentOffset.y
        var resultCount = 0
        for iteration in 0 ..< count {
            let progress = CGFloat(iteration % 997) / 996
            listView.contentOffset.y = maximumOffset * progress
            resultCount &+= listView.indicesForVisibleRows.count
        }
        return resultCount
    }

    private static func runScrollLayouts(in listView: ListView, count: Int) -> Int {
        let maximumOffset = listView.maximumContentOffset.y
        var visibleRowCount = 0
        for iteration in 0 ..< count {
            let progress = CGFloat(iteration) / CGFloat(max(1, count - 1))
            listView.contentOffset.y = maximumOffset * progress
            listView.layoutSubtreeIfNeeded()
            visibleRowCount &+= listView.visibleRowViews.count
        }
        return visibleRowCount
    }

    private static func measure<Result>(_ operation: () -> Result) -> (Result, Double) {
        let start = DispatchTime.now().uptimeNanoseconds
        let result = operation()
        let end = DispatchTime.now().uptimeNanoseconds
        return (result, Double(end - start) / 1_000_000)
    }

    private static func median(_ samples: [Double]) -> Double {
        let sortedSamples = samples.sorted()
        return sortedSamples[sortedSamples.count / 2]
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
#else
#error("ListViewKitBenchmarks currently requires AppKit")
#endif
