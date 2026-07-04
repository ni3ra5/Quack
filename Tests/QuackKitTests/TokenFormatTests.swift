import Testing
@testable import QuackKit

@Suite struct TokenFormatTests {
    @Test func belowThousandVerbatim() { #expect(TokenFormat.compact(900) == "900") }
    @Test func thousandsRounded() {
        #expect(TokenFormat.compact(215_400) == "215k")
        #expect(TokenFormat.compact(1_499) == "1k")
    }
    @Test func millionsOneDecimalUnderTen() {
        #expect(TokenFormat.compact(1_500_000) == "1.5M")
        #expect(TokenFormat.compact(12_400_000) == "12M")
    }
}
