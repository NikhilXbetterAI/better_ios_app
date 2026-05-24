import Foundation

struct SleepAssessmentQuestion: Identifiable, Hashable, Sendable {
    var id: String
    var section: String
    var prompt: String
    var options: [String]

    static let allQuestions: [SleepAssessmentQuestion] = [
        SleepAssessmentQuestion(
            id: "workday_sleep_time",
            section: "Sleep Timing & Body Clock",
            prompt: "On workdays, what time do you usually fall asleep?",
            options: ["Before 10pm", "10-11pm", "11pm-12am", "12-1am", "After 1am"]
        ),
        SleepAssessmentQuestion(
            id: "workday_wake_time",
            section: "Sleep Timing & Body Clock",
            prompt: "On workdays, what time do you wake up?",
            options: ["Before 6am", "6-7am", "7-8am", "8-9am", "After 9am"]
        ),
        SleepAssessmentQuestion(
            id: "free_day_wake_time",
            section: "Sleep Timing & Body Clock",
            prompt: "On free days, what time do you naturally wake up?",
            options: ["Before 6am", "6-7am", "7-8am", "8-9am", "After 9am"]
        ),
        SleepAssessmentQuestion(
            id: "sleep_latency",
            section: "Sleep Quality",
            prompt: "How long does it usually take you to fall asleep?",
            options: ["Less than 10 minutes", "10-20 minutes", "20-40 minutes", "40-60 minutes", "More than 60 minutes"]
        ),
        SleepAssessmentQuestion(
            id: "night_wake_frequency",
            section: "Sleep Quality",
            prompt: "How often do you wake up during the night?",
            options: ["Never", "Once", "2-3 times", "4 or more times"]
        ),
        SleepAssessmentQuestion(
            id: "restored_feeling",
            section: "Sleep Quality",
            prompt: "When you wake up, how restored do you feel?",
            options: ["Very refreshed", "Somewhat refreshed", "Neutral", "Slightly tired", "Very tired"]
        ),
        SleepAssessmentQuestion(
            id: "daytime_sleepiness",
            section: "Daytime Function",
            prompt: "How often do you feel sleepy during the day?",
            options: ["Never", "Occasionally", "1-2 times per day", "3 or more times per day"]
        ),
        SleepAssessmentQuestion(
            id: "caffeine_reliance",
            section: "Daytime Function",
            prompt: "Do you rely on caffeine to stay alert?",
            options: ["Not at all", "1 cup per day", "2-3 cups per day", "4 or more cups per day"]
        ),
        SleepAssessmentQuestion(
            id: "energy_peak",
            section: "Daytime Function",
            prompt: "When is your energy at its peak?",
            options: ["Early morning", "Late morning", "Afternoon", "Evening", "Late night"]
        ),
        SleepAssessmentQuestion(
            id: "last_caffeine",
            section: "Behavioral Drivers",
            prompt: "When is your last caffeine intake?",
            options: ["Before 12pm", "12-2pm", "2-5pm", "After 5pm"]
        ),
        SleepAssessmentQuestion(
            id: "morning_light",
            section: "Behavioral Drivers",
            prompt: "How much light exposure do you get within 1 hour of waking?",
            options: ["20+ minutes outdoors", "10-20 minutes", "Less than 10 minutes", "Almost none"]
        ),
        SleepAssessmentQuestion(
            id: "sleep_driver",
            section: "Behavioral Drivers",
            prompt: "What most affects your sleep right now?",
            options: ["Stress or overthinking", "Waking during the night", "Trouble falling asleep", "Irregular schedule", "Travel or jet lag", "Not sure"]
        )
    ]
}
