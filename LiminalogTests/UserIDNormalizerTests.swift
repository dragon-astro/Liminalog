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
        let spacedValue = try #require(UserIDNormalizer.normalizedValue("  @ Ryu.Log_7  "))

        #expect(value == "ryu.log_7")
        #expect(fullWidthValue == "ryu.log_7")
        #expect(spacedValue == "ryu.log_7")
    }

    @Test
    func convertsFullWidthInputToHalfWidth() throws {
        let value = try #require(UserIDNormalizer.normalizedValue("ＲＹＵ＿Ｌｏｇ７"))

        #expect(value == "ryu_log7")
    }

    @Test
    func rejectsAtMarkInsideUserID() {
        let result = UserIDNormalizer.normalize("Ryu@Log")

        #expect(result == .failure(.invalidCharacters))
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
    func acceptsAllowedSymbolUserIDs() throws {
        let value = try #require(UserIDNormalizer.normalizedValue("Ryu-Log_7.dev"))

        #expect(value == "ryu-log_7.dev")
    }

    @Test
    func rejectsNonAsciiUserIDsToPreventHomoglyphSpoofing() {
        // キリル文字の「а」(U+0430) はラテン文字の「a」と見分けが付かない。
        #expect(UserIDNormalizer.normalize("りゅうログ") == .failure(.invalidCharacters))
        #expect(UserIDNormalizer.normalize("ry\u{0430}log") == .failure(.invalidCharacters))
        #expect(UserIDNormalizer.normalize("cafélog") == .failure(.invalidCharacters))
    }

    @Test
    func rejectsIDsLongerThanMaximum() {
        let tooLong = String(repeating: "a", count: UserIDNormalizer.maximumLength + 1)

        #expect(UserIDNormalizer.normalize(tooLong) == .failure(.tooLong(maximum: UserIDNormalizer.maximumLength)))
        #expect(UserIDNormalizer.normalizedValue(String(repeating: "a", count: UserIDNormalizer.maximumLength)) != nil)
    }
}
