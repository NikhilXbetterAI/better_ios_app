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
            questionContent
        }
        .onAppear { seekFirstUnanswered() }
    }

    // MARK: - Subviews

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

            ProgressView(value: Double(currentIndex + 1), total: Double(questions.count))
                .tint(BetterColors.brand)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: currentIndex)
        }
    }

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
        VStack(alignment: .leading, spacing: BetterSpacing.large) {
            VStack(alignment: .leading, spacing: BetterSpacing.small) {
                Text(question.section.uppercased())
                    .font(BetterTypography.caption)
                    .foregroundStyle(BetterColors.brand)

                Text(question.prompt)
                    .font(BetterTypography.title)
                    .foregroundStyle(BetterColors.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: BetterSpacing.small) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                    QuestionOptionButton(
                        text: option,
                        isSelected: answersByQuestionID[question.id]?.selectedOptionIndex == index,
                        onTap: { selectOption(index, for: question) }
                    )
                }
            }
        }
        .padding(BetterSpacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BetterColors.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Navigation

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
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: BetterSpacing.medium) {
                ZStack {
                    Circle()
                        .stroke(
                            isSelected ? BetterColors.brand : BetterColors.border,
                            lineWidth: 1.5
                        )
                        .frame(width: 22, height: 22)

                    if isSelected {
                        Circle()
                            .fill(BetterColors.brand)
                            .frame(width: 12, height: 12)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)

                Text(text)
                    .font(BetterTypography.body)
                    .foregroundStyle(BetterColors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, BetterSpacing.medium)
            .padding(.vertical, 13)
            .background(
                isSelected ? BetterColors.brand.opacity(0.12) : BetterColors.cardSecondary,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? BetterColors.brand.opacity(0.5) : Color.clear,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isSelected)
    }
}
