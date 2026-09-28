import SwiftUI

// MARK: - Karta klienta
//
// Port `personPage()` z referencji: nagłówek szczegółu, hero z pigułkami,
// szybkie akcje, ścieżka zgłoszenia, powiązana sprawa, zgłoszenie, terminy,
// notatki i dane kontaktowe.
//
// Review 24.09.2026: karta prowadzi przez zgłoszenie jedną ścieżką
// (Nowe → W kontakcie → Klient) z jedną główną czynnością na każdym etapie
// — szczegóły w `LeadActions`. Treść zgłoszenia nie jest już ucinana.

struct ClientCardScreen: View {

    let clientID: ClientID

    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.emmaLayout) private var layout
    @Environment(\.openURL) private var openURL

    @StateObject private var store = ClientCardStore()
    /// Zgłoszenie czekające na potwierdzenie usunięcia.
    @State private var pendingDelete: Client?
    /// Czy długa treść zgłoszenia jest rozwinięta.
    @State private var showsFullReport = false

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
            "Usunąć zgłoszenie?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { client in
            Button("Usuń zgłoszenie", role: .destructive) {
                pendingDelete = nil
                Task { await deleteLead(client) }
            }
            Button("Anuluj", role: .cancel) { pendingDelete = nil }
        } message: { client in
            Text("„\(client.displayName)” zniknie z listy zgłoszeń. Tego nie da się cofnąć.")
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

            if client.stage != .client || model.legalCase == nil {
                LeadPathPanel(
                    client: client,
                    hasCase: model.legalCase != nil,
                    onContact: { url, channel in
                        LeadActions.contact(client, url: url, channel: channel, dependencies: dependencies, openURL: openURL)
                    }
                )
                .padding(.bottom, 4)
            }

            linkedCaseSection(model)

            reportSection(client)

            consultationsSection(model)

            notesBlock(model)

            infoSection(client)

            if client.stage != .client {
                Button(role: .destructive) {
                    pendingDelete = client
                } label: {
                    Text("Usuń zgłoszenie")
                        .font(EmmaTypography.ui(14, .medium))
                        .foregroundStyle(EmmaTheme.danger)
                        .frame(maxWidth: .infinity, minHeight: EmmaSpacing.hitTarget)
                }
                .buttonStyle(.plain)
            }
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
                style: .identity(client.id),
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
                LeadActions.contact(model.client, url: url, channel: "Połączenie", dependencies: dependencies, openURL: openURL)
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
        .padding(.top, 22)
        .padding(.bottom, 12)
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
                        LeadActions.contact(client, url: whatsApp, channel: "WhatsApp", dependencies: dependencies, openURL: openURL)
                    }
                }
                if let mail {
                    SecondaryButton("E-mail", systemImage: "envelope") {
                        LeadActions.contact(client, url: mail, channel: "E-mail", dependencies: dependencies, openURL: openURL)
                    }
                }
            }
        }
    }

    // MARK: Sprawa

    @ViewBuilder
    private func linkedCaseSection(_ model: ClientCardModel) -> some View {
        // Bez sprawy czynność „Przyjmij sprawę” jest w panelu ścieżki zgłoszenia.
        if !model.cases.isEmpty {
            VStack(spacing: 8) {
                ForEach(model.cases) { legalCase in
                    linkedCaseButton(legalCase)
                }
            }
            .padding(.vertical, 18)
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
                    HStack(spacing: 6) {
                        Text(legalCase.number)
                            .font(EmmaTypography.caption(.medium))
                            .tracking(0.7)
                            .foregroundStyle(EmmaTheme.mutedSoft)
                        if legalCase.status != .inProgress {
                            StatusPill(legalCase.status.displayName, kind: .neutral)
                        }
                    }
                    Text(legalCase.title)
                        .font(EmmaTypography.body(for: legalCase.title, size: 13, weight: .medium))
                        .foregroundStyle(legalCase.status.isActive ? EmmaTheme.ink : EmmaTheme.muted)
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
        .buttonStyle(EmmaCardButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(legalCase.number), \(legalCase.title), \(legalCase.status.displayName)")
        .accessibilityHint("Otwiera sprawę")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Zgłoszenie

    private func proseCard(_ client: Client) -> some View {
        // Treść zgłoszenia z rezerwacji zaczyna się od „Termin: …” — termin jest
        // już wyżej, w nagłówku karty, więc tu zostaje sama wiadomość klienta.
        // Review 24.09.2026: dłuższe zgłoszenia były ucinane. Pokazujemy całość;
        // bardzo długą treść zwijamy do kilkunastu linii z „Pokaż całość”.
        let briefing = LeadTopic.parse(client.briefing).text
        let isLong = briefing.count > 600
        return SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(briefing.isEmpty ? "Brak treści zgłoszenia." : briefing)
                    .font(EmmaTypography.body(for: briefing, size: 14))
                    .foregroundStyle(EmmaTheme.muted)
                    .lineSpacing(6)
                    .lineLimit(isLong && !showsFullReport ? 14 : nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if isLong {
                    Button(showsFullReport ? "Zwiń" : "Pokaż całość") {
                        withAnimation(.easeInOut(duration: 0.2)) { showsFullReport.toggle() }
                    }
                    .font(EmmaTypography.caption(.semibold))
                    .foregroundStyle(EmmaTheme.accent)
                    .frame(minHeight: 32)
                }
            }
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

    private func deleteLead(_ client: Client) async {
        let deleted = await dependencies.perform { () async throws -> Bool in
            try await dependencies.repository.deleteClient(client, expectedVersion: client.version)
            return true
        }
        guard deleted == true else { return }
        dependencies.back()
        dependencies.showToast("Usunięto zgłoszenie: \(client.displayName)")
    }
}

// MARK: - Ścieżka zgłoszenia

/// Panel „co dalej” na karcie: trzy etapy (Nowe → W kontakcie → Klient)
/// i jedna główna czynność na każdym z nich. Kolejność czynności odpowiada
/// temu, jak naprawdę pracuje kancelaria: najpierw kontakt, potem konsultacja,
/// na końcu przyjęcie sprawy.
struct LeadPathPanel: View {

    @EnvironmentObject private var dependencies: AppDependencies

    let client: Client
    let hasCase: Bool
    let onContact: (URL, String) -> Void

    var body: some View {
        let status = LeadWorkflow.status(of: client, now: dependencies.now)
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                LeadPathStepper(step: step(for: status))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title(status))
                        .font(EmmaTypography.ui(15, .semibold))
                        .foregroundStyle(EmmaTheme.ink)
                    Text(message(status))
                        .font(EmmaTypography.caption())
                        .foregroundStyle(status == .waiting ? EmmaTheme.pillAmberText : EmmaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                actions(status)
            }
        }
    }

    private func step(for status: LeadStatus) -> Int {
        switch status {
        case .fresh, .waiting: return 0
        case .inContact: return 1
        case .client: return 2
        }
    }

    @ViewBuilder
    private func actions(_ status: LeadStatus) -> some View {
        switch status {
        case .fresh, .waiting:
            contactButtons
            PrimaryButton("Umów konsultację", systemImage: "calendar.badge.plus") {
                dependencies.present(.eventForm(editing: nil, clientID: client.id, caseID: nil, initialDay: nil))
            }
            .accessibilityIdentifier("lead-schedule")
            textButton("Już rozmawialiśmy — oznacz „W kontakcie”") {
                Task { await LeadActions.markInContact(client, dependencies: dependencies) }
            }
            .accessibilityIdentifier("lead-mark-contact")
        case .inContact:
            PrimaryButton("Przyjmij sprawę", systemImage: "folder.badge.plus") {
                dependencies.present(.startCase(client.id))
            }
            .accessibilityIdentifier("lead-accept-case")
            SecondaryButton("Umów konsultację", systemImage: "calendar.badge.plus") {
                dependencies.present(.eventForm(editing: nil, clientID: client.id, caseID: nil, initialDay: nil))
            }
            textButton("Wróć do „Do obsługi”") {
                Task { await LeadActions.reopen(client, dependencies: dependencies) }
            }
        case .client:
            if !hasCase {
                PrimaryButton("Przyjmij sprawę", systemImage: "folder.badge.plus") {
                    dependencies.present(.startCase(client.id))
                }
            }
        }
    }

    /// Kontakt jednym dotknięciem — i od razu „W kontakcie”.
    @ViewBuilder
    private var contactButtons: some View {
        let phone = client.phone.flatMap(ContactLinks.phoneURL)
        let whatsApp = client.phone.flatMap(ContactLinks.whatsAppURL)
        let mail = client.email.flatMap(ContactLinks.mailURL)
        if phone != nil || whatsApp != nil || mail != nil {
            HStack(spacing: 8) {
                if let phone {
                    SecondaryButton("Zadzwoń", systemImage: "phone") { onContact(phone, "Połączenie") }
                }
                if let whatsApp {
                    SecondaryButton("WhatsApp", systemImage: "message") { onContact(whatsApp, "WhatsApp") }
                }
                if let mail, phone == nil || whatsApp == nil {
                    SecondaryButton("E-mail", systemImage: "envelope") { onContact(mail, "E-mail") }
                }
            }
        }
    }

    private func textButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(EmmaTypography.caption(.semibold))
            .foregroundStyle(EmmaTheme.accent)
            .frame(maxWidth: .infinity, minHeight: EmmaSpacing.hitTarget)
            .contentShape(Rectangle())
    }

    private func title(_ status: LeadStatus) -> String {
        switch status {
        case .fresh: return "Nowe zgłoszenie — skontaktuj się"
        case .waiting: return "Czeka na kontakt"
        case .inContact: return "W kontakcie — czy przyjmujesz sprawę?"
        case .client: return "Klient bez sprawy"
        }
    }

    private func message(_ status: LeadStatus) -> String {
        let now = dependencies.now
        let today = dependencies.today
        switch status {
        case .fresh:
            return "Wpłynęło \(LeadWorkflow.receivedAgoText(of: client, now: now, today: today)). Telefon, wiadomość, konsultacja albo notatka same przeniosą je do „W kontakcie”."
        case .waiting:
            return "Bez kontaktu od \(LeadWorkflow.waitingText(of: client, now: now, today: today)). Oddzwoń albo umów konsultację."
        case .inContact:
            return "Gdy klient się zdecyduje, przyjmij sprawę — kartoteka i sprawa powstaną jednym krokiem."
        case .client:
            return "Kartoteka istnieje, ale nie ma prowadzonej sprawy."
        }
    }
}

