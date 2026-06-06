import Testing
@testable import Liminalog

struct UserIDNormalizerTests {
    @Test
    func trimsAndLowercasesUserID() throws {
        let value = try #require(UserIDNormalizer.normalizedValue("  Ryu.Log_7  "))

        #expect(value == "ryu.log_7")
    }

    @Test
    func rejectsIDsShorterThanMinimum() {
        let result = UserIDNormalizer.normalize("ab")

        #expect(result == .failure(.tooShort(minimum: UserIDNormalizer.minimumLength)))
    }

    @Test
    func rejectsUnsupportedCharacters() {
        let result = UserIDNormalizer.normalize("ryu-log")

        #expect(result == .failure(.invalidCharacters))
    }
}
