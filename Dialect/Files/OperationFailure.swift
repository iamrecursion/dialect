import SwiftUI

/// An operation that didn't happen.
struct OperationFailure {
    let title: LocalizedStringResource
    let reason: String

    init(_ title: LocalizedStringResource, _ error: any Error) {
        self.init(title, reason: error.localizedDescription)
    }

    init(_ title: LocalizedStringResource, reason: String) {
        self.title = title
        self.reason = reason
    }
}

extension View {
    /// Shows `failure`'s alert while it's set, clearing it when dismissed, and
    /// then calling `dismissed`.
    func operationFailureAlert(
        _ failure: Binding<OperationFailure?>, dismissed: @escaping () -> Void = {}
    ) -> some View {
        return alert(
            Text(failure.wrappedValue?.title ?? ""),
            isPresented: Binding(
                get: { failure.wrappedValue != nil },
                set: { if !$0 { failure.wrappedValue = nil } }),
            actions: { Button("OK", action: dismissed) },
            message: { Text(verbatim: failure.wrappedValue?.reason ?? "") })
    }
}
