import SwiftUI

extension NumberFormatter {
    static let defaultFormatter: NumberFormatter = .init()
    static let oneDecimalFormatter: NumberFormatter = .init(style: .decimal, minimumFractionDigits: 1, maximumFractionDigits: 1)
    static let twoDecimalFormatter: NumberFormatter = .init(style: .decimal, minimumFractionDigits: 2, maximumFractionDigits: 2)
    static let percentFormatter: NumberFormatter = .init(style: .percent, minimumFractionDigits: 0, maximumFractionDigits: 0)

    // Integer formatters (cached singletons to avoid repeated allocations in views)
    static let integerFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 0
        f.allowsFloats = false
        return f
    }()

    static let signedIntegerFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 0
        f.allowsFloats = false
        f.positivePrefix = "+"
        return f
    }()
}

extension NumberFormatter {
    convenience init(
        style: NumberFormatter.Style = .none,
        minimumFractionDigits: Int? = nil,
        maximumFractionDigits: Int? = nil
    ) {
        self.init()
        numberStyle = style
        if let minDigits = minimumFractionDigits {
            self.minimumFractionDigits = minDigits
        }
        if let maxDigits = maximumFractionDigits {
            self.maximumFractionDigits = maxDigits
        }
    }
}
