import Foundation
import Testing

@testable import Dialect

struct SettingValueTests {
    static let values: [SettingValue] = [
        .bool(true), .bool(false), .int(0), .int(1), .int(30), .string("iso"),
        .strings([]), .strings(["fnl", "lisp"]),
    ]

    /// Through a property list's bytes, as WatchConnectivity sends it.
    private func throughAPropertyList(_ value: SettingValue) throws -> Any {
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["value": value.propertyList], format: .binary, options: 0)
        let list = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require((list as? [String: Any])?["value"])
    }

    @Test(arguments: values)
    func roundTripsThroughAPropertyList(_ value: SettingValue) throws {
        let read = SettingValue(propertyList: try throughAPropertyList(value), as: value.kind)
        #expect(read == value)
    }

    /// A Bool and an integer both arrive as an `NSNumber`.
    @Test func keepsBoolsAndIntegersApart() throws {
        #expect(SettingValue(propertyList: try throughAPropertyList(.bool(true)), as: .int) == nil)
        #expect(SettingValue(propertyList: try throughAPropertyList(.int(1)), as: .bool) == nil)
        #expect(SettingValue(propertyList: try throughAPropertyList(.int(0)), as: .bool) == nil)
    }

    @Test func refusesOtherKinds() {
        #expect(SettingValue(propertyList: "1", as: .int) == nil)
        #expect(SettingValue(propertyList: 1.5, as: .int) == nil)
        #expect(SettingValue(propertyList: ["a", 1] as [Any], as: .strings) == nil)
        #expect(SettingValue(propertyList: 1, as: .string) == nil)
    }

    @Test(arguments: values)
    func roundTripsThroughJSON(_ value: SettingValue) throws {
        let data = try JSONEncoder().encode([value])
        #expect(try JSONDecoder().decode([SettingValue].self, from: data) == [value])
    }
}
