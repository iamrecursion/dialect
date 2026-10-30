import SwiftUI

extension EnvironmentValues {
    /// The one `FileOperations`, which `DialectApp` sets for the whole app.
    /// It's read-only as a key-path write reads it first. It is set by
    /// `fileOperations(_:)`.
    var fileOperations: FileOperations {
        guard let operations = storedFileOperations else {
            preconditionFailure("Files' operations weren't put in the environment.")
        }
        return operations
    }

    /// Optional, so there's no default instance: a second one would break the
    /// actor's one-at-a-time ordering of file changes.
    @Entry fileprivate var storedFileOperations: FileOperations?
}

extension View {
    /// Sets the environment's `fileOperations`.
    func fileOperations(_ operations: FileOperations) -> some View {
        return environment(\.storedFileOperations, operations)
    }
}
