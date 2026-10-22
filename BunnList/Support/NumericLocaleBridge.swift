import BunnListCore
import Foundation

/// The only place that reads the device locale for number input. Core stays locale-free; the app passes
/// "," as an extra decimal separator only when the region's decimal separator is "," and the field allows it.
enum NumericLocaleBridge {
    static func extraDecimalSeparator(for locale: Locale = .current, policy: NumericFieldPolicy) -> Character? {
        guard locale.decimalSeparator == ",", policy.allowsCommaDecimalSeparator else { return nil }
        return ","
    }

    static func parse(_ text: String, policy: NumericFieldPolicy, locale: Locale = .current) throws -> NormalizedDecimal? {
        try NumericInputParser.parse(text, policy: policy,
                                     extraDecimalSeparator: extraDecimalSeparator(for: locale, policy: policy))
    }
}
