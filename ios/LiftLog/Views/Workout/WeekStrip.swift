import SwiftUI

/// The program's days in a row to pick from: a 7-day program as Mon–Sun, other lengths as Day 1…n, and routines
/// outside a program unlabelled. The picked day is filled, up next has a dot under it, and today's weekday is bold.
struct WeekStrip: View {
    let days: [Routine]
    /// A program's days (labelled by weekday or day number) rather than the user's own routines.
    let isProgram: Bool
    let selected: Routine?
    let upNext: Routine?
    var pick: (Routine) -> Void

    /// Day i of a 7-day program is the i-th weekday from Monday.
    private var isWeek: Bool { isProgram && days.count == 7 }

    var body: some View {
        if days.count <= 7 {
            HStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    column(day, index: index).frame(maxWidth: .infinity)
                }
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                        column(day, index: index).frame(width: 48)
                    }
                }
            }
        }
    }

    private func column(_ day: Routine, index: Int) -> some View {
        let isSelected = day.id == selected?.id
        let isToday = isWeek && index == Self.todayIndex
        let isNext = day.id == upNext?.id
        return Button { pick(day) } label: {
            VStack(spacing: 6) {
                if isProgram {
                    Text(isWeek ? Self.weekdayLetter(index) : "Day \(index + 1)")
                        .font(.caption2.weight(isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? Color.primary : Color.secondary)
                }
                Text(DayAbbreviation.of(day))
                    // The rest day's "·" needs a larger size to read as a dot.
                    .font(day.isRestDay ? .title2.weight(.black) : .subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.white : day.isRestDay ? Color.secondary : Color.primary)
                    .frame(width: 40, height: 34)
                    .background {
                        if isSelected { RoundedRectangle(cornerRadius: 9).fill(RoutineStyle(name: day.name).color.gradient) }
                    }
                Circle()
                    .fill(isNext ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
                    .frame(width: 5, height: 5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel([isWeek ? Self.weekdayName(index) : isProgram ? "Day \(index + 1)" : nil, day.name,
                             isNext ? "up next" : nil, isToday ? "today" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Today as an index from Monday (0) to Sunday (6).
    static var todayIndex: Int { (Calendar.current.component(.weekday, from: .now) + 5) % 7 }

    /// "M", "T", … for day `index` from Monday.
    static func weekdayLetter(_ index: Int) -> String {
        Calendar.current.veryShortStandaloneWeekdaySymbols[(index + 1) % 7]
    }

    /// "Mon", "Tue", … for day `index` from Monday.
    static func weekdayName(_ index: Int) -> String {
        Calendar.current.shortStandaloneWeekdaySymbols[(index + 1) % 7]
    }
}

/// A day's short name in the strip: two letters for one word ("Pu" Push, "Pl" Pull, "Lg" Legs, "Up" Upper), initials
/// for two words ("Delts & Arms" → "DA"), and a letter or number variant kept ("Upper A" → "UpA"). Rest days are "·".
enum DayAbbreviation {
    private static let words = [
        "push": "Pu", "pull": "Pl", "legs": "Lg", "leg": "Lg", "upper": "Up", "lower": "Lo", "chest": "Ch",
        "back": "Bk", "arms": "Ar", "shoulders": "Sh", "delts": "De", "glutes": "Gl", "cardio": "Ca",
    ]

    static func of(_ routine: Routine) -> String {
        routine.isRestDay ? "·" : of(routine.name)
    }

    static func of(_ name: String) -> String {
        let parts = name.split { !$0.isLetter && !$0.isNumber }.map(String.init)
            .filter { !["and", "day"].contains($0.lowercased()) }
        guard let first = parts.first else { return "?" }
        let short = words[first.lowercased()] ?? first.prefix(2).capitalized
        guard parts.count > 1 else { return short }
        if parts[1].count == 1 { return short + parts[1].uppercased() }
        return (first.prefix(1) + parts[1].prefix(1)).uppercased()
    }
}
