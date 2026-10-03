import AppIntents

struct HabitShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CompleteHabitIntent(), phrases: ["Complete a habit in \(.applicationName)"], shortTitle: "Complete Habit", systemImageName: "checkmark")
        AppShortcut(intent: ClearHabitIntent(), phrases: ["Clear a habit in \(.applicationName)"], shortTitle: "Clear Habit", systemImageName: "eraser")
        AppShortcut(intent: IncrementHabitIntent(), phrases: ["Add progress in \(.applicationName)"], shortTitle: "Increment Habit", systemImageName: "plus")
        AppShortcut(intent: LogAmountIntent(), phrases: ["Log an amount in \(.applicationName)"], shortTitle: "Log Amount", systemImageName: "number")
        AppShortcut(intent: LogNoteIntent(), phrases: ["Add a note in \(.applicationName)"], shortTitle: "Log Note", systemImageName: "note.text")
        AppShortcut(intent: GetHabitProgressIntent(), phrases: ["Get habit progress in \(.applicationName)"], shortTitle: "Get Progress", systemImageName: "chart.bar")
        AppShortcut(intent: CompleteRoutineIntent(), phrases: ["Complete a routine in \(.applicationName)"], shortTitle: "Complete Routine", systemImageName: "checklist")
        AppShortcut(intent: OpenHabitIntent(), phrases: ["Open a habit in \(.applicationName)"], shortTitle: "Open Habit", systemImageName: "square.grid.3x3")
    }
}

