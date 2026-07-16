//
//  ListViewTypedAdapter.swift
//  ListViewKit
//

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#else
    #error("ListViewKit requires UIKit or AppKit")
#endif

@MainActor
public final class ListViewTypedAdapter<Item: Identifiable & Hashable, Kind: Hashable>: ListViewAdapter {
    public typealias RowKindProvider = (ListView, Item, Int) -> Kind

    private struct Registration {
        let makeRow: () -> ListRowView
        let height: (ListView, Item, Int) -> CGFloat
        let configure: (ListView, ListRowView, Item, Int) -> Void
    }

    private let rowKindProvider: RowKindProvider
    private var registrations: [Kind: Registration] = [:]

    public init(rowKindFor: @escaping RowKindProvider) {
        rowKindProvider = rowKindFor
    }

    @discardableResult
    public func register<Row: ListRowView>(
        _ kind: Kind,
        makeRow: @escaping () -> Row,
        height: @escaping (ListView, Item, Int) -> CGFloat,
        configure: @escaping (ListView, Row, Item, Int) -> Void
    ) -> Self {
        precondition(registrations[kind] == nil, "A row is already registered for kind \(kind).")
        registrations[kind] = Registration(
            makeRow: makeRow,
            height: height,
            configure: { listView, rowView, item, index in
                guard let row = rowView as? Row else {
                    preconditionFailure(
                        "Registered row kind \(kind) expected \(Row.self), "
                            + "but received \(type(of: rowView))."
                    )
                }
                configure(listView, row, item, index)
            }
        )
        return self
    }

    public func listView(
        _ listView: ListView,
        rowKindFor item: ListViewAdapter.ItemType,
        at index: Int
    ) -> ListViewAdapter.RowKind {
        rowKindProvider(listView, typedItem(item), index)
    }

    public func listViewMakeRow(for kind: ListViewAdapter.RowKind) -> ListRowView {
        registration(for: kind).makeRow()
    }

    public func listView(
        _ listView: ListView,
        heightFor item: ListViewAdapter.ItemType,
        at index: Int
    ) -> CGFloat {
        let item = typedItem(item)
        let kind = rowKindProvider(listView, item, index)
        return registration(for: kind).height(listView, item, index)
    }

    public func listView(
        _ listView: ListView,
        configureRowView rowView: ListRowView,
        for item: ListViewAdapter.ItemType,
        at index: Int
    ) {
        let item = typedItem(item)
        let kind = rowKindProvider(listView, item, index)
        registration(for: kind).configure(listView, rowView, item, index)
    }

    private func typedItem(_ item: ListViewAdapter.ItemType) -> Item {
        guard let item = item as? Item else {
            preconditionFailure(
                "ListViewTypedAdapter expected \(Item.self), but received \(type(of: item))."
            )
        }
        return item
    }

    private func registration(for kind: ListViewAdapter.RowKind) -> Registration {
        guard let kind = kind as? Kind else {
            preconditionFailure(
                "ListViewTypedAdapter expected row kind \(Kind.self), "
                    + "but received \(type(of: kind))."
            )
        }
        return registration(for: kind)
    }

    private func registration(for kind: Kind) -> Registration {
        guard let registration = registrations[kind] else {
            preconditionFailure("No row is registered for kind \(kind).")
        }
        return registration
    }
}
