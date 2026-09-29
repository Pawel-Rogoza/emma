import SwiftUI

// MARK: - Współdzielone elementy ekranów
//
// Komponentybudowane z powtarzalnych fragmentów referencji:
//   PersonRow   ← `personRow(p, sub)`            (.person)
//   MeetingCard ← `meetingCard(e)`               (.card.meeting)
//   CaseCard    ← `caseCard(c)`                  (.card.case-card), przebudowana 27.09.2026
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
            PersonAvatar(initials: client.initials, style: .identity(client.id))
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

/// Karta terminu w kalendarzu: godzina, rodzaj, nazwa, klient i miejsce.
/// Bez stanu i czasu trwania — CRM ich nie prowadzi, a „Do potwierdzenia”
/// przy każdym terminie było szumem (review 24.09.2026).
struct MeetingCard: View {
    let event: ScheduledEvent
    /// `nil` — termin kancelarii bez klienta.
    let clientName: String?
    let onOpen: () -> Void

    init(event: ScheduledEvent, clientName: String?, onOpen: @escaping () -> Void) {
        self.event = event
        self.clientName = clientName
        self.onOpen = onOpen
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.isAllDay ? "Cały" : event.time.hhmm)
                        .font(EmmaTypography.ui(16, .semibold))
                        .foregroundStyle(EmmaTheme.ink)
                    if event.isAllDay {
                        Text("dzień")
                            .font(EmmaTypography.caption())
                            .foregroundStyle(EmmaTheme.mutedSoft)
                    }
                }
                .frame(width: 50, alignment: .leading)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(event.kind == .caseDeadline ? EmmaTheme.pillAmberText : EmmaTheme.accent)
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 5) {
                    Label(event.kind.displayTitle, systemImage: event.kind.systemImage)
                        .font(EmmaTypography.caption(.medium))
                        .foregroundStyle(event.kind == .caseDeadline ? EmmaTheme.pillAmberText : EmmaTheme.accent)
                    Text(event.title)
                        .font(EmmaTypography.body(for: event.title, size: 14, weight: .semibold))
                        .foregroundStyle(EmmaTheme.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let meta = metaText {
                        Text(meta)
                            .font(EmmaTypography.meetingMeta)
                            .foregroundStyle(EmmaTheme.muted)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(EdgeInsets(top: 14, leading: 15, bottom: 14, trailing: 15))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(EmmaTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous)
                    .strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
            }
            .emmaCardShadow()
            .contentShape(Rectangle())
        }
        .buttonStyle(EmmaCardButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            [event.isAllDay ? "cały dzień" : event.time.hhmm, event.kind.displayTitle, event.title, metaText]
                .compactMap { $0 }
                .joined(separator: ", ")
        )
        .accessibilityAddTraits(.isButton)
    }

    /// „Maria Kowalska · Kancelaria”.
    private var metaText: String? {
        // Nazwa „Konsultacja — Maria Kowalska” już mówi, z kim — bez powtórzenia.
        let client = clientName.flatMap { event.title.contains($0) ? nil : $0 }
        let parts = [client, event.place.isEmpty ? nil : event.place].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: Sprawa

/// Karta sprawy. Review 27.09.2026: karty spraw „zlewały się” — każda zaczynała
/// się szarym numerem i plakietką „W toku”. Teraz odpowiada na pytania w tej
/// kolejności, w jakiej zadaje je prawnik:
///
///   1. **Czyja?** — awatar w stałym kolorze osoby, nazwisko i język klienta,
///   2. **Czy goni?** — plakietka „dziś / jutro / za 5 dni” (czerwona do 3 dni)
///      i pasek z lewej; spokojna sprawa w toku nie ma plakietki wcale,
///   3. **Co to za sprawa?** — tytuł,
///   4. **Co dalej?** — najbliższy termin, zadania (zaległe na czerwono), numer.
struct CaseCard: View {
    let legalCase: LegalCase
    /// `nil`, gdy kartoteka klienta nie przyszła z backendu — karta pokazuje
    /// wtedy samą nazwę zastępczą.
    let client: Client?
    let openTaskCount: Int
    let overdueTaskCount: Int
    let nextEvent: ScheduledEvent?
    /// Niezakończony termin w sprawie, który już minął — plakietka „minął wczoraj”.
    let missedEvent: ScheduledEvent?
    let onOpen: () -> Void

    init(
        legalCase: LegalCase,
        client: Client?,
        openTaskCount: Int,
        overdueTaskCount: Int = 0,
        nextEvent: ScheduledEvent?,
        missedEvent: ScheduledEvent? = nil,
        onOpen: @escaping () -> Void
    ) {
        self.legalCase = legalCase
        self.client = client
        self.openTaskCount = openTaskCount
        self.overdueTaskCount = overdueTaskCount
        self.nextEvent = nextEvent
        self.missedEvent = missedEvent
        self.onOpen = onOpen
    }

    @EnvironmentObject private var dependencies: AppDependencies

    var body: some View {
        let urgency = CaseUrgency(
            nextEvent: nextEvent?.day,
            missedEvent: legalCase.status.isActive ? missedEvent?.day : nil,
            overdueTasks: overdueTaskCount,
            today: dependencies.today
        )
        let stripe = stripeColor(urgency)
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    if let client {
                        PersonAvatar(initials: client.initials, style: .identity(client.id), diameter: 28)
                    }
                    Text(clientName)
                        .font(EmmaTypography.caption(.medium))
                        .foregroundStyle(EmmaTheme.muted)
                        .lineLimit(1)
                    if let client {
                        LanguageBadge(language: client.language)
                    }
                    Spacer(minLength: 6)
                    if let pill = pill(urgency) {
                        StatusPill(pill.text, kind: pill.kind)
                    }
                }

                Text(legalCase.title)
                    .font(EmmaTypography.ui(16, .semibold))
                    .foregroundStyle(legalCase.status == .closed ? EmmaTheme.muted : EmmaTheme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                footer(urgency)
            }
            .padding(EdgeInsets(top: 14, leading: stripe == nil ? 16 : 19, bottom: 14, trailing: 16))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(EmmaTheme.surface)
            .overlay(alignment: .leading) {
                if let stripe {
                    Rectangle().fill(stripe).frame(width: 4)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous)
                    .strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
            }
            .emmaCardShadow()
            .contentShape(Rectangle())
        }
        .buttonStyle(EmmaCardButtonStyle())
        .accessibilityIdentifier("case-card")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(urgency))
        .accessibilityAddTraits(.isButton)
    }

    private var clientName: String {
        client?.displayName ?? Client.unknownDisplayName
    }

    // MARK: Stopka

    private func footer(_ urgency: CaseUrgency) -> some View {
        HStack(spacing: 12) {
            Label {
                Text(footerEventText ?? "Brak terminu")
                    .font(EmmaTypography.caption(urgency.level == .calm ? .regular : .medium))
            } icon: {
                Image(systemName: "calendar").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(eventColor(urgency))
            // Termin ważniejszy niż numer sprawy — to numer ma się skrócić.
            .layoutPriority(2)

            if overdueTaskCount > 0 {
                Label {
                    Text(EmmaPlural.overdueTasks(overdueTaskCount))
                        .font(EmmaTypography.caption(.medium))
                } icon: {
                    Image(systemName: "exclamationmark.circle").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(EmmaTheme.pillDangerText)
            } else if openTaskCount > 0 {
                Label {
                    Text(EmmaPlural.tasks(openTaskCount))
                        .font(EmmaTypography.caption())
                } icon: {
                    Image(systemName: "checklist").font(.system(size: 11))
                }
                .foregroundStyle(EmmaTheme.mutedSoft)
            }

            Spacer(minLength: 6)

            Text(legalCase.number)
                .font(EmmaTypography.caption())
                .tracking(0.3)
                .foregroundStyle(EmmaTheme.mutedSoft)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }

    /// Po terminie stopka mówi, **który** termin minął — plakietka mówi kiedy.
    private var footerEventText: String? {
        if legalCase.status.isActive, let missedEvent {
            return "Minął: \(dependencies.dateText.dayLabel(missedEvent.day))"
        }
        return eventText
    }

    private var eventText: String? {
        guard let nextEvent else { return nil }
        let day = dependencies.dateText.dayLabel(nextEvent.day)
        return nextEvent.isAllDay ? day : "\(day), \(nextEvent.time.hhmm)"
    }

    private func eventColor(_ urgency: CaseUrgency) -> Color {
        switch urgency.level {
        case .missed, .urgent: return EmmaTheme.pillDangerText
        case .soon: return EmmaTheme.pillAmberText
        case .calm: return EmmaTheme.mutedSoft
        }
    }

    // MARK: Stan

    /// Plakietka tylko wtedy, gdy coś mówi: termin w ciągu tygodnia, sprawa
    /// czeka na klienta albo jest zamknięta. „W toku” to stan domyślny — bez plakietki.
    private func pill(_ urgency: CaseUrgency) -> (text: String, kind: StatusPill.Kind)? {
        if legalCase.status == .closed {
            return (legalCase.status.displayName, .neutral)
        }
        if let countdown = urgency.countdownText {
            return (countdown, urgency.isCritical ? .danger : .amber)
        }
        if legalCase.status == .awaitingClient {
            return ("Czeka na klienta", .neutral)
        }
        return nil
    }

    private func stripeColor(_ urgency: CaseUrgency) -> Color? {
        guard legalCase.status.isActive else { return nil }
        switch urgency.level {
        case .missed, .urgent: return EmmaTheme.pillDangerText
        case .soon: return EmmaTheme.pillAmberText
        case .calm: return urgency.overdueTasks > 0 ? EmmaTheme.pillAmberText : nil
        }
    }

    private func accessibilityText(_ urgency: CaseUrgency) -> String {
        var parts = [legalCase.title, clientName, legalCase.status.displayName]
        if let countdown = urgency.countdownText {
            parts.append(urgency.level == .missed ? "termin \(countdown), niezamknięty" : "termin \(countdown)")
        } else if let eventText {
            parts.append("termin \(eventText)")
        }
        if overdueTaskCount > 0 {
            parts.append(EmmaPlural.overdueTasks(overdueTaskCount))
        } else {
            parts.append(EmmaPlural.tasks(openTaskCount))
        }
        parts.append(legalCase.number)
        return parts.joined(separator: ", ")
    }
}

// MARK: Język klienta

/// Plakietka języka klienta: „UA”, „RU”, „PL”. Przy klienteli mówiącej po
/// rosyjsku i ukraińsku to od razu podpowiada, z kim się rozmawia.
struct LanguageBadge: View {
    let language: LanguageCode

    var body: some View {
        Text(language.badgeCode)
            // Kontrola czytelności (F09): nic poniżej 12 pt.
            .font(EmmaTypography.caption(.semibold))
            .tracking(0.3)
            .foregroundStyle(EmmaTheme.secondaryButtonText)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(EmmaTheme.controlBackground, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .fixedSize()
            .accessibilityLabel(language.displayName)
    }
}

// MARK: Podsumowanie

/// Kafelek podsumowania: liczba, podpis i ikona; dotknięcie otwiera listę.
/// Wspólny dla pulsu dnia na „Dzisiaj” i nagłówka ekranu „Klienci”.
struct PulseTile: View {
    let value: Int
    let label: String
    let systemImage: String
    let tone: Color
    let action: () -> Void

    /// Liczba „przewija się” od zera przy pierwszym pokazaniu kafelka —
    /// mały, szybki akcent (audyt 28.09.2026). „Ogranicz ruch” — od razu wartość.
    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shownValue: Int { revealed || reduceMotion ? value : 0 }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center) {
                    Text("\(shownValue)")
                        .font(EmmaTypography.heading(24))
                        .foregroundStyle(EmmaTheme.ink)
                        .contentTransition(.numericText())
                    Spacer(minLength: 4)
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tone)
                        .frame(width: 26, height: 26)
                        .background(EmmaTheme.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                Text(label)
                    .font(EmmaTypography.caption())
                    .foregroundStyle(EmmaTheme.muted)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
            .padding(12)
            .background(EmmaTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EmmaRadii.card, style: .continuous)
                    .strokeBorder(EmmaTheme.cardBorder, lineWidth: 1)
            }
            .emmaCardShadow()
            .contentShape(Rectangle())
        }
        .buttonStyle(EmmaCardButtonStyle())
        .onAppear {
            guard !revealed else { return }
            withAnimation(.snappy(duration: 0.45).delay(0.05)) { revealed = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
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

// MARK: Grupy list

/// Nagłówek grupy listy: „● CZEKAJĄ PONAD DOBĘ · 2”. Kropka w kolorze stanu;
/// grupa wymagająca działania ma tytuł w tym samym kolorze. Wspólny dla
/// „Klientów”, „Rozmów” i listy „Kalendarza” (przebudowa 29.09.2026).
struct GroupHeader: View {
    let title: String
    let count: Int
    /// `nil` — nagłówek bez kropki (litera kartoteki).
    let tone: Color?
    let emphasized: Bool

    var body: some View {
        HStack(spacing: 7) {
            if let tone {
                Circle()
                    .fill(tone)
                    .frame(width: 7, height: 7)
            }
            Text(title.uppercased())
                .font(EmmaTypography.caption(.semibold))
                .tracking(0.6)
                .foregroundStyle(emphasized ? (tone ?? EmmaTheme.mutedSoft) : EmmaTheme.mutedSoft)
            Text("\(count)")
                .font(EmmaTypography.caption(.medium))
                .foregroundStyle(EmmaTheme.mutedSoft)
                .contentTransition(.numericText())
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// Wiersz `List` wyglądający jak zwykły widok: bez tła, separatorów
    /// i systemowych marginesów — karty mają własny wygląd. `List` zostaje
    /// tam, gdzie potrzebne są systemowe przesunięcia z obsługą VoiceOver.
    func emmaListRow(top: CGFloat, bottom: CGFloat, horizontal: CGFloat) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: horizontal, bottom: bottom, trailing: horizontal))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
