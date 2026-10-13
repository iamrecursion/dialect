import Foundation

/// A mirrored setting's value, as the watch uses it.
enum SettingValue: Hashable, Sendable {
    case bool(Bool)
    case int(Int)
    case string(String)
    case strings([String])

    enum Kind: Sendable {
        case bool
        case int
        case string
        case strings
    }

    var kind: Kind {
        switch self {
        case .bool: return .bool
        case .int: return .int
        case .string: return .string
        case .strings: return .strings
        }
    }

    /// As a property list holds it.
    var propertyList: Any {
        switch self {
        case .bool(let value): return value
        case .int(let value): return value
        case .string(let value): return value
        case .strings(let value): return value
        }
    }

    /// A property-list value read as `kind`, or `nil` if it's something else.
    ///
    /// A property list's Bool and integer can both arrive as an `NSNumber`,
    /// which converts to either, so a number is read by what it was made as.
    init?(propertyList: Any, as kind: Kind) {
        switch kind {
        case .bool:
            guard Self.isBoolean(propertyList), let value = propertyList as? Bool else {
                return nil
            }
            self = .bool(value)
        case .int:
            guard !Self.isBoolean(propertyList), let value = propertyList as? Int else {
                return nil
            }
            self = .int(value)
        case .string:
            guard let value = propertyList as? String else { return nil }
            self = .string(value)
        case .strings:
            guard let value = propertyList as? [String] else { return nil }
            self = .strings(value)
        }
    }

    private static func isBoolean(_ value: Any) -> Bool {
        return CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID()
    }

    var bool: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var int: Int? {
        guard case .int(let value) = self else { return nil }
        return value
    }

    var string: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var strings: [String]? {
        guard case .strings(let value) = self else { return nil }
        return value
    }
}

// JSON, for the watch's mirror. JSON keeps true apart from 1, so a value reads back as the kind it
// was written as.
extension SettingValue: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .strings(try container.decode([String].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .strings(let value): try container.encode(value)
        }
    }
}
