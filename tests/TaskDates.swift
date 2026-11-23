// swiftc Sources/Model.swift tests/TaskDates.swift -o /tmp/pomodoro-task-dates && /tmp/pomodoro-task-dates
import Foundation

@main
struct TaskDates {
    static func main() {
        let calendar = Calendar.current
        func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day))!
        }
        let reference = day(2027, 11, 23)
        let cases: [(String, Date?)] = [
            ("今天", reference), ("明天", day(2027, 11, 24)), ("后天", day(2027, 11, 25)),
            ("11-23", reference), ("11/24", day(2027, 11, 24)), ("11.22", day(2028, 11, 22)),
            ("2-29", day(2028, 2, 29)), ("2028-02-29", day(2028, 2, 29)),
            ("2026-02-30", nil), ("2027-02-29", nil), ("2027-00-12", nil), ("2027-13-01", nil),
            ("2027-11-00", nil), ("2027-abc-11-25", nil), ("2027--11-25", nil),
            ("11-25-", nil), ("+11-25", nil), ("", nil)
        ]
        for (input, expected) in cases {
            precondition(TimerModel.parseDay(input, relativeTo: reference) == expected, input)
        }
        // A yearless February 29 after leap day cannot be silently moved to February 28 next year.
        precondition(TimerModel.parseDay("2-29", relativeTo: day(2028, 3, 1)) == nil)

        let suite = "pomodoro.tests.dates." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = TimerModel(defaults: defaults)
        let invalid = model.addTask("写周报 @2026-02-30")
        precondition(invalid?.title == "写周报 @2026-02-30" && invalid?.due == nil)
        let valid = model.addTask("写周报 @2028-02-29")
        precondition(valid?.title == "写周报" && valid?.due == day(2028, 2, 29))
        print("Task deadline parsing passed.")
    }
}
