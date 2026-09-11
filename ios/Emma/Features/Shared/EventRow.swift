import SwiftUI

// MARK: - Wiersz terminu
//
// Odtworzenie `.event-row.card` z referencji: godzina z małą datą, tytuł,
// „status · opiekun” i chevron. Cały wiersz jest przyciskiem otwierającym
// szczegół terminu (`eventDetail`).

struct EventRow: View {

    /// Data jest prezentowana tym samym dziennikiem co w reszcie aplikacji
    /// („Dzisiaj”, „Jutro”, „11 wrz”). Sygnatura wiersza nie przyjmuje formatera,
    /// więc korzystamy z formatera zależności, a nie z własnego `Calendar`.
    @EnvironmentObject private var dependencies: AppDependencies

    private let event: ScheduledEvent
    private let onOpen: () -> Void

    init(event: ScheduledEvent, onOpen: @escaping () -> Void) {
        self.event = event
        self.onOpen = onOpen
    }

    var body: some View {
        Button(action: onOpen) {
            SurfaceCard(padding: EdgeInsets(top: 15, leading: 15, bottom: 15, trailing: 15)) {
                HStack(alignment: .center, spacing: 13) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.time.hhmm)
                            .font(EmmaTypography.ui(14, .semibold))
                            .foregroundStyle(EmmaTheme.ink)
                        Text(dependencies.dateText.dayLabel(event.day))
                            .font(EmmaTypography.ui(10))
                            .foregroundStyle(EmmaTheme.mutedSoft)
                    }
                    .frame(minWidth: 51, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        // Tytuł terminu może zawierać cyrylicę — czcionka zależna od pisma.
                        Text(event.title)
                            .font(EmmaTypography.body(for: event.title, size: 13, weight: .medium))
                            .foregroundStyle(EmmaTheme.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(event.status.rawValue) · \(event.ownerLabel)")
                            .font(EmmaTypography.ui(11))
                            .foregroundStyle(EmmaTheme.mutedSoft)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(EmmaTheme.mutedSoft)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Otwiera szczegóły terminu")
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityText: String {
        [
            event.time.hhmm,
            dependencies.dateText.dayLabel(event.day),
            event.title,
            "\(event.status.rawValue) · \(event.ownerLabel)"
        ]
        .joined(separator: ", ")
    }
}
