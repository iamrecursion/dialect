import Foundation

/// One row of Info: a label and its value.
struct InfoField: Hashable, Identifiable {
    /// Info's rows, in order.
    enum Label: CaseIterable {
        case name, ext, type, size, created, modified, path, hidden, readOnly, items

        var title: LocalizedStringResource {
            switch self {
            case .name: return "Name"
            case .ext: return "Extension"
            case .type: return "Type"
            case .size: return "Size"
            case .created: return "Created"
            case .modified: return "Modified"
            case .path: return "Path"
            case .hidden: return "Hidden"
            case .readOnly: return "Read Only"
            case .items: return "Items"
            }
        }
    }

    let label: Label
    let value: String

    var id: Label { label }
}

/// What the Extended screen shows: permissions, owner and group, and extended
/// attributes.
struct ExtendedInfo: Equatable {
    /// As `ls` writes them: `rw-r--r--`.
    let permissions: String
    /// What they mean, a line for each of owner, group and everyone.
    let access: [String]
    let owner: String
    let group: String
    let attributes: [ExtendedAttribute]
}

/// The information an item's More screen, Folder Info and the file placeholder
/// show.
enum FileInfo {
    /// Info's fields for an item, in order.
    ///
    /// - Parameters:
    ///   - size: a file's size, or a folder's total once worked out.
    ///   - itemCount: Folder Info's count of entries; `nil` leaves Items out.
    ///   - date: Created and Modified as Settings › Appearance says.
    static func fields(
        for item: FileItem, size: Int64?, itemCount: Int?, date: (Date) -> String
    ) -> [InfoField] {
        let isRoot = item.path == .root
        var fields: [InfoField] = []
        func add(_ label: InfoField.Label, _ value: String) {
            fields.append(InfoField(label: label, value: value))
        }
        // The name without its extension, which has its own row.
        add(.name, isRoot ? String(localized: "Files") : item.baseName)
        if item.kind != .folder {
            add(.ext, item.pathExtension.isEmpty ? String(localized: "None") : item.pathExtension)
        }
        add(.type, String(localized: item.kind.typeName))
        add(.size, SizeDisplay.string(size))
        add(.created, item.created.map(date) ?? "—")
        add(.modified, item.modified.map(date) ?? "—")
        add(.path, item.path.display)
        add(.hidden, yesNo(item.isHidden))
        add(.readOnly, yesNo(item.isReadOnly))
        if let itemCount {
            add(.items, itemCount.formatted())
        }
        return fields
    }

    /// The line under the name in Info's header: "Text Document · 2 KB".
    static func summary(for item: FileItem, size: Int64?) -> String {
        return "\(String(localized: item.kind.typeName)) · \(SizeDisplay.string(size))"
    }

    /// The fields Info's card shows: all but the header's.
    static func cardFields(_ fields: [InfoField]) -> [InfoField] {
        return fields.filter { ![.name, .type, .size].contains($0.label) }
    }

    private static func yesNo(_ value: Bool) -> String {
        return value ? String(localized: "Yes") : String(localized: "No")
    }

    /// Every entry in a folder, hidden ones included; `nil` when it can't be
    /// read.
    static func itemCount(at url: URL) -> Int? {
        return try? FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false))
            .count
    }

    /// An item's extended information, read without following a final symbolic
    /// link; `nil` when it's gone.
    static func extended(at url: URL) -> ExtendedInfo? {
        guard
            let attributes = try? FileManager.default.attributesOfItem(
                atPath: url.path(percentEncoded: false))
        else { return nil }
        let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        return ExtendedInfo(
            permissions: permissions(mode), access: access(mode),
            owner: attributes[.ownerAccountName] as? String ?? "—",
            group: attributes[.groupOwnerAccountName] as? String ?? "—",
            attributes: ExtendedAttributes.names(at: url))
    }

    /// The permission bits as `rwxr-xr-x`.
    static func permissions(_ mode: Int) -> String {
        let letters: [Character] = ["r", "w", "x"]
        return String(
            (0..<9).map { bit in
                mode & (0o400 >> bit) != 0 ? letters[bit % 3] : "-"
            })
    }

    /// The permission bits spelled out: "Owner: Read, Write".
    static func access(_ mode: Int) -> [String] {
        let whom = [
            String(localized: "Owner"), String(localized: "Group"), String(localized: "Everyone"),
        ]
        let what = [
            String(localized: "Read"), String(localized: "Write"), String(localized: "Execute"),
        ]
        return (0..<3).map { who in
            let granted = (0..<3).filter { mode & (0o400 >> (who * 3 + $0)) != 0 }.map { what[$0] }
            let list =
                granted.isEmpty
                ? String(localized: "No Access")
                : granted.formatted(.list(type: .and, width: .narrow))
            return "\(whom[who]): \(list)"
        }
    }
}
