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
        ("lock.shield", "onboarding.step4.title", "onboarding.step4.desc"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                let step = steps[currentStep]

                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.25), Color.accentColor.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 76, height: 76)
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                        .frame(width: 76, height: 76)
                    Image(systemName: step.icon)
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                .id(currentStep)
                .transition(.scale(scale: 0.85).combined(with: .opacity))

                Text(lang.l(step.titleKey))
                    .font(.system(size: 16, weight: .semibold))
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

            HStack(spacing: 6) {
                ForEach(0..<steps.count, id: \.self) { i in
                    Capsule()
                        .fill(i == currentStep ? Color.accentColor : Color.primary.opacity(0.15))
                        .frame(width: i == currentStep ? 18 : 6, height: 6)
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: currentStep)
            .padding(.bottom, 16)

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
