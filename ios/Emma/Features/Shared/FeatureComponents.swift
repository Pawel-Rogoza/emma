import SwiftUI

// MARK: - Współdzielone elementy ekranów
//
// Komponentybudowane z powtarzalnych fragmentów referencji:
//   PersonRow   ← `personRow(p, sub)`            (.person)
//   MeetingCard ← `meetingCard(e)`               (.card.meeting)
//   CaseCard    ← `caseCard(c)`                  (.card.case-card)
//   LeadCard    ← lista leadów w `clientList()`  (.card.large-lead)
//   EventRow    ← `personPage()`                 (.event-row.card)
//   ActivityRow pochodzi z design systemu (EmmaComponents).
//
// Wszystkie przyjmują już rozwiązane dane (nazwę klienta, liczbę zadań) —
// nie sięgają do repozytorium, dzięki czemu są testowalne i przewidywalne.

// MARK: Osoba

/// Wiersz osoby z referencji: awatar, nazwa, temat i opcjonalna strzałka.
struct PersonRow: View {
    let client: Client
    let subtitle: String?
    let showsChevron: Bool
    let onOpen: (() -> Void)?

    init(client: Client, subtitle: String? = nil, showsChevron: Bool = true, onOpen: (() -> Void)? = nil) {
        self.client = client
        self.subtitle = subtitle ?? client.topic
        self.showsChevron = showsChevron
        self.onOpen = onOpen
    }

    var body: some View {
        let content = HStack(spacing: 11) {
            // Awatar listy rozmów ma ton zależny od pozycji; tutaj używamy tonu
            // neutralnego, bo karta nie zna swojej pozycji na liście.
            PersonAvatar(initials: client.initials, style: .person)
            VStack(alignment: .leading, spacing: 3) {
                Text(client.displayName)
                    .font(EmmaTypography.personName)
                    .foregroundStyle(EmmaTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(EmmaTypography.body(for: subtitle, size: 12))
                        .foregroundStyle(EmmaTheme.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(EmmaTheme.mutedSoft)
            }
        }
        .contentShape(Rectangle())

        if let onOpen {
            Button(action: onOpen) { content }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(client.displayName). \(subtitle ?? "")")
                .accessibilityAddTraits(.isButton)
        } else {
            content.accessibilityElement(children: .combine)
        }
    }
}

// MARK: Termin

/// Karta konsultacji: status, godzina z czasem trwania, osoba, miejsce i prowadzący.
struct MeetingCard: View {
    let event: ScheduledEvent
    let clientName: String
    let onOpen: () -> Void

    init(event: ScheduledEvent, clientName: String, onOpen: @escaping () -> Void) {
        self.event = event
        self.clientName = clientName
        self.onOpen = onOpen
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    StatusPill(event.status.rawValue, kind: Self.pillKind(for: event.status))
                    Text("\(event.time.hhmm) · \(event.durationMinutes) min")
                        .font(EmmaTypography.meetingMeta)
                        .foregroundStyle(EmmaTheme.muted)
                    Spacer(minLength: 0)
                }

                HStack(spacing: 11) {
                    PersonAvatar(initials: ClientInitials.make(from: clientName), style: .person)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(clientName)
                            .font(EmmaTypography.personName)
                            .foregroundStyle(EmmaTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(event.title)
                            .font(EmmaTypography.body(for: event.title, size: 12))
                            .foregroundStyle(EmmaTheme.muted)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 14) {
                    Label {
                        Text(event.place)
                            .font(EmmaTypography.meetingMeta)
                    } icon: {
                        Image(systemName: event.place.lowercased().contains("online") ? "video" : "mappin.and.ellipse")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(EmmaTheme.muted)

                    Spacer(minLength: 0)
                }
            }
            .padding(EdgeInsets(top: 16, leading: 17, bottom: 16, trailing: 17))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(EmmaTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous)
                    .strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(event.title), \(clientName), \(event.time.hhmm), \(event.durationMinutes) minut, \(event.status.rawValue), \(event.place)"
        )
        .accessibilityAddTraits(.isButton)
    }

    static func pillKind(for status: EventStatus) -> StatusPill.Kind {
        switch status {
        case .confirmed: return .green
        case .toConfirm: return .amber
        case .finished: return .neutral
        }
    }
}

// MARK: Sprawa

/// Karta sprawy: numer ze statusem, nazwa, klient, licznik zadań i kolejny termin.
struct CaseCard: View {
    let legalCase: LegalCase
    let clientName: String
    let openTaskCount: Int
    let nextEvent: ScheduledEvent?
    let onOpen: () -> Void

    init(
        legalCase: LegalCase,
        clientName: String,
        openTaskCount: Int,
        nextEvent: ScheduledEvent?,
        onOpen: @escaping () -> Void
    ) {
        self.legalCase = legalCase
        self.clientName = clientName
        self.openTaskCount = openTaskCount
        self.nextEvent = nextEvent
        self.onOpen = onOpen
    }

    @EnvironmentObject private var dependencies: AppDependencies

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Text(legalCase.number)
                        .font(EmmaTypography.caseNumber)
                        .tracking(0.4)
                        .foregroundStyle(EmmaTheme.mutedSoft)
                    Spacer(minLength: 0)
                    StatusPill(legalCase.status.rawValue, kind: legalCase.status == .inProgress ? .green : .neutral)
                }

                Text(legalCase.title)
                    .font(EmmaTypography.ui(16, .semibold))
                    .foregroundStyle(EmmaTheme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(clientName)
                    .font(EmmaTypography.caption())
                    .foregroundStyle(EmmaTheme.muted)

                HStack(spacing: 14) {
                    Label {
                        Text(EmmaPlural.tasks(openTaskCount))
                            .font(EmmaTypography.meetingMeta)
                    } icon: {
                        Image(systemName: "checklist").font(.system(size: 12))
                    }

                    if let nextEvent {
                        Label {
                            Text("\(dependencies.dateText.dayLabel(nextEvent.day)), \(nextEvent.time.hhmm)")
                                .font(EmmaTypography.meetingMeta)
                        } icon: {
                            Image(systemName: "calendar").font(.system(size: 12))
                        }
                    } else {
                        Text("Brak kolejnego terminu")
                            .font(EmmaTypography.meetingMeta)
                    }

                    Spacer(minLength: 0)
                }
                .foregroundStyle(EmmaTheme.mutedSoft)
            }
            .padding(EdgeInsets(top: 16, leading: 17, bottom: 16, trailing: 17))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(EmmaTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous)
                    .strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(legalCase.title), \(legalCase.number), \(legalCase.status.displayName), \(clientName), \(EmmaPlural.tasks(openTaskCount))"
        )
        .accessibilityAddTraits(.isButton)
    }
}

enum ClientInitials {
    /// Inicjały z imienia i nazwiska. Wspólne dla awatarów w całej aplikacji.
    static func make(from name: String) -> String {
        let words = name.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first }.map(String.init)
        return letters.joined().uppercased()
    }
}
