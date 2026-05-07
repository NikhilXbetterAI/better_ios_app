import SwiftUI

struct SleepQuestionnaireStepView: View {
    @Binding var answersByQuestionID: [String: SleepAssessmentAnswer]
    let onCompleted: () -> Void

    @State private var currentIndex = 0
    @State private var movingForward = true
    @State private var isAutoAdvancing = false

    private let questions = SleepAssessmentQuestion.allQuestions

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.large) {
            questionHeader
                .padding(.horizontal, BetterSpacing.screen)
                .padding(.top, BetterSpacing.large)

            questionContent
                .padding(.horizontal, BetterSpacing.screen)
        }
        .onAppear { seekFirstUnanswered() }
    }

    // MARK: - Header

    private var questionHeader: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.small) {
            HStack(alignment: .center) {
                Button {
                    navigateBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(currentIndex > 0 ? BetterColors.text : BetterColors.subtext.opacity(0.3))
                        .frame(width: 32, height: 32)
                        .background(BetterColors.card, in: Circle())
                }
                .disabled(currentIndex == 0)
                .buttonStyle(.plain)

                Spacer()

                Text("\(currentIndex + 1) of \(questions.count)")
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.subtext)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: currentIndex)
            }

            // Segmented capsule progress — 12 pills
            HStack(spacing: 4) {
                ForEach(0..<questions.count, id: \.self) { i in
                    Capsule()
                        .fill(i <= currentIndex ? BetterColors.stageDeep : BetterColors.card)
                        .frame(maxWidth: .infinity)
                        .frame(height: 4)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: currentIndex)
                }
            }
        }
    }

    // MARK: - Question content

    private var questionContent: some View {
        ZStack(alignment: .top) {
            questionCard(for: questions[currentIndex])
                .id(currentIndex)
                .transition(slideTransition)
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: currentIndex)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func questionCard(for question: SleepAssessmentQuestion) -> some View {
        let style = sectionStyle(for: question.section)

        VStack(alignment: .leading, spacing: BetterSpacing.large) {
            // Section icon header
            HStack(spacing: BetterSpacing.small) {
                Image(systemName: style.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(style.color)
                    .frame(width: 34, height: 34)
                    .background(style.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(question.section.uppercased())
                    .font(BetterTypography.caption)
                    .foregroundStyle(style.color)
                    .tracking(0.6)
            }

            Text(question.prompt)
                .font(BetterTypography.title)
                .foregroundStyle(BetterColors.text)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: BetterSpacing.small) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                    QuestionOptionButton(
                        text: option,
                        isSelected: answersByQuestionID[question.id]?.selectedOptionIndex == index,
                        accentColor: style.color,
                        onTap: { selectOption(index, for: question) }
                    )
                }
            }
        }
        .padding(BetterSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BetterColors.cardGradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(BetterColors.glassStroke, lineWidth: 1)
        )
    }

    // MARK: - Section accent system

    private func sectionStyle(for section: String) -> (color: Color, icon: String) {
        switch section {
        case "Sleep Timing & Chronotype": return (BetterColors.brand,      "moon.fill")
        case "Sleep Quality":             return (BetterColors.stageDeep,  "heart.fill")
        case "Daytime Function":          return (BetterColors.stageAwake, "figure.run")
        case "Behavioral Drivers":        return (BetterColors.hrv,        "brain.head.profile")
        default:                          return (BetterColors.brand,      "questionmark")
        }
    }

    // MARK: - Navigation (unchanged logic)

    private var slideTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: movingForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: movingForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private func navigateBack() {
        guard currentIndex > 0 else { return }
        movingForward = false
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            currentIndex -= 1
        }
    }

    private func selectOption(_ index: Int, for question: SleepAssessmentQuestion) {
        guard !isAutoAdvancing else { return }

        answersByQuestionID[question.id] = SleepAssessmentAnswer(
            questionID: question.id,
            question: question.prompt,
            section: question.section,
            selectedOption: question.options[index],
            selectedOptionIndex: index
        )

        isAutoAdvancing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            movingForward = true
            if currentIndex < questions.count - 1 {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                    currentIndex += 1
                }
            } else {
                onCompleted()
            }
            isAutoAdvancing = false
        }
    }

    private func seekFirstUnanswered() {
        let firstUnanswered = questions.firstIndex { answersByQuestionID[$0.id] == nil } ?? questions.count - 1
        currentIndex = firstUnanswered
    }
}

// MARK: - Option Button

private struct QuestionOptionButton: View {
    let text: String
    let isSelected: Bool
    var accentColor: Color = BetterColors.brand
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: BetterSpacing.medium) {
                Text(text)
                    .font(BetterTypography.body)
                    .foregroundStyle(BetterColors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(accentColor)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(BetterColors.border.opacity(2))
                }
            }
            .padding(.horizontal, BetterSpacing.medium)
            .padding(.vertical, 14)
            .background(
                isSelected ? accentColor.opacity(0.12) : BetterColors.cardSecondary,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isSelected)
    }
}
