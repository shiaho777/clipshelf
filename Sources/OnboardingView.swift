import SwiftUI

struct OnboardingView: View {
    @ObservedObject var lang = LanguageManager.shared
    @State private var currentStep = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onComplete: () -> Void

    private let steps: [(icon: String, titleKey: String, descKey: String)] = [
        ("doc.on.clipboard", "onboarding.step1.title", "onboarding.step1.desc"),
        ("magnifyingglass", "onboarding.step2.title", "onboarding.step2.desc"),
        ("keyboard", "onboarding.step3.title", "onboarding.step3.desc"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                let step = steps[currentStep]

                Image(systemName: step.icon)
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(height: 44)
                    .id(currentStep) // force transition on step change

                Text(lang.l(step.titleKey))
                    .font(.system(size: 15, weight: .semibold))
                    .multilineTextAlignment(.center)

                Text(lang.l(step.descKey))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 260)
            }
            .padding(.horizontal, 24)

            Spacer()

            // Dots
            HStack(spacing: 8) {
                ForEach(0..<steps.count, id: \.self) { i in
                    Circle()
                        .fill(i == currentStep ? Color.accentColor : Color.primary.opacity(0.15))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.bottom, 16)

            // Button
            Button {
                if currentStep < steps.count - 1 {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.78)) {
                        currentStep += 1
                    }
                } else {
                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                    onComplete()
                }
            } label: {
                Text(currentStep < steps.count - 1 ? lang.l("onboarding.next") : lang.l("onboarding.done"))
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 40)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
