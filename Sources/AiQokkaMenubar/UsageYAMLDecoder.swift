import Foundation
import Yams

enum UsageDecodeError: Error, Equatable, LocalizedError {
    case invalidDocument

    var errorDescription: String? {
        switch self {
        case .invalidDocument:
            return "aiquokka returned YAML with an unsupported document shape."
        }
    }
}

struct UsageYAMLDecoder {
    func decode(yaml: String, fetchedAt: Date = Date()) throws -> UsageSnapshot {
        do {
            guard let root = try Yams.load(yaml: yaml) as? [String: Any] else {
                throw UsageDecodeError.invalidDocument
            }

            let providers = try root.keys.sorted().map { id in
                guard let rawProvider = root[id] as? [String: Any] else {
                    throw UsageDecodeError.invalidDocument
                }
                return decodeProvider(id: id, rawProvider: rawProvider)
            }

            return UsageSnapshot(providers: providers, fetchedAt: fetchedAt)
        } catch let error as UsageDecodeError {
            throw error
        } catch {
            throw UsageDecodeError.invalidDocument
        }
    }

    private func decodeProvider(id: String, rawProvider: [String: Any]) -> ProviderUsage {
        let name = stringValue(rawProvider["provider"]) ?? id
        let plan = stringValue(rawProvider["plan"])
        let windows = decodeWindows(rawProvider["windows"])
        let extras = decodeExtras(rawProvider["extra"])
        return ProviderUsage(id: id, name: name, plan: plan, windows: windows, extras: extras)
    }

    private func decodeWindows(_ rawWindows: Any?) -> [UsageWindow] {
        guard let rawWindows = rawWindows as? [Any] else { return [] }

        return rawWindows.compactMap { rawWindow in
            guard let rawWindow = rawWindow as? [String: Any],
                  let label = stringValue(rawWindow["label"])
            else { return nil }

            let reset = decodeReset(rawWindow["resets_at"])
            return UsageWindow(
                label: label,
                usedPercent: doubleValue(rawWindow["used_percent"]),
                resetDate: reset.date,
                resetText: reset.text
            )
        }
    }

    private func decodeExtras(_ rawExtras: Any?) -> [UsageExtra] {
        guard let rawExtras = rawExtras as? [Any] else { return [] }

        return rawExtras.compactMap { rawExtra in
            guard let rawExtra = rawExtra as? [String: Any],
                  let label = stringValue(rawExtra["label"]),
                  let value = stringValue(rawExtra["value"])
            else { return nil }
            return UsageExtra(label: label, value: value)
        }
    }

    private func decodeReset(_ rawValue: Any?) -> (date: Date?, text: String?) {
        guard let rawValue else { return (nil, nil) }
        if let date = rawValue as? Date { return (date, nil) }

        guard let text = stringValue(rawValue) else { return (nil, nil) }
        if let date = ISO8601DateFormatter.aiQokkaDate(from: text) {
            return (date, nil)
        }
        return (nil, text)
    }

    private func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let value as Double:
            return value
        case let value as NSNumber:
            return value.doubleValue
        case let value as String:
            return Double(value)
        default:
            return nil
        }
    }

    private func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            return value
        case let value as Date:
            return ISO8601DateFormatter.aiQokkaString(from: value)
        case let value as NSNumber:
            return value.stringValue
        case let value as CustomStringConvertible:
            return value.description
        default:
            return nil
        }
    }
}

private extension ISO8601DateFormatter {
    static func aiQokkaDate(from value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }

    static func aiQokkaString(from value: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: value)
    }
}
