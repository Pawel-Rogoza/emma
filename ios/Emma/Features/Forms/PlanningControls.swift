import SwiftUI

// MARK: - Wspólny wybór dnia w formularzach zadania i terminu
//
// Review 11.10.2026: formularze mają być przejrzyste i proste. Oba formularze
// pytają o dzień tak samo: chipy z najczęstszymi wyborami (widoczne naraz,
// bez przewijania w bok), systemowy wybór daty dla reszty i jedno zdanie pod
// spodem, które mówi po ludzku, co wybrano („Wtorek, 13 października · za 2 dni”)
// — razem z ostrzeżeniem o weekendzie, święcie albo dacie z przeszłości.

/// Chipy dnia z `PlanningShortcuts.days`.
struct DayShortcutChips: View {
    let today: LocalDate
    let selection: LocalDate
    let onSelect: (LocalDate) -> Void

    var body: some View {
        ChipFlow {
            ForEach(PlanningShortcuts.days(today: today), id: \.self) { shortcut in
                QuickChip(title: shortcut.title, isSelected: shortcut.date == selection) {
                    onSelect(shortcut.date)
                }
                .accessibilityIdentifier("day-chip-\(shortcut.date.isoString)")
            }
        }
    }
}

/// „Wtorek, 13 października, 10:00 · za 2 dni” i ostrzeżenie pod spodem.
struct DaySummaryLine: View {
    let day: LocalDate
    var time: TimeOfDay?
    let today: LocalDate
    let dateText: DateTextFormatter

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(summary)
                .font(EmmaTypography.caption(.medium))
                .foregroundStyle(EmmaTheme.muted)
                .contentTransition(.opacity)
            if let warning = PlanningShortcuts.warning(for: day, today: today) {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(EmmaTypography.caption())
                    .foregroundStyle(EmmaTheme.pillAmberText)
                    .transition(.opacity)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 4)
        .padding(.top, 6)
        .animation(EmmaMotion.snappy, value: day)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("day-summary")
    }

    private var summary: String {
        var title = dateText.dayTitle(day)
        if let time { title += ", \(time.hhmm)" }
        let relative = PlanningShortcuts.relative(day, today: today)
        // „Dzisiaj, 11 października · dziś” powtarza to samo — wtedy bez dopisku.
        if abs(today.days(until: day)) <= 1 { return title }
        return "\(title) · \(relative)"
    }
}

/// Informacja o przypomnieniu z ostrzeżeniem, gdy powiadomienia są wyłączone.
struct ReminderHint: View {
    let text: String
    let isDenied: Bool

    var body: some View {
        Group {
            if isDenied {
                Text("Powiadomienia Emmy są wyłączone. Włącz je w Ustawieniach iOS → Emma → Powiadomienia.")
                    .foregroundStyle(EmmaTheme.pillAmberText)
            } else {
                Text(text)
                    .foregroundStyle(EmmaTheme.mutedSoft)
            }
        }
        .font(EmmaTypography.caption())
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 6)
        .padding(.horizontal, 4)
    }
}
