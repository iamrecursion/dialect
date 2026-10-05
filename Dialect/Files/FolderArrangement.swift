import Foundation

/// The rolling windows of Group by Modified, counted back from now.
enum ModifiedBucket: Int, CaseIterable, Sendable {
    case lastDay, last2Days, lastWeek, last30Days, older

    var title: LocalizedStringResource {
        switch self {
        case .lastDay: return "Last Day"
        case .last2Days: return "Last 2 Days"
        case .lastWeek: return "Last Week"
        case .last30Days: return "Last 30 Days"
        case .older: return "Older"
        }
    }
}

/// What a section of a grouped folder holds.
enum SectionGroup: Hashable, Sendable {
    case kind(KindGroup)
    case modified(ModifiedBucket)

    var title: LocalizedStringResource {
        switch self {
        case .kind(let group): return group.title
        case .modified(let bucket): return bucket.title
        }
    }
}

/// A run of a folder's items, under a heading when the folder is grouped.
struct FileSection: Identifiable, Sendable {
    /// `nil` when the folder isn't grouped.
    let group: SectionGroup?
    let items: [FileItem]

    var id: SectionGroup? { group }
}

/// Sorting and grouping a folder's items. Pure: no I/O.
enum FolderArrangement {
    /// - Parameters:
    ///   - foldersFirst: Settings › Files › Folders First. Sessions aren't
    ///     folders for this.
    ///   - now: what Group by Modified counts back from.
    ///   - sizes: the totals of folders and sessions worked out so far.
    static func sections(
        _ items: [FileItem], settings: FolderViewSettings, foldersFirst: Bool, now: Date,
        sizes: [FilePath: Int64]
    ) -> [FileSection] {
        guard !items.isEmpty else { return [] }
        let order = Order(settings: settings, sizes: sizes)

        switch settings.grouping {
        case .none:
            return [FileSection(group: nil, items: order.sorted(items, foldersFirst: foldersFirst))]

        case .kind:
            let groups = Dictionary(grouping: items, by: \.kind.group)
            var keys = groups.keys.map { ($0, String(localized: $0.title)) }
                .sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
                .map(\.0)
            if !settings.ascending { keys.reverse() }
            if foldersFirst, let index = keys.firstIndex(of: .folders) {
                keys.insert(keys.remove(at: index), at: 0)
            }
            return keys.map { key in
                FileSection(
                    group: .kind(key), items: order.sorted(groups[key] ?? [], foldersFirst: false))
            }

        case .modified:
            let groups = Dictionary(grouping: items) { bucket(for: $0.modified, now: now) }
            var buckets = ModifiedBucket.allCases.filter { groups[$0] != nil }
            if !settings.ascending { buckets.reverse() }
            return buckets.map { bucket in
                FileSection(
                    group: .modified(bucket),
                    items: order.sorted(groups[bucket] ?? [], foldersFirst: foldersFirst))
            }
        }
    }

    /// The window a modification date falls in. A missing date is Older, and a
    /// date in the future is the Last Day.
    static func bucket(for date: Date?, now: Date) -> ModifiedBucket {
        guard let date else { return .older }
        let days = now.timeIntervalSince(date) / 86400
        switch days {
        case ..<1: return .lastDay
        case ..<2: return .last2Days
        case ..<7: return .lastWeek
        case ..<30: return .last30Days
        default: return .older
        }
    }

    /// One folder's sort.
    private struct Order {
        let settings: FolderViewSettings
        let sizes: [FilePath: Int64]

        func sorted(_ items: [FileItem], foldersFirst: Bool) -> [FileItem] {
            let sorted = items.sorted(by: precedes)
            guard foldersFirst else { return sorted }
            return sorted.filter { $0.kind == .folder } + sorted.filter { $0.kind != .folder }
        }

        /// Descending reverses the comparison, but missing values stay last
        /// either way; ties fall back to the name, in the same direction.
        private func precedes(_ a: FileItem, _ b: FileItem) -> Bool {
            switch settings.sort {
            case .name: return byName(a, b)
            case .modified: return byValue(a.modified, b.modified, a, b)
            case .created: return byValue(a.created, b.created, a, b)
            case .size: return byValue(size(of: a), size(of: b), a, b)
            }
        }

        private func size(of item: FileItem) -> Int64? {
            return item.isDirectory ? sizes[item.path] : item.size
        }

        private func byValue<T: Comparable>(_ x: T?, _ y: T?, _ a: FileItem, _ b: FileItem)
            -> Bool
        {
            switch (x, y) {
            case (nil, nil): return byName(a, b)
            case (nil, _): return false
            case (_, nil): return true
            case (let x?, let y?):
                if x == y { return byName(a, b) }
                return settings.ascending ? x < y : x > y
            }
        }

        private func byName(_ a: FileItem, _ b: FileItem) -> Bool {
            var order = a.name.localizedStandardCompare(b.name)
            // Names that differ only in case, say, still get a fixed order.
            if order == .orderedSame, a.name != b.name {
                order = a.name < b.name ? .orderedAscending : .orderedDescending
            }
            return settings.ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }
}
