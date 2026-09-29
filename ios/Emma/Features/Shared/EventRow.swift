import SwiftUI

// MARK: - Wiersze terminu
//
// Dwa warianty tego samego terminu:
//   • `EventRow` — karta używana na kartach klienta i sprawy,
//   • `TodayEventRow` — wiersz osi dnia na ekranie „Dzisiaj”: jeden wspólny
//     pojemnik, pasek stanu, godzina i czas trwania, a obok menu z usunięciem.
//
// Oba odróżniają termin, który już minął: wygaszają go, żeby wzrok szedł po
// tym, co jeszcze przed nami. Reguła „minęło” siedzi w rdzeniu
// (`ScheduledEvent.hasPassed(at:)`), więc jest jedna dla całej aplikacji.

// MARK: - Wspólne elementy

/// Menu czynności terminu. Świadomie nie jest to sam chevron: strzałka
/// obiecywała przejście dalej, a pod nią jest wybór czynności — między innymi
/// usunięcie terminu.
struct EventActionsMenu: View {
    let onOpen: () -> Void
    let onDelete: (() -> Void)?
    /// „Załatwione” — tylko dla terminu, który minął i nie jest zamknięty.
    var onFinish: (() -> Void)? = nil

    var body: some View {
        Menu {
            if let onFinish {
                Button("Załatwione", systemImage: "checkmark.circle") {
                    onFinish()
                }
            }
            Button("Otwórz szczegóły", systemImage: "arrow.up.forward.square") {
                onOpen()
            }
            if let onDelete {
                Button("Usuń termin", systemImage: "trash", role: .destructive) {
                    onDelete()
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(EmmaTheme.mutedSoft)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Więcej opcji terminu")
    }
}

/// Kolor paska stanu przy wierszu osi dnia.
private func eventBarColor(past: Bool, happening: Bool, status: EventStatus) -> Color {
    if past { return EmmaTheme.mutedSoft.opacity(0.45) }
    if happening { return EmmaTheme.accent }
    return EmmaTheme.accent.opacity(0.45)
}

// MARK: - Wiersz osi dnia („Dzisiaj”)

struct TodayEventRow: View {

    let event: ScheduledEvent
    /// Aktualna godzina dnia — przekazana z ekranu, żeby cała lista liczyła
    /// „minęło” względem tego samego momentu.
    let now: TimeOfDay
    let onOpen: () -> Void
    let onDelete: () -> Void
    /// Zamknięcie terminu z menu wiersza (audyt 28.09.2026) — bez otwierania arkusza.
    var onFinish: (() -> Void)? = nil

    private var isPast: Bool { event.hasPassed(at: now) }
    private var isHappening: Bool { event.isHappening(at: now) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Capsule(style: .continuous)
                .fill(eventBarColor(past: isPast, happening: isHappening, status: event.status))
                .frame(width: 3)
                .frame(maxHeight: .infinity)

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(event.time.hhmm)
                            .font(EmmaTypography.ui(15, .semibold))
                            .foregroundStyle(isPast ? EmmaTheme.muted : EmmaTheme.ink)
                    }

                    Text(event.title)
                        .font(EmmaTypography.body(for: event.title, size: 13, weight: .medium))
                        .foregroundStyle(isPast ? EmmaTheme.muted : EmmaTheme.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        if isHappening {
                            StatusPill("Teraz", kind: .green)
                        } else if isPast {
                            Text("Minęło")
                                .font(EmmaTypography.caption())
                                .foregroundStyle(EmmaTheme.mutedSoft)
                        } else {
                            Text(event.kind.displayTitle)
                                .font(EmmaTypography.caption())
                                .foregroundStyle(EmmaTheme.muted)
                        }
                        if !event.place.isEmpty {
                            Text("· \(event.place)")
                                .font(EmmaTypography.caption())
                                .foregroundStyle(EmmaTheme.mutedSoft)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            EventActionsMenu(
                onOpen: onOpen,
                onDelete: onDelete,
                onFinish: isPast && event.status != .finished ? onFinish : nil
            )
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 15)
        // Miniony termin zostaje na liście (to wciąż zapis dnia), ale schodzi
        // na drugi plan — zamiast znikać i mylić.
        .opacity(isPast ? 0.66 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [event.time.hhmm, event.title]
        if isHappening { parts.append("trwa teraz") }
        else if isPast { parts.append("minęło") }
        else { parts.append(event.kind.displayTitle) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Karta terminu (karty klienta i sprawy)

struct EventRow: View {

    /// Data jest prezentowana tym samym dziennikiem co w reszcie aplikacji
    /// („Dzisiaj”, „Jutro”, „11 wrz”). Sygnatura wiersza nie przyjmuje formatera,
    /// więc korzystamy z formatera zależności, a nie z własnego `Calendar`.
    @EnvironmentObject private var dependencies: AppDependencies

    private let event: ScheduledEvent
    private let onOpen: () -> Void
    private let onDelete: (() -> Void)?

    init(event: ScheduledEvent, onOpen: @escaping () -> Void, onDelete: (() -> Void)? = nil) {
        self.event = event
        self.onOpen = onOpen
        self.onDelete = onDelete
    }

    private var hasPassed: Bool {
        event.hasPassed(at: TimeOfDay.at(dependencies.clock.now()))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: onOpen) {
                SurfaceCard(padding: EdgeInsets(top: 15, leading: 15, bottom: 15, trailing: 15)) {
                    HStack(alignment: .center, spacing: 13) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.time.hhmm)
                                .font(EmmaTypography.ui(14, .semibold))
                                .foregroundStyle(hasPassed ? EmmaTheme.muted : EmmaTheme.ink)
                            Text(dependencies.dateText.dayLabel(event.day))
                                .font(EmmaTypography.caption())
                                .foregroundStyle(EmmaTheme.mutedSoft)
                        }
                        .frame(minWidth: 51, alignment: .leading)

                        VStack(alignment: .leading, spacing: 4) {
                            // Tytuł terminu może zawierać cyrylicę — czcionka zależna od pisma.
                            Text(event.title)
                                .font(EmmaTypography.body(for: event.title, size: 13, weight: .medium))
                                .foregroundStyle(hasPassed ? EmmaTheme.muted : EmmaTheme.ink)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(subtitle)
                                .font(EmmaTypography.caption())
                                .foregroundStyle(EmmaTheme.mutedSoft)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .buttonStyle(.plain)

            if let onDelete {
                EventActionsMenu(onOpen: onOpen, onDelete: onDelete)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(EmmaTheme.mutedSoft)
            }
        }
        .opacity(hasPassed ? 0.72 : 1)
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
            hasPassed ? "minęło" : event.kind.displayTitle
        ]
        .joined(separator: ", ")
    }

    /// „Konsultacja · Kancelaria”, a po czasie „Minęło · Konsultacja”.
    private var subtitle: String {
        var parts = [event.kind.displayTitle]
        if !event.place.isEmpty { parts.append(event.place) }
        if hasPassed { parts.insert("Minęło", at: 0) }
        return parts.joined(separator: " · ")
    }
}
