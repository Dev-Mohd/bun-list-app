import Foundation

/// Per-field rules for numeric input. Range and precision belong to the field, not to the parser.
public struct NumericFieldPolicy: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case integer
        case decimal(maxFractionDigits: Int)
    }

    public let kind: Kind
    public let maxIntegerDigits: Int
    public let minimum: Decimal?
    public let maximum: Decimal?

    public init(kind: Kind, maxIntegerDigits: Int, minimum: Decimal? = nil, maximum: Decimal? = nil) {
        self.kind = kind
        self.maxIntegerDigits = maxIntegerDigits
        self.minimum = minimum
        self.maximum = maximum
    }

    public static func integer(maxDigits: Int, minimum: Decimal? = nil, maximum: Decimal? = nil) -> NumericFieldPolicy {
        NumericFieldPolicy(kind: .integer, maxIntegerDigits: maxDigits, minimum: minimum, maximum: maximum)
    }

    public static func decimal(maxIntegerDigits: Int, maxFractionDigits: Int,
                               minimum: Decimal? = nil, maximum: Decimal? = nil) -> NumericFieldPolicy {
        NumericFieldPolicy(kind: .decimal(maxFractionDigits: maxFractionDigits), maxIntegerDigits: maxIntegerDigits,
                           minimum: minimum, maximum: maximum)
    }

    /// The local "," exception is only allowed on short decimal fields, so "1,500" can never mean 1500.
    public var allowsCommaDecimalSeparator: Bool {
        if case .decimal = kind { return maxIntegerDigits <= NumericInputParser.maxIntegerDigitsForComma }
        return false
    }
}

/// A validated number kept as a canonical decimal string ("12.5"), never as Double.
public struct NormalizedDecimal: Hashable, Codable, Sendable, CustomStringConvertible {
    public let string: String

    public var description: String { string }

    public var decimal: Decimal { Decimal(string: string)! }
}

public enum NumericInputError: Error, Equatable, Sendable {
    case invalidCharacter(Character)
    case repeatedSeparator
    case missingDigits
    case fractionNotAllowed
    case tooManyIntegerDigits
    case tooManyFractionDigits
    case belowMinimum
    case aboveMaximum
    case extraSeparatorNotAllowed
}

/// Deterministic input parser shared by iOS and the Linux tests. It never reads Locale and never
/// uses NumberFormatter; the app decides whether to pass the "," exception (see `extraDecimalSeparator`).
public enum NumericInputParser {
    public static let maxIntegerDigitsForComma = 4

    /// Returns nil for empty input (a missing optional value), which is different from zero or an error.
    public static func parse(_ input: String, policy: NumericFieldPolicy,
                             extraDecimalSeparator: Character? = nil) throws -> NormalizedDecimal? {
        if let extra = extraDecimalSeparator, extra != "," || !policy.allowsCommaDecimalSeparator {
            throw NumericInputError.extraSeparatorNotAllowed
        }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        var integerDigits = ""
        var fractionDigits = ""
        var sawSeparator = false
        for character in trimmed {
            if let digit = asciiDigit(character) {
                if sawSeparator { fractionDigits.append(digit) } else { integerDigits.append(digit) }
            } else if character == "." || character == "\u{066B}" || character == extraDecimalSeparator {
                if sawSeparator { throw NumericInputError.repeatedSeparator }
                sawSeparator = true
            } else {
                throw NumericInputError.invalidCharacter(character)
            }
        }

        guard !integerDigits.isEmpty, !sawSeparator || !fractionDigits.isEmpty else {
            throw NumericInputError.missingDigits
        }
        if sawSeparator, policy.kind == .integer { throw NumericInputError.fractionNotAllowed }

        let integerPart = String(integerDigits.drop(while: { $0 == "0" })).nonEmpty ?? "0"
        if integerPart.count > policy.maxIntegerDigits { throw NumericInputError.tooManyIntegerDigits }
        if case let .decimal(maxFractionDigits) = policy.kind, fractionDigits.count > maxFractionDigits {
            throw NumericInputError.tooManyFractionDigits
        }

        let fractionPart = String(fractionDigits.reversed().drop(while: { $0 == "0" }).reversed())
        let normalized = NormalizedDecimal(string: fractionPart.isEmpty ? integerPart : "\(integerPart).\(fractionPart)")
        if let minimum = policy.minimum, normalized.decimal < minimum { throw NumericInputError.belowMinimum }
        if let maximum = policy.maximum, normalized.decimal > maximum { throw NumericInputError.aboveMaximum }
        return normalized
    }

    /// Maps ASCII, Arabic-Indic (٠–٩) and Extended Arabic-Indic/Persian (۰–۹) digits to ASCII.
    static func asciiDigit(_ character: Character) -> Character? {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else { return nil }
        let value = scalar.value
        let zero: UInt32
        switch value {
        case 0x30...0x39: zero = 0x30
        case 0x0660...0x0669: zero = 0x0660
        case 0x06F0...0x06F9: zero = 0x06F0
        default: return nil
        }
        return Character(Unicode.Scalar(0x30 + value - zero)!)
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
