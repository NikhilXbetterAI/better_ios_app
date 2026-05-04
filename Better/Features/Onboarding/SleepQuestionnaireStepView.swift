import SwiftUI

struct SleepQuestionnaireStepView: View {
    @Binding var answersByQuestionID: [String: SleepAssessmentAnswer]

    private var answeredCount: Int {
        SleepAssessmentQuestion.allQuestions.filter { answersByQuestionID[$0.id] != nil }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.large) {
            OnboardingStepHeader(
                icon: "list.clipboard.fill",
                title: "Personalised sleep assessment",
                body: "Answer 12 quick questions so Better can interpret your data around your timing, sleep quality, daytime function, and behavioral drivers."
            )

            VStack(alignment: .leading, spacing: BetterSpacing.small) {
                HStack {
                    Text("\(answeredCount) of \(SleepAssessmentQuestion.allQuestions.count) answered")
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.subtext)
                    Spacer()
                    Text("\(Int(Double(answeredCount) / Double(SleepAssessmentQuestion.allQuestions.count) * 100))%")
                        .font(BetterTypography.caption)
                        .foregroundStyle(BetterColors.brand)
                }
                ProgressView(value: Double(answeredCount), total: Double(SleepAssessmentQuestion.allQuestions.count))
                    .tint(BetterColors.brand)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: BetterSpacing.large) {
                    ForEach(groupedQuestions, id: \.section) { group in
                        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
                            Text(group.section.uppercased())
                                .font(BetterTypography.caption)
                                .foregroundStyle(BetterColors.brand)

                            ForEach(group.questions) { question in
                                SleepQuestionCard(
                                    question: question,
                                    selectedAnswer: answersByQuestionID[question.id],
                                    onSelect: { selectedIndex in
                                        answersByQuestionID[question.id] = SleepAssessmentAnswer(
                                            questionID: question.id,
                                            question: question.prompt,
                                            section: question.section,
                                            selectedOption: question.options[selectedIndex],
                                            selectedOptionIndex: selectedIndex
                                        )
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(.bottom, BetterSpacing.large)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var groupedQuestions: [(section: String, questions: [SleepAssessmentQuestion])] {
        let sections = SleepAssessmentQuestion.allQuestions.map(\.section).reduce(into: [String]()) { result, section in
            if !result.contains(section) {
                result.append(section)
            }
        }

        return sections.map { section in
            (
                section: section,
                questions: SleepAssessmentQuestion.allQuestions.filter { $0.section == section }
            )
        }
    }
}

private struct SleepQuestionCard: View {
    let question: SleepAssessmentQuestion
    let selectedAnswer: SleepAssessmentAnswer?
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BetterSpacing.medium) {
            Text(question.prompt)
                .font(BetterTypography.subheadline)
                .foregroundStyle(BetterColors.text)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: BetterSpacing.small) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                    Button {
                        onSelect(index)
                    } label: {
                        HStack(spacing: BetterSpacing.medium) {
                            Image(systemName: selectedAnswer?.selectedOptionIndex == index ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedAnswer?.selectedOptionIndex == index ? BetterColors.brand : BetterColors.subtext)
                            Text(option)
                                .font(BetterTypography.footnote)
                                .foregroundStyle(BetterColors.text)
                            Spacer()
                        }
                        .padding(.horizontal, BetterSpacing.medium)
                        .padding(.vertical, 11)
                        .background(
                            selectedAnswer?.selectedOptionIndex == index
                                ? BetterColors.brand.opacity(0.16)
                                : BetterColors.cardSecondary,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(selectedAnswer?.selectedOptionIndex == index ? BetterColors.brand.opacity(0.6) : BetterColors.border, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(BetterSpacing.large)
        .background(BetterColors.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

