import Testing
@testable import Liminalog

struct LiminalogRuntimeTests {
    @Test
    func unitTestProcessIsDetected() {
        #expect(LiminalogRuntime.isRunningUnitTests)
    }
}
