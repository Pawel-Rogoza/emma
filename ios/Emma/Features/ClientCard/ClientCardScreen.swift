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

    @StateObject private var store = ClientCardStore()

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.top, EmmaSpacing.contentTop)
                .padding(.bottom, EmmaSpacing.contentBottom)
        }
        .background(EmmaTheme.bg)
        .task(id: dependencies.dataVersion) {
            await store.load(dependencies, clientID: clientID)
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
                .padding(.bottom, 22)

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
        VStack(spacing: 0) {
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
            Text(client.topic)
                .font(EmmaTypography.body(for: client.topic, size: 13))
                .foregroundStyle(EmmaTheme.mutedSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)
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
        StatusPill(client.stage.displayName)
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
            QuickActions.Action(systemImage: "message", title: "WhatsApp") {
                openWhatsApp(model)
            },
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
        InfoList([
            InfoList.Row("Źródło", client.source.rawValue),
            InfoList.Row("Kontakt od", dependencies.dateText.dayLabel(client.createdAt))
        ])
        .padding(.vertical, 20)
    }

    // MARK: Sprawa

    @ViewBuilder
    private func linkedCaseSection(_ model: ClientCardModel) -> some View {
        if let legalCase = model.legalCase {
            linkedCaseButton(legalCase)
                .padding(.vertical, 18)
        } else {
            PrimaryButton("Rozpocznij prowadzenie sprawy", systemImage: "folder") {
                dependencies.present(.startCase(model.client.id))
            }
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
                        .font(EmmaTypography.ui(10, .medium))
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
        SurfaceCard {
            Text(client.briefing)
                .font(EmmaTypography.body(for: client.briefing, size: 14))
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