/// Trzy etapy ścieżki z zaznaczonym bieżącym.
struct LeadPathStepper: View {
    let step: Int

    private let titles = ["Nowe", "W kontakcie", "Klient"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(titles.indices, id: \.self) { index in
                VStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .fill(index <= step ? EmmaTheme.primaryButton : EmmaTheme.controlBackground)
                            .frame(width: 22, height: 22)
                        if index < step {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(EmmaTheme.primaryButtonText)
                        } else {
                            Text("\(index + 1)")
                                .font(EmmaTypography.caption(.semibold))
                                .foregroundStyle(index <= step ? EmmaTheme.primaryButtonText : EmmaTheme.mutedSoft)
                        }
                    }
                    Text(titles[index])
                        .font(EmmaTypography.caption(index == step ? .semibold : .regular))
                        .foregroundStyle(index == step ? EmmaTheme.ink : EmmaTheme.mutedSoft)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                if index < titles.count - 1 {
                    Rectangle()
                        .fill(index < step ? EmmaTheme.primaryButton : EmmaTheme.controlBackground)
                        .frame(height: 2)
                        .frame(maxWidth: 40)
                        .offset(y: -9)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Etap zgłoszenia: \(titles[min(step, titles.count - 1)]), \(step + 1) z 3")
    }
}
