//
//  Created by ktiays on 2025/1/15.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

@propertyWrapper
final class Reference<T> {
    var wrappedValue: T

    init(wrappedValue: T) {
        self.wrappedValue = wrappedValue
    }

    init(_ wrappedValue: T) {
        self.wrappedValue = wrappedValue
    }

    func modifying<R>(_ modifier: (inout T) throws -> R) rethrows -> R {
        try modifier(&wrappedValue)
    }
}
