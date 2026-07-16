# ListViewKit

[![CI](https://github.com/Lakr233/ListViewKit/actions/workflows/ci.yml/badge.svg)](https://github.com/Lakr233/ListViewKit/actions/workflows/ci.yml)

A lightweight, diffable, reusable list view for Swift, UIKit, and AppKit.

![Preview](./Resource/IMG_0BBF74B35BFB-1.jpeg)

## Features

- Automatic row reuse, grouped by a hashable row kind.
- Diffable snapshots with insert, remove, update, and reorder support.
- Variable row heights with identity-based layout caching.
- Stable content offsets while content size changes.
- Spring-based programmatic scrolling.
- Swift 6 main-actor isolation.
- Repeatable 1k, 10k, and 100k row runtime benchmarks.

## Requirements

- Swift 6.0+
- iOS 17.0+
- macCatalyst 17.0+
- macOS 14.0+

## Installation

Add ListViewKit to your package dependencies:

```swift
dependencies: [
    .package(
        url: "https://github.com/Lakr233/ListViewKit",
        from: "1.2.0"
    ),
]
```

Then add `ListViewKit` to the dependencies of your target.

## Usage

### Define an item and row kind

```swift
struct Message: Identifiable, Hashable {
    enum RowKind: Hashable {
        case text
    }

    let id: UUID
    var text: String
}
```

### Configure a typed adapter

`ListViewTypedAdapter` keeps item, row-kind, and row configuration types out
of application-level force casts:

```swift
@MainActor
final class MessageListController {
    let listView = ListView(frame: .zero)
    let dataSource: ListViewDiffableDataSource<Message>
    let adapter: ListViewTypedAdapter<Message, Message.RowKind>

    init() {
        adapter = ListViewTypedAdapter { _, _, _ in .text }
        dataSource = ListViewDiffableDataSource(listView: listView)
        listView.adapter = adapter

        adapter.register(
            .text,
            makeRow: TextRow.init,
            height: { listView, message, _ in
                TextRow.height(for: message.text, width: listView.bounds.width)
            },
            configure: { _, row, message, _ in
                row.configure(with: message.text)
            }
        )
    }
}
```

`TextRow` is an application-defined `ListRowView` subclass. The original
`ListViewAdapter` protocol remains available for existing integrations.

Both `dataSource` and `adapter` are weakly referenced by `ListView`; retain
them for as long as the list is in use, as shown above.

### Apply data

```swift
var snapshot = dataSource.snapshot()
snapshot.append(Message(id: UUID(), text: "Hello ListViewKit"))
dataSource.applySnapshot(snapshot, animatingDifferences: true)
```

Items must have unique, stable identifiers. Changing an item's hashable value
causes visible content and cached height to be refreshed.

For a high-frequency change to one existing item, avoid rebuilding and diffing
a complete snapshot:

```swift
message.text += delta
dataSource.updateItem(message)
```

`updateItem(_:)` reconfigures and remeasures only that identifier. Insertions,
removals, and reorders should continue to use snapshots.

### Prepare rows for configuration

Override `prepareForReuse()` to clear transient state such as text, images,
menus, callbacks, or asynchronous requests:

```swift
override func prepareForReuse() {
    super.prepareForReuse()
    imageTask?.cancel()
    imageTask = nil
    label.text = nil
}
```

ListViewKit calls this method before every row configuration, including the
initial configuration and reconfiguration of an existing visible item. The
implementation should therefore be idempotent.

### Invalidate a self-sizing row

When hosted or expandable content changes size without changing its data-source
item, invalidate that row by item identifier. ListViewKit re-runs only that
row's height closure and keeps the other identity-based height measurements:

```swift
listView.invalidateLayout(forRowWithID: message.id)
```

Use `invalidateLayout()` only when every cached height may have changed, such
as after replacing global typography metrics. The misspelled legacy
`invaliateLayout()` API remains available as a deprecated compatibility shim.

### Follow streaming content

Chat-style clients can capture bottom affinity before applying a snapshot or
invalidating a growing row:

```swift
let shouldFollow = listView.isScrolledToBottom(tolerance: 4)
dataSource.applySnapshot(snapshot)

if shouldFollow && !listView.isUserInteractingWithScroll {
    listView.setContentOffset(listView.maximumContentOffset, animated: false)
}
```

`isUserInteractingWithScroll` includes platform momentum but excludes
programmatic spring scrolling.

### Scroll to a row

```swift
listView.scrollToRow(at: 20, at: .middle, animated: true)
listView.setContentOffset(CGPoint(x: 0, y: 500), animated: true)
```

Row positioning respects adjusted content insets and clamps targets to the
valid scroll range.

## Tests

Run the Swift 6 test suite:

```bash
swift test
```

CI also builds the macOS example and the library for iOS Simulator and
Mac Catalyst destinations.

## Runtime benchmarks

Run deterministic 1k, 10k, and 100k row benchmarks in Release mode:

```bash
swift run -c release ListViewKitBenchmarks
```

See [`Benchmarks/README.md`](./Benchmarks/README.md) for measured operations
and comparison guidance.

## Examples

- `Example/ListExample`: UIKit example project.
- `Example/ListExampleMac`: Swift Package based AppKit example.

## License

ListViewKit is available under the MIT License. See [LICENSE](./LICENSE).

---

Copyright 2025 © Lakr233 & FlowDown Team. All rights reserved.
