import Testing
@testable import Liminalog

@Suite("Discrete setting slider")
struct DiscreteSliderSelectionTests {
    @Test("境目で揺らしても選択を往復せず、一方向の通過では各段階に一度だけ変わる")
    func slowDragAndBoundaryNoise() {
        var slider = DiscreteSliderSelection(index: 0, count: 5)
        var changes: [Int] = []
        for position in stride(from: 0.0, through: 4.0, by: 0.01) {
            let previous = slider.index
            let index = slider.update(position: position)
            if previous != index { changes.append(index) }
        }
        #expect(changes == [1, 2, 3, 4])
        _ = slider.update(position: 2)
        for position in [2.49, 2.51, 2.48, 2.56, 2.50] {
            #expect(slider.update(position: position) == 2)
        }
        #expect(slider.update(position: 2.60) == 3)
        for position in [2.51, 2.49, 2.45, 2.53] {
            #expect(slider.update(position: position) == 3)
        }
        #expect(slider.update(position: 2.39) == 2)
    }

    @Test("速い操作は到達先へ直接変更し、離した時は最寄りの目盛りに揃う")
    func fastDragAndRelease() {
        var slider = DiscreteSliderSelection(index: 0, count: 5)
        #expect(slider.update(position: 3.1) == 3)
        #expect(slider.update(position: 2.49) == 3)
        #expect(slider.update(position: 2.49, finishing: true) == 2)
        #expect(slider.update(position: -100) == 0)
        #expect(slider.update(position: 100) == 4)
        #expect(slider.update(position: .nan) == 4)
    }

    @Test("文字サイズの9段階も端まで正逆に移動できる")
    func fontSizeSteps() {
        var slider = DiscreteSliderSelection(index: 2, count: 9)
        for index in 0..<9 { #expect(slider.update(position: Double(index)) == index) }
        for index in (0..<9).reversed() { #expect(slider.update(position: Double(index)) == index) }
    }
}
