import SwiftUI

struct DashboardCountUpModifier: ViewModifier {
    let value: Double
    let isEnabled: Bool
    let placeholder: String?
    let animation: Animation
    let formatter: (Double) -> String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedValue: Double?

    func body(content: Content) -> some View {
        content
            .hidden()
            .overlay {
                DashboardAnimatedNumberLabel(
                    value: isEnabled ? (displayedValue ?? 0) : value,
                    text: displayText(for:)
                )
            }
            .accessibilityLabel(Text(finalText))
            .onAppear {
                setDisplayedValue(value, animated: isEnabled && !reduceMotion && displayedValue == nil)
            }
            .onChange(of: value) { _, newValue in
                setDisplayedValue(newValue, animated: isEnabled && !reduceMotion)
            }
            .onChange(of: reduceMotion) { _, _ in
                setDisplayedValue(value, animated: false)
            }
    }

    private var finalText: String {
        isEnabled ? formatter(value) : (placeholder ?? formatter(value))
    }

    private func displayText(for animatedValue: Double) -> String {
        isEnabled ? formatter(animatedValue) : finalText
    }

    private func setDisplayedValue(_ newValue: Double, animated: Bool) {
        if animated {
            if displayedValue == nil {
                displayedValue = 0
            }
            withAnimation(animation) {
                displayedValue = newValue
            }
        } else {
            displayedValue = newValue
        }
    }
}

private struct DashboardAnimatedNumberLabel: View, Animatable {
    var value: Double
    let text: (Double) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(text(value))
            .monospacedDigit()
    }
}

extension View {
    func dashboardCountUp(
        value: Double,
        isEnabled: Bool = true,
        placeholder: String? = nil,
        animation: Animation = .easeOut(duration: 0.7),
        formatter: @escaping (Double) -> String
    ) -> some View {
        modifier(
            DashboardCountUpModifier(
                value: value,
                isEnabled: isEnabled,
                placeholder: placeholder,
                animation: animation,
                formatter: formatter
            )
        )
    }

    @ViewBuilder
    func dashboardCountUpIfNeeded(
        value: Double?,
        formatter: ((Double) -> String)?
    ) -> some View {
        if let value, let formatter {
            dashboardCountUp(value: value, formatter: formatter)
        } else {
            self
        }
    }
}
