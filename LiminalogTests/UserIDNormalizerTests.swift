import Testing
@testable import Liminalog

struct UserIDNormalizerTests {
    @Test
    func trimsAndLowercasesUserID() throws {
        let value = try #require(UserIDNormalizer.normalizedValue("  Ryu.Log_7  "))

        #expect(value == "ryu.log_7")
    }

    @Test
    func stripsLeadingDisplayAtMark() throws {
        let value = try #require(UserIDNormalizer.normalizedValue("  @Ryu.Log_7  "))
        let fullWidthValue = try #require(UserIDNormalizer.normalizedValue("  ＠Ryu.Log_7  "))

        #expect(value == "ryu.log_7")
        #expect(fullWidthValue == "ryu.log_7")
    }

    @Test
    func keepsAtMarkInsideUserID() throws {
        let value = try #require(UserIDNormalizer.normalizedValue("Ryu@Log"))

        #expect(value == "ryu@log")
    }

    @Test
    func rejectsIDsShorterThanMinimum() {
        let result = UserIDNormalizer.normalize("ab")

        #expect(result == .failure(.tooShort(minimum: UserIDNormalizer.minimumLength)))
    }

    @Test
    func rejectsIDsShorterThanMinimumAfterStrippingDisplayAtMark() {
        let result = UserIDNormalizer.normalize("@ab")

        #expect(result == .failure(.tooShort(minimum: UserIDNormalizer.minimumLength)))
    }

    @Test
    func acceptsNonAsciiAndSymbolUserIDsWhenMinimumLengthIsSatisfied() throws {
        let japanese = try #require(UserIDNormalizer.normalizedValue("  りゅうログ  "))
        let symbol = try #require(UserIDNormalizer.normalizedValue("Ryu-Log"))

        #expect(japanese == "りゅうログ")
        #expect(symbol == "ryu-log")
    }
}
