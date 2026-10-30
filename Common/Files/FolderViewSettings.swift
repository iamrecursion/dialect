import Foundation

/// How a folder is sorted and grouped, chosen per folder from its More screen.
///
/// Kept as JSON in an extended attribute on the folder, so it follows the
/// folder through renames, moves and copies.
struct FolderViewSettings: Codable, Hashable, Sendable {
    enum SortKey: String, Codable, CaseIterable, Sendable {
        case name, modified, created, size

        var title: LocalizedStringResource {
            switch self {
            case .name: return "Name"
            case .modified: return "Modified"
            case .created: return "Created"
            case .size: return "Size"
            }
        }
    }

    enum Grouping: String, Codable, CaseIterable, Sendable {
        case none, kind, modified

        var title: LocalizedStringResource {
            switch self {
            case .none: return "None"
            case .kind: return "Kind"
            case .modified: return "Modified"
            }
        }
    }

    var sort: SortKey = .name
    var ascending = true
    var grouping: Grouping = .none

    static let attributeName = "com.iamrecursion.dialect.view"

    init(sort: SortKey = .name, ascending: Bool = true, grouping: Grouping = .none) {
        self.sort = sort
        self.ascending = ascending
        self.grouping = grouping
    }

    /// Fields that are missing or can't be read take their defaults, and
    /// unknown ones are ignored, so builds before and after a new field can
    /// both read it.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = FolderViewSettings()
        sort = (try? container.decodeIfPresent(SortKey.self, forKey: .sort)) ?? defaults.sort
        ascending =
            (try? container.decodeIfPresent(Bool.self, forKey: .ascending)) ?? defaults.ascending
        grouping =
            (try? container.decodeIfPresent(Grouping.self, forKey: .grouping)) ?? defaults.grouping
    }

    /// The folder's settings, or the defaults when it has none or they can't be
    /// read.
    static func read(at folder: URL) -> FolderViewSettings {
        guard let data = ExtendedAttributes.get(attributeName, at: folder),
            let settings = try? JSONDecoder().decode(FolderViewSettings.self, from: data)
        else { return FolderViewSettings() }
        return settings
    }

    func write(to folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        try ExtendedAttributes.set(Self.attributeName, try encoder.encode(self), at: folder)
    }
}
