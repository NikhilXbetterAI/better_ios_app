import Foundation

nonisolated struct SleepAssessmentAnswer: Codable, Hashable, Sendable, Identifiable {
    var questionID: String
    var question: String
    var section: String
    var selectedOption: String
    var selectedOptionIndex: Int

    var id: String { questionID }

    init(
        questionID: String,
        question: String,
        section: String,
        selectedOption: String,
        selectedOptionIndex: Int
    ) {
        self.questionID = questionID
        self.question = question
        self.section = section
        self.selectedOption = selectedOption
        self.selectedOptionIndex = selectedOptionIndex
    }
}
