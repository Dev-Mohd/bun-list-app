import XCTest
@testable import BunnListCore

/// Spec test 21. The same vectors must pass on Linux and iOS (no NumberFormatter, no Locale).
final class NumericInputTests: XCTestCase {
    let grams = NumericFieldPolicy.decimal(maxIntegerDigits: 4, maxFractionDigits: 1, minimum: 0)
    let precise = NumericFieldPolicy.decimal(maxIntegerDigits: 4, maxFractionDigits: 3)
    let wide = NumericFieldPolicy.decimal(maxIntegerDigits: 6, maxFractionDigits: 1)
    let seconds = NumericFieldPolicy.integer(maxDigits: 4, minimum: 1)

    private func parse(_ text: String, _ policy: NumericFieldPolicy, extra: Character? = nil) throws -> String? {
        try NumericInputParser.parse(text, policy: policy, extraDecimalSeparator: extra)?.string
    }

    func testWesternArabicAndPersianDigitsNormalizeToTheSameDecimal() throws {
        XCTAssertEqual(try parse("12.5", grams), "12.5")
        XCTAssertEqual(try parse("١٢٫٥", grams), "12.5")
        XCTAssertEqual(try parse("۱۲٫۵", grams), "12.5")
        XCTAssertEqual(try parse("١٢.٥", grams), "12.5")
        XCTAssertEqual(try parse("  ٢٥٠  ", grams), "250", "outer whitespace is trimmed")
        XCTAssertEqual(try parse("012.50", precise), "12.5", "canonical form drops redundant zeros")
        XCTAssertEqual(try parse("0", grams), "0")
    }

    func testEmptyIsMissingNotZeroOrError() throws {
        XCTAssertNil(try parse("", grams))
        XCTAssertNil(try parse("   ", grams))
    }

    func testCommaIsRejectedWithoutTheExplicitException() {
        for input in ["12,5", "1,500", "١٬٥", "١،٥"] {
            XCTAssertThrowsError(try parse(input, grams), input)
        }
    }

    func testCommaExceptionOnShortDecimalFields() throws {
        XCTAssertEqual(try parse("12,5", grams, extra: ","), "12.5")
        XCTAssertEqual(try parse("1,500", precise, extra: ","), "1.5", "1,500 means 1.500, never 1500")
        XCTAssertThrowsError(try parse("1,500", grams, extra: ",")) {
            XCTAssertEqual($0 as? NumericInputError, .tooManyFractionDigits, "field precision still applies")
        }
        XCTAssertThrowsError(try parse("12345,5", grams, extra: ","))
        XCTAssertThrowsError(try parse("12,5", wide, extra: ",")) {
            XCTAssertEqual($0 as? NumericInputError, .extraSeparatorNotAllowed, "fields over 4 integer digits never take ','")
        }
        XCTAssertThrowsError(try parse("12", seconds, extra: ",")) {
            XCTAssertEqual($0 as? NumericInputError, .extraSeparatorNotAllowed)
        }
        XCTAssertThrowsError(try parse("12٬5", grams, extra: "٬")) {
            XCTAssertEqual($0 as? NumericInputError, .extraSeparatorNotAllowed)
        }
        XCTAssertThrowsError(try parse("1,2.3", grams, extra: ",")) {
            XCTAssertEqual($0 as? NumericInputError, .repeatedSeparator, "mixing separators is rejected")
        }
        XCTAssertThrowsError(try parse("١٬٥", grams, extra: ","))
        XCTAssertThrowsError(try parse("١،٥", grams, extra: ","))
    }

    func testMalformedInputIsRejected() {
        let cases: [(String, NumericInputError)] = [
            ("1.2.3", .repeatedSeparator),
            ("1e3", .invalidCharacter("e")),
            ("1 2", .invalidCharacter(" ")),
            (".5", .missingDigits),
            ("5.", .missingDigits),
            ("+5", .invalidCharacter("+")),
            ("-5", .invalidCharacter("-")),
            ("−5", .invalidCharacter("−")),
            ("12a", .invalidCharacter("a")),
        ]
        for (input, expected) in cases {
            XCTAssertThrowsError(try parse(input, grams), input) { XCTAssertEqual($0 as? NumericInputError, expected, input) }
        }
    }

    func testIntegerFieldsRejectAnySeparatorAndApplyRange() {
        XCTAssertThrowsError(try parse("30.0", seconds)) { XCTAssertEqual($0 as? NumericInputError, .fractionNotAllowed) }
        XCTAssertThrowsError(try parse("٣٠٫٠", seconds)) { XCTAssertEqual($0 as? NumericInputError, .fractionNotAllowed) }
        XCTAssertThrowsError(try parse("0", seconds)) { XCTAssertEqual($0 as? NumericInputError, .belowMinimum) }
        XCTAssertThrowsError(try parse("12345", seconds)) { XCTAssertEqual($0 as? NumericInputError, .tooManyIntegerDigits) }
        XCTAssertEqual(try parse("٢٨", seconds), "28")
    }
}
