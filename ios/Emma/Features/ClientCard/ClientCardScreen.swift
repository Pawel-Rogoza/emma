import SwiftUI

// MARK: - Karta klienta
//
// Port `personPage()` z referencji: nagłówek szczegółu, hero z pigułkami,
// cztery szybkie akcje, lista informacji, powiązana sprawa (albo jej brak),
// zgłoszenie, terminy i notatki.

struct ClientCardScreen: View {

    let clientID: ClientID

    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.emmaLayout) private var layout
    @Environment(\.openURL) private var openURL

    @StateObject private var store = ClientCardStore()
    /// Zgłoszenie czekające na potwierdzenie konwersji w kartotekę.
    @State private var pendingConversion: Client?

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.top, EmmaSpacing.contentTop)
                .padding(.bottom, EmmaSpacing.contentBottom)
        }
        .background(EmmaTheme.bg)
        // F12 audytu: karta klienta miała **dwa** powroty — systemowy i własny
        // w `DetailHeader`. Zostaje jeden (własny), a gest krawędzi wraca przez
        // `emmaPreservesSwipeBack()`.
        .navigationBarBackButtonHidden(true)
        .emmaPreservesSwipeBack()
        .refreshable { await store.load(dependencies, clientID: clientID) }
        .task(id: dependencies.dataVersion) {
            await store.load(dependencies, clientID: clientID)
        }
        .confirmationDialog(
            "Konwertować na klienta?",
            isPresented: Binding(
                get: { pendingConversion != nil },
                set: { if !$0 { pendingConversion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingConversion
        ) { client in
            Button("Konwertuj na klienta") {
                pendingConversion = nil
                Task { await LeadActions.convertToClient(client, dependencies: dependencies) }
            }
            Button("Anuluj", role: .cancel) { pendingConversion = nil }
        } message: { client in
            Text("Dla „\(client.displayName)” powstanie kartoteka klienta. Tego nie cofa się z aplikacji.")
        }
    }

    // MARK: Stany

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle, .loading:
            LoadingState("Wczytuję kartę klienta…")
        case .failed(let failure):
            LoadFailureView(failure) {
                Task { await store.load(dependencies, clientID: clientID) }
            }
        case .loaded(let model):
            loaded(model)
        }
    }

    private func loaded(_ model: ClientCardModel) -> some View {
        let client = model.client
        return VStack(alignment: .leading, spacing: 0) {
            DetailHeader(
                caption: client.source.rawValue,
                title: "Karta klienta",
                onBack: dependencies.back
            )

            hero(client)

            quickActions(model)
                .padding(.bottom, 16)

            if client.stage != .client {
                leadPanel(client)
            }

            infoSection(client)

            linkedCaseSection(model)

            reportSection(client)

            consultationsSection(model)

            notesBlock(model)
        }
    }

    // MARK: Sekcje złożone

    /// Nagłówek „Zgłoszenie” z treścią opisu.
    @ViewBuilder
    private func reportSection(_ client: Client) -> some View {
        SectionHeader("Zgłoszenie")
        proseCard(client)
    }

    /// Nagłówki z akcją „Dodaj” i treścią sekcji terminów.
    @ViewBuilder
    private func consultationsSection(_ model: ClientCardModel) -> some View {
        SectionHeader("Konsultacje i terminy", actionTitle: "Dodaj") {
            dependencies.present(.eventForm(editing: nil, clientID: model.client.id, caseID: model.legalCase?.id, initialDay: nil))
        }
        eventsSection(model)
    }

    /// Nagłówek „Notatki” z akcją „Dodaj” i listą notatek.
    @ViewBuilder
    private func notesBlock(_ model: ClientCardModel) -> some View {
        SectionHeader("Notatki", actionTitle: "Dodaj") {
            dependencies.present(.note(clientID: model.client.id, caseID: model.legalCase?.id))
        }
        notesSection(model)
    }

    // MARK: Hero

    private func hero(_ client: Client) -> some View {
        let topic = LeadTopic.parse(client.topic)
        let topicText = LeadStatusStyle.topicText(topic)
        return VStack(spacing: 0) {
            PersonAvatar(
                initials: client.initials,
                style: .person,
                diameter: EmmaMetrics.clientHeroAvatar
            )
            Text(client.displayName)
                .font(EmmaTypography.clientHero)
                .tracking(-0.8)
                .foregroundStyle(EmmaTheme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 15)
            Text(topicText)
                .font(EmmaTypography.body(for: topicText, size: 13))
                .foregroundStyle(EmmaTheme.mutedSoft)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)
            if let booking = topic.booking {
                Label(
                    LeadStatusStyle.bookingText(booking, dateText: dependencies.dateText, today: dependencies.today),
                    systemImage: "calendar.badge.clock"
                )
                .font(EmmaTypography.caption(.medium))
                .foregroundStyle(EmmaTheme.accent)
                .padding(.top, 9)
            }
            HStack(spacing: 7) {
                statusPills(client)
            }
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        .padding(.bottom, 21)
    }

    @ViewBuilder
    private func statusPills(_ client: Client) -> some View {
        let status = LeadWorkflow.status(of: client, now: dependencies.now)
        LeadStatusBadge(
            status: status,
            text: LeadWorkflow.badgeText(for: client, now: dependencies.now, today: dependencies.today)
        )
        StatusPill(client.language.displayName)
        if showsUrgentContact(client) {
            StatusPill("Pilny kontakt", kind: .amber)
        }
    }

    // MARK: Obsługa zgłoszenia

    /// Panel zgłoszenia: gdzie jest w kolejce i co dalej. Te same czynności co
    /// na liście (obsłużone z „Cofnij”, konwersja po potwierdzeniu).
    private func leadPanel(_ client: Client) -> some View {
        let status = LeadWorkflow.status(of: client, now: dependencies.now)
        return SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: status.needsAction ? "tray.full" : "checkmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(LeadStatusStyle.tone(status))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(leadPanelTitle(status))
                            .font(EmmaTypography.ui(14, .semibold))
                            .foregroundStyle(EmmaTheme.ink)
                        Text(leadPanelMessage(client, status: status))
                            .font(EmmaTypography.caption())
                            .foregroundStyle(EmmaTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if status.needsAction {
                    PrimaryButton("Oznacz jako obsłużone", systemImage: "checkmark") {
                        Task { await LeadActions.markHandled(client, dependencies: dependencies) }
                    }
                    SecondaryButton("Konwertuj na klienta", systemImage: "person.crop.circle.badge.checkmark") {
                        pendingConversion = client
                    }
                } else {
                    PrimaryButton("Konwertuj na klienta", systemImage: "person.crop.circle.badge.checkmark") {
                        pendingConversion = client
                    }
                    SecondaryButton("Przywróć do obsługi", systemImage: "arrow.uturn.backward") {
                        Task { await LeadActions.reopen(client, dependencies: dependencies) }
                    }
                }
            }
        }
        .padding(.bottom, 4)
    }

    private func leadPanelTitle(_ status: LeadStatus) -> String {
        switch status {
        case .fresh: return "Nowe zgłoszenie"
        case .waiting: return "Zgłoszenie czeka na kontakt"
        case .inContact: return "W kontakcie"
        case .client: return "Klient kancelarii"
        }
    }

    private func leadPanelMessage(_ client: Client, status: LeadStatus) -> String {
        let now = dependencies.now
        let today = dependencies.today
        switch status {
        case .fresh:
            return "Wpłynęło \(LeadWorkflow.receivedAgoText(of: client, now: now, today: today)). Po pierwszym kontakcie oznacz je jako obsłużone."
        case .waiting:
            return "Bez kontaktu od \(LeadWorkflow.waitingText(of: client, now: now, today: today)). Oddzwoń albo napisz i oznacz jako obsłużone."
        case .inContact:
            return "Kontakt nawiązany. Gdy klient się zdecyduje, załóż mu kartotekę."
        case .client:
            return "Zgłoszenie ma już kartotekę klienta."
        }
    }

    // MARK: Szybkie akcje

    private func quickActions(_ model: ClientCardModel) -> some View {
        let client = model.client
        let caseID = model.legalCase?.id
        return QuickActions([
            contactAction(model),
            QuickActions.Action(systemImage: "sparkles", title: "Emma") {
                dependencies.openEmma(clientID: client.id)
            },
            QuickActions.Action(systemImage: "square.and.pencil", title: "Notatka") {
                dependencies.present(.note(clientID: client.id, caseID: caseID))
            },
            QuickActions.Action(systemImage: "calendar", title: "Umów") {
                dependencies.present(.eventForm(editing: nil, clientID: client.id, caseID: caseID, initialDay: nil))
            }
        ])
    }

    /// Pierwszy kafel: telefon, gdy go znamy (zgłoszenie to zwykle „oddzwoń”),
    /// a bez numeru — wątek WhatsApp w aplikacji, jak dotąd.
    private func contactAction(_ model: ClientCardModel) -> QuickActions.Action {
        if let phone = model.client.phone, let url = ContactLinks.phoneURL(phone) {
            return QuickActions.Action(systemImage: "phone", title: "Zadzwoń") {
                openURL(url)
            }
        }
        return QuickActions.Action(systemImage: "message", title: "WhatsApp") {
            openWhatsApp(model)
        }
    }

    private func openWhatsApp(_ model: ClientCardModel) {
        guard let threadID = model.threadID else {
            // Wątek powstaje razem z kontaktem; brak wątku to stan, o którym informujemy
            // wprost, zamiast otwierać rozmowę bez odbiorcy.
            dependencies.showToast("Ten kontakt nie ma jeszcze wątku rozmowy.")
            return
        }
        dependencies.openThread(threadID)
    }

    // MARK: Lista informacji

    private func infoSection(_ client: Client) -> some View {
        VStack(spacing: 10) {
            InfoList(infoRows(client))
            contactLinks(client)
        }
        .padding(.vertical, 20)
    }

    private func infoRows(_ client: Client) -> [InfoList.Row] {
        var rows = [InfoList.Row("Źródło", client.source.rawValue)]
        rows.append(InfoList.Row("Zgłoszono", receivedText(client)))
        if let phone = client.phone {
            rows.append(InfoList.Row("Telefon", phone))
        }
        if let email = client.email {
            rows.append(InfoList.Row("E-mail", email))
        }
        return rows
    }

    /// „Dzisiaj, 09:29” przy dokładnym znaczniku, inaczej sama data.
    private func receivedText(_ client: Client) -> String {
        let day = dependencies.dateText.dayLabel(client.createdAt)
        guard let receivedAt = client.receivedAt else { return day }
        return "\(day), \(dependencies.dateText.clockTime(receivedAt))"
    }

    /// WhatsApp i e-mail poza aplikacją — skrzynka WhatsApp w Emmie nie jest
    /// jeszcze połączona z numerem kancelarii, a klient czeka na odpowiedź teraz.
    @ViewBuilder
    private func contactLinks(_ client: Client) -> some View {
        let whatsApp = client.phone.flatMap(ContactLinks.whatsAppURL)
        let mail = client.email.flatMap(ContactLinks.mailURL)
        if whatsApp != nil || mail != nil {
            HStack(spacing: 10) {
                if let whatsApp {
                    SecondaryButton("WhatsApp", systemImage: "message") {
                        openURL(whatsApp)
                    }
                }
                if let mail {
                    SecondaryButton("E-mail", systemImage: "envelope") {
                        openURL(mail)
                    }
                }
            }
        }
    }

    // MARK: Sprawa

    @ViewBuilder
    private func linkedCaseSection(_ model: ClientCardModel) -> some View {
        if let legalCase = model.legalCase {
            linkedCaseButton(legalCase)
                .padding(.vertical, 18)
        } else if dependencies.configuration.usesMockServices {
            PrimaryButton("Rozpocznij prowadzenie sprawy", systemImage: "folder") {
                dependencies.present(.startCase(model.client.id))
            }
        } else {
            // Backend nie ma jeszcze `POST /cases`: przycisk prowadził do
            // formularza, którego zapis zawsze kończył się błędem.
            Label("Sprawę zakładasz w panelu kancelarii — pojawi się tutaj po odświeżeniu.", systemImage: "folder")
                .font(EmmaTypography.caption())
                .foregroundStyle(EmmaTheme.mutedSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 12)
        }
    }

    private func linkedCaseButton(_ legalCase: LegalCase) -> some View {
        Button {
            dependencies.openCase(legalCase.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder")
                    .font(.system(size: 19))
                    .foregroundStyle(EmmaTheme.personAvatarText)
                VStack(alignment: .leading, spacing: 4) {
                    Text(legalCase.number)
                        .font(EmmaTypography.caption(.medium))
                        .tracking(0.7)
                        .foregroundStyle(EmmaTheme.mutedSoft)
                    Text(legalCase.title)
                        .font(EmmaTypography.body(for: legalCase.title, size: 13, weight: .medium))
                        .foregroundStyle(EmmaTheme.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(EmmaTheme.mutedSoft)
            }
            .padding(15)
            .background(EmmaTheme.linkedCaseBackground)
            .clipShape(RoundedRectangle(cornerRadius: EmmaRadii.choiceList, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: EmmaRadii.choiceList, style: .continuous)
                    .strokeBorder(EmmaTheme.linkedCaseBorder, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(legalCase.number), \(legalCase.title)")
        .accessibilityHint("Otwiera sprawę")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Zgłoszenie

    private func proseCard(_ client: Client) -> some View {
        // Treść zgłoszenia z rezerwacji zaczyna się od „Termin: …” — termin jest
        // już wyżej, w nagłówku karty, więc tu zostaje sama wiadomość klienta.
        let briefing = LeadTopic.parse(client.briefing).text
        return SurfaceCard {
            Text(briefing.isEmpty ? "Brak treści zgłoszenia." : briefing)
                .font(EmmaTypography.body(for: briefing, size: 14))
                .foregroundStyle(EmmaTheme.muted)
                .lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Terminy

    @ViewBuilder
    private func eventsSection(_ model: ClientCardModel) -> some View {
        if model.events.isEmpty {
            Text("Nie ustalono jeszcze terminu.")
                .font(EmmaTypography.ui(13))
                .foregroundStyle(EmmaTheme.muted)
                .padding(.top, 12)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: EmmaSpacing.cardGap) {
                ForEach(model.events) { event in
                    EventRow(event: event) {
                        dependencies.present(.eventDetail(event.id))
                    }
                }
            }
        }
    }

    // MARK: Notatki

    @ViewBuilder
    private func notesSection(_ model: ClientCardModel) -> some View {
        if model.notes.isEmpty {
            EmptyState(
                systemImage: "text.bubble",
                title: "Pierwsza rozmowa przed Tobą",
                message: "Dodaj ustalenia po kontakcie z klientem."
            )
        } else {
            VStack(spacing: EmmaSpacing.cardGap) {
                ForEach(model.notes) { note in
                    NoteCard(text: note.text, footer: noteFooter(note))
                }
            }
        }
    }

    /// Datę pokazujemy w stopce karty notatki — komponent `NoteCard`
    /// przyjmuje treść i jedną linię stopki.
    private func noteFooter(_ note: CaseNote) -> String {
        dependencies.dateText.dayLabel(note.createdAt)
    }

    // MARK: Treści pomocnicze

    /// Referencja: `p.urgent && p.needsReply`. Model domeny nie ma pola `urgent`,
    /// dlatego znacznikiem pilności jest `needsReply` (klient czeka na odpowiedź).
    private func showsUrgentContact(_ client: Client) -> Bool { client.needsReply }
}
